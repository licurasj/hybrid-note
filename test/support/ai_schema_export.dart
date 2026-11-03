import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';

// Builds the files the AI function copies from schema/ (T-19 unit 1):
// - ai_tools.bundle.json and ai_tools.strict.json, the tools of
//   ai_tools.schema.json with every $ref resolved into the tool's own
//   $defs (a provider gets one tool at a time);
// - ai_examples.json, list designs in the create_list input format: the
//   four templates with English labels and a few more designed lists.
// The tests compare them with the files in schema/;
// `flutter test --update-goldens` rewrites the files instead.

const String aiToolsSource = 'schema/ai_tools.schema.json';
const String aiToolsBundle = 'schema/ai_tools.bundle.json';
const String aiToolsStrict = 'schema/ai_tools.strict.json';
const String aiExamplesFile = 'schema/ai_examples.json';

const String _listSchemaFile = 'list_definition.schema.json';

Map<String, dynamic> readJson(String path) {
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

String prettyJson(Object? json) =>
    '${const JsonEncoder.withIndent('  ').convert(json)}\n';

// Keywords Claude's strict tool use does not accept (claude-api skill,
// "JSON Schema Limitations", cached 2026-10-06): numeric and string
// constraints and array size limits ("complex array constraints"); pattern
// is not listed either way, so it is left out too. The device checks all of
// them again (lib/lists/list_input.dart, ListDefinition.validate).
const Set<String> strictUnsupported = {
  'minLength',
  'maxLength',
  'pattern',
  'minimum',
  'maximum',
  'exclusiveMinimum',
  'exclusiveMaximum',
  'multipleOf',
  'minItems',
  'maxItems',
};

// The tools, each with an input_schema that has only local refs.
List<Map<String, dynamic>> bundleAiTools({required bool strict}) {
  final Map<String, dynamic> source = readJson(aiToolsSource);
  final Map<String, dynamic> listDefs =
      readJson('schema/$_listSchemaFile')[r'$defs'] as Map<String, dynamic>;
  final Map<String, dynamic> sourceDefs =
      source[r'$defs'] as Map<String, dynamic>;

  return [
    for (final Map<String, dynamic> tool
        in (source['tools'] as List).cast<Map<String, dynamic>>())
      _bundleTool(tool, sourceDefs, listDefs, strict: strict),
  ];
}

Map<String, dynamic> _bundleTool(
  Map<String, dynamic> tool,
  Map<String, dynamic> sourceDefs,
  Map<String, dynamic> listDefs, {
  required bool strict,
}) {
  final Map<String, dynamic> defs = {};
  final Map<String, String> origin = {};

  // Copies [node], pointing every ref at the bundle's $defs and
  // copying the defs it names. [inListSchema]: refs in [node] are
  // relative to list_definition.schema.json.
  Object? resolve(Object? node, bool inListSchema) {
    if (node is List) {
      return [for (final Object? entry in node) resolve(entry, inListSchema)];
    }
    if (node is! Map<String, dynamic>) {
      return node;
    }
    final Map<String, dynamic> copy = {};
    for (final MapEntry<String, dynamic> entry in node.entries) {
      if (entry.key == r'$ref') {
        final String ref = entry.value as String;
        final bool toListSchema =
            inListSchema || ref.startsWith('$_listSchemaFile#');
        final String name = ref.substring(
          ref.indexOf(r'#/$defs/') + r'#/$defs/'.length,
        );
        final String from = toListSchema ? _listSchemaFile : aiToolsSource;
        if (origin[name] != null && origin[name] != from) {
          throw StateError('def "$name" is in both schema files');
        }
        if (origin[name] == null) {
          origin[name] = from;
          final Object? def = (toListSchema ? listDefs : sourceDefs)[name];
          if (def == null) {
            throw StateError('unresolved ref $ref');
          }
          defs[name] = resolve(def, toListSchema);
        }
        copy[r'$ref'] = '#/\$defs/$name';
      } else if (strict &&
          strictUnsupported.contains(entry.key) &&
          entry.value is! Map) {
        continue;
      } else if (entry.key == 'properties') {
        copy['properties'] = {
          for (final MapEntry<String, dynamic> property
              in (entry.value as Map<String, dynamic>).entries)
            property.key: resolve(property.value, inListSchema),
        };
      } else {
        copy[entry.key] = resolve(entry.value, inListSchema);
      }
    }
    return copy;
  }

  final Map<String, dynamic> input =
      resolve(tool['input_schema'], false) as Map<String, dynamic>;
  return {
    'name': tool['name'],
    'description': tool['description'],
    if (strict) 'strict': true,
    'input_schema': {
      ...input,
      if (defs.isNotEmpty)
        r'$defs': {
          for (final String name in defs.keys.toList()..sort())
            name: defs[name],
        },
    },
  };
}

// The English text of an l10n key, from lib/l10n/app_en.arb.
String _english(String key) {
  final Object? text = readJson('lib/l10n/app_en.arb')[key];
  if (text is! String) {
    throw StateError('no English text for "$key"');
  }
  return text;
}

// A map with free keys as {field, value} entries, the AI format.
List<Map<String, dynamic>> _entries(Object? map) {
  return [
    for (final MapEntry<dynamic, dynamic> entry
        in (map as Map? ?? const {}).entries)
      {'field': entry.key, 'value': entry.value},
  ];
}

// A definition as a create_list `list`: English labels, no ids, dates or
// template, free-key maps as entries.
Map<String, dynamic> aiListOf(ListDefinition definition) {
  final Map<String, dynamic> json = definition.toJson();
  String label(Map<String, dynamic> part) =>
      part['label'] as String? ?? _english(part['labelKey'] as String);
  return {
    'name': definition.name ?? _english(definition.nameKey!),
    'icon': json['icon'],
    'color': json['color'],
    'fields': [
      for (final Map<String, dynamic> field
          in (json['fields'] as List).cast<Map<String, dynamic>>())
        {
          for (final MapEntry<String, dynamic> entry in field.entries)
            if (entry.key != 'labelKey') entry.key: entry.value,
          'label': label(field),
          if (field['options'] != null)
            'options': [
              for (final Map<String, dynamic> option
                  in (field['options'] as List).cast<Map<String, dynamic>>())
                {'value': option['value'], 'label': label(option)},
            ],
        },
    ],
    'view': json['view'],
    if ((json['behaviors'] as List).isNotEmpty)
      'behaviors': [
        for (final Map<String, dynamic> behavior
            in (json['behaviors'] as List).cast<Map<String, dynamic>>())
          {
            ...behavior,
            if (behavior['where'] != null) 'where': _entries(behavior['where']),
            if (behavior['setField'] != null)
              'setField': _entries(behavior['setField']),
          },
      ],
  };
}

Map<String, dynamic> _example(
  String id,
  String request,
  Map<String, dynamic> list,
) {
  return {
    'id': id,
    'request': request,
    'tool': 'create_list',
    'input': {'list': list},
  };
}

// Example list designs for the AI (Q-32): the templates and a few more
// that use numbers, ratings, conditions, sections and repeating items.
List<Map<String, dynamic>> aiExamples() {
  return [
    _example(
      'tasks',
      'I need a to-do list with categories, dates and repeating tasks',
      aiListOf(BuiltinTemplates.tasks()),
    ),
    _example(
      'grocery',
      'Make me a shopping list where staples come back next time',
      aiListOf(BuiltinTemplates.grocery()),
    ),
    _example(
      'journal',
      'I want to keep a journal',
      aiListOf(BuiltinTemplates.journal()),
    ),
    _example(
      'watchRead',
      'A list of movies, shows and books I want to watch or read',
      aiListOf(BuiltinTemplates.watchRead()),
    ),
    _example('runLog', 'I need a list for my runs', {
      'name': 'Runs',
      'icon': 'list',
      'color': '#1E88E5',
      'fields': [
        {
          'key': 'title',
          'type': 'text',
          'label': 'Route',
          'required': true,
          'primary': true,
        },
        {'key': 'day', 'type': 'date', 'label': 'Day', 'required': true},
        {'key': 'km', 'type': 'number', 'label': 'Distance (km)', 'min': 0},
        {'key': 'minutes', 'type': 'number', 'label': 'Time (min)', 'min': 0},
        {
          'key': 'effort',
          'type': 'rating',
          'label': 'Effort',
          'min': 1,
          'max': 5,
        },
        {'key': 'notes', 'type': 'longText', 'label': 'Notes'},
      ],
      'view': {
        'kind': 'timeline',
        'dateField': 'day',
        'timelineGrouping': 'month',
      },
    }),
    _example('readingList', 'Keep track of books I want to read', {
      'name': 'Reading',
      'icon': 'book',
      'color': '#8E24AA',
      'fields': [
        {
          'key': 'title',
          'type': 'text',
          'label': 'Title',
          'required': true,
          'primary': true,
        },
        {'key': 'author', 'type': 'text', 'label': 'Author'},
        {
          'key': 'status',
          'type': 'enum',
          'label': 'Status',
          'role': 'status',
          'options': [
            {'value': 'toRead', 'label': 'To read'},
            {'value': 'reading', 'label': 'Reading'},
            {'value': 'finished', 'label': 'Finished'},
          ],
          'default': 'toRead',
        },
        {
          'key': 'rating',
          'type': 'rating',
          'label': 'Rating',
          'min': 1,
          'max': 5,
          'visibleWhen': {
            'field': 'status',
            'in': ['finished'],
          },
        },
        {'key': 'genres', 'type': 'tags', 'label': 'Genres'},
      ],
      'view': {
        'kind': 'grouped',
        'groupBy': 'status',
        'filterChipsBy': 'genres',
      },
    }),
    _example('packingList', 'A packing list for trips, sorted by bag', {
      'name': 'Packing',
      'icon': 'checklist',
      'color': '#FB8C00',
      'fields': [
        {
          'key': 'title',
          'type': 'text',
          'label': 'Item',
          'required': true,
          'primary': true,
        },
        {
          'key': 'packed',
          'type': 'checkbox',
          'label': 'Packed',
          'role': 'completion',
        },
        {
          'key': 'bag',
          'type': 'enum',
          'label': 'Bag',
          'role': 'section',
          'options': [
            {'value': 'carryOn', 'label': 'Carry-on'},
            {'value': 'suitcase', 'label': 'Suitcase'},
          ],
          'default': 'suitcase',
        },
        {'key': 'count', 'type': 'counter', 'label': 'How many', 'min': 1},
      ],
      'view': {'kind': 'sectioned', 'sectionBy': 'bag'},
    }),
    _example('chores', 'Household chores that repeat every week or month', {
      'name': 'Chores',
      'icon': 'pending_actions',
      'color': '#00897B',
      'fields': [
        {
          'key': 'title',
          'type': 'text',
          'label': 'Chore',
          'required': true,
          'primary': true,
        },
        {
          'key': 'done',
          'type': 'checkbox',
          'label': 'Done',
          'role': 'completion',
        },
        {'key': 'due', 'type': 'dateTime', 'label': 'Due', 'role': 'reminder'},
        {'key': 'repeat', 'type': 'recurrence', 'label': 'Repeats'},
        {
          'key': 'room',
          'type': 'category',
          'label': 'Room',
          'role': 'category',
          'options': [
            {'value': 'Kitchen', 'label': 'Kitchen'},
            {'value': 'Bathroom', 'label': 'Bathroom'},
          ],
        },
      ],
      'view': {'kind': 'checklist', 'filterChipsBy': 'room', 'bucketBy': 'due'},
      'behaviors': [
        {
          'kind': 'recurOnClear',
          'dateField': 'due',
          'recurrenceField': 'repeat',
        },
        {'kind': 'clearCompleted'},
      ],
    }),
  ];
}

// Expects [path] to hold [json]; with --update-goldens it writes it.
void expectFileMatches(String path, Object? json) {
  final String text = prettyJson(json);
  if (autoUpdateGoldenFiles) {
    File(path).writeAsStringSync(text);
    return;
  }
  final File file = File(path);
  expect(
    file.existsSync(),
    isTrue,
    reason: '$path is missing; run flutter test --update-goldens',
  );
  expect(
    file.readAsStringSync().replaceAll('\r\n', '\n'),
    text,
    reason: '$path is out of date; run flutter test --update-goldens',
  );
}
