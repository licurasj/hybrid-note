// Home's Today rows after T-23 unit 5: the × clears with Undo (Q-101), a list
// with no tick has no circle (Q-104) and its rows' × takes an item off home
// (Q-107); and the editor's "Suggest on home" (Q-106).
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/home_screen.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_editor_screen.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

import 'support/fake_auth.dart';
import 'support/firestore_store.dart';

final DateTime _now = DateTime.now();
final DateTime _today = DateTime(_now.year, _now.month, _now.day);

ListItem _task(String id, String title, DateTime at, {bool? done}) => ListItem(
  id: id,
  listId: BuiltinTemplates.tasksId,
  values: {
    'title': title,
    'done': ?done,
    'reminderAt': at.toIso8601String(),
  },
  createdAt: _today,
  updatedAt: _today,
);

// Tasks with its tick and the rules needing one removed, as the editor saves
// it (Q-103).
ListDefinition _untickable() {
  final Map<String, dynamic> json = BuiltinTemplates.tasks().toJson();
  json['fields'] = [
    for (final Map<String, dynamic> field
        in (json['fields'] as List).cast<Map<String, dynamic>>())
      if (field['key'] != 'done') field,
  ];
  json['behaviors'] = [];
  json['view'] = {'kind': ViewKind.table.wire};
  return ListDefinition.fromJson(json);
}

Future<FirestoreListStore> _pumpApp(
  WidgetTester tester,
  List<ListItem> items, {
  List<ListDefinition>? lists,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(const {});
  final FirestoreListStore store = await widgetTestStore(
    tester,
    items: items,
    lists: lists,
  );
  await tester.pumpWidget(
    await testApp(
      auth: FakeAuthService(user: testUser),
      openStore: (_) => store,
    ),
  );
  await settle(tester);
  return store;
}

Future<List<ListItem>> _itemsOf(WidgetTester tester, FirestoreListStore store) async =>
    (await tester.runAsync(() => store.watch().first))!.itemsOf(
      BuiltinTemplates.tasksId,
    );

void main() {
  test('an item taken off home is not a Today row; an untickable overdue one stays', () {
    final ListDefinition list = _untickable();
    final List<ListItem> items = [
      _task('late', 'Late', _today.subtract(const Duration(days: 3))),
      ListRules.setHiddenFromHome(
        _task('gone', 'Gone', _today.add(const Duration(hours: 9))),
        true,
        _today,
      ).saved.single,
    ];
    final List<HomeDueItem> due = homeDueItems(
      ListCatalog(definitions: [list], items: items),
      _today.add(const Duration(hours: 12)),
    );
    expect(due.map((entry) => entry.item.id), ['late']);
    expect(due.single.tickable, isFalse);
  });

  testWidgets('× on a ticked row shows "Cleared · Undo"; Undo brings it back', (
    tester,
  ) async {
    final FirestoreListStore store = await _pumpApp(tester, [
      _task('t', 'Submit', _today.add(const Duration(hours: 9)), done: true),
    ]);

    await tester.tap(find.byKey(const ValueKey('home-clear-t')));
    await settle(tester);
    expect(find.byKey(const ValueKey('home-due-t')), findsNothing);
    expect(find.text('Cleared'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-banner-action')));
    await settle(tester);
    expect(find.byKey(const ValueKey('home-due-t')), findsOneWidget);
    final ListItem back = (await _itemsOf(tester, store)).single;
    expect(back.id, 't');
    expect(back['done'], isTrue);
  });

  testWidgets('a list with no tick: no circle, and × takes the item off home with Undo', (
    tester,
  ) async {
    final FirestoreListStore store = await _pumpApp(
      tester,
      [_task('p', 'Pay rent', _today.subtract(const Duration(days: 2)))],
      lists: [_untickable()],
    );

    expect(find.byKey(const ValueKey('home-due-p')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-tick-p')), findsNothing);
    expect(find.byKey(const ValueKey('home-clear-p')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-hide-p')));
    await settle(tester);
    expect(find.byKey(const ValueKey('home-due-p')), findsNothing);
    expect(find.text('Hidden from home'), findsOneWidget);
    // Unchanged in its list but for the mark.
    final ListItem hidden = (await _itemsOf(tester, store)).single;
    expect(hidden['title'], 'Pay rent');
    expect(ListRules.isHiddenFromHome(hidden), isTrue);

    await tester.tap(find.byKey(const ValueKey('app-banner-action')));
    await settle(tester);
    expect(find.byKey(const ValueKey('home-due-p')), findsOneWidget);
    expect(ListRules.isHiddenFromHome((await _itemsOf(tester, store)).single), isFalse);
  });

  group('Suggest on home in the editor (Q-106)', () {
    Future<AccountPreferencesCubit> pumpEditor(
      WidgetTester tester, {
      Map<String, Object> stored = const {},
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(stored);
      final AccountPreferencesCubit preferences = AccountPreferencesCubit(
        await SharedPreferences.getInstance(),
        'test-user',
      );
      addTearDown(preferences.close);
      await tester.pumpWidget(
        BlocProvider<AccountPreferencesCubit>.value(
          value: preferences,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<ListEditorOutcome>(
                    builder: (_) => ListEditorScreen(definition: BuiltinTemplates.grocery()),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return preferences;
    }

    SwitchListTile suggest(WidgetTester tester) =>
        tester.widget<SwitchListTile>(find.byKey(const ValueKey('suggest-on-home')));

    testWidgets('off and saved, it is the same value as Remove on a suggested card', (
      tester,
    ) async {
      final AccountPreferencesCubit preferences = await pumpEditor(tester);
      expect(suggest(tester).value, isTrue);

      await tester.tap(find.byKey(const ValueKey('suggest-on-home')));
      await tester.pumpAndSettle();
      expect(suggest(tester).value, isFalse);
      expect(preferences.state.homeRemoved, isEmpty, reason: 'only on Save');

      await tester.tap(find.byKey(const ValueKey('save-list')));
      await tester.pumpAndSettle();
      expect(preferences.state.homeRemoved, [BuiltinTemplates.groceryId]);
    });

    testWidgets('greyed with a line while Show suggestions is off', (tester) async {
      final AccountPreferencesCubit preferences = await pumpEditor(tester);
      await preferences.setHomeSuggestions(false);
      await tester.pumpAndSettle();

      expect(suggest(tester).onChanged, isNull);
      expect(find.text('Suggestions are off in Preferences.'), findsOneWidget);
    });
  });
}
