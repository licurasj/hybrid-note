import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

import '../support/mini_schema.dart';

// schema/list_definition.schema.json is what the AI backend will validate
// against. These tests keep it in step with the Dart vocabulary and check
// that the built-in templates satisfy it.

void main() {
  final Map<String, dynamic> schema = jsonDecode(
    File('schema/list_definition.schema.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final Map<String, dynamic> defs = schema[r'$defs'] as Map<String, dynamic>;
  final MiniSchemaValidator validator = MiniSchemaValidator(schema);

  List<dynamic> schemaEnum(String name) {
    return (defs[name] as Map<String, dynamic>)['enum'] as List<dynamic>;
  }

  final Map<String, List<WireName>> vocabularies = {
    'fieldType': FieldType.values,
    'fieldRole': FieldRole.values,
    'viewKind': ViewKind.values,
    'timelineGrouping': TimelineGrouping.values,
    'behaviorKind': BehaviorKind.values,
    'recurrenceFrequency': RecurrenceFrequency.values,
  };

  vocabularies.forEach((name, values) {
    test('schema $name matches the Dart vocabulary', () {
      expect(schemaEnum(name), values.map((value) => value.wire).toList());
    });
  });

  test('schema formatVersion matches the Dart format version', () {
    final Map<String, dynamic> properties =
        schema['properties'] as Map<String, dynamic>;
    expect(
      (properties['formatVersion'] as Map<String, dynamic>)['const'],
      ListDefinition.currentFormatVersion,
    );
  });

  for (final ListDefinition definition in BuiltinTemplates.all(
    taskCategories: ['Work'],
  )) {
    test('${definition.id} satisfies the schema', () {
      final Object? json = jsonDecode(jsonEncode(definition.toJson()));
      expect(validator.validate(json), isEmpty);
    });
  }

  test('the schema rejects a field type outside the vocabulary', () {
    final Map<String, dynamic> json =
        jsonDecode(jsonEncode(BuiltinTemplates.journal().toJson()))
            as Map<String, dynamic>;
    ((json['fields'] as List<dynamic>)[1] as Map<String, dynamic>)['type'] =
        'colourPicker';

    expect(validator.validate(json), contains(contains('not in enum')));
  });

  test('the schema rejects unknown keys', () {
    final Map<String, dynamic> json =
        jsonDecode(jsonEncode(BuiltinTemplates.journal().toJson()))
            as Map<String, dynamic>;
    json['script'] = 'alert(1)';

    expect(validator.validate(json), contains(contains('unexpected "script"')));
  });
}
