import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app_cubit.dart';
import 'package:hybrid_note/app_data.dart';
import 'package:hybrid_note/grocery_item.dart';
import 'package:hybrid_note/journal_entry.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/custom_lists.dart';
import 'package:hybrid_note/lists/generic_list_host.dart';
import 'package:hybrid_note/lists/local_list_store.dart';
import 'package:hybrid_note/task_item.dart';

import '../support/fakes.dart';

final DateTime _t0 = DateTime.utc(2026, 3, 1, 9);

Future<AppCubit> _pump(WidgetTester tester, AppData data, String listId) async {
  final FakeAppStorage storage = FakeAppStorage()..data = data;
  final AppCubit cubit = AppCubit(
    storage: storage,
    driveSyncService: FakeDriveSyncService(),
    deviceId: 'd',
  );
  await cubit.loadData();

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: cubit),
        BlocProvider(create: (_) => CustomListsCubit(FakeCustomListsStorage())..load()),
        LocalListStore.provider(),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GenericListHost(listId: listId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

GroceryItem _grocery(String id, String title, GrocerySection section, {bool done = false, bool autoAdd = false}) {
  return GroceryItem(
    id: id,
    title: title,
    description: '',
    section: section,
    isCompleted: done,
    autoAddToNext: autoAdd,
    createdAt: _t0,
    updatedAt: _t0,
  );
}

TaskItem _task(String id, String title, {String category = '', bool done = false, List<SubtaskItem> subtasks = const []}) {
  return TaskItem(
    id: id,
    title: title,
    description: '',
    isCompleted: done,
    category: category,
    subtasks: subtasks,
    reminderAt: null,
    repeatFrequency: RepeatFrequency.none,
    customRepeatDays: null,
    createdAt: _t0,
    updatedAt: _t0,
  );
}

void main() {
  testWidgets('grocery: sections, clear ticked copies auto-add items, move all', (tester) async {
    final AppCubit cubit = await _pump(
      tester,
      AppData.empty('d').copyWith(groceryItems: [
        _grocery('milk', 'Milk', GrocerySection.current, done: true, autoAdd: true),
        _grocery('eggs', 'Eggs', GrocerySection.current),
      ]),
      BuiltinTemplates.groceryId,
    );

    expect(find.text('CURRENT GROCERY RUN · 2'), findsOneWidget);
    expect(find.text('NEXT TIME · 0'), findsOneWidget);

    await tester.tap(find.textContaining('Clear Ticked'));
    await tester.pumpAndSettle();

    expect(cubit.state.data.groceryItems.map((i) => i.title), unorderedEquals(['Eggs', 'Milk']));
    final GroceryItem copy = cubit.state.data.groceryItems.firstWhere((i) => i.title == 'Milk');
    expect(copy.section, GrocerySection.nextTime);
    expect(copy.isCompleted, isFalse);
    expect(find.text('NEXT TIME · 1'), findsOneWidget);

    // The move-all button sits on the Next Time header and points to the current run.
    await tester.tap(find.widgetWithIcon(TextButton, Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(cubit.state.data.groceryItems.every((i) => i.section == GrocerySection.current), isTrue);
    await cubit.close();
  });

  testWidgets('tasks: filter chips, tick, sub-items, clear completed', (tester) async {
    final AppCubit cubit = await _pump(
      tester,
      AppData.empty('d').copyWith(
        categories: [AppData.defaultCategory, 'Home', 'Work'],
        tasks: [
          _task('t1', 'Rent', category: 'Home', subtasks: [
            SubtaskItem(id: 's1', title: 'Check balance', isCompleted: false, createdAt: _t0, updatedAt: _t0),
          ]),
          _task('t2', 'Report', category: 'Work'),
        ],
      ),
      BuiltinTemplates.tasksId,
    );

    expect(find.text('All 2'), findsOneWidget);
    await tester.tap(find.text('Work 1'));
    await tester.pumpAndSettle();
    expect(find.text('Rent'), findsNothing);
    expect(find.text('Report'), findsOneWidget);

    await tester.tap(find.text('All 2'));
    await tester.pumpAndSettle();

    // Sub-items unfold under their row.
    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check balance'));
    await tester.pumpAndSettle();
    expect(
      cubit.state.data.tasks.firstWhere((t) => t.id == 't1').subtasks.single.isCompleted,
      isTrue,
    );

    // Tick Report, then clear completed from the app bar.
    final Finder reportCard = find.byKey(const ValueKey('item-t2'));
    await tester.tap(find.descendant(of: reportCard, matching: find.byType(Checkbox)));
    await tester.pumpAndSettle();
    expect(cubit.state.data.tasks.firstWhere((t) => t.id == 't2').isCompleted, isTrue);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(cubit.state.data.tasks.map((t) => t.id), ['t1']);
    expect(cubit.state.data.taskTombstones.map((t) => t.id), ['t2']);
    await cubit.close();
  });

  testWidgets('tasks: adding with a new category creates the category', (tester) async {
    final AppCubit cubit = await _pump(tester, AppData.empty('d'), BuiltinTemplates.tasksId);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-title')), 'Water plants');
    await tester.tap(find.byTooltip('Create Category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Category name'), 'Garden');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(cubit.state.data.tasks.single.category, 'Garden');
    expect(cubit.state.data.categories, contains('Garden'));
    expect(find.text('Garden 1'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('journal: grouped by year and month, newest first', (tester) async {
    final AppCubit cubit = await _pump(
      tester,
      AppData.empty('d').copyWith(journalEntries: [
        JournalEntry(id: 'a', title: 'Spring', body: 'Warm', createdAt: DateTime(2026, 4, 2, 12), updatedAt: _t0),
        JournalEntry(id: 'b', title: 'Winter', body: '', createdAt: DateTime(2025, 12, 24, 12), updatedAt: _t0),
      ]),
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
    await cubit.close();
  });
}
