// T-13 unit 4: what Done on a ring changes (Rules: Done details, Q-97).
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/reminders/reminder_done.dart';

final ListDefinition _tasks = BuiltinTemplates.tasks();
final DateTime _now = DateTime.utc(2026, 3, 10, 12);
const String _date = '2026-03-10T15:00:00.000Z';

ListItem _task({Object? date = _date, bool done = false, String? repeat}) =>
    ListItem(
      id: 'a',
      listId: _tasks.id,
      values: {
        'title': 'Call',
        'done': done,
        'reminderAt': ?date,
        if (repeat != null) 'repeat': {'frequency': repeat},
      },
      createdAt: _now,
      updatedAt: _now,
    );

void main() {
  test('ticks the item when the list keeps ticked items', () {
    final changes = ReminderDone.changes(
      definition: _tasks,
      item: _task(),
      itemDate: _date,
      preferences: const AccountPreferences(),
      now: _now,
    );
    expect(changes.deletedIds, isEmpty);
    expect(changes.saved.single['done'], isTrue);
  });

  test('does nothing when the date changed or the item is ticked', () {
    for (final ListItem item in [
      _task(date: '2026-03-11T15:00:00.000Z'),
      _task(date: null),
      _task(done: true),
    ]) {
      expect(
        ReminderDone.changes(
          definition: _tasks,
          item: item,
          itemDate: _date,
          preferences: const AccountPreferences(),
          now: _now,
        ).isEmpty,
        isTrue,
      );
    }
  });

  test('clears at once with Clear straight away, and a repeat comes again', () {
    const AccountPreferences clear = AccountPreferences(
      tickedItems: TickedItems.clearAtOnce,
    );
    final once = ReminderDone.changes(
      definition: _tasks,
      item: _task(),
      itemDate: _date,
      preferences: clear,
      now: _now,
    );
    expect(once.deletedIds, ['a']);
    expect(once.saved, isEmpty);

    final repeat = ReminderDone.changes(
      definition: _tasks,
      item: _task(repeat: 'daily'),
      itemDate: _date,
      preferences: clear,
      now: _now,
    );
    expect(repeat.deletedIds, ['a']);
    final ListItem next = repeat.saved.single;
    expect(next['done'], isFalse);
    expect(next['reminderAt'], isNot(_date));
  });
}
