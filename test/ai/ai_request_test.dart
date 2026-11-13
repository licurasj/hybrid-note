import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/ai/ai_service.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_labels.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

// The list summaries the AI sees (Q-36): a description goes along when the
// list has one (Q-44).

ListDefinition _list(String id, String name, {String? description, bool aiAllowed = true}) {
  return ListDefinition(
    id: id,
    name: name,
    description: description,
    aiAllowed: aiAllowed,
    icon: 'list',
    color: '#336699',
    fields: const [
      FieldDefinition(key: 'title', type: FieldType.text, label: 'Title', primary: true),
    ],
    view: const ViewDefinition(kind: ViewKind.cards),
    updatedAt: DateTime.utc(2026),
  );
}

void main() {
  test('each summary carries the description when the list has one', () {
    final AiRequest request = AiRequest.of(
      prompt: 'eggs',
      locale: 'en',
      now: DateTime(2026, 11, 3),
      catalog: ListCatalog(
        definitions: [
          _list('grocery', 'Grocery', description: 'Food to buy'),
          _list('tasks', 'Tasks'),
        ],
        items: const [],
      ),
      labels: ListLabels(lookupAppLocalizations(const Locale('en'))),
    );

    final List<Object?> lists = request.toJson()['lists'] as List<Object?>;
    expect((lists[0] as Map)['description'], 'Food to buy');
    expect((lists[1] as Map).containsKey('description'), isFalse);
  });

  AiRequest of(List<ListDefinition> definitions, {String? openListId}) => AiRequest.of(
    prompt: 'eggs',
    locale: 'en',
    now: DateTime(2026, 11, 3),
    catalog: ListCatalog(definitions: definitions, items: const []),
    labels: ListLabels(lookupAppLocalizations(const Locale('en'))),
    openListId: openListId,
  );

  test('a summary names field roles, so the AI knows which field rings (T-13 unit 5)', () {
    final Map<Object?, Object?> tasks =
        (of([BuiltinTemplates.tasks()]).toJson()['lists'] as List).single as Map;
    final List<Object?> fields = tasks['fields'] as List<Object?>;
    final Map<Object?, Object?> reminder =
        fields.cast<Map<Object?, Object?>>().singleWhere((field) => field['key'] == 'reminderAt');

    expect(reminder['role'], 'reminder');
    expect(fields.cast<Map<Object?, Object?>>().singleWhere((field) => field['key'] == 'title').containsKey('role'), isFalse);
  });

  test('a summary marks required fields, on a list that is not open '
      '(T-13 unit 14, G7)', () {
    final ListDefinition tasks = BuiltinTemplates.tasks();
    final Map<Object?, Object?> summary =
        (of([tasks]).toJson()['lists'] as List).single as Map;
    final List<Map<Object?, Object?>> fields =
        (summary['fields'] as List).cast<Map<Object?, Object?>>();
    expect(tasks.fields.any((field) => field.required), isTrue);
    for (final FieldDefinition field in tasks.fields) {
      final Map<Object?, Object?> sent =
          fields.singleWhere((entry) => entry['key'] == field.key);
      expect(sent['required'], field.required ? isTrue : isNull, reason: field.key);
    }
  });

  test("an AI-off list's description is never sent (review M2)", () {
    final AiRequest request = of([
      _list('grocery', 'Grocery'),
      _list('diary', 'Diary', description: 'DIARYSECRET', aiAllowed: false),
    ], openListId: 'diary');

    expect(jsonEncode(request.toJson()), isNot(contains('DIARYSECRET')));
  });

  test('a stored description over the limit is cut, not sent whole (review M1)', () {
    final Map<Object?, Object?> summary =
        (of([_list('grocery', 'Grocery', description: '\u{1F95A}' * 250)]).toJson()['lists'] as List).single as Map;

    expect(summary['description'], '\u{1F95A}' * 200);
  });

  test("the open list carries the summary's description, not a built-in's key (review L4)", () {
    final Map<Object?, Object?> open =
        of([BuiltinTemplates.grocery()], openListId: BuiltinTemplates.groceryId).toJson()['openList'] as Map;
    final Map<Object?, Object?> definition = open['definition'] as Map;

    expect(definition.containsKey('descriptionKey'), isFalse);
    expect(definition['description'], contains('shopping'));
  });
}
