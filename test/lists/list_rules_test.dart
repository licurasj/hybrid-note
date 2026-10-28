import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

final DateTime _t0 = DateTime.utc(2026, 3, 1, 9);

ListItem _grocery(String id, Map<String, dynamic> values) {
  return ListItem(
    id: id,
    listId: BuiltinTemplates.groceryId,
    values: {'description': '', 'autoAddToNext': false, ...values},
    createdAt: _t0,
    updatedAt: _t0,
  );
}

ListItem _task(String id, Map<String, dynamic> values) {
  return ListItem(
    id: id,
    listId: BuiltinTemplates.tasksId,
    values: {'title': 'Task $id', 'description': '', 'done': true, 'subtasks': [], ...values},
    createdAt: _t0,
    updatedAt: _t0,
  );
}

void main() {
  final ListDefinition grocery = BuiltinTemplates.grocery();
  final ListDefinition tasks = BuiltinTemplates.tasks();
  int idCounter = 0;
  String nextId() => 'new-${idCounter++}';

  setUp(() => idCounter = 0);

  group('copyOnClear (grocery)', () {
    test('a ticked auto-add item in the current run is copied to next time', () {
      final ListChanges changes = ListRules.clearCompleted(
        grocery,
        [
          _grocery('milk', {'title': 'Milk', 'section': 'current', 'done': true, 'autoAddToNext': true}),
          _grocery('eggs', {'title': 'Eggs', 'section': 'current', 'done': true}),
          _grocery('bread', {'title': 'Bread', 'section': 'current', 'done': false}),
        ],
        _t0,
        newId: nextId,
      );

      expect(changes.deletedIds, ['milk', 'eggs']);
      expect(changes.saved, hasLength(1));
      expect(changes.saved.single.id, 'new-0');
      expect(changes.saved.single.values, containsPair('section', 'nextTime'));
      expect(changes.saved.single.values, containsPair('done', false));
      expect(changes.saved.single.values, containsPair('title', 'Milk'));
    });

    test('no copy when next time already has the same open item', () {
      final ListChanges changes = ListRules.clearCompleted(
        grocery,
        [
          _grocery('milk', {'title': 'Milk', 'section': 'current', 'done': true, 'autoAddToNext': true}),
          _grocery('milk2', {'title': ' milk ', 'section': 'nextTime', 'done': false}),
        ],
        _t0,
        newId: nextId,
      );

      expect(changes.deletedIds, ['milk']);
      expect(changes.saved, isEmpty);
    });

    test('clearing only one section leaves the other alone', () {
      final ListChanges changes = ListRules.clearCompleted(
        grocery,
        [
          _grocery('a', {'title': 'A', 'section': 'current', 'done': true}),
          _grocery('b', {'title': 'B', 'section': 'nextTime', 'done': true}),
        ],
        _t0,
        inScope: (item) => item['section'] == 'nextTime',
      );

      expect(changes.deletedIds, ['b']);
    });
  });

  test('moveAll moves next time into the current run and unticks', () {
    final ListChanges changes = ListRules.moveAll(
      grocery,
      [
        _grocery('a', {'title': 'A', 'section': 'nextTime', 'done': true}),
        _grocery('b', {'title': 'B', 'section': 'current', 'done': true}),
      ],
      grocery.behaviors.firstWhere((b) => b.kind == BehaviorKind.moveAll),
      _t0,
    );

    expect(changes.saved.map((item) => item.id), ['a']);
    expect(changes.saved.single.values, containsPair('section', 'current'));
    expect(changes.saved.single.values, containsPair('done', false));
  });

  group('recurOnClear (tasks)', () {
    test('a cleared daily task comes back for the next future day', () {
      final ListItem item = _task('1', {
        'reminderAt': DateTime.utc(2026, 2, 26, 8).toIso8601String(),
        'repeat': {'frequency': 'daily'},
        'subtasks': [
          {'id': 's1', 'title': 'Step', 'done': true, 'createdAt': _t0.toIso8601String(), 'updatedAt': _t0.toIso8601String()},
        ],
      });

      final ListChanges changes = ListRules.clearCompleted(tasks, [item], _t0);
      final ListItem next = changes.saved.single;
      final DateTime nextDate = DateTime.parse(next['reminderAt'] as String);

      expect(changes.deletedIds, ['1']);
      expect(nextDate.isAfter(_t0), isTrue);
      expect(nextDate.difference(_t0).inHours, lessThan(24));
      expect(next.id, 'repeat-1-${nextDate.millisecondsSinceEpoch}');
      expect(next['done'], false);
      expect((next['subtasks'] as List).single, containsPair('done', false));
      expect((next['subtasks'] as List).single, containsPair('id', '${next.id}-subtask-s1'));
    });

    test('monthly repeats clamp to the end of short months', () {
      final DateTime jan31 = DateTime(2026, 1, 31, 8);
      final DateTime? next = ListRules.nextOccurrence(
        jan31.toUtc(),
        RecurrenceFrequency.monthly,
        null,
        jan31.toUtc(),
      );

      expect(next!.toLocal(), DateTime(2026, 2, 28, 8));
    });

    test('no repeat without a date, and normalize turns the repeat off', () {
      final ListItem item = _task('1', {'repeat': {'frequency': 'weekly'}});

      expect(ListRules.clearCompleted(tasks, [item], _t0).saved, isEmpty);
      expect(
        ListRules.normalize(tasks, item)['repeat'],
        {'frequency': 'none'},
      );
    });
  });
}
