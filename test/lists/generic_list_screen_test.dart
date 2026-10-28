import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app_cubit.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/custom_lists.dart';
import 'package:hybrid_note/lists/generic_list_screen.dart';
import 'package:hybrid_note/lists/generic_list_host.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_labels.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:hybrid_note/lists/list_store.dart';
import 'package:hybrid_note/lists/local_list_store.dart';
import 'package:hybrid_note/watch_item.dart';

import '../support/fakes.dart';

final ListDefinition _watch = BuiltinTemplates.watchRead();

ListItem _item(String id, Map<String, dynamic> values, {int day = 1}) {
  final DateTime time = DateTime.utc(2026, 3, day);
  return ListItem(
    id: id,
    listId: _watch.id,
    values: values,
    createdAt: time,
    updatedAt: time,
  );
}

Widget _app(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

// Records what the screen asks the store to do.
class _Recorder implements ListStore {
  final List<ListItem> saved = [];
  final List<String> deleted = [];

  @override
  Future<void> apply(ListChanges changes) async {
    saved.addAll(changes.saved);
    deleted.addAll(changes.deletedIds);
  }

  @override
  Future<void> addOption(String listId, String fieldKey, String value) async {}

  @override
  Future<void> removeOption(String listId, String fieldKey, String value) async {}

  @override
  Future<void> refresh() async {}

  // The screen uses only the item writes above.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _screen(List<ListItem> items, _Recorder recorder) {
  return _app(
    GenericListScreen(
      definition: _watch,
      items: items,
      store: recorder,
      texts: const GenericListTexts(
        title: 'Watch',
        emptyText: 'Nothing here',
        addTooltip: 'Add item',
        addDialogTitle: 'Add',
        editDialogTitle: 'Edit',
      ),
    ),
  );
}

Future<void> _pickOption(WidgetTester tester, String field, String label) async {
  await tester.tap(find.byKey(ValueKey('field-$field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  test('every l10n key the built-ins use has a translation lookup', () {
    final ListLabels labels = ListLabels(lookupAppLocalizations(const Locale('en')));
    final List<String> missing = [];

    for (final ListDefinition definition in BuiltinTemplates.all()) {
      final List<String?> keys = [
        definition.nameKey,
        for (final FieldDefinition field in definition.fields) ...[
          field.labelKey,
          for (final FieldOption option in field.options) option.labelKey,
        ],
      ];
      for (final String? key in keys) {
        if (key != null && labels.lookup(key) == null) {
          missing.add(key);
        }
      }
    }

    expect(missing, isEmpty);
  });

  testWidgets('shows the empty text when there are no items', (tester) async {
    await tester.pumpWidget(_screen(const [], _Recorder()));

    expect(find.text('Nothing here'), findsOneWidget);
  });

  testWidgets('groups items by status in option order with summaries', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen([
        _item('a', {'title': 'Dune', 'type': 'book', 'status': 'completed', 'season': 0, 'episode': 0, 'notes': ''}),
        _item('b', {'title': 'Severance', 'type': 'tvShow', 'status': 'inProgress', 'season': 2, 'episode': 4, 'notes': 'Great'}),
        _item('c', {'title': 'Alien', 'type': 'movie', 'status': 'planned', 'season': 0, 'episode': 0, 'notes': ''}),
      ], _Recorder()),
    );

    final double planned = tester.getTopLeft(find.text('PLANNED · 1')).dy;
    final double inProgress = tester.getTopLeft(find.text('IN PROGRESS · 1')).dy;
    final double completed = tester.getTopLeft(find.text('COMPLETED · 1')).dy;
    expect(planned < inProgress && inProgress < completed, isTrue);

    expect(
      find.text('TV Show · Season 2 · Episode 4 · Great'),
      findsOneWidget,
    );
    expect(find.text('Book'), findsOneWidget);
  });

  testWidgets('add: save needs a title; season only shows for TV shows', (
    tester,
  ) async {
    final _Recorder recorder = _Recorder();
    await tester.pumpWidget(_screen(const [], recorder));

    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();

    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
    expect(saveButton().onPressed, isNull);
    expect(find.byKey(const ValueKey('field-season')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('field-title')), '  Severance ');
    await _pickOption(tester, 'type', 'TV Show');
    expect(find.byKey(const ValueKey('field-season')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('field-season')), '2');
    await tester.pump();

    expect(saveButton().onPressed, isNotNull);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(recorder.saved, hasLength(1));
    final ListItem saved = recorder.saved.single;
    expect(saved.values, {
      'title': 'Severance',
      'type': 'tvShow',
      'status': 'planned',
      'season': 2,
      'episode': 0,
      'notes': '',
    });
    expect(saved.validateAgainst(_watch), isEmpty);
  });

  testWidgets('edit keeps id and createdAt and clears hidden fields', (
    tester,
  ) async {
    final _Recorder recorder = _Recorder();
    final ListItem original = _item('b', {
      'title': 'Severance',
      'type': 'tvShow',
      'status': 'inProgress',
      'season': 2,
      'episode': 4,
      'notes': '',
    });
    await tester.pumpWidget(_screen([original], recorder));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '2'), findsOneWidget);
    await _pickOption(tester, 'type', 'Book');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final ListItem saved = recorder.saved.single;
    expect(saved.id, 'b');
    expect(saved.createdAt, original.createdAt);
    expect(saved.values.containsKey('season'), isFalse);
    expect(saved.values.containsKey('episode'), isFalse);
    expect(saved.values['type'], 'book');
  });

  testWidgets('delete passes the item on', (tester) async {
    final _Recorder recorder = _Recorder();
    await tester.pumpWidget(
      _screen([_item('c', {'title': 'Alien', 'type': 'movie', 'status': 'planned'})], recorder),
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(recorder.deleted.single, 'c');
  });

  testWidgets('Watch/Read adapter adds through AppCubit', (tester) async {
    final FakeAppStorage storage = FakeAppStorage();
    final AppCubit cubit = AppCubit(
      storage: storage,
      driveSyncService: FakeDriveSyncService(),
      deviceId: 'test-device',
    );
    await cubit.loadData();

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: cubit),
          BlocProvider(create: (_) => CustomListsCubit(FakeCustomListsStorage())..load()),
          LocalListStore.provider(),
        ],
        child: _app(const GenericListHost(listId: BuiltinTemplates.watchReadId)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-title')), 'Dune');
    await _pickOption(tester, 'type', 'Book');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final WatchItem added = cubit.state.data.watchItems.single;
    expect(added.title, 'Dune');
    expect(added.type, MediaType.book);
    expect(storage.data.watchItems.single.id, added.id);
    expect(find.text('Book'), findsOneWidget);

    await cubit.close();
  });
}
