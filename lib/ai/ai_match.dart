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
// How a request refers to a list by name (Q-62). clear: quoted, or with a list
// word. possible: the name on its own, which may be an everyday word.
enum AiMention { none, possible, clear }

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

  // Lower-case words with a plural "s" dropped, for comparing names.
  static List<String> words(String text) => [
    for (final String word in _tokens(text)) _singular(word),
  ];

  // Lower-case words as written. Quotes and brackets separate words; an
  // apostrophe inside a word does not.
  static List<String> _tokens(String text) => [
    for (final String word
        in text
            .toLowerCase()
            .replaceAll(_edgeApostrophe, ' ')
            .split(_separators))
      if (word.isNotEmpty) word,
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
  static final RegExp _listWordStart = RegExp(
    '^(\u6E05\u5355|\u6E05\u55AE|\u5217\u8868|\u30EA\u30B9\u30C8)',
  );
  // Text in quotation marks.
  static final RegExp _quoted = RegExp(
    '"([^"]+)"|\u201C([^\u201D]+)\u201D|\u2018([^\u2019]+)\u2019|'
    "(?<![\\p{L}\\p{N}])'([^']+)'(?![\\p{L}\\p{N}])|"
    '\u300C([^\u300D]+)\u300D|\u300E([^\u300F]+)\u300F|'
    '\u300A([^\u300B]+)\u300B|\u3010([^\u3011]+)\u3011',
    unicode: true,
  );

  // Whether [text] names the list called [name] (Q-41, Q-54).
  static bool namedIn(String text, String name) =>
      mention(text, name) != AiMention.none;

  // Whether [text] is exactly the name [name].
  static bool isName(String text, String name) {
    final List<String> said = _tokens(text);
    final List<String> wanted = _tokens(name);
    return wanted.isNotEmpty &&
        (_at(said, wanted, 0) && said.length == wanted.length ||
            (_noSpaces.hasMatch(name) && said.join() == wanted.join()));
  }

  // How [text] refers to the list called [name]: its words in a row, or, in a
  // script without spaces, inside one word of the text (punctuation is a
  // boundary, Codex R5). A name without its trailing list word counts too, and
  // a one-character name in such a script must stand alone. A mention inside a
  // longer name of [otherNames] names that list, not this one (Q-62).
  static AiMention mention(
    String text,
    String name, {
    Iterable<String> otherNames = const [],
  }) {
    final List<String> wanted = _tokens(name);
    if (wanted.isEmpty) {
      return AiMention.none;
    }
    final bool noSpaces = _noSpaces.hasMatch(name);
    final String compact = wanted.join();
    final String short = compact.replaceFirst(_listWordSuffix, '');
    final bool endsInListWord =
        wanted.length > 1 && _sameWord(wanted.last, 'list') || short != compact;
    final List<String> shortWords = wanted.length > 1 && _sameWord(wanted.last, 'list')
        ? wanted.sublist(0, wanted.length - 1)
        : wanted;

    // Quoted exactly: clear.
    for (final RegExpMatch match in _quoted.allMatches(text.toLowerCase())) {
      final String? inside = [
        for (int i = 1; i <= match.groupCount; i++) match.group(i),
      ].nonNulls.firstOrNull;
      if (inside != null &&
          (_at(_tokens(inside), wanted, 0) && _tokens(inside).length == wanted.length ||
              _tokens(inside).join() == compact ||
              _tokens(inside).join() == short)) {
        return AiMention.clear;
      }
    }

    List<String> said = _tokens(text);
    for (final String other in otherNames) {
      final List<String> longer = _tokens(other);
      if (longer.join().runes.length > compact.runes.length) {
        said = _without(said, longer, _noSpaces.hasMatch(other));
      }
    }

    if (noSpaces) {
      bool found = false;
      for (final String word in said) {
        // The name with a list word, in full or written after it.
        if (word.contains(compact) && short != compact) {
          return AiMention.clear;
        }
        for (int at = word.indexOf(short); at >= 0; at = word.indexOf(short, at + 1)) {
          if (_listWordStart.hasMatch(word.substring(at + short.length))) {
            return AiMention.clear;
          }
        }
        if (short.runes.length >= 2 ? word.contains(short) : word == short) {
          found = true;
        }
      }
      if (!found && wanted.length > 1 && _find(said, wanted) >= 0) {
        found = true;
      }
      return found ? AiMention.possible : AiMention.none;
    }

    // Every occurrence counts: the strongest one decides (F2 of the last pass).
    bool found = false;
    for (int i = 0; i + wanted.length <= said.length; i++) {
      if (_at(said, wanted, i)) {
        final int next = i + wanted.length;
        if (endsInListWord ||
            (next < said.length && _sameWord(said[next], 'list'))) {
          return AiMention.clear;
        }
        found = true;
      }
    }
    return found ||
            (shortWords.length < wanted.length && _find(said, shortWords) >= 0)
        ? AiMention.possible
        : AiMention.none;
  }

  // Where [wanted] starts in [said], or -1.
  static int _find(List<String> said, List<String> wanted) {
    for (int i = 0; i + wanted.length <= said.length; i++) {
      if (_at(said, wanted, i)) {
        return i;
      }
    }
    return -1;
  }

  static bool _at(List<String> said, List<String> wanted, int start) {
    if (start + wanted.length > said.length) {
      return false;
    }
    for (int i = 0; i < wanted.length; i++) {
      if (!_sameWord(said[start + i], wanted[i])) {
        return false;
      }
    }
    return true;
  }

  // [said] without the mentions of a list named [name].
  static List<String> _without(
    List<String> said,
    List<String> name,
    bool noSpaces,
  ) {
    if (name.isEmpty) {
      return said;
    }
    if (noSpaces) {
      final String compact = name.join();
      return [
        for (final String word in said)
          ...word.split(compact).where((part) => part.isNotEmpty),
      ];
    }
    final List<String> left = [];
    for (int i = 0; i < said.length; i++) {
      if (_at(said, name, i)) {
        i += name.length - 1;
      } else {
        left.add(said[i]);
      }
    }
    return left;
  }

  // Equal as written, without a plural "s", or with "ies" for "y".
  static bool _sameWord(String a, String b) {
    Set<String> forms(String word) => {
      word,
      _singular(word),
      if (word.length > 4 && word.endsWith('ies'))
        '${word.substring(0, word.length - 3)}y',
    };
    return forms(a).intersection(forms(b)).isNotEmpty;
  }

  static String _singular(String word) {
    return word.length > 3 && word.endsWith('s') && !word.endsWith('ss')
        ? word.substring(0, word.length - 1)
        : word;
  }
}
