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

// Malformed AI input never throws (T-19 unit 1): ops and tool arguments
// with wrong types, unknown keys or missing arguments become ListErrors.

final DateTime _t0 = DateTime.utc(2026, 3, 1);
final DateTime _now = DateTime.utc(2026, 3, 2);

final ListDefinition _grocery = BuiltinTemplates.grocery();
final ListDefinition _tasks = BuiltinTemplates.tasks();

ListItem _milk() => ListItem(
  id: 'milk',
  listId: _grocery.id,
  values: const {'title': 'Milk', 'done': false, 'section': 'current'},
  createdAt: _t0,
  updatedAt: _t0,
);

ListItem _call() => ListItem(
  id: 'call',
  listId: _tasks.id,
  values: const {'title': 'Call mum'},
  createdAt: _t0,
  updatedAt: _t0,
);

final ListCatalog _catalog = ListCatalog(
  definitions: [_grocery, _tasks],
  items: [_milk(), _call()],
);

String Function() _ids() {
  int next = 0;
  return () => 'new-${next++}';
}

// A value of a different JSON type than [type] accepts.
List<Object?> _wrongValues(ArgType type) {
  switch (type) {
    case ArgType.string:
      return [7, true, const ['a'], const {'a': 1}];
    case ArgType.boolean:
      return ['yes', 1, const <Object?>[]];
    case ArgType.integer:
      return ['2', 2.5, true];
    case ArgType.number:
      return ['2', false];
    case ArgType.object:
      return ['x', 3, const <Object?>[]];
    case ArgType.list:
      return ['x', const {'a': 1}, 2];
    case ArgType.any:
      return const [];
  }
}

// Arguments that make each op valid on the grocery list.
const Map<PatchOpKind, Map<String, dynamic>> _validArgs = {
  PatchOpKind.setListInfo: {'name': 'Shop', 'icon': 'store', 'color': '#123456', 'aiAllowed': true},
  PatchOpKind.addField: {
    'field': {'key': 'price', 'type': 'number', 'label': 'Price'},
    'index': 1,
  },
  PatchOpKind.removeField: {'key': 'description'},
  PatchOpKind.renameField: {'key': 'description', 'label': 'Notes'},
  PatchOpKind.changeFieldType: {
    'key': 'description',
    'type': 'enum',
    'options': [
      {'value': 'a'},
    ],
  },
  PatchOpKind.setFieldProps: {'key': 'description', 'required': false},
  PatchOpKind.setOptions: {
    'key': 'section',
    'options': [
      {'value': 'current'},
      {'value': 'nextTime'},
    ],
  },
  PatchOpKind.moveField: {'key': 'description', 'index': 0},
  PatchOpKind.setView: {
    'view': {'kind': 'cards'},
  },
  PatchOpKind.addBehavior: {
    'behavior': {'kind': 'clearCompleted'},
  },
  PatchOpKind.removeBehavior: {'kind': 'moveAll'},
};

Set<ListErrorCode> _codes(List<ListError> errors) => {for (final ListError error in errors) error.code};

ListPatchResult _apply(PatchOpKind kind, Map<String, dynamic> args) {
  return ListPatch.apply(_grocery, [_milk()], [ListPatchOp(kind, args)], _now);
}

void main() {
  group('ListPatch.apply on malformed ops', () {
    test('every op kind has its arguments listed', () {
      expect(ListPatchOp.argTypes.keys, unorderedEquals(PatchOpKind.values));
      expect(ListPatchOp.requiredArgs.keys, unorderedEquals(PatchOpKind.values));
      expect(_validArgs.keys, unorderedEquals(PatchOpKind.values));
    });

    for (final PatchOpKind kind in PatchOpKind.values) {
      test('${kind.wire}: the valid arguments apply', () {
        expect(_apply(kind, _validArgs[kind]!).errors, isEmpty);
      });

      for (final MapEntry<String, ArgType> arg in ListPatchOp.argTypes[kind]!.entries) {
        for (final Object? wrong in _wrongValues(arg.value)) {
          test('${kind.wire}: ${arg.key} = $wrong is wrongArgType', () {
            final ListPatchResult result = _apply(kind, {..._validArgs[kind]!, arg.key: wrong});
            final ListError error = result.errors.first;
            expect(error.code, ListErrorCode.wrongArgType);
            expect(error.arg('arg'), arg.key);
            expect(error.arg('expected'), arg.value.wire);
            expect('$error', startsWith('${kind.wire}: "${arg.key}" must be'));
          });
        }
      }

      for (final String arg in ListPatchOp.requiredArgs[kind]!) {
        test('${kind.wire}: missing or null $arg is missingArg', () {
          for (final Map<String, dynamic> args in [
            {..._validArgs[kind]!}..remove(arg),
            {..._validArgs[kind]!, arg: null},
          ]) {
            final ListError error = _apply(kind, args).errors.first;
            expect(error.code, ListErrorCode.missingArg);
            expect('$error', '${kind.wire}: missing "$arg"');
          }
        });
      }

      test('${kind.wire}: an unknown argument is unknownArg', () {
        final ListError error = _apply(kind, {..._validArgs[kind]!, 'colour': 'red'}).errors.first;
        expect(error.code, ListErrorCode.unknownArg);
        expect('$error', '${kind.wire}: unknown "colour"');
      });

      test('${kind.wire}: no junk value of any argument throws', () {
        const List<Object?> junk = [
          null, 0, -1, 2.5, '', 'x', true, <Object?>[], <String, Object?>{},
          [1, 'a'], {'kind': 7}, {'key': null}, [<String, Object?>{}],
        ];
        for (final String arg in {...ListPatchOp.argTypes[kind]!.keys, 'key'}) {
          for (final Object? value in junk) {
            expect(
              () => _apply(kind, {..._validArgs[kind]!, arg: value}),
              returnsNormally,
              reason: '$arg = $value',
            );
          }
        }
      });
    }

    final List<(String, PatchOpKind, Map<String, dynamic>, ListErrorCode, String)> nested = [
      ('unknown key in a field', PatchOpKind.addField, {
        'field': {'key': 'p', 'type': 'text', 'label': 'P', 'colour': 'red'},
      }, ListErrorCode.unknownArg, 'addField: unknown "field.colour"'),
      ('unknown key in an option', PatchOpKind.setOptions, {
        'key': 'section',
        'options': [
          {'value': 'current', 'emoji': 'x'},
        ],
      }, ListErrorCode.unknownArg, 'setOptions: unknown "options[0].emoji"'),
      ('unknown key in visibleWhen', PatchOpKind.addField, {
        'field': {'key': 'p', 'type': 'text', 'label': 'P', 'visibleWhen': {'field': 'section', 'in': ['current'], 'not': true}},
      }, ListErrorCode.unknownArg, 'addField: unknown "field.visibleWhen.not"'),
      ('unknown key in a view', PatchOpKind.setView, {
        'view': {'kind': 'cards', 'sortBy': 'title'},
      }, ListErrorCode.unknownArg, 'setView: unknown "view.sortBy"'),
      ('unknown key in a behavior', PatchOpKind.addBehavior, {
        'behavior': {'kind': 'clearCompleted', 'every': 'day'},
      }, ListErrorCode.unknownArg, 'addBehavior: unknown "behavior.every"'),
      ('a field key that is no string', PatchOpKind.addField, {
        'field': {'key': 3, 'type': 'text', 'label': 'P'},
      }, ListErrorCode.badOp, 'addField: field: "key" must be a string'),
      ('a field type outside the vocabulary', PatchOpKind.addField, {
        'field': {'key': 'p', 'type': 'colour', 'label': 'P'},
      }, ListErrorCode.badOp, 'addField: field "p" type: "colour" is not one of'),
      ('an option that is no object', PatchOpKind.setOptions, {
        'key': 'section',
        'options': ['current'],
      }, ListErrorCode.badOp, 'setOptions: option must be a JSON object'),
      ('changeFieldType options that are no objects', PatchOpKind.changeFieldType, {
        'key': 'description',
        'type': 'enum',
        'options': [1],
      }, ListErrorCode.badOp, 'changeFieldType: option must be a JSON object'),
      ('a view kind that is no string', PatchOpKind.setView, {
        'view': {'kind': 3},
      }, ListErrorCode.badOp, 'setView: view kind: "3" is not one of'),
      ('visibleWhen values that are no list', PatchOpKind.addField, {
        'field': {'key': 'p', 'type': 'text', 'label': 'P', 'visibleWhen': {'field': 'section', 'in': 'current'}},
      }, ListErrorCode.badOp, 'addField: visibleWhen: "in" must be a list'),
      ('a behavior parameter of the wrong type', PatchOpKind.addBehavior, {
        'behavior': {'kind': 'moveAll', 'field': 3, 'from': 'nextTime', 'to': 'current'},
      }, ListErrorCode.ruleNeedsParam, 'behavior moveAll: needs field'),
    ];
    for (final (String name, PatchOpKind kind, Map<String, dynamic> args, ListErrorCode code, String english)
        in nested) {
      test(name, () {
        final ListError error = _apply(kind, args).errors.first;
        expect(error.code, code);
        expect('$error', startsWith(english));
      });
    }
  });

  group('ListPatchOp.fromJson', () {
    test('a non-object or unknown op is a FormatException, not a TypeError', () {
      expect(() => ListPatchOp.fromJson('x'), throwsFormatException);
      expect(() => ListPatchOp.fromJson({'op': 3}), throwsFormatException);
      expect(ListPatchOp.fromJson({'op': 'removeField', 'key': 7}).key, isNull);
    });
  });

  group('patch_list', () {
    test('reads the ops for one of the lists', () {
      final (String? listId, List<ListPatchOp> ops, List<ListError> errors) = ListInput.patchList({
        'listId': _grocery.id,
        'ops': [
          {'op': 'renameField', 'key': 'description', 'label': 'Notes'},
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
            },
          },
        ],
      }, _catalog);

      expect(errors, isEmpty);
      expect(listId, _grocery.id);
      expect(ops.map((op) => op.kind), [PatchOpKind.renameField, PatchOpKind.addBehavior]);
      // Entries become the maps the definition stores.
      expect((ops.last.args['behavior'] as Map)['setField'], {'section': 'nextTime'});
      expect(ListPatch.apply(_grocery, [_milk()], ops, _now).errors, isEmpty);
    });

    final List<(String, Object?, Set<ListErrorCode>)> bad = [
      ('arguments that are no object', 'renameField', {ListErrorCode.wrongArgType}),
      ('no listId or ops', <String, Object?>{}, {ListErrorCode.missingArg}),
      ('a list that is not there', {'listId': 'list-x', 'ops': <Object?>[]}, {ListErrorCode.unknownList}),
      ('ops that are no list', {'listId': 'builtin.grocery', 'ops': 'x'}, {ListErrorCode.wrongArgType}),
      ('an op that is no object', {'listId': 'builtin.grocery', 'ops': ['x']}, {ListErrorCode.wrongArgType}),
      ('an unknown op', {
        'listId': 'builtin.grocery',
        'ops': [
          {'op': 'deleteList'},
        ],
      }, {ListErrorCode.badOp}),
      ('a change of the AI switch', {
        'listId': 'builtin.grocery',
        'ops': [
          {'op': 'setListInfo', 'aiAllowed': false},
        ],
      }, {ListErrorCode.unknownArg}),
      ("a list's own Ticked items", {
        'listId': 'builtin.grocery',
        'ops': [
          {'op': 'setListInfo', 'tickedItems': 'hide'},
        ],
      }, {ListErrorCode.unknownArg}),
      ("a list's own Confirm before deleting", {
        'listId': 'builtin.grocery',
        'ops': [
          {'op': 'setListInfo', 'confirmDelete': false},
        ],
      }, {ListErrorCode.unknownArg}),
      ('a behavior entry without its field', {
        'listId': 'builtin.grocery',
        'ops': [
          {
            'op': 'addBehavior',
            'behavior': {
              'kind': 'copyOnClear',
              'setField': [
                {'value': 'x'},
              ],
            },
          },
        ],
      }, {ListErrorCode.missingArg}),
      ('an unknown top-level argument', {'listId': 'builtin.grocery', 'ops': <Object?>[], 'force': true}, {ListErrorCode.unknownArg}),
    ];
    for (final (String name, Object? args, Set<ListErrorCode> codes) in bad) {
      test('refuses $name', () {
        expect(_codes(ListInput.patchList(args, _catalog).$3), codes);
      });
    }
  });

  group('upsert_items', () {
    (ListChanges, List<ListError>) upsert(Object? args) {
      return ListInput.upsertItems(args, _catalog, newId: _ids(), now: _now);
    }

    test('adds items with the fields\' defaults and edits only the given fields', () {
      final (ListChanges changes, List<ListError> errors) = upsert({
        'listId': _grocery.id,
        'items': [
          {
            'values': [
              {'field': 'title', 'value': 'Eggs'},
            ],
          },
          {
            'id': 'milk',
            'values': [
              {'field': 'description', 'value': '2 litres'},
              {'field': 'section', 'value': null},
            ],
          },
        ],
      });

      expect(errors, isEmpty);
      expect(changes.saved.map((item) => item.toJson()), [
        {
          'id': 'new-0',
          'listId': _grocery.id,
          'values': {'section': 'current', 'title': 'Eggs'},
          'createdAt': _now.toIso8601String(),
          'updatedAt': _now.toIso8601String(),
        },
        {
          'id': 'milk',
          'listId': _grocery.id,
          'values': {'title': 'Milk', 'done': false, 'description': '2 litres'},
          'createdAt': _t0.toIso8601String(),
          'updatedAt': _now.toIso8601String(),
        },
      ]);
    });

    test('an AI time is stored as its UTC moment, a day as a day (F8)', () {
      final (ListChanges changes, List<ListError> errors) = upsert({
        'listId': _tasks.id,
        'items': [
          for (final String value in [
            '2026-11-13T15:00',
            '2026-11-13T15:00:00Z',
            '2026-11-13',
          ])
            {
              'values': [
                {'field': 'title', 'value': 'Call'},
                {'field': 'reminderAt', 'value': value},
              ],
            },
        ],
      });
      expect(errors, isEmpty);
      expect(changes.saved.map((item) => item['reminderAt']), [
        // No zone: this phone's wall clock.
        DateTime(2026, 11, 13, 15).toUtc().toIso8601String(),
        '2026-11-13T15:00:00.000Z',
        '2026-11-13',
      ]);
    });

    test('checklist sub-items get ids and dates', () {
      final (ListChanges changes, List<ListError> errors) = upsert({
        'listId': _tasks.id,
        'items': [
          {
            'values': [
              {'field': 'title', 'value': 'Move'},
              {
                'field': 'subtasks',
                'value': [
                  {'title': 'Boxes', 'done': false},
                ],
              },
            ],
          },
        ],
      });

      expect(errors, isEmpty);
      expect(changes.saved.single['subtasks'], [
        {
          'id': 'new-0',
          'createdAt': _now.toIso8601String(),
          'updatedAt': _now.toIso8601String(),
          'title': 'Boxes',
          'done': false,
        },
      ]);
    });

    final List<(String, Object?, Set<ListErrorCode>, String)> bad = [
      ('arguments that are no object', 3, {ListErrorCode.wrongArgType}, 'upsert_items: "arguments" must be a JSON object'),
      ('no items', {'listId': 'builtin.grocery'}, {ListErrorCode.missingArg}, 'upsert_items: missing "items"'),
      ('a list that is not there', {'listId': 'list-x', 'items': <Object?>[]}, {ListErrorCode.unknownList}, 'no list "list-x" among the user lists'),
      ('an item that is no object', {'listId': 'builtin.grocery', 'items': ['Eggs']}, {ListErrorCode.wrongArgType}, 'upsert_items: "items[0]" must be a JSON object'),
      ('values that are a map', {
        'listId': 'builtin.grocery',
        'items': [
          {'values': {'title': 'Eggs'}},
        ],
      }, {ListErrorCode.wrongArgType}, 'upsert_items: "items[0].values" must be a list'),
      ('an entry with an unknown key', {
        'listId': 'builtin.grocery',
        'items': [
          {
            'values': [
              {'field': 'title', 'value': 'Eggs', 'unit': 'dozen'},
            ],
          },
        ],
      }, {ListErrorCode.unknownArg}, 'upsert_items: unknown "items[0].values[0].unit"'),
      ('an entry whose field is no string', {
        'listId': 'builtin.grocery',
        'items': [
          {
            'values': [
              {'field': 1, 'value': 'Eggs'},
            ],
          },
        ],
      }, {ListErrorCode.wrongArgType}, 'upsert_items: "items[0].values[0].field" must be a string'),
      ('an id that is not in the list', {
        'listId': 'builtin.grocery',
        'items': [
          {'id': 'nope', 'values': <Object?>[]},
        ],
      }, {ListErrorCode.unknownItem}, 'no item "nope" in list "builtin.grocery"'),
      ('an id of another list (Q-36)', {
        'listId': 'builtin.grocery',
        'items': [
          {'id': 'call', 'values': <Object?>[]},
        ],
      }, {ListErrorCode.unknownItem}, 'no item "call" in list "builtin.grocery"'),
      ('the same id twice in one call (N3)', {
        'listId': 'builtin.grocery',
        'items': [
          {
            'id': 'milk',
            'values': [
              {'field': 'title', 'value': 'Oat milk'},
            ],
          },
          {
            'id': 'milk',
            'values': [
              {'field': 'done', 'value': true},
            ],
          },
        ],
      }, {ListErrorCode.duplicateItemId}, 'item "milk": duplicate id'),
      ('an id that is no string', {
        'listId': 'builtin.grocery',
        'items': [
          {'id': 5, 'values': <Object?>[]},
        ],
      }, {ListErrorCode.wrongArgType}, 'upsert_items: "items[0].id" must be a string'),
      ('a field the list does not have', {
        'listId': 'builtin.grocery',
        'items': [
          {
            'values': [
              {'field': 'title', 'value': 'Eggs'},
              {'field': 'price', 'value': 3},
            ],
          },
        ],
      }, {ListErrorCode.unknownField}, 'field "price" is not a field of list "builtin.grocery"'),
      ('a value of the wrong type', {
        'listId': 'builtin.grocery',
        'items': [
          {
            'values': [
              {'field': 'title', 'value': 'Eggs'},
              {'field': 'done', 'value': 'yes'},
            ],
          },
        ],
      }, {ListErrorCode.wrongValueType}, 'item "new-0": field "done": must be true or false'),
      ('a new item without its required field', {
        'listId': 'builtin.grocery',
        'items': [
          {'values': <Object?>[]},
        ],
      }, {ListErrorCode.fieldRequired}, 'item "new-0": field "title" is required'),
      ('a choice that is not an option', {
        'listId': 'builtin.grocery',
        'items': [
          {
            'values': [
              {'field': 'title', 'value': 'Eggs'},
              {'field': 'section', 'value': 'someday'},
            ],
          },
        ],
      }, {ListErrorCode.notAnOption}, 'item "new-0": field "section": "someday" is not an option'),
    ];
    for (final (String name, Object? args, Set<ListErrorCode> codes, String english) in bad) {
      test('refuses $name and saves nothing', () {
        final (ListChanges changes, List<ListError> errors) = upsert(args);
        expect(_codes(errors), codes);
        expect('${errors.first}', english);
        expect(changes.isEmpty, isTrue);
      });
    }
  });

  group('delete_items', () {
    test('deletes items of the list', () {
      final (ListChanges changes, List<ListError> errors) =
          ListInput.deleteItems({'listId': _grocery.id, 'ids': ['milk']}, _catalog);
      expect(errors, isEmpty);
      expect(changes.deletedIds, ['milk']);
    });

    final List<(String, Object?, Set<ListErrorCode>)> bad = [
      ('no ids', {'listId': 'builtin.grocery'}, {ListErrorCode.missingArg}),
      ('ids that are no list', {'listId': 'builtin.grocery', 'ids': 'milk'}, {ListErrorCode.wrongArgType}),
      ('an id that is no string', {'listId': 'builtin.grocery', 'ids': [1]}, {ListErrorCode.wrongArgType}),
      ('an id of another list (Q-36)', {'listId': 'builtin.grocery', 'ids': ['call']}, {ListErrorCode.unknownItem}),
      ('a list that is not there', {'listId': 'list-x', 'ids': ['milk']}, {ListErrorCode.unknownList}),
    ];
    for (final (String name, Object? args, Set<ListErrorCode> codes) in bad) {
      test('refuses $name and deletes nothing', () {
        final (ListChanges changes, List<ListError> errors) = ListInput.deleteItems(args, _catalog);
        expect(_codes(errors), codes);
        expect(changes.isEmpty, isTrue);
      });
    }
  });

  group('lists with AI off (Q-36)', () {
    final ListDefinition private = ListDefinition.fromJson({
      ..._tasks.toJson(),
      'id': 'private',
      'name': 'Private',
      'aiAllowed': false,
    });
    final ListItem secret = ListItem(
      id: 'secret',
      listId: 'private',
      values: const {'title': 'Secret'},
      createdAt: _t0,
      updatedAt: _t0,
    );
    final ListCatalog catalog = ListCatalog(
      definitions: [_grocery, private],
      items: [_milk(), secret],
    );
    const List<ListErrorCode> refused = [ListErrorCode.aiNotAllowed];

    test('upsert_items adds nothing to it and changes none of its items', () {
      for (final Map<String, Object?> item in [
        {
          'values': [
            {'field': 'title', 'value': 'x'},
          ],
        },
        {
          'id': 'secret',
          'values': [
            {'field': 'title', 'value': 'x'},
          ],
        },
      ]) {
        final (ListChanges changes, List<ListError> errors) = ListInput.upsertItems(
          {'listId': 'private', 'items': [item]},
          catalog,
          newId: _ids(),
          now: _now,
        );
        expect(errors.map((e) => e.code), refused);
        expect(errors.single.toString(), 'list "private" does not allow AI changes');
        expect(changes.isEmpty, isTrue);
      }
    });

    test('delete_items deletes none of its items', () {
      final (ListChanges changes, List<ListError> errors) =
          ListInput.deleteItems({'listId': 'private', 'ids': ['secret']}, catalog);
      expect(errors.map((e) => e.code), refused);
      expect(changes.isEmpty, isTrue);
    });

    test('patch_list changes nothing of its structure', () {
      final (String? listId, List<ListPatchOp> ops, List<ListError> errors) = ListInput.patchList({
        'listId': 'private',
        'ops': [
          {'op': 'removeField', 'key': 'title'},
        ],
      }, catalog);
      expect(errors.map((e) => e.code), refused);
      expect(listId, isNull);
      expect(ops, isEmpty);
    });

    test('the other lists of the same catalog still work', () {
      final (ListChanges changes, List<ListError> errors) =
          ListInput.deleteItems({'listId': _grocery.id, 'ids': ['milk']}, catalog);
      expect(errors, isEmpty);
      expect(changes.deletedIds, ['milk']);
    });
  });

  group('create_list', () {
    Map<String, dynamic> runs() => {
      'name': 'Runs',
      'icon': 'directions_run',
      'color': '#1E88E5',
      'fields': [
        {'key': 'title', 'type': 'text', 'label': 'Route', 'required': true, 'primary': true},
        {'key': 'km', 'type': 'number', 'label': 'Distance (km)', 'min': 0},
        {'key': 'day', 'type': 'date', 'label': 'Day'},
      ],
      'view': {'kind': 'timeline', 'dateField': 'day', 'timelineGrouping': 'month'},
    };

    (ListDefinition?, List<ListItem>, List<ListError>) create(Object? args) {
      return ListInput.createList(args, listId: 'list-runs', newId: _ids(), now: _now);
    }

    test('builds a valid list with its first items', () {
      final (ListDefinition? definition, List<ListItem> items, List<ListError> errors) = create({
        'list': runs(),
        'items': [
          {
            'values': [
              {'field': 'title', 'value': 'Park loop'},
              {'field': 'km', 'value': 5.2},
            ],
          },
        ],
      });

      expect(errors, isEmpty);
      expect(definition!.id, 'list-runs');
      expect(definition.updatedAt, _now);
      expect(definition.view.kind, ViewKind.timeline);
      expect(items.single.listId, 'list-runs');
      expect(items.single['km'], 5.2);
    });

    test('takes an optional description; a blank one is none (Q-44)', () {
      final (ListDefinition? described, _, List<ListError> errors) =
          create({'list': {...runs(), 'description': ' Runs and how far '}});
      expect(errors, isEmpty);
      expect(described!.description, 'Runs and how far');

      final (ListDefinition? blank, _, _) = create({'list': {...runs(), 'description': ''}});
      expect(blank!.description, isNull);

      final (_, _, List<ListError> long) = create({'list': {...runs(), 'description': 'x' * 201}});
      expect(long.map((error) => error.code), [ListErrorCode.descriptionTooLong]);
    });

    final List<(String, Object?, Set<ListErrorCode>)> bad = [
      ('no list', <String, Object?>{}, {ListErrorCode.missingArg}),
      ('an id chosen by the AI', {'list': {...runs(), 'id': 'mine'}}, {ListErrorCode.unknownArg}),
      ('a missing name', {'list': {...runs()}..remove('name')}, {ListErrorCode.missingArg}),
      ('a name that is no string', {'list': {...runs(), 'name': 4}}, {ListErrorCode.wrongArgType}),
      ('an unknown key in a field', {
        'list': {
          ...runs(),
          'fields': [
            {'key': 'title', 'type': 'text', 'label': 'Route', 'primary': true, 'width': 3},
          ],
        },
      }, {ListErrorCode.unknownArg}),
      ('a field type outside the vocabulary', {
        'list': {
          ...runs(),
          'fields': [
            {'key': 'title', 'type': 'map', 'label': 'Route', 'primary': true},
          ],
        },
      }, {ListErrorCode.badOp}),
      ('a definition that does not fit together', {
        'list': {...runs(), 'view': {'kind': 'sectioned'}},
      }, {ListErrorCode.viewNeedsParam}),
      ('items with ids', {
        'list': runs(),
        'items': [
          {'id': 'x', 'values': [{'field': 'title', 'value': 'A'}]},
        ],
      }, {ListErrorCode.unknownArg}),
      ('an invalid first item', {
        'list': runs(),
        'items': [
          {'values': [{'field': 'km', 'value': -1}]},
        ],
      }, {ListErrorCode.fieldRequired, ListErrorCode.belowMin}),
    ];
    for (final (String name, Object? args, Set<ListErrorCode> codes) in bad) {
      test('refuses $name', () {
        final (ListDefinition? definition, List<ListItem> items, List<ListError> errors) = create(args);
        expect(_codes(errors), codes);
        expect(definition, isNull);
        expect(items, isEmpty);
      });
    }
  });
}
