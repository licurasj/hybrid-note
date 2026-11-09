import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/generic_list_host.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_store.dart';

import '../support/firestore_store.dart';

final DateTime _t0 = DateTime.utc(2026, 3, 1, 9);

Future<FirestoreListStore> _pump(
  WidgetTester tester,
  List<ListItem> items,
  String listId, {
  List<ListDefinition>? lists,
}) async {
  final FirestoreListStore store = await widgetTestStore(tester, lists: lists, items: items);

  await tester.pumpWidget(
    RepositoryProvider<ListStore>.value(
      value: store,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GenericListHost(listId: listId),
      ),
    ),
  );
  await settle(tester);
  return store;
}

ListItem _grocery(String id, String title, String section, {bool done = false, bool autoAdd = false}) {
  return ListItem(
    id: id,
    listId: BuiltinTemplates.groceryId,
    values: {'title': title, 'description': '', 'section': section, 'done': done, 'autoAddToNext': autoAdd},
    createdAt: _t0,
    updatedAt: _t0,
  );
}

ListItem _task(String id, String title, {String? category, List<Map<String, dynamic>> subtasks = const []}) {
  return ListItem(
    id: id,
    listId: BuiltinTemplates.tasksId,
    values: {
      'title': title,
      'description': '',
      'done': false,
      'category': ?category,
      'subtasks': subtasks,
      'repeat': {'frequency': 'none'},
    },
    createdAt: _t0,
    updatedAt: _t0,
  );
}

ListItem _entry(String id, String title, String body, DateTime createdAt) {
  return ListItem(
    id: id,
    listId: BuiltinTemplates.journalId,
    values: {'title': title, 'body': body},
    createdAt: createdAt,
    updatedAt: _t0,
  );
}

void main() {
  testWidgets('grocery: sections, clear ticked copies auto-add items, move all', (tester) async {
    final FirestoreListStore store = await _pump(
      tester,
      [
        _grocery('milk', 'Milk', 'current', done: true, autoAdd: true),
        _grocery('eggs', 'Eggs', 'current'),
      ],
      BuiltinTemplates.groceryId,
    );
    List<ListItem> groceries() => store.current.itemsOf(BuiltinTemplates.groceryId);

    expect(find.text('CURRENT GROCERY RUN · 2'), findsOneWidget);
    expect(find.text('NEXT TIME · 0'), findsOneWidget);

    await tester.tap(find.textContaining('Clear Ticked'));
    await settle(tester);

    expect(groceries().map((i) => i['title']), unorderedEquals(['Eggs', 'Milk']));
    final ListItem copy = groceries().firstWhere((i) => i['title'] == 'Milk');
    expect(copy['section'], 'nextTime');
    expect(copy['done'], isFalse);
    expect(find.text('NEXT TIME · 1'), findsOneWidget);

    // The move-all button sits on the Next Time header and points to the current run.
    await tester.tap(find.widgetWithIcon(TextButton, Icons.arrow_upward));
    await settle(tester);

    expect(groceries().every((i) => i['section'] == 'current'), isTrue);
  });

  testWidgets('tasks: filter chips, tick, sub-items, clear completed', (tester) async {
    final FirestoreListStore store = await _pump(
      tester,
      [
        _task('t1', 'Rent', category: 'Home', subtasks: [
          {'id': 's1', 'title': 'Check balance', 'done': false},
        ]),
        _task('t2', 'Report', category: 'Work'),
      ],
      BuiltinTemplates.tasksId,
      lists: starterLists(taskCategories: ['Home', 'Work']),
    );
    List<ListItem> tasks() => store.current.itemsOf(BuiltinTemplates.tasksId);

    expect(find.text('All 2'), findsOneWidget);
    await tester.tap(find.text('Work 1'));
    await settle(tester);
    expect(find.text('Rent'), findsNothing);
    expect(find.text('Report'), findsOneWidget);

    await tester.tap(find.text('All 2'));
    await settle(tester);

    // Sub-items unfold under their row.
    await tester.tap(find.text('Rent'));
    await settle(tester);
    await tester.tap(find.text('Check balance'));
    await settle(tester);
    expect(
      (tasks().firstWhere((t) => t.id == 't1')['subtasks'] as List).single['done'],
      isTrue,
    );

    // Tick Report, then clear completed from the app bar.
    final Finder reportCard = find.byKey(const ValueKey('item-t2'));
    await tester.tap(find.descendant(of: reportCard, matching: find.byType(Checkbox)));
    await settle(tester);
    expect(tasks().firstWhere((t) => t.id == 't2')['done'], isTrue);

    await tester.tap(find.byTooltip('Clear Ticked'));
    await settle(tester);
    expect(tasks().map((t) => t.id), ['t1']);
  });

  testWidgets('tasks: adding with a new category creates the category', (tester) async {
    final FirestoreListStore store = await _pump(tester, const [], BuiltinTemplates.tasksId);

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('field-title')), 'Water plants');
    await tester.tap(find.byTooltip('Create Category'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Category name'), 'Garden');
    await tester.tap(find.text('Create'));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(store.current.itemsOf(BuiltinTemplates.tasksId).single['category'], 'Garden');
    expect(
      store.current.definition(BuiltinTemplates.tasksId)!.field('category')!.options.map((o) => o.value),
      contains('Garden'),
    );
    expect(find.text('Garden 1'), findsOneWidget);
  });

  testWidgets('journal: grouped by year and month, newest first', (tester) async {
    await _pump(
      tester,
      [
        _entry('a', 'Spring', 'Warm', DateTime(2026, 4, 2, 12)),
        _entry('b', 'Winter', '', DateTime(2025, 12, 24, 12)),
      ],
      BuiltinTemplates.journalId,
    );

    expect(find.text('2026'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('APRIL'), findsOneWidget);
    expect(find.text('Spring'), findsOneWidget);
    // Older years start folded.
    expect(find.text('Winter'), findsNothing);
    expect(
      tester.getTopLeft(find.text('2026')).dy < tester.getTopLeft(find.text('2025')).dy,
      isTrue,
    );
  });

  testWidgets('a copy of a template under its own id gets the template texts', (tester) async {
    final ListDefinition copy = ListDefinition.fromJson({
      ...BuiltinTemplates.journal().toJson(),
      'id': 'list-dream-diary',
    });
    await _pump(tester, const [], copy.id, lists: [copy]);

    expect(find.text(_en.noJournalEntriesYet), findsOneWidget);
    expect(find.byTooltip(_en.addJournalEntryTooltip), findsOneWidget);
  });
}

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));
