import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_error.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_patch.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:hybrid_note/lists/list_store.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

import '../support/firestore_store.dart';

// The ListStore contract, written against the interface only. It runs
// against FirestoreListStore on fake_cloud_firestore below; other files can
// run it too (import this file with `show listStoreContract`).
//
// `create` returns a store that holds one starter copy of each template
// (Q-22 D) and no other list; `dispose` releases it after each test. The
// starter lists are ordinary lists, found by their templateId, since their
// list ids are the seeding's choice. Each test first
// waits for the initial load (watch() emits nothing before it, D-12). Writes
// may reach the read side later than they finish and in steps (a list before
// its items), so the tests wait on watch() for all of the state they assert.
void listStoreContract(
  String name,
  Future<ListStore> Function() create, {
  Future<void> Function(ListStore store)? dispose,
}) {
  group('ListStore contract: $name', () {
    late ListStore store;

    setUp(() async {
      store = await create();
      await store.watch().first.timeout(const Duration(seconds: 10));
    });

    tearDown(() async {
      await dispose?.call(store);
    });

    Future<ListCatalog> until(bool Function(ListCatalog catalog) test) {
      return store.watch().firstWhere(test).timeout(const Duration(seconds: 10));
    }

    // The starter copy of [templateId].
    ListDefinition starter(ListCatalog catalog, String templateId) {
      return catalog.definitions.singleWhere((d) => d.templateId == templateId);
    }

    test('the initial load holds the starter lists and no other list', () async {
      final ListCatalog first = await store.watch().first.timeout(const Duration(seconds: 10));
      expect(first.definitions.map((d) => d.templateId), unorderedEquals(_templateIds));
      expect(store.current.definitions.map((d) => d.templateId), unorderedEquals(_templateIds));
      expect(first.definition(_plantsId), isNull);
    });

    test('read after create: the list and its items', () async {
      final List<ListError> errors = await store.createList(_plants(), items: [_plant('fern', 'fern')]);
      expect(errors, isEmpty);

      final ListCatalog catalog = await until(
        (c) => c.definition(_plantsId) != null && c.itemsOf(_plantsId).length == 1,
      );
      expect(catalog.definition(_plantsId)!.toJson(), _plants().toJson());
      expect(catalog.itemsOf(_plantsId).single.toJson(), _plant('fern', 'fern').toJson());
      expect(store.current.definition(_plantsId), isNotNull);
    });

    // Refusals carry the codes the screens translate (Q-14 A).
    Future<Set<ListErrorCode>> codesOf(Future<List<ListError>> errors) async {
      return {for (final ListError error in await errors) error.code};
    }

    test('create refuses an invalid definition, bad or duplicate items and a taken id', () async {
      final ListDefinition noName = ListDefinition.fromJson({..._plantsJson(), 'name': ''});
      expect(await codesOf(store.createList(noName)), contains(ListErrorCode.missingName));
      final ListItem untitled = ListItem(
        id: 'nameless',
        listId: _plantsId,
        values: const {'kind': 'fern'},
        createdAt: _t0,
        updatedAt: _t0,
      );
      expect(
        await codesOf(store.createList(_plants(), items: [untitled])),
        contains(ListErrorCode.fieldRequired),
      );
      // Two items with one id cannot both be kept (one document per item).
      expect(
        await codesOf(
          store.createList(_plants(), items: [_plant('fern', 'fern'), _plant('fern', 'cactus')]),
        ),
        contains(ListErrorCode.duplicateItemId),
      );
      await pumpEventQueue();
      expect(store.current.definition(_plantsId), isNull);
      expect(store.current.itemsOf(_plantsId), isEmpty);

      expect(await store.createList(_plants()), isEmpty);
      await until((c) => c.definition(_plantsId) != null);
      expect(await codesOf(store.createList(_plants())), contains(ListErrorCode.listExists));
    });

    test('item save, edit and delete', () async {
      await store.createList(_plants());
      await until((c) => c.definition(_plantsId) != null);

      await store.apply(ListChanges(saved: [_plant('fern', 'fern'), _plant('cactus', 'cactus')]));
      ListCatalog catalog = await until((c) => c.itemsOf(_plantsId).length == 2);

      final ListItem fern = catalog.itemsOf(_plantsId).firstWhere((i) => i.id == 'fern');
      final ListItem edited = ListItem(
        id: fern.id,
        listId: fern.listId,
        values: const {'title': 'Big fern', 'kind': 'fern'},
        createdAt: fern.createdAt,
        updatedAt: _t0.add(const Duration(hours: 1)),
      );
      await store.apply(ListChanges(saved: [edited], deletedIds: const ['cactus']));
      catalog = await until(
        (c) => c.itemsOf(_plantsId).length == 1 && c.itemsOf(_plantsId).single['title'] == 'Big fern',
      );
      expect(catalog.itemsOf(_plantsId).single.id, 'fern');
    });

    test('patch: valid ops are applied to the current items and saved', () async {
      await store.createList(_plants(), items: [_plant('fern', 'fern')]);
      await until((c) => c.itemsOf(_plantsId).isNotEmpty);
      // An item added after the caller last looked is migrated too.
      await store.apply(ListChanges(saved: [_plant('cactus', 'cactus')]));
      await until((c) => c.itemsOf(_plantsId).length == 2);

      // A kind like "fern" is no whole number, so both values are hidden.
      final ListPatchResult? result = await store.patchList(_plantsId, const [
        ListPatchOp(PatchOpKind.renameField, {'key': 'kind', 'label': 'Pots'}),
        ListPatchOp(PatchOpKind.changeFieldType, {'key': 'kind', 'type': 'counter'}),
        ListPatchOp(PatchOpKind.addField, {
          'field': {'key': 'water', 'type': 'text', 'label': 'Water every'},
        }),
      ]);
      expect(result, isNotNull);
      expect(result!.errors, isEmpty);
      expect(result.hiddenValues, 2);

      final ListCatalog catalog = await until(
        (c) =>
            c.definition(_plantsId)!.field('water') != null &&
            c.itemsOf(_plantsId).length == 2 &&
            c.itemsOf(_plantsId).every((item) => item[ListPatch.legacyKey] != null),
      );
      final ListDefinition definition = catalog.definition(_plantsId)!;
      expect(definition.field('kind')!.label, 'Pots');
      expect(definition.field('kind')!.type, FieldType.counter);
      expect(
        {for (final ListItem item in catalog.itemsOf(_plantsId)) item.id: item[ListPatch.legacyKey]},
        {
          'fern': {'kind': ['fern']},
          'cactus': {'kind': ['cactus']},
        },
      );
    });

    test('patch: invalid ops are refused and change nothing', () async {
      await store.createList(_plants(), items: [_plant('fern', 'fern')]);
      await until((c) => c.itemsOf(_plantsId).isNotEmpty);

      final ListPatchResult? result = await store.patchList(_plantsId, const [
        ListPatchOp(PatchOpKind.addField, {
          'field': {'key': 'title', 'type': 'text', 'label': 'Again'},
        }),
      ]);
      expect(result, isNotNull);
      expect(result!.isValid, isFalse);
      expect(result.errors.map((error) => error.code), contains(ListErrorCode.fieldExists));
      expect(store.current.definition(_plantsId)!.toJson(), _plants().toJson());

      expect(await store.patchList('list-missing', const []), isNull);
    });

    test('delete and restore round trip', () async {
      await store.createList(_plants(), items: [_plant('fern', 'fern'), _plant('cactus', 'cactus')]);
      await until((c) => c.itemsOf(_plantsId).length == 2);

      final DeletedList? deleted = await store.deleteList(_plantsId);
      expect(deleted, isNotNull);
      expect(deleted!.definition.id, _plantsId);
      expect(deleted.items.map((i) => i.id), unorderedEquals(['fern', 'cactus']));
      ListCatalog catalog = await until(
        (c) => c.definition(_plantsId) == null && c.itemsOf(_plantsId).isEmpty,
      );
      expect(catalog.definitions.map((d) => d.id), isNot(contains(_plantsId)));

      await store.restoreList(deleted);
      catalog = await until((c) => c.definition(_plantsId) != null && c.itemsOf(_plantsId).length == 2);
      expect(catalog.definition(_plantsId)!.toJson(), _plants().toJson());

      expect(await store.deleteList('list-missing'), isNull);
    });

    test('a starter list is an ordinary list: any patch, delete and restore', () async {
      final ListDefinition before = starter(store.current, BuiltinTemplates.groceryId);
      final String groceryId = before.id;
      final ListPatchResult? result = await store.patchList(groceryId, const [
        ListPatchOp(PatchOpKind.setListInfo, {
          'name': 'Shopping',
          'icon': 'local_florist',
          'color': '#E53935',
          'aiAllowed': false,
        }),
        ListPatchOp(PatchOpKind.addField, {
          'field': {'key': 'shop', 'type': 'text', 'label': 'Shop'},
        }),
      ]);
      expect(result?.errors, isEmpty);

      ListCatalog catalog = await until((c) {
        final ListDefinition? grocery = c.definition(groceryId);
        return grocery != null &&
            grocery.name == 'Shopping' &&
            grocery.icon == 'local_florist' &&
            grocery.color == '#E53935' &&
            !grocery.aiAllowed &&
            grocery.field('shop') != null;
      });
      expect(catalog.definition(groceryId)!.templateId, BuiltinTemplates.groceryId);
      // A patched list keeps its place.
      expect(
        catalog.definitions.map((d) => d.id).toList().indexOf(groceryId),
        store.current.definitions.map((d) => d.id).toList().indexOf(groceryId),
      );

      await store.apply(ListChanges(saved: [
        ListItem(
          id: 'milk',
          listId: groceryId,
          values: const {'title': 'Milk', 'section': 'current'},
          createdAt: _t0,
          updatedAt: _t0,
        ),
      ]));
      await until((c) => c.itemsOf(groceryId).length == 1);

      final DeletedList? deleted = await store.deleteList(groceryId);
      expect(deleted, isNotNull);
      catalog = await until((c) => c.definition(groceryId) == null && c.itemsOf(groceryId).isEmpty);
      expect(catalog.definitions.map((d) => d.templateId), isNot(contains(BuiltinTemplates.groceryId)));

      await store.restoreList(deleted!);
      catalog = await until((c) => c.definition(groceryId) != null && c.itemsOf(groceryId).length == 1);
      expect(catalog.definition(groceryId)!.name, 'Shopping');
    });

    test('add and remove a user option', () async {
      await store.createList(_plants());
      await until((c) => c.definition(_plantsId) != null);

      List<String> options(ListCatalog c) =>
          c.definition(_plantsId)!.field('kind')!.options.map((o) => o.value).toList();

      await store.addOption(_plantsId, 'kind', 'moss');
      ListCatalog catalog = await until((c) => options(c).contains('moss'));
      expect(options(catalog), ['fern', 'cactus', 'moss']);

      await store.removeOption(_plantsId, 'kind', 'moss');
      catalog = await until((c) => !options(c).contains('moss'));
      expect(options(catalog), ['fern', 'cactus']);
    });

    test('the read side emits after each write', () async {
      final List<ListCatalog> seen = [];
      final StreamSubscription<ListCatalog> subscription = store.watch().listen(seen.add);
      addTearDown(subscription.cancel);

      Future<void> expectEmit(Future<Object?> Function() write, bool Function(ListCatalog c) test) async {
        final int before = seen.length;
        await write();
        await until(test);
        await pumpEventQueue();
        expect(seen.length, greaterThan(before));
        expect(test(seen.last), isTrue);
      }

      await pumpEventQueue();
      expect(seen, isNotEmpty);

      await expectEmit(() => store.createList(_plants()), (c) => c.definition(_plantsId) != null);
      await expectEmit(
        () => store.apply(ListChanges(saved: [_plant('fern', 'fern')])),
        (c) => c.itemsOf(_plantsId).length == 1,
      );
      await expectEmit(
        () => store.apply(const ListChanges(deletedIds: ['fern'])),
        (c) => c.itemsOf(_plantsId).isEmpty,
      );
      await expectEmit(
        () => store.addOption(_plantsId, 'kind', 'moss'),
        (c) => c.definition(_plantsId)!.field('kind')!.options.length == 3,
      );
      await expectEmit(
        () => store.patchList(_plantsId, const [
          ListPatchOp(PatchOpKind.setListInfo, {'name': 'House plants'}),
        ]),
        (c) => c.definition(_plantsId)!.name == 'House plants',
      );
      final String tasksId = starter(store.current, BuiltinTemplates.tasksId).id;
      await expectEmit(
        () => store.patchList(tasksId, const [
          ListPatchOp(PatchOpKind.setListInfo, {'name': 'To do'}),
        ]),
        (c) => c.definition(tasksId)!.name == 'To do',
      );
      late DeletedList deleted;
      await expectEmit(() async => deleted = (await store.deleteList(_plantsId))!, (c) => c.definition(_plantsId) == null && c.itemsOf(_plantsId).isEmpty);
      await expectEmit(() => store.restoreList(deleted), (c) => c.definition(_plantsId) != null);
    });
  });
}

const List<String> _templateIds = [
  BuiltinTemplates.tasksId,
  BuiltinTemplates.groceryId,
  BuiltinTemplates.journalId,
  BuiltinTemplates.watchReadId,
];

const String _plantsId = 'list-plants';
final DateTime _t0 = DateTime.utc(2026, 3, 1);

Map<String, dynamic> _plantsJson() {
  return {
    'id': _plantsId,
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
    'updatedAt': _t0.toIso8601String(),
  };
}

ListDefinition _plants() => ListDefinition.fromJson(_plantsJson());

ListItem _plant(String id, String kind) {
  return ListItem(
    id: id,
    listId: _plantsId,
    values: {'title': id, 'kind': kind},
    createdAt: _t0,
    updatedAt: _t0,
  );
}

// Wraps a store and passes each change on in two steps, the lists first and
// their items one event later, as a Firestore store merging a lists
// listener with per-list item listeners may (D-12). The initial catalog is
// passed on whole. Running the contract through it checks that the tests
// wait for all of the state they assert.
class StaggeredListStore implements ListStore {
  StaggeredListStore(this.inner) {
    _subscription = inner.watch().listen((catalog) {
      _queue = _queue.then((_) => _pass(catalog));
    });
  }

  final ListStore inner;
  late final StreamSubscription<ListCatalog> _subscription;
  final StreamController<ListCatalog> _changes = StreamController<ListCatalog>.broadcast();
  Future<void> _queue = Future<void>.value();
  ListCatalog? _shown;

  Future<void> _pass(ListCatalog catalog) async {
    final ListCatalog? shown = _shown;
    if (shown != null) {
      _show(ListCatalog(definitions: catalog.definitions, items: shown.items));
      await Future<void>.delayed(Duration.zero);
    }
    _show(catalog);
  }

  void _show(ListCatalog catalog) {
    _shown = catalog;
    if (!_changes.isClosed) {
      _changes.add(catalog);
    }
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _queue;
    await _changes.close();
  }

  @override
  ListCatalog get current => _shown ?? const ListCatalog(definitions: [], items: []);

  @override
  Stream<ListCatalog> watch() {
    late final StreamController<ListCatalog> controller;
    StreamSubscription<ListCatalog>? subscription;
    controller = StreamController<ListCatalog>(
      onListen: () {
        if (_shown != null) {
          controller.add(_shown!);
        }
        subscription = _changes.stream.listen(controller.add, onDone: controller.close);
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<void> apply(ListChanges changes) => inner.apply(changes);

  @override
  Future<void> addOption(String listId, String fieldKey, String value) =>
      inner.addOption(listId, fieldKey, value);

  @override
  Future<void> removeOption(String listId, String fieldKey, String value) =>
      inner.removeOption(listId, fieldKey, value);

  @override
  Future<void> refresh() => inner.refresh();

  @override
  Future<List<ListError>> createList(ListDefinition definition, {List<ListItem> items = const []}) =>
      inner.createList(definition, items: items);

  @override
  Future<ListPatchResult?> patchList(String listId, List<ListPatchOp> ops) => inner.patchList(listId, ops);

  @override
  Future<DeletedList?> deleteList(String listId) => inner.deleteList(listId);

  @override
  Future<void> restoreList(DeletedList deleted) => inner.restoreList(deleted);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<ListStore, Future<void> Function()> closers = {};
  Future<void> dispose(ListStore store) => closers.remove(store)!();

  listStoreContract('FirestoreListStore', fakeFirestoreStore);

  listStoreContract(
    'FirestoreListStore with staggered updates',
    () async {
      final FirestoreListStore inner = await fakeFirestoreStore();
      final StaggeredListStore store = StaggeredListStore(inner);
      closers[store] = store.close;
      // The initial catalog arrives whole before the store is handed out.
      await store.watch().first;
      return store;
    },
    dispose: dispose,
  );
}
