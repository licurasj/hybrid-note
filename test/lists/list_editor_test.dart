import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_rules.dart';

import '../support/editor_sections.dart';
import '../support/fake_auth.dart';
import '../support/firestore_store.dart';

// The app on a store holding [lists]; none unless given, so the user's own
// list is the only one.
Future<FirestoreListStore> _pumpApp(WidgetTester tester, {List<ListDefinition> lists = const []}) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final FirestoreListStore store = await widgetTestStore(tester, lists: lists);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    await testApp(auth: FakeAuthService(user: testUser), openStore: (_) => store),
  );
  await settle(tester);
  return store;
}

Future<void> _openLauncher(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('launcher-hub')));
  await tester.pump();
}

void main() {
  testWidgets('"+" creates a list in the editor, which then opens', (tester) async {
    final FirestoreListStore store = await _pumpApp(tester);

    await _openLauncher(tester);
    await tester.tap(find.byKey(const ValueKey('launcher-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('template-blank')));
    await tester.pumpAndSettle();
    expect(find.text('New list'), findsOneWidget);

    // No name yet, so Save stays disabled.
    IconButton save() => tester.widget<IconButton>(find.byKey(const ValueKey('save-list')));
    expect(save().onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('list-name')), 'Plants');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('new-field-name')), 'Light');
    await tester.tap(find.byKey(const ValueKey('new-field-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choice').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-list')));
    await settle(tester);

    final ListDefinition created = store.current.definitions.single;
    expect(created.name, 'Plants');
    expect(created.fields.map((f) => f.key), ['title', 'done', 'light']);
    expect(created.validate(), isEmpty);
    // The new list opens right away.
    expect(find.text('Plants'), findsWidgets);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('long-press a tab to edit; delete shows Undo, which restores it', (tester) async {
    final FirestoreListStore store = await _pumpApp(tester);
    await tester.runAsync(() => store.createList(
      ListDefinition.fromJson({
        'id': 'list-plants',
        'name': 'Plants',
        'icon': 'local_florist',
        'color': '#43A047',
        'fields': [
          {'key': 'title', 'type': 'text', 'label': 'Plant', 'required': true, 'primary': true},
          {'key': 'water', 'type': 'text', 'label': 'Water'},
        ],
        'view': {'kind': 'cards'},
        'updatedAt': DateTime.utc(2026).toIso8601String(),
      }),
    ));
    await tester.runAsync(() => store.apply(
      ListChanges(saved: [
        ListItem(
          id: 'cactus',
          listId: 'list-plants',
          values: const {'title': 'Cactus', 'water': 'rarely'},
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ]),
    ));
    await settle(tester);

    // Change "water" to a number: the old text cannot convert and is kept hidden.
    await _openLauncher(tester);
    await tester.longPress(find.byKey(const ValueKey('launcher-note-list-plants')));
    await tester.pumpAndSettle();
    await openEditorSections(tester);
    await tester.tap(find.byKey(const ValueKey('field-type-water-text')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Number').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('kept hidden'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-list')));
    await settle(tester);

    expect(store.current.definitions.single.field('water')!.type.wire, 'number');
    expect(store.current.items.single['_legacy'], {'water': ['rarely']});

    // Delete, then undo.
    await _openLauncher(tester);
    await tester.longPress(find.byKey(const ValueKey('launcher-note-list-plants')));
    await tester.pumpAndSettle();
    await openEditorSections(tester);
    await tester.tap(find.byKey(const ValueKey('delete-list')));
    await settle(tester);
    expect(store.current.definitions, isEmpty);
    expect(find.text('List deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(store.current.definitions.single.id, 'list-plants');
    expect(store.current.items.single.id, 'cactus');

    // The Undo offer times out by itself, so it never blocks the hub.
    await _openLauncher(tester);
    await tester.longPress(find.byKey(const ValueKey('launcher-note-list-plants')));
    await tester.pumpAndSettle();
    await openEditorSections(tester);
    await tester.tap(find.byKey(const ValueKey('delete-list')));
    await settle(tester);
    expect(find.text('List deleted'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('List deleted'), findsNothing);
  });

  testWidgets('a starter list edits like any list: fields, rename, delete', (tester) async {
    final FirestoreListStore store = await _pumpApp(tester, lists: starterLists());
    const ValueKey<String> tab = ValueKey('launcher-note-${BuiltinTemplates.groceryId}');

    await _openLauncher(tester);
    await tester.longPress(find.byKey(tab));
    await tester.pumpAndSettle();
    await openEditorSections(tester);
    expect(find.byKey(const ValueKey('add-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-list')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('list-name')), 'Shopping');
    await tester.enterText(find.byKey(const ValueKey('list-description')), 'Food and household things');
    await tester.tap(find.byKey(const ValueKey('color-#FF2D55')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-list')));
    await settle(tester);

    final ListDefinition grocery = store.current.definition(BuiltinTemplates.groceryId)!;
    expect(grocery.name, 'Shopping');
    expect(grocery.description, 'Food and household things');
    expect(grocery.color, '#FF2D55');

    await _openLauncher(tester);
    await tester.longPress(find.byKey(tab));
    await tester.pumpAndSettle();
    await openEditorSections(tester);
    // Delete list is at the end of the editor.
    await tester.ensureVisible(find.byKey(const ValueKey('delete-list')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('delete-list')));
    await settle(tester);
    expect(store.current.definition(BuiltinTemplates.groceryId), isNull);
  });

  testWidgets("the description box stops at 200 characters and a cleared default stays cleared (review M2)", (
    tester,
  ) async {
    final FirestoreListStore store = await _pumpApp(tester, lists: starterLists());
    const ValueKey<String> tab = ValueKey('launcher-note-${BuiltinTemplates.groceryId}');
    final Finder box = find.byKey(const ValueKey('list-description'));
    String text() => tester.widget<EditableText>(find.descendant(of: box, matching: find.byType(EditableText))).controller.text;

    await _openLauncher(tester);
    await tester.longPress(find.byKey(tab));
    await tester.pumpAndSettle();
    await openEditorSections(tester);
    expect(text(), contains('shopping'));
    await tester.enterText(box, '\u{1F95A}' * 250);
    await tester.pump();
    expect(text().runes.length, 200);
    expect(find.text('200/200'), findsOneWidget);

    await tester.enterText(box, '');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-list')));
    await settle(tester);
    final ListDefinition grocery = store.current.definition(BuiltinTemplates.groceryId)!;
    expect(grocery.description, isNull);
    expect(grocery.descriptionKey, isNull);

    await _openLauncher(tester);
    await tester.longPress(find.byKey(tab));
    await tester.pumpAndSettle();
    await openEditorSections(tester);
    expect(text(), isEmpty);
  });

  group('a view that names a removed or retyped field', () {
    Future<FirestoreListStore> pumpWithFilter(WidgetTester tester) async {
      final FirestoreListStore store = await _pumpApp(tester);
      await tester.runAsync(() => store.createList(
        ListDefinition.fromJson({
          'id': 'list-plants',
          'name': 'Plants',
          'icon': 'local_florist',
          'color': '#43A047',
          'fields': [
            {'key': 'title', 'type': 'text', 'label': 'Plant', 'required': true, 'primary': true},
            {
              'key': 'kind',
              'type': 'category',
              'label': 'Kind',
              'options': [
                {'value': 'fern'},
                {'value': 'cactus'},
              ],
            },
          ],
          'view': {'kind': 'cards'},
          'updatedAt': DateTime.utc(2026).toIso8601String(),
        }),
      ));
      await settle(tester);

      await _openLauncher(tester);
      await tester.longPress(find.byKey(const ValueKey('launcher-note-list-plants')));
      await tester.pumpAndSettle();
    await openEditorSections(tester);
      // Filter the view by the category field.
      await tester.tap(find.byKey(const ValueKey('filter-null-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kind').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('filter-kind-1')), findsOneWidget);
      return store;
    }

    void expectEditorStillWorks(WidgetTester tester) {
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('filter-null-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-errors')), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byKey(const ValueKey('save-list'))).onPressed,
        isNull,
      );
    }

    testWidgets('deleting the field keeps the editor working', (tester) async {
      await pumpWithFilter(tester);

      await tester.tap(find.byKey(const ValueKey('remove-field-kind')));
      await tester.pumpAndSettle();

      expectEditorStillWorks(tester);
    });

    testWidgets('changing the field to text keeps the editor working', (tester) async {
      await pumpWithFilter(tester);

      await tester.tap(find.byKey(const ValueKey('field-type-kind-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Text').last);
      await tester.pumpAndSettle();

      expectEditorStillWorks(tester);
    });
  });
}
