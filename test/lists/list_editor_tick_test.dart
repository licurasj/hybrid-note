// Removing and adding back a list's tick in the editor (T-23 unit 3, Q-103).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_editor_screen.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_patch.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

final DateTime _t0 = DateTime.utc(2026, 3, 1, 9);

ListItem _item(ListDefinition list, String id, Map<String, dynamic> values) =>
    ListItem(id: id, listId: list.id, values: values, createdAt: _t0, updatedAt: _t0);

// Opens the editor on [definition] and returns what Save hands back.
Future<Future<ListEditorOutcome?> Function()> _pumpEditor(
  WidgetTester tester,
  ListDefinition definition,
  List<ListItem> items,
) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late Future<ListEditorOutcome?> outcome;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () {
            outcome = Navigator.of(context).push<ListEditorOutcome>(
              MaterialPageRoute(
                builder: (_) => ListEditorScreen(definition: definition, items: items),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  return () => outcome;
}

Future<ListEditorOutcome> _save(WidgetTester tester, Future<ListEditorOutcome?> outcome) async {
  final IconButton save = tester.widget<IconButton>(find.byKey(const ValueKey('save-list')));
  expect(save.onPressed, isNotNull, reason: 'Save is enabled');
  await tester.tap(find.byKey(const ValueKey('save-list')));
  await tester.pumpAndSettle();
  return (await outcome)!;
}

void main() {
  testWidgets('Tasks: removing the tick saves; the checklist becomes a table and its rules go', (tester) async {
    final ListDefinition tasks = BuiltinTemplates.tasks();
    final Future<ListEditorOutcome?> Function() outcome = await _pumpEditor(tester, tasks, const []);
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('remove-field-done')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('editor-errors')), findsNothing);
    final String line = tester.widget<Text>(find.byKey(const ValueKey('no-tick-line'))).data!;
    expect(line, contains('items can no longer be ticked'));
    expect(line, contains('The checklist shows as Table.'));
    expect(line, contains('Clear completed items'));
    expect(line, contains('Repeat when cleared'));
    expect(line, isNot(contains('Next time')));

    final ListEditorOutcome saved = await _save(tester, outcome());
    final ListDefinition result = saved.result!.definition;
    expect(result.fieldWithRole(FieldRole.completion), isNull);
    expect(result.view.kind, ViewKind.table);
    expect(result.view.filterChipsBy, tasks.view.filterChipsBy);
    expect(result.behaviors, isEmpty);
    expect(result.validate(), isEmpty);
    expect(saved.ops.map((op) => op.kind), [
      PatchOpKind.removeField,
      PatchOpKind.removeBehavior,
      PatchOpKind.removeBehavior,
      PatchOpKind.setView,
    ]);
  });

  testWidgets('Grocery: removing the tick keeps Move all and the sections', (tester) async {
    final ListDefinition grocery = BuiltinTemplates.grocery();
    final Future<ListEditorOutcome?> Function() outcome = await _pumpEditor(tester, grocery, const []);
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('remove-field-done')));
    await tester.pumpAndSettle();

    final String line = tester.widget<Text>(find.byKey(const ValueKey('no-tick-line'))).data!;
    expect(line, isNot(contains('checklist')));
    expect(line, contains('Copying to Next time can only be added back by the AI.'));
    // Clear ticked cannot be turned on again without a tick.
    expect(
      tester.widget<SwitchListTile>(find.byKey(const ValueKey('rule-clearCompleted'))).onChanged,
      isNull,
    );

    final ListDefinition result = (await _save(tester, outcome())).result!.definition;
    expect(result.view.kind, ViewKind.sectioned);
    expect(result.behaviors.map((rule) => rule.kind), [BehaviorKind.moveAll]);
    expect(result.validate(), isEmpty);
  });

  testWidgets('a list that lost its tick gets it back, with its ticks, by adding a checkbox', (tester) async {
    final ListDefinition tasks = BuiltinTemplates.tasks();
    final List<ListItem> items = [
      _item(tasks, 'a', {'title': 'Call', 'done': true}),
      _item(tasks, 'b', {'title': 'Write', 'done': false}),
    ];
    // Saved once without the tick: the ticks stay on the items.
    final ListPatchResult without = ListPatch.apply(tasks, items, [
      ListPatchOp(PatchOpKind.removeField, {'key': 'done'}),
      ListPatchOp(PatchOpKind.removeBehavior, {'kind': 'clearCompleted'}),
      ListPatchOp(PatchOpKind.removeBehavior, {'kind': 'recurOnClear'}),
      ListPatchOp(PatchOpKind.setView, {'view': {'kind': 'table'}}),
    ], _t0);
    expect(without.isValid, isTrue);
    expect(items.first.values['done'], isTrue);

    final Future<ListEditorOutcome?> Function() outcome =
        await _pumpEditor(tester, without.definition, items);
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('no-tick-line')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('add-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('new-field-name')), 'Done');
    await tester.tap(find.byKey(const ValueKey('new-field-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checkbox').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final ListDefinition result = (await _save(tester, outcome())).result!.definition;
    final FieldDefinition tick = result.fieldWithRole(FieldRole.completion)!;
    expect(tick.key, 'done');
    expect(result.behaviors.map((rule) => rule.kind), [BehaviorKind.clearCompleted]);
    expect(ListRules.isCompleted(result, items.first), isTrue);
    expect(ListRules.isCompleted(result, items.last), isFalse);
  });
}
