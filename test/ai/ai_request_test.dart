import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/ai/ai_service.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_labels.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

// The list summaries the AI sees (Q-36): a description goes along when the
// list has one (Q-44).

ListDefinition _list(String id, String name, {String? description}) {
  return ListDefinition(
    id: id,
    name: name,
    description: description,
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
}
