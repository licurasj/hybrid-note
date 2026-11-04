import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_note/ai/ai_match.dart';
import 'package:hybrid_note/ai/ai_service.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_error.dart';
import 'package:hybrid_note/lists/list_item.dart';

// Items named by their words (Q-39, T-19 unit 8).
const String _grocery = BuiltinTemplates.groceryId;
final DateTime _t0 = DateTime.utc(2026, 11, 4);

ListItem _item(String id, String title) => ListItem(
  id: id,
  listId: _grocery,
  values: {'title': title},
  createdAt: _t0,
  updatedAt: _t0,
);

ListCatalog _catalog(List<ListItem> items) {
  final ListDefinition grocery = BuiltinTemplates.all().firstWhere(
    (list) => list.id == _grocery,
  );
  return ListCatalog(definitions: [grocery], items: items);
}

AiAnswer _answer(List<AiToolCall> calls) =>
    AiAnswer(requestId: 'r', toolCalls: calls);

void main() {
  final ListCatalog catalog = _catalog([
    _item('m', 'Milk'),
    _item('e', 'Eggs'),
    _item('b1', 'Brown bread'),
    _item('b2', 'White bread'),
    _item('o', 'Oat milk'),
  ]);
  final ListDefinition grocery = catalog.definition(_grocery)!;

  test('an exact name wins, ignoring case and a plural "s"', () {
    expect(
      AiMatch.matches(grocery, catalog.itemsOf(_grocery), 'milk').single.id,
      'm',
    );
    expect(
      AiMatch.matches(grocery, catalog.itemsOf(_grocery), 'egg').single.id,
      'e',
    );
  });

  test('otherwise the items holding all the words; several are unclear', () {
    expect(
      AiMatch.matches(grocery, catalog.itemsOf(_grocery), 'brown').single.id,
      'b1',
    );
    expect(
      AiMatch.matches(grocery, catalog.itemsOf(_grocery), 'bread'),
      hasLength(2),
    );
    expect(AiMatch.matches(grocery, catalog.itemsOf(_grocery), 'jam'), isEmpty);
  });

  test('clear matches become ids in delete_items and upsert_items', () {
    final AiMatchResult result = AiMatch.resolve(
      _answer([
        const AiToolCall('delete_items', {
          'listId': _grocery,
          'match': ['milk', 'eggs'],
        }),
        const AiToolCall('upsert_items', {
          'listId': _grocery,
          'items': [
            {
              'match': 'brown bread',
              'values': [
                {'field': 'done', 'value': true},
              ],
            },
          ],
        }),
      ]),
      catalog,
    );
    expect(result.unclearListId, isNull);
    expect(result.errors, isEmpty);
    expect(result.answer.toolCalls[0].args, {
      'listId': _grocery,
      'ids': ['m', 'e'],
    });
    final Map items =
        ((result.answer.toolCalls[1].args! as Map)['items'] as List).single
            as Map;
    expect(items['id'], 'b1');
    expect(items.containsKey('match'), isFalse);
  });

  test('an unclear match asks for a second round with the list\'s items, '
      'or is an error when they were sent', () {
    final AiAnswer answer = _answer([
      const AiToolCall('delete_items', {
        'listId': _grocery,
        'match': ['bread'],
      }),
    ]);
    expect(AiMatch.resolve(answer, catalog).unclearListId, _grocery);

    final AiMatchResult second = AiMatch.resolve(
      answer,
      catalog,
      itemsSent: _grocery,
    );
    expect(second.unclearListId, isNull);
    expect(second.errors.single.code, ListErrorCode.unknownItem);
  });

  test('calls without match pass unchanged', () {
    final AiAnswer answer = _answer([
      const AiToolCall('delete_items', {
        'listId': _grocery,
        'ids': ['m'],
      }),
      const AiToolCall('reply', {'text': 'Fine.'}),
    ]);
    final AiMatchResult result = AiMatch.resolve(answer, catalog);
    expect(result.answer.toolCalls[0].args, answer.toolCalls[0].args);
    expect(result.answer.toolCalls[1].args, {'text': 'Fine.'});
  });
}
