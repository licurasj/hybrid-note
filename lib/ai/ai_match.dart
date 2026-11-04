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
  // [itemsSent] are the lists whose items went with this submission. With
  // [lastRound] no other round will come, so every unclear match is an error
  // (M1 of the Codex review).
  static AiMatchResult resolve(
    AiAnswer answer,
    ListCatalog catalog, {
    Set<String> itemsSent = const {},
    bool lastRound = false,
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
      if (lastRound || itemsSent.contains(listId)) {
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

  // Lower-case words with a plural dropped, for comparing names. Quotes and
  // brackets separate words; an apostrophe inside a word does not.
  static List<String> words(String text) => [
    for (final String word
        in text
            .toLowerCase()
            .replaceAll(_edgeApostrophe, ' ')
            .split(_separators))
      if (word.isNotEmpty) _singular(word),
  ];

  static final RegExp _edgeApostrophe = RegExp(
    r"(?<![\p{L}\p{N}])['\u2019]|['\u2019](?![\p{L}\p{N}])",
    unicode: true,
  );
  static final RegExp _separators = RegExp(
    r'[\s,.;:!?"`\u201C\u201D\u2018\u201E\u00AB\u00BB()\[\]{}<>\uFF08\uFF09\u3010\u3011\u300A\u300B\u3008\u3009\u300C\u300D\u300E\u300F\uFF0C\u3002\uFF1B\uFF1A\uFF01\uFF1F\u3001\u00B7\u2026]+',
  );
  // Scripts written without spaces between words.
  static final RegExp _noSpaces = RegExp(
    r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Thai}]',
    unicode: true,
  );
  // A trailing word that only says "list", in scripts without spaces.
  static final RegExp _listWordSuffix = RegExp(
    '(\u6E05\u5355|\u6E05\u55AE|\u5217\u8868|\u30EA\u30B9\u30C8)\$',
  );

  // Whether [text] names the list called [name] (Q-41, Q-54): its words in a
  // row, or inside the text in a script without spaces. "grocery" also names
  // "Grocery list". A one-character name in such a script must stand alone,
  // since it is too often part of another word. With [whole], [text] is exactly
  // the name.
  static bool namedIn(String text, String name, {bool whole = false}) {
    final List<String> nameWords = words(name);
    if (nameWords.isEmpty) {
      return false;
    }
    final List<String> said = words(text);
    if (whole) {
      return said.join(' ') == nameWords.join(' ') ||
          (_noSpaces.hasMatch(name) && said.join() == nameWords.join());
    }
    if (_noSpaces.hasMatch(name)) {
      final String compact = nameWords.join();
      final String short = compact.replaceFirst(_listWordSuffix, '');
      return [compact, if (short != compact) short].any(
        (form) => form.runes.length >= 2
            ? said.join().contains(form)
            : said.contains(form),
      );
    }
    final String joined = ' ${said.join(' ')} ';
    return joined.contains(' ${nameWords.join(' ')} ') ||
        (nameWords.length > 1 &&
            nameWords.last == 'list' &&
            joined.contains(
              ' ${nameWords.sublist(0, nameWords.length - 1).join(' ')} ',
            ));
  }

  static String _singular(String word) {
    if (word.length > 4 && word.endsWith('ies')) {
      return '${word.substring(0, word.length - 3)}y';
    }
    if (word.length > 3 && word.endsWith('ie')) {
      return '${word.substring(0, word.length - 2)}y';
    }
    return word.length > 3 && word.endsWith('s') && !word.endsWith('ss')
        ? word.substring(0, word.length - 1)
        : word;
  }
}
