import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/home_cards_view.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_rules.dart';

import 'support/fake_auth.dart';
import 'support/firestore_store.dart';
import 'support/scripted_preferences_sync.dart';

// Home's list cards on screen (T-22 unit 2): pins, what a refresh is, the
// switches, the blob and the list page's fixed title.

final DateTime _now = DateTime.now();

ListItem _item(String listId, String title, {bool done = false, DateTime? at}) {
  final DateTime changed = at ?? _now.subtract(const Duration(days: 3));
  return ListItem(
    id: '$listId-$title',
    listId: listId,
    values: {'title': title, 'done': done},
    createdAt: changed,
    updatedAt: changed,
  );
}

final List<ListItem> _items = [
  for (int i = 1; i <= 4; i++) _item(BuiltinTemplates.tasksId, 'Task $i'),
  _item(BuiltinTemplates.groceryId, 'Milk'),
];

Finder _card(String listId) => find.byKey(ValueKey('home-card-$listId'));
Finder _pin(String listId) => find.byKey(ValueKey('home-pin-$listId'));

Future<(FirestoreListStore, ScriptedPreferencesSync)> _pumpApp(
  WidgetTester tester, {
  Map<String, Object?> preferences = const {},
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
  sync.send(preferences);
  await settle(tester);
  return (store, sync);
}

AccountPreferences _preferences(WidgetTester tester) =>
    tester.element(find.byType(HomeListCard).first).accountPreferences;

Future<void> _openAndComeBack(WidgetTester tester, String listId) async {
  await tester.tap(_card(listId));
  await settle(tester);
  expect(_card(listId), findsNothing);
  await tester.pageBack();
  await settle(tester);
}

void main() {
  group('the cards', () {
    testWidgets('pinned first with a pin, suggestions below with none', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        preferences: {
          AccountPreferences.homePinsKey: [BuiltinTemplates.groceryId],
        },
      );
      expect(_pin(BuiltinTemplates.groceryId), findsOneWidget);
      expect(_card(BuiltinTemplates.tasksId), findsOneWidget);
      expect(_pin(BuiltinTemplates.tasksId), findsNothing);
      expect(
        tester.getTopLeft(_card(BuiltinTemplates.groceryId)).dy,
        lessThan(tester.getTopLeft(_card(BuiltinTemplates.tasksId)).dy),
      );
    });

    testWidgets('a card shows the top three open items, and a tap opens', (
      tester,
    ) async {
      await _pumpApp(tester);
      final Finder inCard = find.descendant(
        of: _card(BuiltinTemplates.tasksId),
        matching: find.textContaining('Task '),
      );
      expect(inCard, findsNWidgets(3));
      await tester.tap(_card(BuiltinTemplates.tasksId));
      await settle(tester);
      expect(find.byKey(const ValueKey('list-pin')), findsOneWidget);
    });

    testWidgets('a pinned list with nothing open says so', (tester) async {
      await _pumpApp(
        tester,
        preferences: {
          AccountPreferences.homePinsKey: [BuiltinTemplates.journalId],
        },
      );
      expect(
        find.descendant(
          of: _card(BuiltinTemplates.journalId),
          matching: find.text('Nothing open'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an item changing elsewhere updates inside the card', (
      tester,
    ) async {
      final (FirestoreListStore store, _) = await _pumpApp(tester);
      expect(find.text('Milk'), findsOneWidget);
      await tester.runAsync(
        () => store.apply(
          ListChanges(saved: [_item(BuiltinTemplates.groceryId, 'Eggs')]),
        ),
      );
      await settle(tester);
      expect(find.text('Eggs'), findsOneWidget);
    });
  });

  group('the pin on a card', () {
    final Map<String, Object?> pinned = {
      AccountPreferences.homePinsKey: [
        BuiltinTemplates.tasksId,
        BuiltinTemplates.groceryId,
      ],
    };

    testWidgets('unpins, the card staying with an unfilled pin', (
      tester,
    ) async {
      await _pumpApp(tester, preferences: pinned);
      await tester.tap(_pin(BuiltinTemplates.tasksId));
      await settle(tester);
      expect(_preferences(tester).homePins, [BuiltinTemplates.groceryId]);
      expect(_card(BuiltinTemplates.tasksId), findsOneWidget);
      expect(
        find.descendant(
          of: _pin(BuiltinTemplates.tasksId),
          matching: find.byIcon(Icons.push_pin_outlined),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a second tap pins it back', (tester) async {
      await _pumpApp(tester, preferences: pinned);
      await tester.tap(_pin(BuiltinTemplates.tasksId));
      await settle(tester);
      await tester.tap(_pin(BuiltinTemplates.tasksId));
      await settle(tester);
      expect(
        _preferences(tester).homePins,
        containsAll([BuiltinTemplates.tasksId, BuiltinTemplates.groceryId]),
      );
      expect(
        find.descendant(
          of: _pin(BuiltinTemplates.tasksId),
          matching: find.byIcon(Icons.push_pin),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the next refresh turns an unpinned card into a suggestion', (
      tester,
    ) async {
      await _pumpApp(tester, preferences: pinned);
      await tester.tap(_pin(BuiltinTemplates.tasksId));
      await settle(tester);
      await _openAndComeBack(tester, BuiltinTemplates.groceryId);
      expect(_pin(BuiltinTemplates.tasksId), findsNothing);
      expect(_card(BuiltinTemplates.tasksId), findsOneWidget);
    });
  });

  group('what a refresh is', () {
    Finder scroll() => find.byKey(const ValueKey('home-scroll'));

    // The grocery list gets the newest change while home is showing; it would
    // rank first if the cards were worked out again.
    Future<FirestoreListStore> changed(WidgetTester tester) async {
      final (FirestoreListStore store, _) = await _pumpApp(
        tester,
        items: [
          _item(
            BuiltinTemplates.tasksId,
            'Task',
            at: _now.subtract(const Duration(days: 1)),
          ),
          _item(
            BuiltinTemplates.groceryId,
            'Milk',
            at: _now.subtract(const Duration(days: 2)),
          ),
        ],
      );
      expect(
        tester.getTopLeft(_card(BuiltinTemplates.tasksId)).dy,
        lessThan(tester.getTopLeft(_card(BuiltinTemplates.groceryId)).dy),
      );
      await tester.runAsync(
        () => store.apply(
          ListChanges(
            saved: [_item(BuiltinTemplates.groceryId, 'Eggs', at: _now)],
          ),
        ),
      );
      await settle(tester);
      return store;
    }

    bool groceryFirst(WidgetTester tester) =>
        tester.getTopLeft(_card(BuiltinTemplates.groceryId)).dy <
        tester.getTopLeft(_card(BuiltinTemplates.tasksId)).dy;

    testWidgets('without one, the cards stay still', (tester) async {
      await changed(tester);
      expect(groceryFirst(tester), isFalse);
    });

    testWidgets('switching apps and back is not one', (tester) async {
      await changed(tester);
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(groceryFirst(tester), isFalse);
    });

    testWidgets('coming back from a list is', (tester) async {
      await changed(tester);
      await _openAndComeBack(tester, BuiltinTemplates.tasksId);
      expect(groceryFirst(tester), isTrue);
    });

    testWidgets('pulling down is', (tester) async {
      await changed(tester);
      await tester.drag(scroll(), const Offset(0, 400));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(groceryFirst(tester), isTrue);
    });

    testWidgets('opening a sheet and closing it is not', (tester) async {
      await changed(tester);
      await tester.tap(find.byKey(const ValueKey('settings')));
      await settle(tester);
      await tester.tapAt(const Offset(250, 20));
      await settle(tester);
      expect(groceryFirst(tester), isFalse);
    });

    testWidgets('pins arriving from another phone show at once', (
      tester,
    ) async {
      final (_, ScriptedPreferencesSync sync) = await _pumpApp(tester);
      expect(_pin(BuiltinTemplates.groceryId), findsNothing);
      sync.send({
        AccountPreferences.homePinsKey: [BuiltinTemplates.groceryId],
      });
      await settle(tester);
      expect(_pin(BuiltinTemplates.groceryId), findsOneWidget);
    });
  });

  group('the switches', () {
    testWidgets('cards off: weekday, date and Today only, pins kept', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        preferences: {
          AccountPreferences.homeCardsKey: false,
          AccountPreferences.homePinsKey: [BuiltinTemplates.tasksId],
        },
      );
      expect(find.byType(HomeListCard), findsNothing);
      expect(find.byKey(const ValueKey('home-weekday')), findsOneWidget);
      final AccountPreferences preferences = tester
          .element(find.byKey(const ValueKey('home-weekday')))
          .accountPreferences;
      expect(preferences.homePins, [BuiltinTemplates.tasksId]);
    });

    testWidgets(
      'suggestions off leaves only pinned cards, and all go at once',
      (tester) async {
        final (_, ScriptedPreferencesSync sync) = await _pumpApp(
          tester,
          preferences: {
            AccountPreferences.homePinsKey: [BuiltinTemplates.tasksId],
          },
        );
        expect(_card(BuiltinTemplates.groceryId), findsOneWidget);
        sync.send({
          AccountPreferences.homePinsKey: [BuiltinTemplates.tasksId],
          AccountPreferences.homeSuggestionsKey: false,
        });
        await settle(tester);
        expect(_card(BuiltinTemplates.groceryId), findsNothing);
        expect(_card(BuiltinTemplates.tasksId), findsOneWidget);
      },
    );
  });

  group('the list page', () {
    testWidgets('its pin pins the list, and home shows it on coming back', (
      tester,
    ) async {
      await _pumpApp(tester);
      await tester.tap(_card(BuiltinTemplates.groceryId));
      await settle(tester);
      final Finder pin = find.byKey(const ValueKey('list-pin'));
      expect(
        find.descendant(
          of: pin,
          matching: find.byIcon(Icons.push_pin_outlined),
        ),
        findsOneWidget,
      );
      await tester.tap(pin);
      await settle(tester);
      expect(
        find.descendant(of: pin, matching: find.byIcon(Icons.push_pin)),
        findsOneWidget,
      );
      await tester.pageBack();
      await settle(tester);
      expect(_pin(BuiltinTemplates.groceryId), findsOneWidget);
    });

    testWidgets('the title stays while the items scroll', (tester) async {
      await _pumpApp(
        tester,
        items: [
          for (int i = 0; i < 60; i++)
            _item(BuiltinTemplates.tasksId, 'Task $i'),
        ],
      );
      await tester.tap(_card(BuiltinTemplates.tasksId));
      await settle(tester);
      final Finder count = find.textContaining('open');
      final double before = tester.getTopLeft(count.first).dy;
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await settle(tester);
      expect(tester.getTopLeft(count.first).dy, before);
    });
  });

  group('the blob', () {
    setUp(() => HomeBlob.stillForTests = false);
    tearDown(() => HomeBlob.stillForTests = true);

    Widget blob({bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const Center(child: HomeBlob(color: Colors.red, seed: 7)),
      ),
    );

    testWidgets('moves', (tester) async {
      await tester.pumpWidget(blob());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('stops under reduced motion', (tester) async {
      await tester.pumpWidget(blob(reduced: true));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('stops when reduced motion comes on, and starts again', (
      tester,
    ) async {
      await tester.pumpWidget(blob());
      await tester.pumpWidget(blob(reduced: true));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(blob());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('stops while a page covers it', (tester) async {
      await tester.pumpWidget(blob());
      await tester.pump();
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      navigator.push(
        PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      navigator.pop();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    test('the same list keeps the same blob, and lists differ', () {
      expect(homeBlobSeed('builtin.tasks'), 808235644);
      expect(
        homeBlobSeed('builtin.tasks'),
        isNot(homeBlobSeed('builtin.grocery')),
      );
    });
  });
}
