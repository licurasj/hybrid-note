import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_error.dart';
import 'package:hybrid_note/lists/list_labels.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';

Map<String, dynamic> _jsonRoundTrip(Map<String, dynamic> json) {
  return jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
}

// A list the AI might propose: not one of the built-ins.
Map<String, dynamic> _plantList() {
  return {
    'formatVersion': 1,
    'id': 'list-plants',
    'name': 'Plants',
    'icon': 'local_florist',
    'color': '#2E7D32',
    'templateId': null,
    'schemaRevision': 1,
    'fields': <dynamic>[
      {'key': 'name', 'type': 'text', 'label': 'Plant', 'required': true, 'primary': true},
      {'key': 'watered', 'type': 'checkbox', 'label': 'Watered', 'role': 'completion'},
      {'key': 'lastWatered', 'type': 'date', 'label': 'Last watered'},
      {'key': 'every', 'type': 'recurrence', 'label': 'Water every'},
      {
        'key': 'light',
        'type': 'enum',
        'label': 'Light',
        'options': [
          {'value': 'low', 'label': 'Low'},
          {'value': 'bright', 'label': 'Bright'},
        ],
      },
      {'key': 'health', 'type': 'rating', 'label': 'Health', 'min': 1, 'max': 5},
    ],
    'view': {'kind': 'grouped', 'groupBy': 'light'},
    'behaviors': [
      {'kind': 'recurOnClear', 'dateField': 'lastWatered', 'recurrenceField': 'every'},
    ],
    'aiAllowed': true,
    'updatedAt': '2026-10-25T00:00:00.000Z',
  };
}

void main() {
  group('built-in templates', () {
    for (final ListDefinition definition in BuiltinTemplates.all(
      taskCategories: ['Work', 'Home'],
    )) {
      test('${definition.id} is valid', () {
        expect(definition.validate(), isEmpty);
      });

      test('${definition.id} survives a JSON round trip unchanged', () {
        final Map<String, dynamic> json = definition.toJson();
        final ListDefinition reloaded =
            ListDefinition.fromJson(_jsonRoundTrip(json));

        expect(reloaded.toJson(), json);
        expect(reloaded.validate(), isEmpty);
      });
    }

    test('every l10n key the templates use exists in app_en.arb', () {
      final Map<String, dynamic> arb = jsonDecode(
        File('lib/l10n/app_en.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Set<String> keys = {
        for (final ListDefinition definition in BuiltinTemplates.all()) ...[
          definition.nameKey!,
          for (final FieldDefinition field in definition.fields) ...[
            if (field.labelKey != null) field.labelKey!,
            for (final FieldOption option in field.options)
              if (option.labelKey != null) option.labelKey!,
          ],
        ],
      };

      expect(keys.where((key) => !arb.containsKey(key)), isEmpty);
    });

    test('task categories become category options', () {
      final ListDefinition tasks =
          BuiltinTemplates.tasks(categories: ['Work', 'Home']);

      expect(
        tasks.field('category')!.options.map((option) => option.value),
        ['Work', 'Home'],
      );
    });
  });

  group('custom definitions', () {
    test('a non-built-in list made from the vocabulary is valid', () {
      final ListDefinition plants = ListDefinition.fromJson(_plantList());

      expect(plants.validate(), isEmpty);
      expect(plants.toJson(), _plantList());
    });

    test('keys from a newer build are kept when saving', () {
      final Map<String, dynamic> json = _plantList()
        ..['sharedWith'] = ['someone'];

      final ListDefinition plants = ListDefinition.fromJson(json);

      expect(plants.toJson()['sharedWith'], ['someone']);
    });

    test('a description round-trips and is left out when there is none (Q-44)', () {
      final Map<String, dynamic> json = _plantList()..['description'] = 'Pots on the balcony';

      final ListDefinition plants = ListDefinition.fromJson(json);

      expect(plants.description, 'Pots on the balcony');
      expect(plants.toJson(), json);
      expect(ListDefinition.fromJson(_plantList()).description, isNull);
      expect(ListDefinition.fromJson(_plantList()).toJson().containsKey('description'), isFalse);
      expect(() => ListDefinition.fromJson(_plantList()..['description'] = 3), throwsFormatException);
    });

    test('built-in lists have a translated default description (Q-44)', () {
      final ListLabels labels = ListLabels(lookupAppLocalizations(const Locale('en')));
      for (final ListDefinition template in BuiltinTemplates.all()) {
        expect(template.descriptionKey, ListDefinition.templateDescriptionKeys[template.templateId]);
        expect(labels.listDescription(template), isNot(template.descriptionKey));
      }
      expect(labels.listDescription(BuiltinTemplates.grocery()), contains('shopping'));
      expect(labels.listDescription(ListDefinition.fromJson(_plantList())), isNull);
    });

    test('a built-in list stored before descriptions gets the default; a cleared one stays cleared', () {
      final Map<String, dynamic> stored = BuiltinTemplates.grocery().toJson()..remove('descriptionKey');
      expect(ListDefinition.fromJson(stored).descriptionKey, 'groceryDescription');

      final Map<String, dynamic> cleared = {...stored, 'descriptionKey': null};
      final ListDefinition read = ListDefinition.fromJson(cleared);
      expect(read.descriptionKey, isNull);
      expect(read.toJson(), containsPair('descriptionKey', null));
      expect(ListDefinition.fromJson(read.toJson()).descriptionKey, isNull);

      final Map<String, dynamic> own = {...stored, 'description': 'Mine'};
      expect(ListDefinition.fromJson(own).descriptionKey, isNull);
    });

    test('a description over 200 characters is reported', () {
      final ListDefinition ok = ListDefinition.fromJson(_plantList()..['description'] = '🌱' * 200);
      final ListDefinition long = ListDefinition.fromJson(_plantList()..['description'] = 'x' * 201);

      expect(ok.validate(), isEmpty);
      expect(long.validate().map((error) => error.code), [ListErrorCode.descriptionTooLong]);
    });

    test('a newer format version is reported', () {
      final ListDefinition plants =
          ListDefinition.fromJson(_plantList()..['formatVersion'] = 2);

      expect(plants.validate().map((error) => '$error'), contains(contains('formatVersion 2')));
    });
  });

  group('rejects', () {
    Map<String, dynamic> withField(int index, Map<String, dynamic> changes) {
      final Map<String, dynamic> json = _plantList();
      final List<dynamic> fields = List<dynamic>.from(json['fields'] as List);
      fields[index] = {...fields[index] as Map<String, dynamic>, ...changes};
      return json..['fields'] = fields;
    }

    test('a field type outside the vocabulary', () {
      expect(
        () => ListDefinition.fromJson(withField(1, {'type': 'colourPicker'})),
        throwsFormatException,
      );
    });

    test('a definition that is not an object', () {
      expect(() => ListDefinition.fromJson('Plants'), throwsFormatException);
    });

    test('missing fields list', () {
      expect(
        () => ListDefinition.fromJson(_plantList()..remove('fields')),
        throwsFormatException,
      );
    });

    List<String> errorsFor(Map<String, dynamic> json) {
      return ListDefinition.fromJson(json).validate().map((error) => '$error').toList();
    }

    test('an enum field without options', () {
      expect(
        errorsFor(withField(4, {'options': <dynamic>[]})),
        contains(contains('enum field needs options')),
      );
    });

    test('two primary fields', () {
      expect(
        errorsFor(withField(2, {'type': 'text', 'primary': true})),
        contains('exactly one field must be primary'),
      );
    });

    test('duplicate field keys', () {
      expect(
        errorsFor(withField(2, {'key': 'name', 'type': 'text'})),
        contains(contains('duplicate key')),
      );
    });

    test('a role on the wrong field type', () {
      expect(
        errorsFor(withField(1, {'type': 'toggle'})),
        contains(contains('completion role needs a checkbox')),
      );
    });

    test('a view grouped by a field that does not exist', () {
      expect(
        errorsFor(_plantList()..['view'] = {'kind': 'grouped', 'groupBy': 'soil'}),
        contains(contains('"soil" is not a field')),
      );
    });

    test('a behavior pointing at a field of the wrong type', () {
      expect(
        errorsFor(
          _plantList()
            ..['behaviors'] = [
              {'kind': 'recurOnClear', 'dateField': 'name', 'recurrenceField': 'every'},
            ],
        ),
        contains(contains('dateField "name" must be date or dateTime')),
      );
    });

    test('moveAll to a value that is not an option', () {
      expect(
        errorsFor(
          _plantList()
            ..['behaviors'] = [
              {'kind': 'moveAll', 'field': 'light', 'from': 'low', 'to': 'dark'},
            ],
        ),
        contains(contains('to must be an option')),
      );
    });

    test('visibleWhen naming a value that is not an option', () {
      expect(
        errorsFor(
          withField(5, {
            'visibleWhen': {'field': 'light', 'in': ['dark']},
          }),
        ),
        contains(contains('visibleWhen "dark" is not an option')),
      );
    });

    test('visibleWhen naming a field that is not an enum', () {
      expect(
        errorsFor(
          withField(5, {
            'visibleWhen': {'field': 'name', 'in': ['x']},
          }),
        ),
        contains(contains('visibleWhen must name an enum field')),
      );
    });

    test('a bad color', () {
      expect(
        errorsFor(_plantList()..['color'] = 'green'),
        contains('color must look like #RRGGBB'),
      );
    });
  });
}
