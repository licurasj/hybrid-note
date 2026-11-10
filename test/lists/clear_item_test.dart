// The × on ticked items and the clear banners on the list page (T-23 unit 2,
// Q-101, Q-102).
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/app_banner.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/generic_list_host.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_store.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

import '../support/firestore_store.dart';

final DateTime _t0 = DateTime.utc(2026, 3, 1, 9);

ListItem _grocery(String id, String title, {bool done = false, String section = 'current'}) =>
    ListItem(
      id: id,
      listId: BuiltinTemplates.groceryId,
      values: {'title': title, 'done': done, 'section': section},
      createdAt: _t0,
      updatedAt: _t0,
    );

Future<(FirestoreListStore, AppBannerController)> _pump(
  WidgetTester tester,
  List<ListItem> items, {
  List<ListDefinition>? lists,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final FirestoreListStore store = await widgetTestStore(tester, items: items, lists: lists);
  final AppBannerController banners = AppBannerController();
  addTearDown(banners.dispose);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ListStore>.value(value: store),
        RepositoryProvider<AppBannerController>.value(value: banners),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => AppBannerHost(controller: banners, child: child!),
        home: const GenericListHost(listId: BuiltinTemplates.groceryId),
      ),
    ),
  );
  await settle(tester);
  return (store, banners);
}

Finder _x(String id) => find.byKey(ValueKey('clear-item-$id'));
Finder _slot(String id) => find.byKey(ValueKey('clear-slot-$id'));

void main() {
  testWidgets('a ticked item has a ×, an open one none, and the dots have no Clear', (tester) async {
    await _pump(tester, [_grocery('milk', 'Milk', done: true), _grocery('eggs', 'Eggs')]);

    expect(_x('milk'), findsOneWidget);
    expect(_x('eggs'), findsNothing);
    expect(tester.getSize(_slot('eggs')).width, 0);

    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
    expect(find.text('Clear'), findsNothing);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('a list without the Clear ticked rule shows no ×', (tester) async {
    final Map<String, dynamic> json = BuiltinTemplates.grocery().toJson();
    json['behaviors'] = [
      for (final Map<String, dynamic> behavior in (json['behaviors'] as List).cast<Map<String, dynamic>>())
        if (behavior['kind'] != BehaviorKind.clearCompleted.wire) behavior,
    ];
    final ListDefinition noClear = ListDefinition.fromJson(json);
    await _pump(
      tester,
      [_grocery('milk', 'Milk', done: true)],
      lists: [noClear],
    );

    expect(find.text('Milk'), findsOneWidget);
    expect(_x('milk'), findsNothing);
    expect(_slot('milk'), findsNothing);
  });

  testWidgets('× clears that item only, with "Cleared · Undo"; Undo brings it back', (tester) async {
    final (FirestoreListStore store, _) = await _pump(tester, [
      _grocery('milk', 'Milk', done: true),
      _grocery('bread', 'Bread', done: true),
    ]);

    await tester.tap(_x('milk'));
    await settle(tester);

    expect(find.text('Milk'), findsNothing);
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('Cleared'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-banner-action')));
    await settle(tester);

    expect(find.text('Milk'), findsOneWidget);
    expect(store.current.itemsOf(BuiltinTemplates.groceryId).map((item) => item.id).toSet(), {'milk', 'bread'});
  });

  testWidgets('Clear ticked (N) says how many were cleared', (tester) async {
    await _pump(tester, [
      _grocery('milk', 'Milk', done: true, section: 'nextTime'),
      _grocery('bread', 'Bread', done: true, section: 'nextTime'),
    ]);

    await tester.tap(find.byKey(const ValueKey('clear-ticked-button-nextTime')));
    await settle(tester);

    expect(find.text('2 cleared'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(AppBannerController.withActionFor);
    await tester.pumpAndSettle();
  });
}
