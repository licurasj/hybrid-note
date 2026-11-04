import '../lists/list_catalog.dart';
import '../lists/list_definition.dart';
import '../lists/list_error.dart';
import '../lists/list_item.dart';
import 'ai_service.dart';

// Items named by their words (Q-39): when a list's items are not in the
// request, the AI names them in `match` ("milk") and the phone finds them.
// A word that fits exactly one item becomes that item's id; one that fits
// none or several is unclear, and the request goes again with that list's
// items (the second round), or, when they were already sent, is an error.
class AiMatchResult {
  const AiMatchResult({
    required this.answer,
    this.unclearListId,
    this.errors = const [],
  });

  // The answer with every clear match replaced by its id.
  final AiAnswer answer;
  // A list with an unclear match whose items the request did not carry.
  final String? unclearListId;
  // Unclear matches in a list whose items the request carried.
  final List<ListError> errors;
}

class AiMatch {
  // [itemsSent] is the list whose items went with the request, if any.
  static AiMatchResult resolve(
    AiAnswer answer,
    ListCatalog catalog, {
    String? itemsSent,
  }) {
    String? unclear;
    final List<ListError> errors = [];

    // An unclear delete is reported here; an unclear change keeps the
    // words as its id, which ListInput reports as an unknown item.
    String? find(String listId, String words, {bool report = true}) {
      final ListDefinition? definition = catalog.definition(listId);
      if (definition == null) {
        return null;
      }
      final List<ListItem> found = matches(
        definition,
        catalog.itemsOf(listId),
        words,
      );
      if (found.length == 1) {
        return found.single.id;
      }
      if (listId == itemsSent) {
        if (!report) {
          return null;
        }
        errors.add(
          ListError(ListErrorCode.unknownItem, {'item': words, 'list': listId}),
        );
      } else {
        unclear ??= listId;
      }
      return null;
    }

    final List<AiToolCall> calls = [];
    for (final AiToolCall call in answer.toolCalls) {
      final Object? args = call.args;
      if (args is! Map || args['listId'] is! String) {
        calls.add(call);
        continue;
      }
      final String listId = args['listId'] as String;
      if (call.name == 'delete_items' && args['match'] is List) {
        final List<String> ids = [];
        for (final Object? words in args['match'] as List) {
          final String? id = words is String ? find(listId, words) : null;
          if (id != null && !ids.contains(id)) {
            ids.add(id);
          }
        }
        calls.add(
          AiToolCall(call.name, {
            for (final MapEntry entry in args.entries)
              if (entry.key != 'match') entry.key: entry.value,
            'ids': ids,
          }),
        );
      } else if (call.name == 'upsert_items' && args['items'] is List) {
        calls.add(
          AiToolCall(call.name, {
            ...args,
            'items': [
              for (final Object? item in args['items'] as List)
                if (item is Map && item['match'] is String)
                  {
                    for (final MapEntry entry in item.entries)
                      if (entry.key != 'match') entry.key: entry.value,
                    'id':
                        find(listId, item['match'] as String, report: false) ??
                        item['match'],
                  }
                else
                  item,
            ],
          }),
        );
      } else {
        calls.add(call);
      }
    }
    return AiMatchResult(
      answer: answer.withToolCalls(calls),
      unclearListId: unclear,
      errors: errors,
    );
  }

  // The items whose text is [said]: an exact match first (case, spaces and
  // a plural "s" aside), else the items whose text holds all its words.
  static List<ListItem> matches(
    ListDefinition definition,
    List<ListItem> items,
    String said,
  ) {
    final List<String> wanted = words(said);
    if (wanted.isEmpty) {
      return const [];
    }
    final List<(ListItem, List<String>)> texts = [
      for (final ListItem item in items) (item, words(_text(definition, item))),
    ];
    final List<ListItem> exact = [
      for (final (ListItem item, List<String> text) in texts)
        if (text.join(' ') == wanted.join(' ')) item,
    ];
    if (exact.isNotEmpty) {
      return exact;
    }
    return [
      for (final (ListItem item, List<String> text) in texts)
        if (wanted.every(text.contains)) item,
    ];
  }

  // The item's primary text, or its first text value.
  static String _text(ListDefinition definition, ListItem item) {
    for (final FieldDefinition field in definition.fields) {
      if (field.primary && item[field.key] is String) {
        return item[field.key] as String;
      }
    }
    for (final FieldDefinition field in definition.fields) {
      if (item[field.key] is String) {
        return item[field.key] as String;
      }
    }
    return '';
  }

  // Lower-case words with a plural "s" dropped, for comparing names.
  static List<String> words(String text) => [
    for (final String word in text.toLowerCase().split(RegExp(r'[\s,.;:!?]+')))
      if (word.isNotEmpty) _singular(word),
  ];

  static String _singular(String word) =>
      word.length > 3 && word.endsWith('s') && !word.endsWith('ss')
      ? word.substring(0, word.length - 1)
      : word;
}
