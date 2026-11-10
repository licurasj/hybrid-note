import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_editor_screen.dart';
import 'package:hybrid_note/lists/list_error.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_labels.dart';
import 'package:hybrid_note/lists/list_rules.dart';

import '../support/editor_sections.dart';

final DateTime _then = DateTime.utc(2026, 10, 1);

ListDefinition _list(List<Map<String, dynamic>> fields, {List<Map<String, dynamic>> behaviors = const []}) {
  return ListDefinition.fromJson({
    'id': 'list-test',
    'name': 'Test',
    'icon': 'list',
    'color': '#43A047',
    'fields': [
      {'key': 'title', 'type': 'text', 'label': 'Title', 'required': true, 'primary': true},
      ...fields,
    ],
    'view': {'kind': 'checklist'},
    'behaviors': behaviors,
    'updatedAt': _then.toIso8601String(),
  });
}

const Map<String, dynamic> _done = {'key': 'done', 'type': 'checkbox', 'label': 'Done', 'role': 'completion'};

// Chores: a date and a repeat, ready for recurOnClear.
final ListDefinition _chores = _list([
  _done,
  {'key': 'due', 'type': 'dateTime', 'label': 'Due'},
  {'key': 'every', 'type': 'recurrence', 'label': 'Every'},
], behaviors: [
  {'kind': 'clearCompleted'},
]);

// Groceries: a section field with two options, ready for moveAll.
final ListDefinition _groceries = _list([
  _done,
  {
    'key': 'run',
    'type': 'enum',
    'label': 'Run',
    'options': [
      {'value': 'now', 'label': 'This run'},
      {'value': 'later', 'label': 'Next run'},
    ],
  },
]);

ListItem _item(String id, Map<String, dynamic> values) {
  return ListItem(id: id, listId: 'list-test', values: values, createdAt: _then, updatedAt: _then);
}

// Opens the editor on `definition` and returns a function that saves it and
// gives back what the editor handed to its caller.
Future<Future<ListEditorOutcome?> Function()> _openEditor(
  WidgetTester tester,
  ListDefinition definition, {
  List<ListItem> items = const [],
  String language = 'en',
}) async {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  ListEditorOutcome? outcome;
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            outcome = await Navigator.of(context).push<ListEditorOutcome>(
              MaterialPageRoute(builder: (_) => ListEditorScreen(definition: definition, items: items)),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await openEditorSections(tester);

  return () async {
    await tester.tap(find.byKey(const ValueKey('save-list')));
    await tester.pumpAndSettle();
    return outcome;
  };
}

Future<void> _pick(WidgetTester tester, String param, String choice) async {
  await tester.tap(find.byKey(ValueKey('rule-$param')));
  await tester.pumpAndSettle();
  // The choices open in place, under the picker (T-24).
  await tester.tap(
    find.descendant(of: find.byKey(ValueKey('rule-$param')), matching: find.text(choice)).last,
  );
  await tester.pumpAndSettle();
}

// The choice a rule picker shows.
Finder _shown(String param, String text) {
  return find.descendant(of: find.byKey(ValueKey('rule-$param')), matching: find.text(text));
}

Future<void> _openAddRule(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('add-rule')));
  await tester.pumpAndSettle();
}

FilledButton _addButton(WidgetTester tester) {
  return tester.widget<FilledButton>(find.byKey(const ValueKey('add-rule-confirm')));
}

void main() {
  testWidgets('adds "repeat when cleared" with the date and repeat fields', (tester) async {
    final List<ListItem> items = [
      _item('mop', {
        'title': 'Mop',
        'done': true,
        'due': DateTime(2026, 10, 20, 9).toIso8601String(),
        'every': {'frequency': 'weekly'},
      }),
      _item('dust', {'title': 'Dust', 'done': false}),
    ];
    final save = await _openEditor(tester, _chores, items: items);

    await _openAddRule(tester);
    // The first rule and the only fitting fields are picked already.
    expect(_shown('kind', 'Repeat when cleared'), findsOneWidget);
    expect(_shown('dateField', 'Due'), findsOneWidget);
    expect(_shown('recurrenceField', 'Every'), findsOneWidget);
    expect(find.byKey(const ValueKey('rule-errors')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('add-rule-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Date field: Due · Repeat field: Every'), findsOneWidget);
    final ListEditorOutcome? outcome = await save();

    expect(outcome!.ops.map((op) => op.toJson()), [
      {
        'op': 'addBehavior',
        'behavior': {'kind': 'recurOnClear', 'dateField': 'due', 'recurrenceField': 'every'},
      },
    ]);
    final ListDefinition saved = outcome.result!.definition;
    expect(saved.validate(), isEmpty);
    expect(saved.behaviors.map((behavior) => behavior.kind.wire), ['clearCompleted', 'recurOnClear']);

    // Clearing the ticked chore now brings it back a week later, unticked.
    final ListChanges cleared = ListRules.clearCompleted(saved, outcome.result!.items, DateTime(2026, 10, 21));
    expect(cleared.deletedIds, ['mop']);
    final ListItem next = cleared.saved.single;
    expect(next['title'], 'Mop');
    expect(next['done'], false);
    expect(DateTime.parse(next['due'] as String).toLocal(), DateTime(2026, 10, 27, 9));
  });

  testWidgets('adds "move all" with field, from and to', (tester) async {
    final List<ListItem> items = [
      _item('milk', {'title': 'Milk', 'run': 'later'}),
      _item('eggs', {'title': 'Eggs', 'run': 'now'}),
      _item('tea', {'title': 'Tea', 'run': 'later', 'done': true}),
    ];
    final save = await _openEditor(tester, _groceries, items: items);

    await _openAddRule(tester);
    await _pick(tester, 'kind', 'Move all button');
    // Starts on the first option; "to" never offers the "from" option.
    expect(_shown('field', 'Run'), findsOneWidget);
    expect(_shown('from', 'This run'), findsOneWidget);
    expect(_shown('to', 'Next run'), findsOneWidget);
    await _pick(tester, 'from', 'Next run');
    expect(_shown('to', 'This run'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-rule-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Run: Next run → This run'), findsOneWidget);
    final ListEditorOutcome? outcome = await save();

    expect(outcome!.ops.map((op) => op.toJson()), [
      {
        'op': 'addBehavior',
        'behavior': {'kind': 'moveAll', 'field': 'run', 'from': 'later', 'to': 'now'},
      },
    ]);
    final ListDefinition saved = outcome.result!.definition;
    expect(saved.validate(), isEmpty);

    // The button moves every "next run" item to this run, unticked.
    final ListChanges moved = ListRules.moveAll(
      saved,
      outcome.result!.items,
      saved.behaviors.single,
      DateTime(2026, 10, 21),
    );
    expect({for (final ListItem item in moved.saved) item.id: [item['run'], item['done']]}, {
      'milk': ['now', false],
      'tea': ['now', false],
    });
  });

  testWidgets('removing a rule is a removeBehavior op; the add button hides when both are there', (tester) async {
    final ListDefinition both = _list([
      _done,
      {'key': 'due', 'type': 'date', 'label': 'Due'},
      {'key': 'every', 'type': 'recurrence', 'label': 'Every'},
      {
        'key': 'run',
        'type': 'enum',
        'label': 'Run',
        'options': [
          {'value': 'now'},
          {'value': 'later'},
        ],
      },
    ], behaviors: [
      {'kind': 'recurOnClear', 'dateField': 'due', 'recurrenceField': 'every'},
      {'kind': 'moveAll', 'field': 'run', 'from': 'later', 'to': 'now'},
    ]);
    final save = await _openEditor(tester, both);
    expect(find.byKey(const ValueKey('add-rule')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('remove-rule-moveAll-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rule-moveAll-0')), findsNothing);
    expect(find.byKey(const ValueKey('add-rule')), findsOneWidget);

    final ListEditorOutcome? outcome = await save();
    expect(outcome!.ops.map((op) => op.toJson()), [
      {'op': 'removeBehavior', 'kind': 'moveAll'},
    ]);
    expect(outcome.result!.definition.behaviors.map((behavior) => behavior.kind.wire), ['recurOnClear']);
  });

  testWidgets('a stored list with two rules of one kind opens and lists both', (tester) async {
    // The schema allows repeated kinds, for example from a template or the AI.
    final ListDefinition twice = _list([
      _done,
      {
        'key': 'run',
        'type': 'enum',
        'label': 'Run',
        'options': [
          {'value': 'now', 'label': 'This run'},
          {'value': 'later', 'label': 'Next run'},
          {'value': 'someday', 'label': 'Someday'},
        ],
      },
    ], behaviors: [
      {'kind': 'moveAll', 'field': 'run', 'from': 'later', 'to': 'now'},
      {'kind': 'moveAll', 'field': 'run', 'from': 'someday', 'to': 'later'},
    ]);
    final save = await _openEditor(tester, twice);

    expect(tester.takeException(), isNull);
    expect(find.descendant(of: find.byKey(const ValueKey('rule-moveAll-0')), matching: find.text('Run: Next run → This run')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('rule-moveAll-1')), matching: find.text('Run: Someday → Next run')), findsOneWidget);

    // removeBehavior works by kind, so removing one removes both.
    await tester.tap(find.byKey(const ValueKey('remove-rule-moveAll-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rule-moveAll-0')), findsNothing);

    final ListEditorOutcome? outcome = await save();
    expect(outcome!.ops.map((op) => op.toJson()), [
      {'op': 'removeBehavior', 'kind': 'moveAll'},
    ]);
    expect(outcome.result!.definition.behaviors, isEmpty);
  });

  group('invalid choices show the translated error and cannot be added', () {
    for (final String language in ['en', 'de']) {
      testWidgets('a list without fitting fields ($language)', (tester) async {
        final ListDefinition plain = _list([]);
        await _openEditor(tester, plain, language: language);
        final ListLabels labels = ListLabels(lookupAppLocalizations(Locale(language)));
        String rendered(ListError error) => labels.error(error, plain);

        await _openAddRule(tester);
        final String recurErrors = tester.widget<Text>(find.byKey(const ValueKey('rule-errors'))).data!;
        expect(
          recurErrors,
          [
            const ListError(ListErrorCode.ruleNeedsCompletion, {'rule': 'recurOnClear'}),
            const ListError(ListErrorCode.ruleNeedsParam, {'rule': 'recurOnClear', 'param': 'dateField'}),
            const ListError(ListErrorCode.ruleNeedsParam, {'rule': 'recurOnClear', 'param': 'recurrenceField'}),
          ].map(rendered).join('\n'),
        );
        expect(_addButton(tester).onPressed, isNull);

        await _pick(tester, 'kind', labels.loc.ruleMoveAll);
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('rule-errors'))).data,
          rendered(const ListError(ListErrorCode.ruleNeedsParam, {'rule': 'moveAll', 'param': 'field'})),
        );
        expect(_addButton(tester).onPressed, isNull);
      });
    }

    testWidgets('a choice field with one option has nothing to move to', (tester) async {
      final ListDefinition oneOption = _list([
        {
          'key': 'run',
          'type': 'enum',
          'label': 'Run',
          'options': [
            {'value': 'now', 'label': 'This run'},
          ],
        },
      ]);
      await _openEditor(tester, oneOption);

      await _openAddRule(tester);
      await _pick(tester, 'kind', 'Move all button');
      expect(find.byKey(const ValueKey('rule-errors')), findsOneWidget);
      expect(_addButton(tester).onPressed, isNull);
    });
  });

  testWidgets('removing a field a rule uses keeps Save disabled with the error', (tester) async {
    await _openEditor(tester, _chores);

    await _openAddRule(tester);
    await tester.tap(find.byKey(const ValueKey('add-rule-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remove-field-every')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<IconButton>(find.byKey(const ValueKey('save-list'))).onPressed,
      isNull,
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('editor-errors'))).data,
      contains('"Repeat when cleared"'),
    );
  });
}
