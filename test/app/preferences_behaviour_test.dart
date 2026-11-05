import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/ai/ai_service.dart';
import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/app/app_settings.dart';
import 'package:hybrid_note/app/date_preferences.dart';
import 'package:hybrid_note/app/list_order.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/backend/firestore_setup.dart';
import 'package:hybrid_note/home_screen.dart';
import 'package:hybrid_note/launcher/dial_launcher.dart';
import 'package:hybrid_note/launcher/launcher_geometry.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/generic_list_host.dart';
import 'package:hybrid_note/lists/generic_list_screen.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';

import '../support/fake_auth.dart';
import '../support/firestore_store.dart';
import '../support/scripted_preferences_sync.dart';

// What each preference does in the app (T-21 unit 3). The page that sets them
// is in preferences_screen_test.dart.

final Finder _hub = find.byKey(const ValueKey('launcher-hub'));
final String _tasks = BuiltinTemplates.tasksId;

ListDefinition _list(String id, String name) => ListDefinition.fromJson({
  'id': id,
  'name': name,
  'icon': 'task_alt',
  'color': '#43A047',
  'fields': [
    {
      'key': 'title',
      'type': 'text',
      'label': 'Title',
      'required': true,
      'primary': true,
    },
  ],
  'view': {'kind': 'table'},
  'updatedAt': '2026-03-01T00:00:00.000Z',
});

Future<FirestoreListStore> _pumpApp(
  WidgetTester tester, {
  Map<String, Object> stored = const {},
  List<ListDefinition>? lists,
  List<ListItem> items = const [],
  Widget Function(Widget app)? wrap,
  AccountPreferencesSync? sync,
  StarterSeeding? starter,
}) async {
  tester.view.physicalSize = const Size(412, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(stored);
  final FirestoreListStore store = await widgetTestStore(
    tester,
    lists: lists,
    items: items,
  );
  final Widget app = await testApp(
    auth: FakeAuthService(user: testUser),
    openStore: (_) => store,
    starter: starter,
    openPreferences: sync == null ? null : (_) => sync,
  );
  await tester.pumpWidget(wrap == null ? app : wrap(app));
  await settle(tester);
  return store;
}

AccountPreferencesCubit _account(WidgetTester tester) => tester
    .element(find.byType(HomeScreen, skipOffstage: false))
    .read<AccountPreferencesCubit>();

// The list ids the dial was given, in order.
List<String> _dialIds(WidgetTester tester) => [
  for (final note
      in tester.widget<DialLauncher>(find.byType(DialLauncher)).notes)
    note.id,
];

void main() {
  group('orderLists', () {
    final List<ListDefinition> lists = [
      _list('c', 'cherry'),
      _list('a', 'Apple'),
      _list('b', 'banana'),
    ];

    List<String> order(
      ListOrder order, {
      List<String> myOrder = const [],
      List<String> recent = const [],
    }) => [
      for (final ListDefinition list in orderLists(
        lists,
        order: order,
        myOrder: myOrder,
        recent: recent,
        nameOf: (definition) => definition.name!,
      ))
        list.id,
    ];

    test('Last used: newest first, the rest in creation order', () {
      expect(order(ListOrder.lastUsed), ['c', 'a', 'b']);
      expect(order(ListOrder.lastUsed, recent: ['b']), ['b', 'c', 'a']);
      expect(order(ListOrder.lastUsed, recent: ['a', 'b', 'c']), [
        'a',
        'b',
        'c',
      ]);
    });

    test(
      'My order: as arranged; new lists at the end, deleted ids skipped',
      () {
        expect(order(ListOrder.myOrder), ['c', 'a', 'b']);
        expect(order(ListOrder.myOrder, myOrder: ['b', 'gone', 'c']), [
          'b',
          'c',
          'a',
        ]);
      },
    );

    test('A to Z: by the shown name, whatever the case', () {
      expect(order(ListOrder.alphabetical), ['a', 'b', 'c']);
    });

    test('the same name keeps creation order', () {
      expect(
        orderLists(
          [_list('x', 'Same'), _list('y', 'same'), _list('z', 'SAME')],
          order: ListOrder.alphabetical,
          myOrder: const [],
          recent: const [],
          nameOf: (definition) => definition.name!,
        ).map((list) => list.id),
        ['x', 'y', 'z'],
      );
    });
  });

  group('list order in the app', () {
    testWidgets('Last used survives a restart and is per user', (tester) async {
      await _pumpApp(tester);
      await tester.tap(_hub);
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('launcher-note-$_tasks')));
      await settle(tester);

      final SharedPreferences stored = await SharedPreferences.getInstance();
      expect(
        stored.getStringList(AppSettingsCubit.recentListsKey(testUser.uid)),
        [_tasks],
      );
      expect(
        tester
            .element(find.byType(GenericListScreen))
            .read<AppSettingsCubit>()
            .recentLists('someone-else'),
        isEmpty,
      );
    });

    testWidgets('sign-out forgets it', (tester) async {
      await _pumpApp(
        tester,
        stored: {
          AppSettingsCubit.recentListsKey(testUser.uid): [_tasks],
        },
      );
      await tester.tap(find.byKey(const ValueKey('settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-out')));
      await settle(tester);

      final SharedPreferences stored = await SharedPreferences.getInstance();
      expect(
        stored.containsKey(AppSettingsCubit.recentListsKey(testUser.uid)),
        isFalse,
      );
    });

    testWidgets('the dial follows the choice as it changes', (tester) async {
      await _pumpApp(
        tester,
        lists: [_list('a', 'zeta'), _list('b', 'Mid'), _list('c', 'alpha')],
      );
      expect(_dialIds(tester), ['a', 'b', 'c']);

      await _account(tester).setListOrder(ListOrder.alphabetical);
      await tester.pump();
      expect(_dialIds(tester), ['c', 'b', 'a']);

      await _account(tester).setMyListOrder(['b', 'c', 'a']);
      await _account(tester).setListOrder(ListOrder.myOrder);
      await tester.pump();
      expect(_dialIds(tester), ['b', 'c', 'a']);
    });
  });

  group('arranging on the dial (Q-49)', () {
    final Finder area = find.byKey(const ValueKey('launcher-arrange-area'));
    final Finder prompt = find.byKey(const ValueKey('launcher-arrange-prompt'));

    Future<void> openArranging(WidgetTester tester) async {
      final Offset hub = tester.getCenter(_hub);
      final TestGesture gesture = await tester.startGesture(hub);
      for (int i = 0; i < 200 && prompt.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump(const Duration(milliseconds: 300));
      final Offset target = tester.getCenter(prompt);
      for (int i = 1; i <= 8; i++) {
        await gesture.moveTo(Offset.lerp(hub, target, i / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(area, findsOneWidget);
    }

    Future<void> dragFirstPastSecond(WidgetTester tester) async {
      final Offset hub = tester.getCenter(_hub);
      final double diagonal = math.atan2(hub.dy, -hub.dx);
      final double step = 12 * 1.3 * math.pi / 180;
      Offset at(double angle) =>
          hub + Offset(math.cos(angle), -math.sin(angle)) * 170;
      final TestGesture gesture = await tester.startGesture(at(diagonal));
      await tester.pump(
        const LauncherConfig().dialPickUpDelay +
            const Duration(milliseconds: 50),
      );
      for (int i = 1; i <= 8; i++) {
        await gesture.moveTo(at(diagonal + step * i / 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('the first drag switches to My order, from what is on screen', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        lists: [_list('a', 'zeta'), _list('b', 'Mid'), _list('c', 'alpha')],
      );
      await _account(tester).setListOrder(ListOrder.alphabetical);
      await tester.pump();
      expect(_dialIds(tester), ['c', 'b', 'a']);

      await openArranging(tester);
      // Opening it alone changes nothing.
      expect(_account(tester).state.listOrder, ListOrder.alphabetical);

      await dragFirstPastSecond(tester);
      expect(_account(tester).state.listOrder, ListOrder.myOrder);
      expect(_account(tester).state.myListOrder, ['b', 'c', 'a']);
      expect(_dialIds(tester), ['b', 'c', 'a']);
      expect(area, findsOneWidget);
    });

    testWidgets('inside a list Back ends it and leaves the list open', (
      tester,
    ) async {
      await _pumpApp(tester, lists: [_list('a', 'One'), _list('b', 'Two')]);
      await tester.tap(_hub);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('launcher-note-a')));
      await settle(tester);
      await openArranging(tester);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(area, findsNothing);
      expect(find.byType(GenericListScreen), findsOneWidget);

      // The next Back goes home as usual.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(GenericListScreen), findsNothing);
    });
  });

  group('a setting the server will not save (Codex H1)', () {
    const String message =
        'A setting could not be saved to your account. It stays as you set it '
        'on this phone.';

    testWidgets('a banner says so, and the choice stays', (tester) async {
      final ScriptedPreferencesSync sync = ScriptedPreferencesSync();
      addTearDown(sync.snapshots.close);
      await _pumpApp(tester, sync: sync);
      sync.send(const {'vibration': true});
      await settle(tester);
      expect(find.text(message), findsNothing);

      sync.refuse = true;
      await _account(tester).setVibration(false);
      await tester.pump();
      await tester.pump();
      expect(find.text(message), findsOneWidget);

      sync.send(const {'vibration': true});
      await tester.pump();
      expect(_account(tester).state.vibration, isFalse);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('offline nothing is said', (tester) async {
      final ScriptedPreferencesSync sync = ScriptedPreferencesSync();
      addTearDown(sync.snapshots.close);
      await _pumpApp(tester, sync: sync);
      sync.send(const {'vibration': true});
      await settle(tester);

      sync.offline = true;
      await _account(tester).setVibration(false);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(message), findsNothing);
      expect(_account(tester).state.vibration, isFalse);
    });
  });

  group('start screen', () {
    Map<String, Object> lastList(List<String> recent) => {
      AccountPreferencesCubit.mirrorKey(testUser.uid):
          '{"startScreen":"lastOpenList"}',
      AppSettingsCubit.recentListsKey(testUser.uid): recent,
    };

    testWidgets('Home by default, whatever was open', (tester) async {
      await _pumpApp(
        tester,
        stored: {
          AppSettingsCubit.recentListsKey(testUser.uid): [_tasks],
        },
      );
      expect(find.byType(GenericListScreen), findsNothing);
    });

    testWidgets('Last open list opens it; Back goes home', (tester) async {
      await _pumpApp(tester, stored: lastList([_tasks]));
      expect(find.byType(GenericListScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(GenericListScreen), findsNothing);
      expect(find.byKey(const ValueKey('home-weekday')), findsOneWidget);
    });

    testWidgets('nothing opened yet: Home', (tester) async {
      await _pumpApp(tester, stored: lastList(const []));
      expect(find.byType(GenericListScreen), findsNothing);
    });

    testWidgets('no lists left in the account: Home, not a dead route', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        stored: lastList(const ['gone-list']),
        lists: const [],
      );
      await settle(tester);
      expect(find.byType(GenericListHost), findsNothing);
      expect(find.byKey(const ValueKey('home-weekday')), findsOneWidget);
    });

    testWidgets('no lists yet: it waits for the starter lists to be done', (
      tester,
    ) async {
      final Completer<bool> seeded = Completer<bool>();
      final StarterSeeding starter = StarterSeeding(
        ({required empty}) => seeded.future,
      );
      unawaited(starter.start());
      await _pumpApp(
        tester,
        stored: lastList(const ['gone-list']),
        lists: const [],
        starter: starter,
      );
      await settle(tester);
      expect(find.byType(GenericListHost), findsOneWidget);

      seeded.complete(false);
      await settle(tester);
      expect(find.byType(GenericListHost), findsNothing);
      expect(find.byKey(const ValueKey('home-weekday')), findsOneWidget);
    });

    testWidgets('the list still there stays open once the lists have loaded', (
      tester,
    ) async {
      await _pumpApp(tester, stored: lastList([_tasks]));
      await settle(tester);
      expect(find.byType(GenericListHost), findsOneWidget);
    });

    testWidgets('a list that is gone: Home', (tester) async {
      await _pumpApp(tester, stored: lastList(const ['gone-list']));
      await settle(tester);
      expect(find.byType(GenericListScreen), findsNothing);
      expect(find.byKey(const ValueKey('home-weekday')), findsOneWidget);
    });
  });

  group('ticked items', () {
    final ListDefinition checklist = ListDefinition.fromJson({
      'id': 'chores',
      'name': 'Chores',
      'icon': 'task_alt',
      'color': '#43A047',
      'fields': [
        {
          'key': 'title',
          'type': 'text',
          'label': 'Title',
          'required': true,
          'primary': true,
        },
        {
          'key': 'done',
          'type': 'checkbox',
          'label': 'Done',
          'role': 'completion',
        },
      ],
      'view': {'kind': 'checklist'},
      'updatedAt': '2026-03-01T00:00:00.000Z',
    });
    ListItem item(String id, {required bool done, required int minute}) =>
        ListItem.fromJson({
          'id': id,
          'listId': 'chores',
          'values': {'title': id, 'done': done},
          'createdAt':
              '2026-03-01T00:${minute.toString().padLeft(2, '0')}:00.000Z',
          'updatedAt': '2026-03-01T00:00:00.000Z',
        });
    final List<ListItem> items = [
      item('new-open', done: false, minute: 1),
      item('ticked', done: true, minute: 2),
      item('old-open', done: false, minute: 0),
    ];

    Future<void> open(WidgetTester tester, TickedItems ticked) async {
      await _pumpApp(
        tester,
        lists: [checklist],
        items: items,
        stored: {
          AccountPreferencesCubit.mirrorKey(testUser.uid):
              '{"tickedItems":"${ticked.wire}"}',
        },
      );
      await tester.tap(_hub);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('launcher-note-chores')));
      await settle(tester);
    }

    double y(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    testWidgets('Move to Done: a Done group at the end', (tester) async {
      await open(tester, TickedItems.moveToDone);
      expect(find.textContaining('DONE'), findsOneWidget);
      expect(y(tester, 'ticked'), greaterThan(y(tester, 'old-open')));
      expect(y(tester, 'ticked'), greaterThan(y(tester, 'new-open')));
    });

    testWidgets('Stay in place: no group, and in its own order', (
      tester,
    ) async {
      await open(tester, TickedItems.stayInPlace);
      expect(find.textContaining('DONE'), findsNothing);
      // Newest first, ticked or not.
      expect(y(tester, 'ticked'), lessThan(y(tester, 'new-open')));
      expect(y(tester, 'new-open'), lessThan(y(tester, 'old-open')));
    });

    testWidgets('Hide: folded under Done; a tap shows them', (tester) async {
      await open(tester, TickedItems.hide);
      expect(find.text('ticked'), findsNothing);
      expect(find.text('new-open'), findsOneWidget);
      final Finder fold = find.textContaining('DONE');
      expect(fold, findsOneWidget);

      await tester.tap(fold);
      await settle(tester);
      expect(find.text('ticked'), findsOneWidget);

      await tester.tap(fold);
      await settle(tester);
      expect(find.text('ticked'), findsNothing);
    });
  });

  group('confirm before deleting', () {
    Future<void> deleteFirstItem(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
    }

    final ListDefinition list = _list('l', 'Plain');
    ListItem row(String id) => ListItem.fromJson({
      'id': id,
      'listId': 'l',
      'values': {'title': id},
      'createdAt': '2026-03-01T00:00:00.000Z',
      'updatedAt': '2026-03-01T00:00:00.000Z',
    });

    Future<FirestoreListStore> open(WidgetTester tester) async {
      final FirestoreListStore store = await _pumpApp(
        tester,
        lists: [list],
        items: [row('milk')],
      );
      await tester.tap(_hub);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('launcher-note-l')));
      await settle(tester);
      return store;
    }

    testWidgets('off: an item goes at once', (tester) async {
      final FirestoreListStore store = await open(tester);
      await deleteFirstItem(tester);
      await settle(tester);
      expect(find.byKey(const ValueKey('confirm-delete-yes')), findsNothing);
      expect(store.current.itemsOf('l'), isEmpty);
    });

    testWidgets('on: asks, naming it; Cancel keeps it, Delete removes it', (
      tester,
    ) async {
      final FirestoreListStore store = await open(tester);
      await _account(tester).setConfirmDelete(true);
      await deleteFirstItem(tester);
      expect(find.text('Delete “milk”?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('confirm-delete-cancel')));
      await settle(tester);
      expect(store.current.itemsOf('l'), hasLength(1));

      await deleteFirstItem(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-delete-yes')));
      await settle(tester);
      expect(store.current.itemsOf('l'), isEmpty);
    });
  });

  group('the banner', () {
    Future<void> openEditor(WidgetTester tester) async {
      await tester.tap(_hub);
      await tester.pump();
      await tester.longPress(find.byKey(const ValueKey('launcher-note-l')));
      await tester.pumpAndSettle();
    }

    final Finder banner = find.byKey(const ValueKey('app-banner'));
    final Finder deleteList = find.byKey(const ValueKey('delete-list'));

    testWidgets('slides up with no fade, clear of the hub; Undo restores', (
      tester,
    ) async {
      final FirestoreListStore store = await _pumpApp(
        tester,
        lists: [_list('l', 'Plain')],
      );
      await openEditor(tester);
      await tester.ensureVisible(deleteList);
      await tester.pumpAndSettle();
      await tester.tap(deleteList);
      await settle(tester);

      expect(find.byType(SnackBar), findsNothing);
      expect(banner, findsOneWidget);
      expect(find.text('List deleted'), findsOneWidget);
      expect(
        find.ancestor(of: banner, matching: find.byType(FadeTransition)),
        findsNothing,
      );
      expect(
        tester.getBottomLeft(banner).dy,
        lessThan(tester.getTopLeft(_hub).dy),
      );

      await tester.tap(find.byKey(const ValueKey('app-banner-action')));
      await settle(tester);
      expect(store.current.definition('l'), isNotNull);
      expect(banner, findsNothing);
    });

    testWidgets('goes by itself', (tester) async {
      await _pumpApp(tester, lists: [_list('l', 'Plain')]);
      await openEditor(tester);
      await tester.ensureVisible(deleteList);
      await tester.pumpAndSettle();
      await tester.tap(deleteList);
      await settle(tester);
      expect(banner, findsOneWidget);

      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(banner, findsNothing);
    });

    testWidgets('a list with confirm on: Cancel stays in the editor', (
      tester,
    ) async {
      final FirestoreListStore store = await _pumpApp(
        tester,
        lists: [_list('l', 'Plain')],
      );
      await _account(tester).setConfirmDelete(true);
      await openEditor(tester);
      await tester.ensureVisible(deleteList);
      await tester.pumpAndSettle();
      await tester.tap(deleteList);
      await tester.pumpAndSettle();
      expect(find.text('Delete “Plain”?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('confirm-delete-cancel')));
      await tester.pumpAndSettle();
      expect(deleteList, findsOneWidget);
      expect(store.current.definition('l'), isNotNull);

      await tester.tap(deleteList);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-delete-yes')));
      await settle(tester);
      expect(store.current.definition('l'), isNull);
      expect(banner, findsOneWidget);
    });
  });

  group('vibration', () {
    testWidgets('the dial clicks only when it is on', (tester) async {
      final List<String> haptics = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.method);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pumpApp(tester);

      Future<void> sweep() async {
        final TestGesture gesture = await tester.startGesture(
          tester.getCenter(_hub),
        );
        await tester.pump(const Duration(milliseconds: 100));
        for (int i = 1; i <= 8; i++) {
          await gesture.moveBy(const Offset(-30, -30));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await gesture.moveTo(tester.getCenter(_hub));
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.up();
        await settle(tester);
      }

      await sweep();
      expect(haptics, isNotEmpty);

      haptics.clear();
      await _account(tester).setVibration(false);
      await tester.pump();
      await sweep();
      expect(haptics, isEmpty);
    });
  });

  group('show the AI bar', () {
    final Finder bar = find.byKey(const ValueKey('ai-bar'), skipOffstage: true);

    Widget withAi(Widget app) =>
        RepositoryProvider<AiService>.value(value: _NoAi(), child: app);

    testWidgets('off: no bar and no Describe; on: back', (tester) async {
      await _pumpApp(tester, wrap: withAi);
      expect(bar, findsOneWidget);

      await _account(tester).setShowAiBar(false);
      await tester.pumpAndSettle();
      expect(bar, findsNothing);

      await _account(tester).setShowAiBar(true);
      await tester.pumpAndSettle();
      expect(bar, findsOneWidget);
    });
  });

  group('time format', () {
    final DateTime afternoon = DateTime(2026, 3, 1, 15, 5);

    test('follows the language, or is fixed', () {
      expect(
        timeFormat('en', TimeFormat.followLanguage).format(afternoon),
        contains('3:05'),
      );
      expect(timeFormat('en', TimeFormat.h24).format(afternoon), '15:05');
      expect(
        timeFormat('de', TimeFormat.h12).format(afternoon),
        contains('3:05'),
      );
      expect(timeFormat('de', TimeFormat.h24).format(afternoon), '15:05');
    });

    test('with a date', () {
      expect(
        dateTimeFormat('en', TimeFormat.h24).format(afternoon),
        allOf(contains('Mar 1, 2026'), contains('15:05')),
      );
      expect(
        dateTimeFormat('en', TimeFormat.h12).format(afternoon),
        allOf(contains('Mar 1, 2026'), contains('3:05')),
      );
    });

    // The real picker at 15:05: 12 hours shows 3 and AM and PM, 24 shows 15,
    // and the labels stay translated.
    Future<void> openPicker(
      WidgetTester tester,
      TimeFormat format,
      Locale locale, {
      bool phoneUses24Hours = false,
    }) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(alwaysUse24HourFormat: phoneUses24Hours),
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [
              Locale('en'),
              Locale('de'),
              Locale('es'),
              Locale('fr'),
              Locale('ja'),
              Locale('zh'),
            ],
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 15, minute: 5),
                  builder: (context, child) =>
                      timePickerIn(format, context, child),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
    }

    const Map<String, String> cancelLabels = {
      'en': 'Cancel',
      'de': 'Abbrechen',
      'es': 'Cancelar',
      'fr': 'Annuler',
      'ja': 'キャンセル',
      'zh': '取消',
    };

    MaterialLocalizations pickerLabels(WidgetTester tester) =>
        MaterialLocalizations.of(tester.element(find.byType(TimePickerDialog)));

    for (final MapEntry(key: String language, value: String cancel)
        in cancelLabels.entries) {
      testWidgets('12 hours in $language: the picker shows 3 and PM', (
        tester,
      ) async {
        await openPicker(tester, TimeFormat.h12, Locale(language));
        expect(find.text('3'), findsWidgets);
        expect(find.text('15'), findsNothing);
        expect(find.text(cancel), findsOneWidget);
        expect(
          find.text(pickerLabels(tester).postMeridiemAbbreviation),
          findsOneWidget,
        );
        expect(
          find.text(pickerLabels(tester).anteMeridiemAbbreviation),
          findsOneWidget,
        );
      });

      testWidgets('24 hours in $language: the picker shows 15, no PM', (
        tester,
      ) async {
        await openPicker(tester, TimeFormat.h24, Locale(language));
        expect(find.text('15'), findsWidgets);
        expect(find.text(cancel), findsOneWidget);
        expect(
          find.text(pickerLabels(tester).postMeridiemAbbreviation),
          findsNothing,
        );
      });
    }

    testWidgets('12 hours wins over a phone set to 24 hours', (tester) async {
      await openPicker(
        tester,
        TimeFormat.h12,
        const Locale('en'),
        phoneUses24Hours: true,
      );
      expect(find.text('3'), findsWidgets);
      expect(find.text('PM'), findsOneWidget);
    });

    testWidgets("Follow the language keeps the language's own", (tester) async {
      await openPicker(tester, TimeFormat.followLanguage, const Locale('de'));
      expect(find.text('15'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await openPicker(tester, TimeFormat.followLanguage, const Locale('en'));
      expect(find.text('3'), findsWidgets);
      expect(find.text('PM'), findsOneWidget);
    });
  });

  group('week start', () {
    Future<int> firstDay(
      WidgetTester tester,
      WeekStart start,
      Locale locale,
    ) async {
      late int found;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [
            Locale('en'),
            Locale('de'),
            Locale('es'),
            Locale('fr'),
            Locale('ja'),
            Locale('zh'),
          ],
          home: Builder(
            builder: (context) => datePickerIn(
              start,
              context,
              Builder(
                builder: (inner) {
                  found = MaterialLocalizations.of(inner).firstDayOfWeekIndex;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return found;
    }

    testWidgets('Monday and Sunday win in every language, and the text stays', (
      tester,
    ) async {
      for (final String language in ['en', 'de', 'es', 'fr', 'ja', 'zh']) {
        final Locale locale = Locale(language);
        expect(
          await firstDay(tester, WeekStart.monday, locale),
          1,
          reason: language,
        );
        expect(
          await firstDay(tester, WeekStart.sunday, locale),
          0,
          reason: language,
        );
      }
    });

    testWidgets('Follow the language keeps its own', (tester) async {
      expect(
        await firstDay(tester, WeekStart.followLanguage, const Locale('de')),
        1,
      );
      expect(
        await firstDay(tester, WeekStart.followLanguage, const Locale('en')),
        0,
      );
    });
  });
}

class _NoAi implements AiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
