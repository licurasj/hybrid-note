// T-13 unit 10, F7: a date field holds a calendar day, the same on every
// phone; values saved before as a UTC moment are read by their UTC date.
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/item_dates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

void main() {
  test('a day reads as its local midnight, in either field type', () {
    for (final FieldType? type in [FieldType.date, FieldType.dateTime, null]) {
      expect(ItemDates.local('2026-11-15', type), DateTime(2026, 11, 15));
    }
  });

  test('an older date-field moment reads by its UTC date', () {
    // Saved west of UTC (the owner's zone), and at UTC itself.
    expect(
      ItemDates.local('2026-11-15T08:00:00.000Z', FieldType.date),
      DateTime(2026, 11, 15),
    );
    expect(
      ItemDates.local('2026-11-15T00:00:00.000Z', FieldType.date),
      DateTime(2026, 11, 15),
    );
  });

  test('a dateTime moment stays a moment, in the phone zone', () {
    final DateTime moment = DateTime.utc(2026, 11, 15, 8, 30);
    expect(
      ItemDates.local(moment.toIso8601String(), FieldType.dateTime),
      moment.toLocal(),
    );
    expect(ItemDates.local('not a date', FieldType.date), isNull);
    expect(ItemDates.local(null, FieldType.date), isNull);
  });

  test('a repeat on a date field writes its next day as YYYY-MM-DD', () {
    final Map<String, dynamic> json = BuiltinTemplates.tasks().toJson();
    for (final Map field in json['fields'] as List) {
      if (field['key'] == 'reminderAt') {
        field['type'] = 'date';
      }
    }
    final ListDefinition list = ListDefinition.fromJson(json);
    final DateTime now = DateTime(2026, 11, 15, 12);
    for (final String saved in ['2026-11-15', '2026-11-15T08:00:00.000Z']) {
      final ListItem item = ListItem(
        id: 'a',
        listId: list.id,
        values: {
          'title': 'Water plants',
          'done': true,
          'reminderAt': saved,
          'repeat': {'frequency': 'daily'},
        },
        createdAt: now.toUtc(),
        updatedAt: now.toUtc(),
      );
      final ListChanges changes = ListRules.clearCompleted(list, [item], now);
      expect(changes.saved.single['reminderAt'], '2026-11-16', reason: saved);
    }
  });

  test('input dates are stored as the sheet stores them (F8)', () {
    expect(
      ItemDates.fromInput('2026-11-13T15:00', FieldType.dateTime),
      DateTime(2026, 11, 13, 15).toUtc().toIso8601String(),
    );
    expect(
      ItemDates.fromInput('2026-11-13T15:00+01:00', FieldType.dateTime),
      '2026-11-13T14:00:00.000Z',
    );
    expect(ItemDates.fromInput(' 2026-11-13 ', FieldType.dateTime), '2026-11-13');
    expect(ItemDates.fromInput('2026-11-13T15:00', FieldType.date), '2026-11-13');
    expect(ItemDates.fromInput('2026-11-13T23:30:00Z', FieldType.date), '2026-11-13');
    expect(ItemDates.fromInput('soon', FieldType.dateTime), 'soon');
    expect(ItemDates.fromInput(null, FieldType.dateTime), isNull);
  });
}
