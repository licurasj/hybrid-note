import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/app/home_cards.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/home_cards_view.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_item.dart';

import 'support/fake_auth.dart';
import 'support/firestore_store.dart';
import 'support/scripted_preferences_sync.dart';

// Holding a home card, its three dots, arranging and the Journal sheet (T-22
// unit 3, Q-71, Q-76, Q-77, Q-78).

const String _tasks = BuiltinTemplates.tasksId;
const String _grocery = BuiltinTemplates.groceryId;
const String _journal = BuiltinTemplates.journalId;
const String _watch = BuiltinTemplates.watchReadId;

const Duration _holdTime = Duration(milliseconds: 1300);
const Duration _restTime = Duration(milliseconds: 400);

final DateTime _now = DateTime.now();

ListItem _item(String listId, String title, {String? body}) => ListItem(
  id: '$listId-$title',
  listId: listId,
  values: {
    'title': title,
    if (listId != _journal) 'done': false,
    'body': ?body,
  },
  createdAt: _now,
  updatedAt: _now,
);

final List<ListItem> _items = [
  _item(_tasks, 'Task'),
  _item(_grocery, 'Milk'),
  _item(_journal, 'Walk', body: 'By the river.'),
  _item(_watch, 'Film'),
];

Finder _card(String listId) => find.byKey(ValueKey('home-card-$listId'));
Finder _prompt(HomeCardAction action) =>
    find.byKey(ValueKey('home-prompt-${action.name}'));

Future<void> _pumpApp(
  WidgetTester tester, {
  List<String> pins = const [],
  List<ListItem>? items,
}) async {
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(const {});
  final FirestoreListStore store = await widgetTestStore(
    tester,
    items: items ?? _items,
  );
  final ScriptedPreferencesSync sync = ScriptedPreferencesSync();
  await tester.pumpWidget(
    await testApp(
      auth: FakeAuthService(user: testUser),
      openStore: (_) => store,
      openPreferences: (_) => sync,
    ),
  );
  await settle(tester);
  sync.send({AccountPreferences.homePinsKey: pins});
  await settle(tester);
}

AccountPreferences _preferences(WidgetTester tester) => tester
    .element(find.byKey(const ValueKey('home-weekday')))
    .accountPreferences;

Future<TestGesture> _hold(WidgetTester tester, String listId) async {
  final TestGesture gesture = await tester.startGesture(
    tester.getCenter(_card(listId)),
  );
  await tester.pump(_holdTime);
  await tester.pump();
  return gesture;
}

// Hold, slide to the prompt and let go.
Future<void> _choose(
  WidgetTester tester,
  String listId,
  HomeCardAction action,
) async {
  final TestGesture gesture = await _hold(tester, listId);
  await tester.pump(const Duration(milliseconds: 300));
  await gesture.moveTo(tester.getCenter(_prompt(action)));
  await tester.pump();
  await gesture.up();
  await settle(tester);
}

List<HomeCardAction> _shownPrompts() => [
  for (final HomeCardAction action in HomeCardAction.values)
    if (_prompt(action).evaluate().isNotEmpty) action,
];

void main() {
  group('what a card offers', () {
    test('each kind of card', () {
      expect(homeCardActions(pinned: true, pinnedLists: 2), [
        HomeCardAction.rearrange,
        HomeCardAction.edit,
        HomeCardAction.unpin,
      ]);
      expect(homeCardActions(pinned: true, pinnedLists: 1), [
        HomeCardAction.edit,
        HomeCardAction.unpin,
      ]);
      expect(homeCardActions(pinned: null, pinnedLists: 0), [
        HomeCardAction.pin,
        HomeCardAction.edit,
        HomeCardAction.remove,
        HomeCardAction.noSuggestions,
      ]);
      expect(homeCardActions(pinned: false, pinnedLists: 5), [
        HomeCardAction.pin,
        HomeCardAction.edit,
      ]);
    });
  });

  group('where the prompts go', () {
    // Every card position, both sides, on small and everyday phones, with a
    // wide prompt as French and German need, and the hub at each corner.
    for (final Size screen in const [Size(360, 640), Size(412, 900)]) {
      for (final double width in const [110.0, 190.0, 300.0]) {
        for (final int count in const [2, 3, 4]) {
          test('$count of width $width fit on $screen', () {
            for (double x = 0; x <= screen.width; x += 30) {
              for (double y = 40; y <= screen.height; y += 30) {
                for (final Offset hub in [
                  Offset(screen.width - 56, screen.height - 72),
                  Offset(56, screen.height - 72),
                  Offset(screen.width - 56, 72),
                  const Offset(56, 72),
                ]) {
                  final List<Offset> centres = homePromptCentres(
                    finger: Offset(x, y),
                    count: count,
                    promptWidth: width,
                    screen: screen,
                    top: 32,
                    bottom: screen.height - homePromptBottomRoom,
                    avoid: Rect.fromCircle(center: hub, radius: 44),
                  );
                  expect(centres, hasLength(count));
                  final Rect hubArea = Rect.fromCircle(center: hub, radius: 44);
                  for (int i = 0; i < count; i++) {
                    final Offset c = centres[i];
                    expect(c.dx - width / 2, greaterThanOrEqualTo(0));
                    expect(c.dx + width / 2, lessThanOrEqualTo(screen.width));
                    expect(c.dy - 20, greaterThanOrEqualTo(32));
                    expect(
                      Rect.fromCenter(
                        center: c,
                        width: width,
                        height: 40,
                      ).overlaps(hubArea),
                      isFalse,
                      reason: 'finger $x,$y hub $hub',
                    );
                    expect(
                      c.dy + 20,
                      lessThanOrEqualTo(screen.height - homePromptBottomRoom),
                    );
                    if (i > 0) {
                      expect(
                        c.dy - centres[i - 1].dy,
                        moreOrLessEquals(homePromptSpacing),
                      );
                    }
                  }
                }
              }
            }
          });
        }
      }
    }

    test('a prompt is not under the finger at the start, on a phone', () {
      for (double x = 0; x <= 360; x += 30) {
        for (double y = 200; y <= 500; y += 30) {
          final List<Offset> centres = homePromptCentres(
            finger: Offset(x, y),
            count: 4,
            promptWidth: 150,
            screen: const Size(360, 640),
            top: 32,
            bottom: 640 - homePromptBottomRoom,
          );
          for (final Offset c in centres) {
            expect((c - Offset(x, y)).distance, greaterThan(26));
          }
        }
      }
    });
  });

  group('the hold', () {
    testWidgets('a pinned card offers Rearrange, Edit and Unpin', (
      tester,
    ) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      final TestGesture gesture = await _hold(tester, _tasks);
      expect(_shownPrompts(), [
        HomeCardAction.rearrange,
        HomeCardAction.edit,
        HomeCardAction.unpin,
      ]);
      await gesture.up();
      await settle(tester);
    });

    testWidgets('with one pin there is no Rearrange', (tester) async {
      await _pumpApp(tester, pins: [_tasks]);
      final TestGesture gesture = await _hold(tester, _tasks);
      expect(_shownPrompts(), [HomeCardAction.edit, HomeCardAction.unpin]);
      await gesture.up();
      await settle(tester);
    });

    testWidgets('a suggestion offers Pin, Edit, Remove, No suggestions', (
      tester,
    ) async {
      await _pumpApp(tester);
      final TestGesture gesture = await _hold(tester, _tasks);
      expect(_shownPrompts(), [
        HomeCardAction.edit,
        HomeCardAction.pin,
        HomeCardAction.remove,
        HomeCardAction.noSuggestions,
      ]);
      await gesture.up();
      await settle(tester);
    });

    testWidgets('an unfilled pin offers Pin and Edit', (tester) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      await tester.tap(find.byKey(const ValueKey('home-pin-$_tasks')));
      await settle(tester);
      final TestGesture gesture = await _hold(tester, _tasks);
      expect(_shownPrompts(), [HomeCardAction.edit, HomeCardAction.pin]);
      await gesture.up();
      await settle(tester);
    });

    testWidgets('before the hold time no prompts, and moving scrolls', (
      tester,
    ) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(_card(_tasks)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(_shownPrompts(), isEmpty);
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump(_holdTime);
      expect(_shownPrompts(), isEmpty);
      await gesture.up();
      await settle(tester);
    });

    testWidgets('letting go on no prompt does nothing and opens nothing', (
      tester,
    ) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      final TestGesture gesture = await _hold(tester, _tasks);
      await gesture.up();
      await settle(tester);
      expect(_shownPrompts(), isEmpty);
      expect(find.byKey(const ValueKey('list-pin')), findsNothing);
      expect(_preferences(tester).homePins, [_tasks, _grocery]);
      expect(_card(_tasks), findsOneWidget);
    });

    testWidgets('moving back away unselects a prompt (rule 3)', (tester) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      final Offset start = tester.getCenter(_card(_tasks));
      final TestGesture gesture = await _hold(tester, _tasks);
      await gesture.moveTo(tester.getCenter(_prompt(HomeCardAction.unpin)));
      await tester.pump();
      await gesture.moveTo(start);
      await tester.pump();
      await gesture.up();
      await settle(tester);
      expect(_preferences(tester).homePins, [_tasks, _grocery]);
    });

    testWidgets('Unpin keeps the card with an unfilled pin', (tester) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      await _choose(tester, _tasks, HomeCardAction.unpin);
      expect(_preferences(tester).homePins, [_grocery]);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-pin-$_tasks')),
          matching: find.byIcon(Icons.push_pin_outlined),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'Pin moves a suggestion to the end of the pinned cards at once',
      (tester) async {
        await _pumpApp(tester, pins: [_tasks]);
        await _choose(tester, _watch, HomeCardAction.pin);
        expect(_preferences(tester).homePins, [_tasks, _watch]);
        expect(find.byKey(const ValueKey('home-pin-$_watch')), findsOneWidget);
        expect(
          tester.getTopLeft(_card(_watch)).dy,
          lessThan(tester.getTopLeft(_card(_grocery)).dy),
        );
      },
    );

    testWidgets('Remove goes at once, and Undo brings it back', (tester) async {
      await _pumpApp(tester);
      await _choose(tester, _grocery, HomeCardAction.remove);
      expect(_card(_grocery), findsNothing);
      expect(_preferences(tester).homeRemoved, [_grocery]);
      expect(find.text('Removed from home'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(_preferences(tester).homeRemoved, isEmpty);
      expect(_card(_grocery), findsOneWidget);
    });

    testWidgets('No suggestions turns them all off, and Undo back on', (
      tester,
    ) async {
      await _pumpApp(tester, pins: [_tasks]);
      await _choose(tester, _grocery, HomeCardAction.noSuggestions);
      expect(_preferences(tester).homeSuggestions, isFalse);
      expect(_card(_grocery), findsNothing);
      expect(_card(_tasks), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(_preferences(tester).homeSuggestions, isTrue);
      expect(_card(_grocery), findsOneWidget);
    });

    testWidgets('Edit opens the list editor', (tester) async {
      await _pumpApp(tester, pins: [_tasks]);
      await _choose(tester, _tasks, HomeCardAction.edit);
      expect(find.byType(HomeListCard), findsNothing);
      await tester.pageBack();
      await settle(tester);
    });
  });

  group('the three dots', () {
    Future<void> openDots(WidgetTester tester, String listId) async {
      await tester.tap(find.byKey(ValueKey('home-dots-$listId')));
      await settle(tester);
    }

    testWidgets('the same choices as the hold, on each kind of card', (
      tester,
    ) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      await openDots(tester, _tasks);
      expect(find.text('Rearrange'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Unpin'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      await openDots(tester, _journal);
      expect(find.text('Pin'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.text('No suggestions'), findsOneWidget);
    });

    testWidgets('Unpin matches the pin icon', (tester) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      await openDots(tester, _tasks);
      await tester.tap(find.text('Unpin'));
      await settle(tester);
      expect(_preferences(tester).homePins, [_grocery]);
      expect(_card(_tasks), findsOneWidget);
    });

    testWidgets('Rearrange opens arranging, and the dots hide', (tester) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      await openDots(tester, _grocery);
      await tester.tap(find.text('Rearrange'));
      await settle(tester);
      expect(find.byKey(const ValueKey('home-dots-$_tasks')), findsNothing);
      await tester.tapAt(const Offset(10, 300));
      await settle(tester);
      expect(find.byKey(const ValueKey('home-dots-$_tasks')), findsOneWidget);
    });
  });

  group('arranging', () {
    Future<void> arrange(WidgetTester tester, String listId) =>
        _choose(tester, listId, HomeCardAction.rearrange);

    bool isArranging() =>
        find.byKey(const ValueKey('home-dots-$_tasks')).evaluate().isEmpty;

    double topOf(WidgetTester tester, String listId) =>
        tester.getTopLeft(_card(listId)).dy;

    List<String> onScreen(WidgetTester tester, List<String> pins) =>
        [...pins]..sort((x, y) => topOf(tester, x).compareTo(topOf(tester, y)));

    testWidgets(
      'the held card drags with no further hold, also after a while',
      (tester) async {
        const List<String> pins = [_tasks, _grocery, _journal];
        await _pumpApp(tester, pins: pins);
        final List<String> before = onScreen(tester, pins);
        await arrange(tester, before.first);
        expect(isArranging(), isTrue);
        await tester.pump(const Duration(seconds: 5));
        final TestGesture gesture = await tester.startGesture(
          tester.getCenter(_card(before.first)),
        );
        await tester.pump(const Duration(milliseconds: 1));
        for (int i = 0; i < 4; i++) {
          await gesture.moveBy(const Offset(0, 100));
          await tester.pump();
        }
        await gesture.up();
        await settle(tester);
        final List<String> after = [...before.skip(1), before.first];
        expect(onScreen(tester, pins), after);
        expect(_preferences(tester).homeOrder, after);
        expect(_preferences(tester).homeArranged, isTrue);
        expect(isArranging(), isTrue);
      },
    );

    testWidgets('another card moves only after the short rest', (tester) async {
      await _pumpApp(tester, pins: [_tasks, _grocery, _journal]);
      await arrange(tester, _tasks);
      final double groceryTop = topOf(tester, _grocery);
      final TestGesture swipe = await tester.startGesture(
        tester.getCenter(_card(_journal)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await swipe.moveBy(const Offset(0, -300));
      await tester.pump();
      await swipe.up();
      await settle(tester);
      expect(_preferences(tester).homeArranged, isFalse);
      expect(isArranging(), isTrue);
      expect(topOf(tester, _grocery), lessThanOrEqualTo(groceryTop));

      final TestGesture rest = await tester.startGesture(
        tester.getCenter(_card(_journal)),
      );
      await tester.pump(_restTime);
      await rest.moveBy(const Offset(0, -150));
      await tester.pump();
      await rest.moveBy(const Offset(0, -150));
      await tester.pump();
      await rest.up();
      await settle(tester);
      expect(_preferences(tester).homeOrder.first, isNot(_grocery));
      expect(_preferences(tester).homeArranged, isTrue);
    });

    testWidgets('a press that lifts without moving does nothing', (
      tester,
    ) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      await arrange(tester, _tasks);
      await tester.tap(_card(_grocery));
      await settle(tester);
      expect(isArranging(), isTrue);
      expect(find.byKey(const ValueKey('list-pin')), findsNothing);
      expect(_preferences(tester).homeArranged, isFalse);
    });

    testWidgets('a tap outside ends it, a suggestion and a swipe as stated', (
      tester,
    ) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      await arrange(tester, _tasks);
      // On a suggestion: it ends, and opens nothing.
      await tester.tap(_card(_journal));
      await settle(tester);
      expect(isArranging(), isFalse);
      expect(find.byKey(const ValueKey('list-pin')), findsNothing);

      await arrange(tester, _tasks);
      await tester.dragFrom(const Offset(10, 300), const Offset(0, -40));
      await settle(tester);
      expect(isArranging(), isTrue);
    });

    testWidgets('Back ends it and stays on home', (tester) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      await arrange(tester, _tasks);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(isArranging(), isFalse);
      expect(_card(_tasks), findsOneWidget);
    });

    testWidgets('only pinned cards can be moved', (tester) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      await arrange(tester, _tasks);
      final double before = topOf(tester, _journal);
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(_card(_journal)),
      );
      await tester.pump(_restTime);
      await tester.pump(const Duration(seconds: 1));
      await gesture.moveBy(const Offset(0, -200));
      await tester.pump();
      await gesture.up();
      await settle(tester);
      expect(_preferences(tester).homeArranged, isFalse);
      expect(topOf(tester, _journal), lessThanOrEqualTo(before));
    });

    testWidgets('a home drag moves the dial, and Match dial order shows only '
        'once they split', (tester) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      final List<String> before = onScreen(tester, [_tasks, _grocery]);
      await arrange(tester, before.first);
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(_card(before.first)),
      );
      await tester.pump(const Duration(milliseconds: 1));
      for (int i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(0, 100));
        await tester.pump();
      }
      await gesture.up();
      await settle(tester);
      final AccountPreferences preferences = _preferences(tester);
      expect(preferences.listOrder, ListOrder.myOrder);
      expect(
        preferences.myListOrder.indexOf(before.last),
        lessThan(preferences.myListOrder.indexOf(before.first)),
      );
      expect(preferences.homeHasOwnOrder, isFalse);
    });

    testWidgets('a screen reader moves a card with its actions', (
      tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      const List<String> pins = [_tasks, _grocery];
      await _pumpApp(tester, pins: pins);
      final List<String> before = onScreen(tester, pins);
      final SemanticsNode node = tester.getSemantics(_card(before.first));
      final CustomSemanticsAction later = [
        for (final int id
            in node.getSemanticsData().customSemanticsActionIds ??
                const <int>[])
          CustomSemanticsAction.getAction(id)!,
      ].singleWhere((action) => action.label == 'Move later');
      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        CustomSemanticsAction.getIdentifier(later),
      );
      await settle(tester);
      expect(onScreen(tester, pins), before.reversed.toList());
      semantics.dispose();
    });
  });

  testWidgets('Match dial order shows once they split, and rejoins them', (
    tester,
  ) async {
    await _pumpApp(tester, pins: [_tasks, _grocery]);
    final Finder row = find.byKey(const ValueKey('preferences-match-dial'));
    final BuildContext home = tester.element(
      find.byKey(const ValueKey('home-weekday')),
    );
    await tester.tap(find.byKey(const ValueKey('settings')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('settings-preferences')));
    await settle(tester);
    expect(row, findsNothing);
    final AccountPreferencesCubit cubit = home.read<AccountPreferencesCubit>();
    await cubit.arrangedOnDial([_grocery, _tasks]);
    await cubit.arrangedOnHome(
      [_tasks, _grocery],
      dialOrder: [_grocery, _tasks],
    );
    await settle(tester);
    expect(find.text('Home has its own order'), findsOneWidget);
    await tester.tap(row);
    await settle(tester);
    expect(row, findsNothing);
    expect(cubit.state.homeArranged, isFalse);
    expect(cubit.state.dialArranged, isTrue);
  });

  group('the Journal sheet', () {
    Future<void> openEntry(
      WidgetTester tester,
      String listId,
      String title, {
      String? body,
    }) async {
      await _pumpApp(tester, items: [_item(listId, title, body: body)]);
      await tester.tap(_card(listId));
      await settle(tester);
      await tester.tap(find.text(title).first);
      await settle(tester);
    }

    Finder bar() => find.byKey(const ValueKey('item-sheet-bar'));
    double sheetHeight(WidgetTester tester) =>
        tester.getSize(find.byType(BottomSheet)).height;

    Future<void> dragBar(WidgetTester tester, double dy) async {
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(bar()),
      );
      await gesture.moveBy(Offset(0, dy / 2));
      await tester.pump();
      await gesture.moveBy(Offset(0, dy / 2));
      await tester.pump();
      await gesture.up();
      await settle(tester);
    }

    testWidgets('drags up to almost the full screen, and back down', (
      tester,
    ) async {
      await openEntry(tester, _journal, 'Walk', body: 'By the river.');
      final double small = sheetHeight(tester);
      await dragBar(tester, -900);
      expect(sheetHeight(tester), greaterThan(1400));
      await dragBar(tester, 1200);
      expect(sheetHeight(tester), small);
      expect(bar(), findsOneWidget);
    });

    testWidgets('a tap on the bar expands it, and a second tap leaves it', (
      tester,
    ) async {
      await openEntry(tester, _journal, 'Walk', body: 'By the river.');
      final double small = sheetHeight(tester);
      await tester.tap(bar());
      await settle(tester);
      final double big = sheetHeight(tester);
      expect(big, greaterThan(1400));
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(bar());
      await settle(tester);
      expect(sheetHeight(tester), big);
      await dragBar(tester, 1200);
      expect(sheetHeight(tester), small);
    });

    testWidgets('a tap expands it at once with reduced motion', (tester) async {
      await openEntry(tester, _journal, 'Walk', body: 'By the river.');
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      await tester.tap(bar());
      await tester.pump();
      expect(sheetHeight(tester), greaterThan(1400));
    });

    testWidgets('a cancelled press on the bar does not expand it', (
      tester,
    ) async {
      await openEntry(tester, _journal, 'Walk', body: 'By the river.');
      final double small = sheetHeight(tester);
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(bar()),
      );
      await gesture.cancel();
      await settle(tester);
      expect(sheetHeight(tester), small);
    });

    testWidgets('a short pull up settles back', (tester) async {
      await openEntry(tester, _journal, 'Walk', body: 'By the river.');
      final double small = sheetHeight(tester);
      await dragBar(tester, -60);
      expect(sheetHeight(tester), small);
    });

    testWidgets('down from the small sheet closes it, as today', (
      tester,
    ) async {
      await openEntry(tester, _journal, 'Walk', body: 'By the river.');
      await dragBar(tester, 900);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('no keyboard until the text is tapped', (tester) async {
      await openEntry(tester, _journal, 'Walk', body: 'By the river.');
      await dragBar(tester, -900);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byKey(const ValueKey('field-body')));
      await settle(tester);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('the text scrolls only when it is too long', (tester) async {
      final String long = List.filled(400, 'A line of the day.').join('\n');
      await openEntry(tester, _journal, 'Walk', body: long);
      await dragBar(tester, -900);
      final Scrollbar scrollbar = tester.widget(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollbar),
        ),
      );
      expect(scrollbar.controller!.position.maxScrollExtent, greaterThan(0));
    });

    testWidgets('other lists keep today\'s sheet', (tester) async {
      await openEntry(tester, _tasks, 'Task');
      expect(bar(), findsNothing);
    });
  });
}
