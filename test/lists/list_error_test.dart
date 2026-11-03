import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/generic_item_dialog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_editor_screen.dart';
import 'package:hybrid_note/lists/list_error.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_labels.dart';
import 'package:hybrid_note/lists/list_patch.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

// Validation errors are codes plus arguments (Q-14 A): ListLabels shows them
// in the user's language, toString() keeps the English the AI and logs read.

final ListDefinition _plants = ListDefinition(
  id: 'plants',
  name: 'Plants',
  icon: 'list',
  color: '#336699',
  fields: const [
    FieldDefinition(key: 'title', type: FieldType.text, label: 'Name', required: true, primary: true),
    FieldDefinition(key: 'count', type: FieldType.counter, label: 'Pots', min: 0),
    FieldDefinition(key: 'done', type: FieldType.checkbox, label: 'Watered', role: FieldRole.completion),
  ],
  view: const ViewDefinition(kind: ViewKind.checklist),
  updatedAt: DateTime.utc(2026),
);

// One error of every kind, with arguments that name the fields above.
ListError _sample(ListErrorCode code) {
  const Map<String, String> args = {
    'field': 'count',
    'version': '2',
    'role': 'status',
    'type': 'counter',
    'types': 'date|dateTime',
    'option': 'big',
    'value': 'huge',
    'target': 'title',
    'view': 'timeline',
    'param': 'dateField',
    'rule': 'recurOnClear',
    'list': 'other',
    'expected': 'plants',
    'min': '0',
    'max': '9',
    'op': 'removeField',
    'detail': 'bad json',
    'arg': 'field.colour',
    'item': 'fern',
  };
  return ListError(code, args, code == ListErrorCode.duplicateItemId ? 'fern' : null);
}

String _translated(String language, ListError error) {
  return ListLabels(lookupAppLocalizations(Locale(language))).error(error, _plants);
}

void main() {
  group('every error kind', () {
    for (final ListErrorCode code in ListErrorCode.values) {
      test('${code.wire} is translated and has English text', () {
        final ListError error = _sample(code);
        final String english = _translated('en', error);
        final String german = _translated('de', error);

        expect(english, isNotEmpty);
        expect(german, isNotEmpty);
        // A missing translation would fall back to the English template.
        for (final String language in ['de', 'es', 'fr', 'ja', 'zh']) {
          expect(_translated(language, error), isNot(english), reason: language);
        }
        expect(english, isNot(contains(code.wire)));
        expect('$error', isNotEmpty);
      });
    }

    test('field keys show as their labels, ids are left out', () {
      expect(_translated('en', _sample(ListErrorCode.belowMin)), '"Pots" must be at least 0.');
      expect(_translated('de', _sample(ListErrorCode.belowMin)), '„Pots“ muss mindestens 0 sein.');
      expect(
        _translated('en', _sample(ListErrorCode.viewParamWrongType)),
        '"Date field": "Pots" must be of type Date / Date and time.',
      );
      expect(
        _translated('de', _sample(ListErrorCode.ruleNeedsCompletion)),
        'Regel „Beim Entfernen wiederholen“ braucht ein Feld, das Einträge als erledigt markiert.',
      );
      expect(_translated('en', _sample(ListErrorCode.duplicateItemId)), 'Two items have the same ID.');
      expect(_translated('ja', _sample(ListErrorCode.missingName)), 'リストには名前が必要です。');
    });
  });

  group('toString keeps the English', () {
    test('definition, view and rule errors', () {
      final ListDefinition broken = ListDefinition.fromJson({
        ..._plants.toJson(),
        'color': 'green',
        'fields': [
          ..._plants.toJson()['fields'] as List,
          {'key': 'when', 'type': 'text', 'label': 'When', 'role': 'status'},
          {'key': 'when', 'type': 'number', 'label': 'Again', 'options': [{'value': 'a'}]},
        ],
        'view': {'kind': 'timeline'},
        'behaviors': [
          {'kind': 'moveAll', 'field': 'title'},
        ],
      });

      expect(broken.validate().map((error) => '$error'), [
        'color must look like #RRGGBB',
        'field "when": status role needs an enum field',
        'field "when": duplicate key',
        'field "when": number fields cannot have options',
        'timeline view needs dateField',
        'behavior moveAll: field "title" must be enum',
      ]);
    });

    test('item errors, with the item id when a store names it', () {
      final ListItem item = ListItem(
        id: 'fern',
        listId: 'plants',
        values: const {'count': -1, 'done': 'yes'},
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final List<ListError> errors = item.validateAgainst(_plants);

      expect(errors.map((error) => '$error'), [
        'field "title" is required',
        'field "count": must be at least 0',
        'field "done": must be true or false',
      ]);
      expect('${errors.first.forItem('fern')}', 'item "fern": field "title" is required');
    });

    test('patch op errors', () {
      final ListPatchResult result = ListPatch.apply(_plants, const [], const [
        ListPatchOp(PatchOpKind.changeFieldType, {'key': 'count', 'type': 'colour'}),
        ListPatchOp(PatchOpKind.addField, {
          'field': {'key': 'title', 'type': 'text', 'label': 'Again'},
        }),
        // An op without its key, as malformed AI input can be.
        ListPatchOp(PatchOpKind.removeField),
      ], DateTime.utc(2026));

      expect(result.errors.map((error) => '$error'), [
        'changeFieldType: unknown type "colour"',
        'addField: "title" already exists',
        'removeField: missing "key"',
      ]);
      expect(result.errors.map((error) => error.code), [
        ListErrorCode.unknownFieldType,
        ListErrorCode.fieldExists,
        ListErrorCode.missingArg,
      ]);
    });
  });

  group('screens show translated errors', () {
    Widget app(String language, Widget home) {
      return MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      );
    }

    for (final (String language, String expected) in [
      ('en', 'The list needs a name.'),
      ('de', 'Die Liste braucht einen Namen.'),
    ]) {
      testWidgets('list editor ($language)', (tester) async {
        // Tall enough that the error text below the sections is built.
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final AppLocalizations loc = lookupAppLocalizations(Locale(language));
        await tester.pumpWidget(
          app(language, ListEditorScreen(definition: blankListDefinition(loc), isNew: true)),
        );
        await tester.pumpAndSettle();

        final Text errors = tester.widget<Text>(find.byKey(const ValueKey('editor-errors')));
        expect(errors.data, expected);
      });
    }

    for (final (String language, String save, String expected) in [
      ('en', 'Save', '"Pots" must be at least 0.'),
      ('de', 'Speichern', '„Pots“ muss mindestens 0 sein.'),
    ]) {
      testWidgets('item dialog ($language)', (tester) async {
        await tester.pumpWidget(
          app(language, Scaffold(body: GenericItemDialog(definition: _plants, title: 'Plant'))),
        );
        await tester.enterText(find.byKey(const ValueKey('field-title')), 'Fern');
        await tester.enterText(find.byKey(const ValueKey('field-count')), '-1');
        await tester.pump();
        await tester.tap(find.text(save));
        await tester.pumpAndSettle();

        expect(find.text(expected), findsOneWidget);
      });
    }
  });
}
