import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app_cubit.dart';
import 'package:hybrid_note/lists/custom_lists.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:hybrid_note/lists/local_list_store.dart';
import 'package:hybrid_note/app/hybrid_note_app.dart';

import '../support/fakes.dart';

Future<CustomListsCubit> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final CustomListsCubit custom = CustomListsCubit(FakeCustomListsStorage())..load();
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => AppCubit(
            storage: FakeAppStorage(),
            driveSyncService: FakeDriveSyncService(),
            deviceId: 'd',
          )..loadData(),
        ),
        BlocProvider.value(value: custom),
        LocalListStore.provider(),
      ],
      child: const HybridNoteApp(),
    ),
  );
  await tester.pumpAndSettle();
  return custom;
}

Future<void> _openLauncher(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('launcher-hub')));
  await tester.pump();
}

void main() {
  testWidgets('"+" creates a list in the editor, which then opens', (tester) async {
    final CustomListsCubit custom = await _pumpApp(tester);

    await _openLauncher(tester);
    await tester.tap(find.byKey(const ValueKey('launcher-add')));
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
    await tester.pumpAndSettle();

    final ListDefinition created = custom.state.definitions.single;
    expect(created.name, 'Plants');
    expect(created.fields.map((f) => f.key), ['title', 'done', 'light']);
    expect(created.validate(), isEmpty);
    // The new list opens right away.
    expect(find.text('Plants'), findsWidgets);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('long-press a tab to edit; delete shows Undo, which restores it', (tester) async {
    final CustomListsCubit custom = await _pumpApp(tester);
    await custom.createList(
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
    );
    await custom.apply(
      ListChanges(saved: [
        ListItem(
          id: 'cactus',
          listId: 'list-plants',
          values: const {'title': 'Cactus', 'water': 'rarely'},
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ]),
    );
    await tester.pump();

    // Change "water" to a number: the old text cannot convert and is kept hidden.
    await _openLauncher(tester);
    await tester.longPress(find.byKey(const ValueKey('launcher-note-list-plants')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('field-type-water-text')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Number').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('kept hidden'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-list')));
    await tester.pumpAndSettle();

    expect(custom.state.definitions.single.field('water')!.type.wire, 'number');
    expect(custom.state.items.single['_legacy'], {'water': ['rarely']});

    // Delete, then undo.
    await _openLauncher(tester);
    await tester.longPress(find.byKey(const ValueKey('launcher-note-list-plants')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-list')));
    await tester.pumpAndSettle();
    expect(custom.state.definitions, isEmpty);
    expect(find.text('List deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(custom.state.definitions.single.id, 'list-plants');
    expect(custom.state.items.single.id, 'cactus');

    // The Undo offer times out by itself, so it never blocks the hub.
    await _openLauncher(tester);
    await tester.longPress(find.byKey(const ValueKey('launcher-note-list-plants')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-list')));
    await tester.pumpAndSettle();
    expect(find.text('List deleted'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('List deleted'), findsNothing);
  });

  testWidgets('built-in lists: name and colour change, fields stay', (tester) async {
    final CustomListsCubit custom = await _pumpApp(tester);

    await _openLauncher(tester);
    await tester.longPress(find.byKey(const ValueKey('launcher-note-builtin.grocery')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-field')), findsNothing);
    expect(find.byKey(const ValueKey('delete-list')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('list-name')), 'Shopping');
    await tester.tap(find.byKey(const ValueKey('color-#FF2D55')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-list')));
    await tester.pumpAndSettle();

    expect(custom.state.builtinInfo['builtin.grocery'], {'name': 'Shopping', 'color': '#FF2D55'});
    await _openLauncher(tester);
    expect(find.text('Shopping'), findsOneWidget);
  });

  group('a view that names a removed or retyped field', () {
    Future<CustomListsCubit> pumpWithFilter(WidgetTester tester) async {
      final CustomListsCubit custom = await _pumpApp(tester);
      await custom.createList(
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
      );
      await tester.pump();

      await _openLauncher(tester);
      await tester.longPress(find.byKey(const ValueKey('launcher-note-list-plants')));
      await tester.pumpAndSettle();
      // Filter the view by the category field.
      await tester.tap(find.byKey(const ValueKey('filter-null-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kind').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('filter-kind-1')), findsOneWidget);
      return custom;
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
