import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_error.dart';
import 'package:hybrid_note/lists/list_input.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_patch.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

import '../support/ai_schema_export.dart';
import '../support/mini_schema.dart';

// The AI tool schemas (schema/ai_tools.*.json, T-19 unit 1) and the Dart
// side that reads the tool inputs (ListInput) must agree: the enums match
// list_vocabulary.dart, every op kind and its arguments match ListPatchOp,
// good tool calls pass both and bad ones fail both. The generated files and
// the example lists stay in step with their sources.

final DateTime _t0 = DateTime.utc(2026, 3, 1);
final ListDefinition _grocery = BuiltinTemplates.grocery();
final ListDefinition _tasks = BuiltinTemplates.tasks();
final ListCatalog _catalog = ListCatalog(
  definitions: [_grocery, _tasks],
  items: [
    ListItem(
      id: 'milk',
      listId: _grocery.id,
      values: const {'title': 'Milk', 'section': 'current'},
      createdAt: _t0,
      updatedAt: _t0,
    ),
  ],
);

const List<String> _toolNames = [
  'create_list',
  'patch_list',
  'upsert_items',
  'delete_items',
  'choose_list',
  'reply',
  'decline',
];

// Every schema object inside [node], with its path.
Iterable<(String, Map<String, dynamic>)> _schemas(Object? node, String path) sync* {
  if (node is Map<String, dynamic>) {
    yield (path, node);
    for (final MapEntry<String, dynamic> entry in node.entries) {
      if (entry.key == 'properties' || entry.key == r'$defs') {
        for (final MapEntry<String, dynamic> inner in (entry.value as Map<String, dynamic>).entries) {
          yield* _schemas(inner.value, '$path.${entry.key}.${inner.key}');
        }
      } else if (entry.key == 'items') {
        yield* _schemas(entry.value, '$path.items');
      } else if (entry.key == 'anyOf') {
        final List<dynamic> options = entry.value as List<dynamic>;
        for (int i = 0; i < options.length; i++) {
          yield* _schemas(options[i], '$path.anyOf[$i]');
        }
      }
    }
  }
}

// Good tool calls: one op of every kind, item adds and edits in the open
// list and in another one (Q-36), deletes.
final Map<String, List<Map<String, dynamic>>> _good = {
  'patch_list': [
    {
      'listId': 'builtin.grocery',
      'ops': [
        {'op': 'setListInfo', 'name': 'Shopping', 'icon': 'shopping_cart', 'color': '#00A63E'},
        {
          'op': 'addField',
          'field': {
            'key': 'price',
            'type': 'number',
            'label': 'Price',
            'min': 0,
            'visibleWhen': {'field': 'section', 'in': ['current']},
          },
          'index': 2,
        },
        {'op': 'renameField', 'key': 'description', 'label': 'Notes'},
        {'op': 'setFieldProps', 'key': 'description', 'required': false},
        {'op': 'moveField', 'key': 'description', 'index': 1},
        {
          'op': 'addField',
          'field': {
            'key': 'shop',
            'type': 'text',
            'label': 'Shop',
          },
        },
        {
          'op': 'changeFieldType',
          'key': 'shop',
          'type': 'enum',
          'options': [
            {'value': 'market', 'label': 'Market'},
          ],
        },
        {
          'op': 'setOptions',
          'key': 'shop',
          'options': [
            {'value': 'market', 'label': 'Market'},
            {'value': 'corner', 'label': 'Corner shop'},
          ],
        },
        {
          'op': 'setView',
          'view': {'kind': 'sectioned', 'sectionBy': 'section', 'filterChipsBy': 'shop'},
        },
        {'op': 'removeBehavior', 'kind': 'copyOnClear'},
        {
          'op': 'addBehavior',
          'behavior': {
            'kind': 'copyOnClear',
            'when': 'autoAddToNext',
            'where': [
              {'field': 'section', 'value': 'current'},
            ],
            'setField': [
              {'field': 'section', 'value': 'nextTime'},
            ],
            'dedupeBy': 'title',
          },
        },
        {'op': 'removeField', 'key': 'price'},
      ],
    },
  ],
  'upsert_items': [
    {
      'listId': 'builtin.grocery',
      'items': [
        {
          'values': [
            {'field': 'title', 'value': 'Eggs'},
          ],
        },
        {
          'values': [
            {'field': 'title', 'value': 'Chicken'},
            {'field': 'description', 'value': '2 lb'},
            {'field': 'autoAddToNext', 'value': true},
          ],
        },
        {
          'id': 'milk',
          'values': [
            {'field': 'done', 'value': true},
            {'field': 'description', 'value': null},
          ],
        },
      ],
    },
    {
      'listId': 'builtin.tasks',
      'items': [
        {
          'values': [
            {'field': 'title', 'value': 'Renew passport'},
            {'field': 'reminderAt', 'value': '2026-11-06T09:00:00.000'},
            {
              'field': 'repeat',
              'value': {'frequency': 'custom', 'customDays': 10},
            },
            {
              'field': 'subtasks',
              'value': [
                {'title': 'Photo', 'done': false},
              ],
            },
          ],
        },
      ],
    },
  ],
  'delete_items': [
    {
      'listId': 'builtin.grocery',
      'ids': ['milk'],
    },
  ],
};

// Bad tool calls both sides refuse.
final Map<String, List<Map<String, dynamic>>> _bad = {
  'patch_list': [
    {'listId': 'builtin.grocery'},
    {
      'listId': 'builtin.grocery',
      'ops': [
        {'op': 'deleteList'},
      ],
    },
    {
      'listId': 'builtin.grocery',
      'ops': [
        {'op': 'setListInfo', 'aiAllowed': false},
      ],
    },
    {
      'listId': 'builtin.grocery',
      'ops': [
        {'op': 'renameField', 'key': 'description'},
      ],
    },
    {
      'listId': 'builtin.grocery',
      'ops': [
        {
          'op': 'addField',
          'field': {'key': 'shop', 'type': 'shopPicker', 'label': 'Shop'},
        },
      ],
    },
    {
      'listId': 'builtin.grocery',
      'ops': [
        {
          'op': 'setView',
          'view': {'kind': 'cards', 'sortBy': 'title'},
        },
      ],
    },
    {
      'listId': 'builtin.grocery',
      'ops': [
        {
          'op': 'addBehavior',
          'behavior': {
            'kind': 'copyOnClear',
            'setField': {'section': 'nextTime'},
          },
        },
      ],
    },
  ],
  'upsert_items': [
    {'listId': 'builtin.grocery', 'items': 'milk'},
    {
      'listId': 'builtin.grocery',
      'items': [
        {
          'values': {'title': 'Eggs'},
        },
      ],
    },
    {
      'listId': 'builtin.grocery',
      'items': [
        {
          'values': [
            {'field': 'title', 'value': 'Eggs', 'note': 'x'},
          ],
        },
      ],
    },
    {
      'listId': 'builtin.grocery',
      'items': [
        {
          'id': 'milk',
          'values': [
            {'field': 'title', 'value': 'Oat milk'},
          ],
          'list': 'other',
        },
      ],
    },
    {
      'listId': 'builtin.grocery',
      'items': [
        {
          'values': [
            {'field': 'title', 'value': 'Eggs'},
            {
              'field': 'title',
              'value': {'text': 'Eggs'},
            },
          ],
        },
      ],
    },
  ],
  'delete_items': [
    {'listId': 'builtin.grocery'},
    {
      'listId': 'builtin.grocery',
      'ids': [3],
    },
  ],
};

// The Dart side's errors for a tool call, including those of applying the
// ops and of the definition a create_list makes.
List<ListError> _dartErrors(String tool, Map<String, dynamic> input) {
  int next = 0;
  String newId() => 'new-${next++}';
  final DateTime now = DateTime.utc(2026, 3, 2);
  switch (tool) {
    case 'patch_list':
      final (String? listId, List<ListPatchOp> ops, List<ListError> errors) = ListInput.patchList(input, _catalog);
      if (errors.isNotEmpty || listId == null) {
        return errors;
      }
      return ListPatch.apply(_catalog.definition(listId)!, _catalog.itemsOf(listId), ops, now).errors;
    case 'upsert_items':
      return ListInput.upsertItems(input, _catalog, newId: newId, now: now).$2;
    case 'delete_items':
      return ListInput.deleteItems(input, _catalog).$2;
    case 'create_list':
      return ListInput.createList(input, listId: 'list-new', newId: newId, now: now).$3;
  }
  throw ArgumentError(tool);
}

void main() {
  final Map<String, dynamic> source = readJson(aiToolsSource);
  final List<Map<String, dynamic>> bundle = bundleAiTools(strict: false);
  final List<Map<String, dynamic>> strict = bundleAiTools(strict: true);

  Map<String, dynamic> tool(List<Map<String, dynamic>> tools, String name) {
    return tools.singleWhere((tool) => tool['name'] == name);
  }

  MiniSchemaValidator validator(List<Map<String, dynamic>> tools, String name) {
    return MiniSchemaValidator(tool(tools, name)['input_schema'] as Map<String, dynamic>);
  }

  Map<String, dynamic> def(String name) => (source[r'$defs'] as Map<String, dynamic>)[name] as Map<String, dynamic>;

  Set<String> propertiesOf(String name) => (def(name)['properties'] as Map<String, dynamic>).keys.toSet();

  group('generated files', () {
    test('ai_tools.bundle.json is the bundled source', () {
      expectFileMatches(aiToolsBundle, bundle);
    });

    test('ai_tools.strict.json is the bundled source for strict mode', () {
      expectFileMatches(aiToolsStrict, strict);
    });

    test('ai_examples.json holds the example lists', () {
      expectFileMatches(aiExamplesFile, {
        'description':
            'Example list designs for the AI (T-19, Q-32), in the create_list input format. Generated by test/support/ai_schema_export.dart from the templates (lib/lists/builtin_templates.dart, English labels) and the designs there; regenerate with flutter test --update-goldens.',
        'examples': aiExamples(),
      });
    });
  });

  group('the tools', () {
    test('are the Q-32 / Q-36 tool set, each with a use-when description', () {
      expect(bundle.map((tool) => tool['name']), _toolNames);
      for (final Map<String, dynamic> tool in bundle) {
        expect(tool['description'], startsWith('Use '), reason: '${tool['name']}');
      }
    });

    for (final (String name, List<Map<String, dynamic>> tools) in [('bundle', bundle), ('strict', strict)]) {
      test('$name: every object closes its keys, every ref is local and resolves', () {
        for (final Map<String, dynamic> tool in tools) {
          final Map<String, dynamic> input = tool['input_schema'] as Map<String, dynamic>;
          final Map<String, dynamic> defs = input[r'$defs'] as Map<String, dynamic>? ?? const {};
          for (final (String path, Map<String, dynamic> schema) in _schemas(input, tool['name'] as String)) {
            if (schema['type'] == 'object' || schema.containsKey('properties')) {
              expect(schema['additionalProperties'], isFalse, reason: path);
              expect(schema['properties'], isA<Map<String, dynamic>>(), reason: path);
            }
            final Object? ref = schema[r'$ref'];
            if (ref != null) {
              expect(schema.keys, [r'$ref'], reason: '$path: nothing beside a ref');
              expect(defs[(ref as String).substring(r'#/$defs/'.length)], isNotNull, reason: path);
            }
            if (name == 'strict') {
              expect(schema.keys.toSet().intersection(strictUnsupported), isEmpty, reason: path);
            }
          }
        }
      });
    }

    test('strict tools say so, the full ones do not', () {
      expect(strict.every((tool) => tool['strict'] == true), isTrue);
      expect(bundle.any((tool) => tool.containsKey('strict')), isFalse);
    });

    final Map<String, List<WireName>> vocabularies = {
      'fieldType': FieldType.values,
      'fieldRole': FieldRole.values,
      'viewKind': ViewKind.values,
      'timelineGrouping': TimelineGrouping.values,
      'behaviorKind': BehaviorKind.values,
      'recurrenceFrequency': RecurrenceFrequency.values,
    };
    vocabularies.forEach((name, values) {
      test('$name matches the Dart vocabulary and says when to use each', () {
        final Map<String, dynamic> enumDef =
            (tool(bundle, name == 'recurrenceFrequency' ? 'upsert_items' : 'create_list')['input_schema']
                    as Map<String, dynamic>)[r'$defs'][name]
                as Map<String, dynamic>;
        expect(enumDef['enum'], values.map((value) => value.wire).toList());
        final String description = enumDef['description'] as String;
        if (name != 'recurrenceFrequency' && name != 'timelineGrouping') {
          for (final WireName value in values) {
            expect(description, contains('${value.wire} ='), reason: '$name ${value.wire}');
          }
        }
      });
    });

    test('the ops are the PatchOpKinds with the Dart arguments', () {
      final List<dynamic> variants = def('aiOp')['anyOf'] as List<dynamic>;
      final Map<String, Map<String, dynamic>> ops = {
        for (final Map<String, dynamic> variant in variants.cast<Map<String, dynamic>>())
          () {
            final Map<String, dynamic> op = def((variant[r'$ref'] as String).substring(r'#/$defs/'.length));
            return (op['properties'] as Map<String, dynamic>)['op']['const'] as String;
          }(): def((variant[r'$ref'] as String).substring(r'#/$defs/'.length)),
      };
      expect(ops.keys, unorderedEquals(PatchOpKind.values.map((kind) => kind.wire)));
      for (final PatchOpKind kind in PatchOpKind.values) {
        final Map<String, dynamic> op = ops[kind.wire]!;
        final Set<String> arguments = (op['properties'] as Map<String, dynamic>).keys.toSet()..remove('op');
        // The AI never changes whether a list may be sent to it.
        final Set<String> dart = ListPatchOp.argTypes[kind]!.keys.toSet()..remove('aiAllowed');
        expect(arguments, dart, reason: kind.wire);
        expect((op['required'] as List).toSet(), containsAll(ListPatchOp.requiredArgs[kind]!), reason: kind.wire);
        expect(op['description'], isNotEmpty, reason: kind.wire);
      }
    });

    test('the objects have the keys ListInput accepts', () {
      expect(propertiesOf('aiField'), InputShape.field.keys.difference({'labelKey'}));
      expect(propertiesOf('aiOption'), InputShape.option.keys.difference({'labelKey'}));
      expect(propertiesOf('aiVisibleWhen'), InputShape.visibleWhen.keys);
      expect(propertiesOf('aiView'), InputShape.view.keys);
      expect(propertiesOf('aiBehavior'), InputShape.behavior.keys);
      expect(propertiesOf('aiNewList'), InputShape.newList.keys);
    });
  });

  group('tool calls', () {
    _good.forEach((name, inputs) {
      for (int i = 0; i < inputs.length; i++) {
        test('good $name #$i: valid for the schemas and the Dart side', () {
          expect(validator(bundle, name).validate(inputs[i]), isEmpty);
          expect(validator(strict, name).validate(inputs[i]), isEmpty);
          expect(_dartErrors(name, inputs[i]), isEmpty);
        });
      }
    });

    _bad.forEach((name, inputs) {
      for (int i = 0; i < inputs.length; i++) {
        test('bad $name #$i: refused by the schema and the Dart side', () {
          expect(validator(bundle, name).validate(inputs[i]), isNotEmpty);
          expect(_dartErrors(name, inputs[i]), isNotEmpty);
        });
      }
    });

    test('the other tools take what their descriptions say', () {
      expect(validator(bundle, 'choose_list').validate({
        'question': 'Grocery or Tasks?',
        'candidates': ['builtin.grocery', 'builtin.tasks'],
      }), isEmpty);
      expect(validator(bundle, 'choose_list').validate({
        'question': 'Which?',
        'candidates': ['a', 'b', 'c', 'd'],
      }), isNotEmpty);
      expect(validator(bundle, 'reply').validate({'text': 'Milk and eggs.'}), isEmpty);
      expect(validator(bundle, 'reply').validate({'text': 'x' * 501}), isNotEmpty);
      expect(validator(strict, 'decline').validate({'reason': 'offTopic'}), isEmpty);
      expect(validator(strict, 'decline').validate({'reason': 'bored'}), isNotEmpty);
    });
  });

  group('example lists', () {
    final List<Map<String, dynamic>> examples = aiExamples();

    test('are the four templates and at least three more designs', () {
      expect(examples.map((e) => e['id']), containsAll(['tasks', 'grocery', 'journal', 'watchRead']));
      expect(examples.length, greaterThanOrEqualTo(7));
    });

    for (final Map<String, dynamic> example in examples) {
      test('${example['id']}: valid for create_list and ListDefinition.validate()', () {
        final Map<String, dynamic> input = example['input'] as Map<String, dynamic>;
        expect(validator(bundle, 'create_list').validate(input), isEmpty);
        expect(validator(strict, 'create_list').validate(input), isEmpty);
        final (ListDefinition? definition, _, List<ListError> errors) =
            ListInput.createList(input, listId: 'list-${example['id']}', newId: () => 'x', now: _t0);
        expect(errors, isEmpty);
        expect(definition!.validate(), isEmpty);
      });
    }

    test('a template example builds the template back', () {
      final (ListDefinition? grocery, _, _) = ListInput.createList(
        examples.singleWhere((e) => e['id'] == 'grocery')['input'],
        listId: _grocery.id,
        newId: () => 'x',
        now: _t0,
      );
      expect(grocery!.behaviors.map((b) => b.toJson()), _grocery.behaviors.map((b) => b.toJson()));
      expect(grocery.fields.map((f) => f.key), _grocery.fields.map((f) => f.key));
      expect(grocery.view.toJson(), _grocery.view.toJson());
      // Items saved by the AI fit the template's rules too.
      expect(
        ListRules.withValues(_catalog.itemsOf(_grocery.id).single, const {'done': true}, _t0).validateAgainst(grocery),
        isEmpty,
      );
    });
  });
}
