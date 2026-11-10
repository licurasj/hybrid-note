// Ticked items act the same in every layout (T-24 unit 2, Q-109), and Clear
// straight away (Q-119).
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/app/app_banner.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/generic_list_host.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_store.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

import '../support/firestore_store.dart';

final DateTime _t0 = DateTime.utc(2026, 3, 1, 9);

ListDefinition _list(Map<String, dynamic> view) => ListDefinition.fromJson({
  'id': 'list-test',
  'name': 'Test',
  'icon': 'list',
  'color': '#43A047',
  'fields': [
    {'key': 'title', 'type': 'text', 'label': 'Title', 'required': true, 'primary': true},
    {'key': 'done', 'type': 'checkbox', 'label': 'Done', 'role': 'completion'},
    {
      'key': 'kind',
      'type': 'enum',
      'label': 'Kind',
      'options': [
        {'value': 'a', 'label': 'Alpha'},
        {'value': 'b', 'label': 'Beta'},
      ],
    },
  ],
  'view': view,
  'behaviors': [
    {'kind': 'clearCompleted'},
  ],
  'updatedAt': _t0.toIso8601String(),
});

final Map<ViewKind, Map<String, dynamic>> _views = {
  ViewKind.checklist: {'kind': 'checklist'},
  ViewKind.table: {'kind': 'table'},
  ViewKind.cards: {'kind': 'cards'},
  ViewKind.grouped: {'kind': 'grouped', 'groupBy': 'kind'},
  ViewKind.sectioned: {'kind': 'sectioned', 'sectionBy': 'kind'},
  ViewKind.timeline: {'kind': 'timeline', 'dateField': 'createdAt', 'timelineGrouping': 'month'},
};

ListItem _item(String id, String title, {bool done = false}) => ListItem(
  id: id,
  listId: 'list-test',
  values: {'title': title, 'done': done, 'kind': 'a'},
  createdAt: _t0,
  updatedAt: _t0,
);

Future<(FirestoreListStore, AccountPreferencesCubit)> _pump(
  WidgetTester tester,
  ListDefinition list,
  TickedItems ticked,
  List<ListItem> items,
) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final FirestoreListStore store = await widgetTestStore(tester, lists: [list], items: items);
  SharedPreferences.setMockInitialValues({});
  final AccountPreferencesCubit preferences = AccountPreferencesCubit(
    await SharedPreferences.getInstance(),
    'test-user',
  );
  addTearDown(preferences.close);
  await preferences.setTickedItems(ticked);
  final AppBannerController banners = AppBannerController();
  addTearDown(banners.dispose);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ListStore>.value(value: store),
        RepositoryProvider<AppBannerController>.value(value: banners),
      ],
      child: BlocProvider<AccountPreferencesCubit>.value(
        value: preferences,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => AppBannerHost(controller: banners, child: child!),
          home: const GenericListHost(listId: 'list-test'),
        ),
      ),
    ),
  );
  await settle(tester);
  return (store, preferences);
}

double _top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

void main() {
  for (final MapEntry<ViewKind, Map<String, dynamic>> view in _views.entries) {
    group('${view.key.wire}:', () {
      final List<ListItem> items = [
        _item('open', 'Open one'),
        _item('ticked', 'Ticked one', done: true),
      ];

      testWidgets('Move to the bottom puts ticked items in an open Done group last', (tester) async {
        await _pump(tester, _list(view.value), TickedItems.moveToDone, items);
        expect(find.text('DONE · 1'), findsOneWidget);
        expect(find.text('Ticked one'), findsOneWidget);
        expect(_top(tester, 'Ticked one'), greaterThan(_top(tester, 'DONE · 1')));
        expect(_top(tester, 'DONE · 1'), greaterThan(_top(tester, 'Open one')));
      });

      testWidgets('Stay in place has no Done group', (tester) async {
        await _pump(tester, _list(view.value), TickedItems.stayInPlace, items);
        expect(find.textContaining('DONE'), findsNothing);
        expect(find.text('Ticked one'), findsOneWidget);
      });

      testWidgets('Fold away keeps them in a closed Done group at the bottom', (tester) async {
        await _pump(tester, _list(view.value), TickedItems.hide, items);
        expect(find.text('Ticked one'), findsNothing);
        expect(find.text('DONE · 1'), findsOneWidget);
        await tester.tap(find.text('DONE · 1'));
        await tester.pumpAndSettle();
        expect(find.text('Ticked one'), findsOneWidget);
      });
    });
  }

  testWidgets('Clear straight away: a tick clears the item with Undo, which brings it back unticked', (
    tester,
  ) async {
    final (FirestoreListStore store, _) = await _pump(
      tester,
      _list(_views[ViewKind.checklist]!),
      TickedItems.clearAtOnce,
      [_item('open', 'Open one')],
    );

    await tester.tap(find.byType(Checkbox).first);
    await settle(tester);
    expect(find.text('Open one'), findsNothing);
    expect(find.text('Cleared'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-banner-action')));
    await settle(tester);
    expect(find.text('Open one'), findsOneWidget);
    final ListItem back = store.current.itemsOf('list-test').single;
    expect(back['done'], isFalse);
  });

  testWidgets('Clear straight away on a list without the Clear ticked rule: just a tick (Q-124)', (
    tester,
  ) async {
    final Map<String, dynamic> json = _list(_views[ViewKind.checklist]!).toJson()
      ..['behaviors'] = <Object>[];
    final (FirestoreListStore store, _) = await _pump(
      tester,
      ListDefinition.fromJson(json),
      TickedItems.clearAtOnce,
      [_item('open', 'Open one')],
    );

    await tester.tap(find.byType(Checkbox).first);
    await settle(tester);
    expect(find.text('Open one'), findsOneWidget);
    expect(find.text('Cleared'), findsNothing);
    expect(store.current.itemsOf('list-test').single['done'], isTrue);
  });

  testWidgets('Sections: Clear ticked still counts the ticked ones moved to Done', (tester) async {
    await _pump(
      tester,
      _list(_views[ViewKind.sectioned]!),
      TickedItems.moveToDone,
      [_item('open', 'Open one'), _item('ticked', 'Ticked one', done: true)],
    );
    expect(find.text('Clear Ticked (1 ticked)'), findsOneWidget);
  });

  testWidgets("a list's own choice wins over Preferences (Q-117)", (tester) async {
    final Map<String, dynamic> json = _list(_views[ViewKind.table]!).toJson()
      ..['tickedItems'] = 'hide';
    final (_, AccountPreferencesCubit preferences) = await _pump(
      tester,
      ListDefinition.fromJson(json),
      TickedItems.moveToDone,
      [_item('open', 'Open one'), _item('ticked', 'Ticked one', done: true)],
    );
    expect(find.text('Ticked one'), findsNothing);
    expect(find.text('DONE · 1'), findsOneWidget);

    // Lists can have their own off: it follows Preferences again.
    await preferences.setListsOwnTickedItems(false);
    await tester.pumpAndSettle();
    expect(find.text('Ticked one'), findsOneWidget);
  });
}
