import 'dart:math' as math;

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
  Map<String, Object?> preferences = const {},
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
  sync.send({AccountPreferences.homePinsKey: pins, ...preferences});
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
    // Every finger position on small and everyday phones, with the shortest and
    // the widest rows, and the hub at each corner.
    for (final Size screen in const [Size(360, 640), Size(412, 900)]) {
      for (final List<double> widths in const [
        [60.0, 60.0],
        [80.0, 60.0, 70.0],
        [60.0, 60.0, 80.0, 110.0],
        [80.0, 80.0, 80.0, 70.0],
      ]) {
        test('$widths stays in one clear row on $screen', () {
          for (double x = 0; x <= screen.width; x += 30) {
            for (double y = 40; y <= screen.height; y += 30) {
              for (final Offset hub in [
                Offset(screen.width - 56, screen.height - 72),
                Offset(56, screen.height - 72),
                Offset(screen.width - 56, 72),
                const Offset(56, 72),
              ]) {
                final Rect hubArea = Rect.fromCircle(center: hub, radius: 44);
                final List<Rect> rects = homePromptRow(
                  finger: Offset(x, y),
                  widths: widths,
                  height: homePromptHeight,
                  screen: screen,
                  top: 32,
                  bottom: screen.height - homePromptBottomRoom,
                  avoid: hubArea,
                );
                expect(rects, hasLength(widths.length));
                expect(
                  rects.first.left,
                  greaterThanOrEqualTo(homePromptMargin),
                );
                expect(
                  rects.last.right,
                  lessThanOrEqualTo(screen.width - homePromptMargin),
                );
                for (int i = 0; i < rects.length; i++) {
                  final Rect rect = rects[i];
                  expect(rect.width, widths[i]);
                  expect(rect.height, moreOrLessEquals(homePromptHeight));
                  expect(rect.top, greaterThanOrEqualTo(32));
                  expect(
                    rect.bottom,
                    lessThanOrEqualTo(screen.height - homePromptBottomRoom),
                  );
                  expect(
                    rect.overlaps(hubArea),
                    isFalse,
                    reason: 'finger $x,$y hub $hub',
                  );
                  if (i > 0) {
                    expect(
                      rect.left - rects[i - 1].right,
                      moreOrLessEquals(homePromptGap),
                    );
                  }
                }
              }
            }
          }
        });
      }
    }

    List<Rect> row(Offset finger, {Size screen = const Size(393, 852)}) =>
        homePromptRow(
          finger: finger,
          widths: const [60, 60, 80, 130],
          height: homePromptHeight,
          screen: screen,
          top: 32,
          bottom: screen.height - homePromptBottomRoom,
        );

    test('above the finger and clear of it, whatever the side', () {
      for (double x = 0; x <= 393; x += 30) {
        for (double y = 120; y <= 852; y += 30) {
          for (final Rect rect in row(Offset(x, y))) {
            // Above the finger, and at least 40 from it at the nearest point.
            expect(rect.bottom, lessThan(y), reason: 'finger $x,$y');
            final Offset nearest = Offset(
              x.clamp(rect.left, rect.right),
              y.clamp(rect.top, rect.bottom),
            );
            expect(
              (nearest - Offset(x, y)).distance,
              greaterThan(40),
              reason: 'finger $x,$y',
            );
          }
        }
      }
    });

    test('on a slight curve around the finger, above and below', () {
      final List<Rect> above = row(const Offset(196, 400));
      final double top = above.map((r) => r.top).reduce(math.min);
      for (final Rect rect in above) {
        // Nearer the finger's height the further to the side, by no more than
        // the curve.
        final double side = (rect.center.dx - 196).abs();
        expect(
          rect.top - top,
          moreOrLessEquals(
            homePromptCurve *
                math.pow(math.min(side / homePromptCurveReach, 1), 2),
            epsilon: 1,
          ),
        );
      }
      expect(above.last.top, greaterThan(top + 4));
      final List<Rect> below = row(const Offset(196, 60));
      final double bottom = below.map((r) => r.bottom).reduce(math.max);
      expect(below.last.bottom, lessThan(bottom - 4));
    });

    test('centred on the finger, and kept on screen at the edges', () {
      final List<Rect> middle = row(const Offset(196, 400));
      expect(
        (middle.first.left + middle.last.right) / 2,
        moreOrLessEquals(196),
      );
      expect(row(const Offset(4, 400)).first.left, homePromptMargin);
      expect(row(const Offset(390, 400)).last.right, 393 - homePromptMargin);
    });

    test('below the finger only with no room above', () {
      expect(row(const Offset(196, 60)).first.top, greaterThan(60));
      expect(row(const Offset(196, 121)).first.bottom, lessThan(121));
    });

    test('beside the hub if the row fits there, else above it', () {
      List<Rect> near(Rect hub, List<double> widths) => homePromptRow(
        finger: const Offset(300, 700),
        widths: widths,
        height: homePromptHeight,
        screen: const Size(393, 852),
        top: 32,
        bottom: 742,
        avoid: hub,
      );
      final Rect hub = Rect.fromCircle(
        center: const Offset(330, 630),
        radius: 44,
      );
      final List<Rect> short = near(hub, const [60, 60]);
      expect(short.last.right, lessThan(hub.left));
      // The finger's height less the rise, and the curve towards it.
      expect(short.first.center.dy, greaterThan(632));
      expect(short.first.center.dy, lessThan(632 + homePromptCurve));
      final List<Rect> long = near(hub, const [80, 80, 80, 90]);
      expect(long.first.bottom, lessThan(hub.top));
    });

    test('fills by how far the finger has come, and is full once on it', () {
      const Rect prompt = Rect.fromLTWH(100, 100, 80, 40);
      const Offset start = Offset(140, 240);
      expect(homePromptProgress(start, start, prompt), 0);
      expect(
        homePromptProgress(start, const Offset(140, 190), prompt),
        moreOrLessEquals(0.5),
      );
      expect(homePromptProgress(start, const Offset(105, 110), prompt), 1);
      expect(homePromptProgress(start, const Offset(140, 400), prompt), 0);
    });

    group('fitting the labels', () {
      HomePromptFit fit(
        List<double> oneLine,
        List<double> broken,
        double room,
      ) => homePromptFit(oneLine: oneLine, broken: broken, room: room);

      double used(HomePromptFit fit) =>
          fit.widths.fold<double>(0, (sum, width) => sum + width) +
          (fit.widths.length - 1) * homePromptGap;

      const List<double> text = [30, 30, 50, 100];
      const List<double> broken = [30, 30, 50, 60];

      test('roomy when it fits', () {
        final HomePromptFit roomy = fit(text, broken, 400);
        expect(roomy.padding, 14);
        expect(roomy.wrapped, isEmpty);
        expect(roomy.textScale, 1);
      });

      test('then tighter', () {
        final HomePromptFit tight = fit(text, broken, 325);
        expect(tight.padding, 8);
        expect(tight.wrapped, isEmpty);
        expect(used(tight), lessThanOrEqualTo(325));
      });

      test('then the widest on two lines, and only as many as it takes', () {
        final HomePromptFit wrapped = fit(
          const [60, 90, 60, 120],
          const [60, 50, 60, 70],
          400,
        );
        expect(wrapped.wrapped, {3});
        expect(used(wrapped), lessThanOrEqualTo(400));
      });

      test('last the text a little smaller, and never past the room', () {
        final HomePromptFit small = fit(text, broken, 220);
        expect(small.wrapped, {3});
        expect(small.textScale, lessThan(1));
        expect(used(small), moreOrLessEquals(220));
      });
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

    testWidgets('the prompts stand in one row above the finger', (
      tester,
    ) async {
      await _pumpApp(tester);
      final Offset finger = tester.getCenter(_card(_tasks));
      final TestGesture gesture = await _hold(tester, _tasks);
      await tester.pump(const Duration(milliseconds: 300));
      final List<Rect> rects = [
        for (final HomeCardAction action in homeCardActions(
          pinned: null,
          pinnedLists: 0,
        ))
          tester.getRect(_prompt(action)),
      ];
      expect(rects, hasLength(4));
      final double top = rects.map((r) => r.top).reduce(math.min);
      for (int i = 0; i < rects.length; i++) {
        // A slight curve: the sides a little nearer the finger's height.
        expect(rects[i].top - top, lessThanOrEqualTo(homePromptCurve + 0.01));
        expect(rects[i].bottom, lessThan(finger.dy));
        if (i > 0) {
          expect(rects[i].left, greaterThan(rects[i - 1].right));
        }
      }
      await gesture.up();
      await settle(tester);
    });

    testWidgets('they slide out from under the finger', (tester) async {
      await _pumpApp(tester);
      final Offset finger = tester.getCenter(_card(_tasks));
      // Movement on, by hand, as the sway never settles.
      HomeBlob.stillForTests = false;
      addTearDown(() => HomeBlob.stillForTests = true);
      final TestGesture gesture = await _hold(tester, _tasks);
      await tester.pump(const Duration(milliseconds: 16));
      final List<HomeCardAction> actions = _shownPrompts();
      final List<Offset> early = [
        for (final HomeCardAction action in actions)
          tester.getCenter(_prompt(action)),
      ];
      await tester.pump(const Duration(milliseconds: 300));
      for (int i = 0; i < actions.length; i++) {
        final Offset out = tester.getCenter(_prompt(actions[i]));
        expect(
          (early[i] - finger).distance,
          lessThan((out - finger).distance * 0.25),
          reason: '${actions[i]}',
        );
      }
      await gesture.up();
      await tester.pump();
      HomeBlob.stillForTests = true;
      await settle(tester);
    });

    testWidgets('a filled prompt stays clear of its neighbours', (
      tester,
    ) async {
      await _pumpApp(tester);
      final TestGesture gesture = await _hold(tester, _tasks);
      await tester.pump(const Duration(milliseconds: 300));
      final List<HomeCardAction> actions = _shownPrompts()
        ..sort(
          (a, b) => tester
              .getRect(_prompt(a))
              .left
              .compareTo(tester.getRect(_prompt(b)).left),
        );
      final Rect before = tester.getRect(_prompt(actions[1]));
      for (final HomeCardAction action in actions.sublist(1, 3)) {
        await gesture.moveTo(tester.getCenter(_prompt(action)));
        await tester.pump();
        final List<Rect> rects = [
          for (final HomeCardAction each in actions)
            tester.getRect(_prompt(each)),
        ];
        for (int i = 1; i < rects.length; i++) {
          expect(
            rects[i].left - rects[i - 1].right,
            greaterThanOrEqualTo(2),
            reason: 'on $action',
          );
        }
      }
      // It did grow while filled.
      await gesture.moveTo(tester.getCenter(_prompt(actions[1])));
      await tester.pump();
      expect(
        tester.getRect(_prompt(actions[1])).height,
        greaterThan(before.height + 3),
      );
      await gesture.moveTo(
        tester.getCenter(_card(_tasks)) + const Offset(0, 200),
      );
      await tester.pump();
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

    testWidgets('a hold the system cancels ends as a release on none', (
      tester,
    ) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      final TestGesture gesture = await _hold(tester, _tasks);
      await gesture.moveTo(tester.getCenter(_prompt(HomeCardAction.unpin)));
      await tester.pump();
      expect(_shownPrompts(), isNotEmpty);
      await gesture.cancel();
      await settle(tester);
      expect(_shownPrompts(), isEmpty);
      expect(_preferences(tester).homePins, [_tasks, _grocery]);
      // Nothing is stuck: the next hold offers its prompts again.
      final TestGesture again = await _hold(tester, _grocery);
      expect(_shownPrompts(), isNotEmpty);
      await again.up();
      await settle(tester);
      expect(_shownPrompts(), isEmpty);
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

    testWidgets('No suggestions leaves the other cards as they are (R5)', (
      tester,
    ) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      // Grocery keeps its card with an unfilled pin until the next refresh.
      await _choose(tester, _grocery, HomeCardAction.unpin);
      expect(_card(_grocery), findsOneWidget);
      await _choose(tester, _journal, HomeCardAction.noSuggestions);
      expect(_preferences(tester).homeSuggestions, isFalse);
      expect(_card(_journal), findsNothing);
      expect(_card(_watch), findsNothing);
      expect(_card(_grocery), findsOneWidget);
      expect(_card(_tasks), findsOneWidget);
    });

    // Owner, 2026-11-09: on A to Z a new pin did not take its sorted place.
    // Same as dial with the dial on A to Z, or home itself on A to Z (Q-108).
    for (final (String name, Map<String, Object?> order) in [
      (
        'Same as dial',
        {AccountPreferences.listOrderKey: ListOrder.alphabetical.wire},
      ),
      (
        'home on A to Z',
        {
          AccountPreferences.listOrderKey: ListOrder.myOrder.wire,
          AccountPreferences.homeListOrderKey: HomeListOrder.alphabetical.wire,
        },
      ),
    ]) {
      testWidgets('on A to Z a pin takes its sorted place at once, $name', (
        tester,
      ) async {
        await _pumpApp(tester, pins: [_watch, _tasks], preferences: order);
        double top(String id) => tester.getTopLeft(_card(id)).dy;
        expect(top(_tasks), lessThan(top(_watch)));
        await _choose(tester, _grocery, HomeCardAction.pin);
        // Grocery, Tasks, Watch/Read: A to Z, before any refresh.
        expect(top(_grocery), lessThan(top(_tasks)));
        expect(top(_tasks), lessThan(top(_watch)));
        // Pinning changes no setting.
        expect(
          _preferences(tester).homeListOrder.wire,
          order[AccountPreferences.homeListOrderKey] ??
              HomeListOrder.sameAsDial.wire,
        );
        expect(
          _preferences(tester).listOrder.wire,
          order[AccountPreferences.listOrderKey],
        );
      });
    }

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
        expect(_preferences(tester).homeListOrder, HomeListOrder.myOrder);
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
      expect(_preferences(tester).homeListOrder, HomeListOrder.sameAsDial);
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
      expect(_preferences(tester).homeListOrder, HomeListOrder.myOrder);
    });

    testWidgets('a drag the system cancels puts the cards back', (
      tester,
    ) async {
      const List<String> pins = [_tasks, _grocery, _journal];
      await _pumpApp(tester, pins: pins);
      final List<String> before = onScreen(tester, pins);
      await arrange(tester, before.first);
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(_card(before.first)),
      );
      await tester.pump(const Duration(milliseconds: 1));
      for (int i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(0, 100));
        await tester.pump();
      }
      expect(onScreen(tester, pins), isNot(before));
      await gesture.cancel();
      await settle(tester);
      expect(onScreen(tester, pins), before);
      expect(_preferences(tester).homeListOrder, HomeListOrder.sameAsDial);
      expect(isArranging(), isTrue);
      // Nothing is stuck: the card still drags, and that drop saves.
      final TestGesture again = await tester.startGesture(
        tester.getCenter(_card(before.first)),
      );
      await tester.pump(const Duration(milliseconds: 1));
      for (int i = 0; i < 4; i++) {
        await again.moveBy(const Offset(0, 100));
        await tester.pump();
      }
      await again.up();
      await settle(tester);
      expect(_preferences(tester).homeListOrder, HomeListOrder.myOrder);
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
      expect(_preferences(tester).homeListOrder, HomeListOrder.sameAsDial);
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

    testWidgets('a rest lifts the card, and it eases back on moving off', (
      tester,
    ) async {
      double width() => tester
          .getRect(
            find.descendant(
              of: _card(_grocery),
              matching: find.byType(HomeListCard),
            ),
          )
          .width;
      await _pumpApp(tester, pins: [_tasks, _grocery, _journal]);
      await arrange(tester, _tasks);
      // Movement on, by hand, as the sway never settles.
      HomeBlob.stillForTests = false;
      addTearDown(() => HomeBlob.stillForTests = true);
      await tester.pump();
      final double atRest = width();
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(_card(_grocery)),
      );
      // Until just before the pick-up.
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 170));
      expect(width(), greaterThan(atRest + 8));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 20));
      expect(width(), lessThan(atRest + 6));
      await gesture.up();
      await tester.pump();
      HomeBlob.stillForTests = true;
      await tester.tap(find.byKey(const ValueKey('home-arrange-done')));
      await settle(tester);
    });

    testWidgets('a hold and a rest lift only after their delays', (
      tester,
    ) async {
      double width(String id) => tester
          .getRect(
            find.descendant(of: _card(id), matching: find.byType(HomeListCard)),
          )
          .width;
      await _pumpApp(tester, pins: [_tasks, _grocery, _journal]);
      HomeBlob.stillForTests = false;
      addTearDown(() => HomeBlob.stillForTests = true);
      final double atRest = width(_tasks);
      TestGesture gesture = await tester.startGesture(
        tester.getCenter(_card(_tasks)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 200));
      expect(width(_tasks), atRest);
      await tester.pump(const Duration(milliseconds: 500));
      expect(width(_tasks), greaterThan(atRest + 3));
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      HomeBlob.stillForTests = true;
      await settle(tester);

      await arrange(tester, _tasks);
      HomeBlob.stillForTests = false;
      await tester.pump();
      final double grocery = width(_grocery);
      gesture = await tester.startGesture(tester.getCenter(_card(_grocery)));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 30));
      expect(width(_grocery), lessThan(grocery + 4));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      HomeBlob.stillForTests = true;
      await tester.tap(find.byKey(const ValueKey('home-arrange-done')));
      await settle(tester);
    });

    testWidgets('the start of a slow swipe scrolls and picks up nothing', (
      tester,
    ) async {
      await _pumpApp(tester, pins: [_tasks, _grocery, _journal]);
      await arrange(tester, _tasks);
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(_card(_journal)),
      );
      // About 120 dp a second: past the touch slop before the rest ends.
      for (int i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, -3));
        await tester.pump(const Duration(milliseconds: 25));
      }
      await gesture.up();
      await settle(tester);
      expect(_preferences(tester).homeListOrder, HomeListOrder.sameAsDial);
      expect(isArranging(), isTrue);
    });

    testWidgets('Done ends it', (tester) async {
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      final Finder done = find.byKey(const ValueKey('home-arrange-done'));
      expect(done, findsNothing);
      await arrange(tester, _tasks);
      expect(done, findsOneWidget);
      await tester.tap(done);
      await settle(tester);
      expect(isArranging(), isFalse);
      expect(done, findsNothing);
    });

    testWidgets('only pinned cards get a surface, and only while arranging', (
      tester,
    ) async {
      Finder surface(String id) =>
          find.byKey(ValueKey('home-arrange-surface-$id'));
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      expect(surface(_tasks), findsNothing);
      await arrange(tester, _tasks);
      expect(surface(_tasks), findsOneWidget);
      expect(surface(_grocery), findsOneWidget);
      expect(surface(_journal), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-arrange-done')));
      await settle(tester);
      expect(surface(_tasks), findsNothing);
    });

    testWidgets('all but the pinned cards dim, and home is not dim after', (
      tester,
    ) async {
      double opacityOf(Finder finder) => tester
          .widget<Opacity>(
            find.ancestor(of: finder, matching: find.byType(Opacity)).first,
          )
          .opacity;
      final Finder weekday = find.byKey(const ValueKey('home-weekday'));
      final Finder suggestion = find.descendant(
        of: _card(_journal),
        matching: find.byType(HomeListCard),
      );
      final Finder pinned = find.descendant(
        of: _card(_grocery),
        matching: find.byType(HomeListCard),
      );
      await _pumpApp(tester, pins: [_tasks, _grocery]);
      expect(opacityOf(weekday), 1);
      expect(opacityOf(suggestion), 1);
      await arrange(tester, _tasks);
      expect(opacityOf(weekday), lessThan(1));
      expect(opacityOf(suggestion), lessThan(1));
      expect(opacityOf(pinned), 1);
      await tester.tap(find.byKey(const ValueKey('home-arrange-done')));
      await settle(tester);
      expect(opacityOf(weekday), 1);
      expect(opacityOf(suggestion), 1);
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
      expect(_preferences(tester).homeListOrder, HomeListOrder.sameAsDial);
      expect(topOf(tester, _journal), lessThanOrEqualTo(before));
    });

    testWidgets('a home drag makes Home list order My order and leaves the '
        'dial (Q-108)', (tester) async {
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
      expect(preferences.homeListOrder, HomeListOrder.myOrder);
      expect(preferences.homeOrder, before.reversed.toList());
      expect(preferences.listOrder, ListOrder.lastUsed);
      expect(preferences.myListOrder, isEmpty);
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

  testWidgets('Same as dial in Preferences puts home back on the dial\'s '
      'order (Q-108)', (tester) async {
    await _pumpApp(tester, pins: [_tasks, _grocery]);
    final BuildContext home = tester.element(
      find.byKey(const ValueKey('home-weekday')),
    );
    final AccountPreferencesCubit cubit = home.read<AccountPreferencesCubit>();
    await cubit.arrangedOnDial([_grocery, _tasks]);
    await cubit.arrangedOnHome([_tasks, _grocery]);
    await tester.tap(find.byKey(const ValueKey('settings')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('settings-preferences')));
    await settle(tester);
    expect(find.byKey(const ValueKey('preferences-match-dial')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('preferences-home-list-order')));
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('choice-HomeListOrder.sameAsDial')),
    );
    await settle(tester);
    expect(cubit.state.homeListOrder, HomeListOrder.sameAsDial);
    expect(cubit.state.myListOrder, [_grocery, _tasks]);
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
