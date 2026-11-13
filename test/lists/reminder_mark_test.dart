// T-13 unit 1: days with No time, the reminder mark on date fields, and the
// one field edit for existing fields (Q-91, Q-96, Q-128, Q-129).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/item_dates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_editor_screen.dart';
import 'package:hybrid_note/lists/list_error.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_patch.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

import '../support/editor_sections.dart';

final DateTime _now = DateTime.utc(2026, 3, 1, 9);

ListDefinition _withDue(FieldType type, {FieldRole? role}) => ListDefinition(
  formatVersion: 1,
  id: 'dates',
  name: 'Dates',
  icon: 'event',
  color: '#2E7D32',
  fields: [
    const FieldDefinition(key: 'title', type: FieldType.text, label: 'Title', primary: true),
    const FieldDefinition(key: 'done', type: FieldType.checkbox, label: 'Done', role: FieldRole.completion),
    FieldDefinition(key: 'due', type: type, label: 'Due', role: role),
    const FieldDefinition(
      key: 'kind',
      type: FieldType.choice,
      label: 'Kind',
      options: [FieldOption(value: 'a'), FieldOption(value: 'b')],
    ),
    const FieldDefinition(key: 'count', type: FieldType.counter, label: 'Count'),
  ],
  view: const ViewDefinition(kind: ViewKind.checklist),
  behaviors: const [],
  updatedAt: _now,
);

ListPatchResult _props(ListDefinition list, Map<String, dynamic> args) =>
    ListPatch.apply(list, const [], [ListPatchOp(PatchOpKind.setFieldProps, args)], _now);

void main() {
  group('ItemDates', () {
    test('a day alone has no time; a moment has one; a date field never', () {
      expect(ItemDates.isDayOnly('2026-03-05'), isTrue);
      expect(ItemDates.isDayOnly('2026-03-05T08:00:00.000Z'), isFalse);
      expect(ItemDates.hasTime(FieldType.dateTime, '2026-03-05'), isFalse);
      expect(ItemDates.hasTime(FieldType.dateTime, '2026-03-05T08:00:00.000Z'), isTrue);
      expect(ItemDates.hasTime(FieldType.date, '2026-03-05T08:00:00.000Z'), isFalse);
      expect(ItemDates.dayValue(DateTime(2026, 3, 5, 23, 30)), '2026-03-05');
      expect(ItemDates.local('2026-03-05'), DateTime(2026, 3, 5));
    });
  });

  group('the reminder role', () {
    test('fits a date and a date-and-time field, not others', () {
      expect(_withDue(FieldType.date, role: FieldRole.reminder).validate(), isEmpty);
      expect(_withDue(FieldType.dateTime, role: FieldRole.reminder).validate(), isEmpty);
      final List<ListError> errors =
          _withDue(FieldType.text, role: FieldRole.reminder).validate();
      expect(errors.map((e) => e.code), [ListErrorCode.roleNeedsType]);
      expect(errors.single.toString(), contains('date or dateTime'));
    });

    test('survives changing a reminder field between date and dateTime', () {
      final ListPatchResult result = ListPatch.apply(
        _withDue(FieldType.dateTime, role: FieldRole.reminder),
        const [],
        [const ListPatchOp(PatchOpKind.changeFieldType, {'key': 'due', 'type': 'date'})],
        _now,
      );
      expect(result.errors, isEmpty);
      expect(result.definition.field('due')!.role, FieldRole.reminder);
    });

    test('an old document with no mark and Tasks as built still validate', () {
      expect(_withDue(FieldType.date).validate(), isEmpty);
      expect(BuiltinTemplates.tasks().validate(), isEmpty);
    });
  });

  group('setFieldProps', () {
    test('sets and clears the reminder mark', () {
      final ListPatchResult on = _props(_withDue(FieldType.date), {'key': 'due', 'role': 'reminder'});
      expect(on.errors, isEmpty);
      expect(on.definition.field('due')!.role, FieldRole.reminder);
      final ListPatchResult off = _props(on.definition, {'key': 'due', 'role': null});
      expect(off.errors, isEmpty);
      expect(off.definition.field('due')!.role, isNull);
    });

    test('a second reminder field is refused', () {
      final ListPatchResult result = ListPatch.apply(
        _withDue(FieldType.date, role: FieldRole.reminder),
        const [],
        [
          const ListPatchOp(PatchOpKind.addField, {
            'field': {'key': 'other', 'type': 'dateTime', 'label': 'Other'},
          }),
          const ListPatchOp(PatchOpKind.setFieldProps, {'key': 'other', 'role': 'reminder'}),
        ],
        _now,
      );
      expect(result.errors.map((e) => e.code), contains(ListErrorCode.duplicateRole));
    });

    test('changes default, min, max and visibleWhen in one edit, and null removes them', () {
      final ListPatchResult set = _props(_withDue(FieldType.date), {
        'key': 'count',
        'required': true,
        'default': '3',
        'min': 0,
        'max': 10,
        'visibleWhen': {'field': 'kind', 'in': ['a']},
      });
      expect(set.errors, isEmpty);
      final FieldDefinition count = set.definition.field('count')!;
      expect(count.required, isTrue);
      expect(count.defaultValue, 3);
      expect((count.min, count.max), (0, 10));
      expect(count.visibleWhen!.values, ['a']);

      final ListPatchResult cleared = _props(set.definition, {
        'key': 'count',
        'default': null,
        'min': null,
        'max': null,
        'visibleWhen': null,
      });
      final FieldDefinition plain = cleared.definition.field('count')!;
      expect(cleared.errors, isEmpty);
      expect(plain.required, isTrue, reason: 'absent means unchanged');
      expect([plain.defaultValue, plain.min, plain.max, plain.visibleWhen], everyElement(isNull));
    });

    test('refuses the title field, an unknown role, a bad default and unknown keys', () {
      ListErrorCode? code(Map<String, dynamic> args) {
        final List<ListError> errors = _props(_withDue(FieldType.date), args).errors;
        return errors.isEmpty ? null : errors.first.code;
      }

      expect(code({'key': 'title', 'required': false}), ListErrorCode.badOp);
      expect(code({'key': 'due', 'role': 'alarm'}), ListErrorCode.badOp);
      expect(code({'key': 'count', 'default': 'many'}), ListErrorCode.badOp);
      expect(code({'key': 'count', 'min': 'low'}), ListErrorCode.badOp);
      expect(code({'key': 'kind', 'default': 'c'}), ListErrorCode.badOp);
      expect(code({'key': 'count', 'visibleWhen': {'field': 'kind', 'in': ['a'], 'x': 1}}), isNotNull);
      expect(code({'key': 'count', 'visibleWhen': {'field': 'kind', 'in': ['zz']}}), ListErrorCode.conditionNotOption);
    });
  });

  group('repeats', () {
    final ListDefinition tasks = BuiltinTemplates.tasks();
    ListItem task(String date, String frequency) => ListItem(
      id: 't1',
      listId: tasks.id,
      values: {
        'title': 'Water plants',
        'done': true,
        'reminderAt': date,
        'repeat': {'frequency': frequency},
      },
      createdAt: _now,
      updatedAt: _now,
    );

    ListItem? next(ListItem item, DateTime now) =>
        ListRules.clearCompleted(tasks, [item], now).saved.where((saved) => saved.id != item.id).firstOrNull;

    test('a day with No time comes again as a day', () {
      final ListItem? copy = next(task('2026-02-27', 'daily'), DateTime(2026, 3, 1, 15));
      expect(copy!['reminderAt'], '2026-03-01', reason: 'today still counts for a day');
      expect(next(task('2026-01-31', 'monthly'), DateTime(2026, 2, 10))!['reminderAt'], '2026-02-28');
    });

    test('a timed one keeps its wall-clock time and steps past now', () {
      final DateTime at = DateTime(2026, 2, 27, 8);
      final ListItem? copy = next(task(at.toUtc().toIso8601String(), 'daily'), DateTime(2026, 3, 1, 15));
      expect(DateTime.parse(copy!['reminderAt'] as String).toLocal(), DateTime(2026, 3, 2, 8));
    });

    test('monthly counts from the first date, so the 31st returns', () {
      final DateTime from = DateTime(2026, 1, 31, 8);
      expect(ListRules.occurrence(from, RecurrenceFrequency.monthly, null, 1), DateTime(2026, 2, 28, 8));
      expect(ListRules.occurrence(from, RecurrenceFrequency.monthly, null, 2), DateTime(2026, 3, 31, 8));
      expect(ListRules.occurrence(from, RecurrenceFrequency.daily, null, 40), DateTime(2026, 3, 12, 8));
    });
  });

  testWidgets('Remind me moves the list\'s one mark and takes it off', (tester) async {
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ListDefinition tasks = ListPatch.apply(
      BuiltinTemplates.tasks(),
      const [],
      [
        const ListPatchOp(PatchOpKind.addField, {
          'field': {'key': 'birthday', 'type': 'date', 'label': 'Birthday'},
        }),
      ],
      _now,
    ).definition;
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
                MaterialPageRoute(builder: (_) => ListEditorScreen(definition: tasks, items: const [])),
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

    Switch remind(String key) => tester.widget<Switch>(
      find.descendant(of: find.byKey(ValueKey('field-remind-$key')), matching: find.byType(Switch)),
    );
    expect(remind('reminderAt').value, isTrue);
    expect(remind('birthday').value, isFalse);
    expect(find.byKey(const ValueKey('field-remind-title')), findsNothing);
    expect(find.text('Rings at its time; a date with no time rings in the morning.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('field-remind-birthday')));
    await tester.pumpAndSettle();
    expect(remind('reminderAt').value, isFalse);
    expect(remind('birthday').value, isTrue);

    await tester.tap(find.byKey(const ValueKey('field-remind-birthday')));
    await tester.pumpAndSettle();
    expect(remind('birthday').value, isFalse);

    await tester.tap(find.byKey(const ValueKey('save-list')));
    await tester.pumpAndSettle();
    final ListDefinition saved = (await outcome)!.result!.definition;
    expect(saved.fieldWithRole(FieldRole.reminder), isNull);
    expect(saved.validate(), isEmpty);
  });
}
