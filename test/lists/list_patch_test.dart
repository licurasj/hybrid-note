import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_error.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_patch.dart';

final DateTime _t0 = DateTime.utc(2026, 3, 1);
final DateTime _t1 = DateTime.utc(2026, 3, 2);

ListDefinition _books() {
  return ListDefinition.fromJson({
    'id': 'books',
    'name': 'Books',
    'icon': 'book',
    'color': '#123456',
    'fields': [
      {'key': 'title', 'type': 'text', 'label': 'Title', 'required': true, 'primary': true},
      {'key': 'price', 'type': 'text', 'label': 'Price'},
      {'key': 'shop', 'type': 'text', 'label': 'Shop'},
    ],
    'view': {'kind': 'cards'},
    'updatedAt': _t0.toIso8601String(),
  });
}

ListItem _item(String id, Map<String, dynamic> values) {
  return ListItem(id: id, listId: 'books', values: {'title': id, ...values}, createdAt: _t0, updatedAt: _t0);
}

void main() {
  final List<ListItem> items = [
    _item('a', {'price': '4', 'shop': 'Corner'}),
    _item('b', {'price': r'$3', 'shop': 'corner'}),
    _item('c', {'price': 'about 5', 'shop': 'Market'}),
    _item('d', {'price': ''}),
  ];

  test('changing text to number converts what it can and hides the rest', () {
    final ListPatchResult result = ListPatch.apply(_books(), items, const [
      ListPatchOp(PatchOpKind.changeFieldType, {'key': 'price', 'type': 'number'}),
    ], _t1);

    expect(result.isValid, isTrue);
    expect(result.items[0]['price'], 4);
    expect(result.items[1]['price'], isNull);
    expect(result.items[1]['_legacy'], {'price': [r'$3']});
    expect(result.items[2]['_legacy'], {'price': ['about 5']});
    expect(result.items[3].values.containsKey('price'), isFalse);
    expect(result.hiddenValues, 2);
    expect(result.changedItemIds, {'a', 'b', 'c', 'd'});
  });

  test('a stored _legacy that is not a map is replaced, not a crash (N5)', () {
    final ListPatchResult result = ListPatch.apply(_books(), [
      _item('x', {'price': 'about 5', '_legacy': 'broken'}),
    ], const [
      ListPatchOp(PatchOpKind.changeFieldType, {'key': 'price', 'type': 'number'}),
    ], _t1);

    expect(result.isValid, isTrue);
    expect(result.items.single['_legacy'], {'price': ['about 5']});
    expect(result.items[0].updatedAt, _t1);
    expect(result.definition.schemaRevision, 2);
    for (final ListItem item in result.items) {
      expect(item.validateAgainst(result.definition), isEmpty);
    }
  });

  test('changing text to a choice offers the values already used', () {
    final ListPatchResult result = ListPatch.apply(_books(), items, const [
      ListPatchOp(PatchOpKind.changeFieldType, {'key': 'shop', 'type': 'enum'}),
    ], _t1);

    expect(result.definition.field('shop')!.options.map((o) => o.value), ['Corner', 'Market']);
    // "corner" matches "Corner" regardless of case.
    expect(result.items[1]['shop'], 'Corner');
    expect(result.hiddenValues, 0);
  });

  test('removing a field keeps its values on the items', () {
    final ListPatchResult result = ListPatch.apply(_books(), items, const [
      ListPatchOp(PatchOpKind.removeField, {'key': 'shop'}),
    ], _t1);

    expect(result.definition.field('shop'), isNull);
    expect(result.items[0]['shop'], 'Corner');
    expect(result.items[0].validateAgainst(result.definition), isEmpty);
  });

  test('checklist and recurrence do not take each other\'s values', () {
    ListDefinition plan(String type) => ListDefinition.fromJson({
          ..._books().toJson(),
          'fields': [
            {'key': 'title', 'type': 'text', 'label': 'Title', 'required': true, 'primary': true},
            {'key': 'plan', 'type': type, 'label': 'Plan'},
          ],
        });
    const Map<String, dynamic> weekly = {'frequency': 'weekly'};
    final List<Map<String, dynamic>> steps = [
      {'id': 's1', 'title': 'Step', 'done': false, 'createdAt': _t0.toIso8601String(), 'updatedAt': _t0.toIso8601String()},
    ];

    final ListPatchResult toChecklist = ListPatch.apply(plan('recurrence'), [
      _item('a', {'plan': weekly}),
    ], const [
      ListPatchOp(PatchOpKind.changeFieldType, {'key': 'plan', 'type': 'checklist'}),
    ], _t1);
    expect(toChecklist.isValid, isTrue);
    expect(toChecklist.hiddenValues, 1);
    expect(toChecklist.items.single['plan'], isNull);
    expect(toChecklist.items.single['_legacy'], {'plan': [weekly]});
    expect(toChecklist.items.single.validateAgainst(toChecklist.definition), isEmpty);

    final ListPatchResult toRecurrence = ListPatch.apply(plan('checklist'), [
      _item('a', {'plan': steps}),
    ], const [
      ListPatchOp(PatchOpKind.changeFieldType, {'key': 'plan', 'type': 'recurrence'}),
    ], _t1);
    expect(toRecurrence.hiddenValues, 1);
    expect(toRecurrence.items.single['plan'], isNull);
    expect(toRecurrence.items.single['_legacy'], {'plan': [steps]});
    expect(toRecurrence.items.single.validateAgainst(toRecurrence.definition), isEmpty);
  });

  test('a second failed conversion keeps the first hidden value too', () {
    // text -> number hides "about five"; 7 entered later; number -> checklist hides 7.
    final ListPatchResult toNumber = ListPatch.apply(_books(), [
      _item('a', {'price': 'about five'}),
    ], const [
      ListPatchOp(PatchOpKind.changeFieldType, {'key': 'price', 'type': 'number'}),
    ], _t1);
    expect(toNumber.items.single['_legacy'], {'price': ['about five']});

    final ListItem edited = ListItem(
      id: 'a',
      listId: 'books',
      values: {...toNumber.items.single.values, 'price': 7},
      createdAt: _t0,
      updatedAt: _t1,
    );
    final ListPatchResult toChecklist = ListPatch.apply(toNumber.definition, [edited], const [
      ListPatchOp(PatchOpKind.changeFieldType, {'key': 'price', 'type': 'checklist'}),
    ], _t1);
    expect(toChecklist.hiddenValues, 1);
    expect(toChecklist.items.single['_legacy'], {'price': ['about five', 7]});
  });

  test('an old single hidden value reads as a one-entry list', () {
    final ListPatchResult result = ListPatch.apply(_books(), [
      _item('a', {'price': 'about five', '_legacy': {'price': 'older', 'shop': 'kept'}}),
    ], const [
      ListPatchOp(PatchOpKind.changeFieldType, {'key': 'price', 'type': 'number'}),
    ], _t1);

    expect(result.items.single['_legacy'], {'price': ['older', 'about five'], 'shop': 'kept'});
    expect(ListPatch.archivedValues({'shop': 'kept'}, 'shop'), ['kept']);
    expect(ListPatch.archivedValues(null, 'shop'), isEmpty);
  });

  test('setListInfo sets a description, trimmed, and a blank one removes it (Q-44)', () {
    final ListPatchResult described = ListPatch.apply(_books(), items, const [
      ListPatchOp(PatchOpKind.setListInfo, {'description': '  Books to buy  '}),
    ], _t1);
    expect(described.errors, isEmpty);
    expect(described.definition.description, 'Books to buy');
    expect(described.definition.name, _books().name);

    final ListPatchResult untouched = ListPatch.apply(described.definition, items, const [
      ListPatchOp(PatchOpKind.setListInfo, {'color': '#654321'}),
    ], _t1);
    expect(untouched.definition.description, 'Books to buy');

    final ListPatchResult cleared = ListPatch.apply(described.definition, items, const [
      ListPatchOp(PatchOpKind.setListInfo, {'description': ' '}),
    ], _t1);
    expect(cleared.definition.description, isNull);

    final ListPatchResult tooLong = ListPatch.apply(_books(), items, [
      ListPatchOp(PatchOpKind.setListInfo, {'description': 'x' * 201}),
    ], _t1);
    expect(tooLong.errors.map((error) => error.code), contains(ListErrorCode.descriptionTooLong));
    expect(
      const ListPatchOp(PatchOpKind.setListInfo, {'description': 4}).argErrors().map((e) => e.code),
      [ListErrorCode.wrongArgType],
    );
  });

  test("editing or clearing a built-in list's default description drops its key (Q-44)", () {
    final ListDefinition grocery = BuiltinTemplates.grocery();
    final ListPatchResult edited = ListPatch.apply(grocery, const [], const [
      ListPatchOp(PatchOpKind.setListInfo, {'description': 'Saturday market'}),
    ], _t1);
    expect(edited.definition.description, 'Saturday market');
    expect(edited.definition.descriptionKey, isNull);

    final ListPatchResult cleared = ListPatch.apply(grocery, const [], const [
      ListPatchOp(PatchOpKind.setListInfo, {'description': ''}),
    ], _t1);
    expect(cleared.definition.description, isNull);
    expect(cleared.definition.descriptionKey, isNull);
    expect(ListDefinition.fromJson(cleared.definition.toJson()).descriptionKey, isNull);

    final ListPatchResult recolored = ListPatch.apply(grocery, const [], const [
      ListPatchOp(PatchOpKind.setListInfo, {'color': '#654321'}),
    ], _t1);
    expect(recolored.definition.descriptionKey, 'groceryDescription');
  });

  test('add, rename, move and set view build a valid definition', () {
    final ListPatchResult result = ListPatch.apply(_books(), items, const [
      ListPatchOp(PatchOpKind.setListInfo, {'name': 'Reading', 'color': '#654321'}),
      ListPatchOp(PatchOpKind.addField, {
        'field': {
          'key': 'status',
          'type': 'enum',
          'label': 'Status',
          'options': [
            {'value': 'toRead', 'label': 'To read'},
            {'value': 'done', 'label': 'Done'},
          ],
        },
      }),
      ListPatchOp(PatchOpKind.renameField, {'key': 'price', 'label': 'Cost'}),
      ListPatchOp(PatchOpKind.moveField, {'key': 'status', 'index': 1}),
      ListPatchOp(PatchOpKind.setView, {'view': {'kind': 'grouped', 'groupBy': 'status'}}),
    ], _t1);

    expect(result.errors, isEmpty);
    expect(result.definition.name, 'Reading');
    expect(result.definition.fields.map((f) => f.key), ['title', 'status', 'price', 'shop']);
    expect(result.definition.field('price')!.label, 'Cost');
    expect(result.definition.view.groupBy, 'status');
  });

  test('narrowing a choice hides values that no longer exist', () {
    final ListPatchResult withChoice = ListPatch.apply(_books(), items, const [
      ListPatchOp(PatchOpKind.changeFieldType, {'key': 'shop', 'type': 'enum'}),
    ], _t1);
    final ListPatchResult narrowed = ListPatch.apply(withChoice.definition, withChoice.items, const [
      ListPatchOp(PatchOpKind.setOptions, {
        'key': 'shop',
        'options': [
          {'value': 'Corner', 'label': 'Corner'},
        ],
      }),
    ], _t1);

    expect(narrowed.items[2]['_legacy'], {'shop': ['Market']});
    expect(narrowed.hiddenValues, 1);
  });

  test('invalid results are reported, not applied silently', () {
    final ListPatchResult result = ListPatch.apply(_books(), items, const [
      ListPatchOp(PatchOpKind.removeField, {'key': 'nope'}),
      ListPatchOp(PatchOpKind.setView, {'view': {'kind': 'grouped', 'groupBy': 'price'}}),
    ], _t1);

    expect(result.isValid, isFalse);
    expect(result.errors.map((error) => '$error'), contains('removeField: no field "nope"'));
    expect(result.errors.map((error) => '$error'), contains(contains('groupBy "price" must be')));
  });

  test('ops round-trip through JSON, as the AI will send them', () {
    const ListPatchOp op = ListPatchOp(PatchOpKind.changeFieldType, {'key': 'price', 'type': 'number'});
    expect(ListPatchOp.fromJson(op.toJson()).toJson(), op.toJson());
    expect(() => ListPatchOp.fromJson({'op': 'dropTable'}), throwsFormatException);
  });
}
