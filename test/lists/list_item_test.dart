import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';

final DateTime _created = DateTime.utc(2026, 3, 1, 9, 30);

// Saves an item as JSON text and loads it again, as storage will.
ListItem _reload(ListItem item) {
  return ListItem.fromJson(jsonDecode(jsonEncode(item.toJson())));
}

void main() {
  group('value validation', () {
    final ListDefinition watch = BuiltinTemplates.watchRead();

    ListItem watchItem(Map<String, dynamic> values) {
      return ListItem(
        id: 'w',
        listId: watch.id,
        values: {'title': 'Dune', ...values},
        createdAt: _created,
        updatedAt: _created,
      );
    }

    test('an option that does not exist', () {
      expect(
        watchItem({'status': 'abandoned'}).validateAgainst(watch).map((error) => '$error'),
        contains(contains('"abandoned" is not an option')),
      );
    });

    test('a counter below its minimum', () {
      expect(
        watchItem({'season': -1}).validateAgainst(watch).map((error) => '$error'),
        contains(contains('must be at least 0')),
      );
    });

    test('a missing required field', () {
      final ListItem item = ListItem(
        id: 'w',
        listId: watch.id,
        values: const {},
        createdAt: _created,
        updatedAt: _created,
      );

      expect(
        item.validateAgainst(watch).map((error) => '$error'),
        contains('field "title" is required'),
      );
    });

    test('values of removed fields are kept and ignored', () {
      final ListItem item = _reload(watchItem({'_legacy': {'price': r'$3'}}));

      expect(item.validateAgainst(watch), isEmpty);
      expect(item['_legacy'], {'price': r'$3'});
    });

    test('custom repeat without a day count', () {
      final ListDefinition tasks = BuiltinTemplates.tasks();
      final ListItem item = ListItem(
        id: 'task-1',
        listId: tasks.id,
        values: {
          'title': 'Pay rent',
          'reminderAt': _created.toIso8601String(),
          'repeat': {'frequency': 'custom'},
        },
        createdAt: _created,
        updatedAt: _created,
      );

      expect(
        item.validateAgainst(tasks).map((error) => '$error'),
        contains(contains('custom frequency needs customDays')),
      );
    });
  });
}
