import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_patch.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:hybrid_note/lists/list_store.dart';

import '../lists/list_store_contract_test.dart' show listStoreContract;
import '../support/firestore_store.dart' show DelayedAckFirestore;

const String _uid = 'user-1';
final DateTime _t0 = DateTime.utc(2026, 3, 1);

// A Firestore holding the four built-in definitions, as the Block B
// switch-over writes them for a new user.
Future<T> _seeded<T extends FakeFirebaseFirestore>([T? into]) async {
  final T firestore = into ?? FakeFirebaseFirestore() as T;
  for (final ListDefinition definition in BuiltinTemplates.all()) {
    await firestore
        .doc('users/$_uid/lists/${definition.id}')
        .set(definition.toJson());
  }
  return firestore;
}

Future<FirestoreListStore> _loaded(
  FakeFirebaseFirestore firestore, {
  void Function(String path, Object error)? onSkipped,
  int batchLimit = FirestoreListStore.maxBatchWrites,
  Duration transactionTimeout = const Duration(seconds: 10),
}) async {
  final FirestoreListStore store = FirestoreListStore(
    firestore,
    _uid,
    onSkipped: onSkipped,
    batchLimit: batchLimit,
    transactionTimeout: transactionTimeout,
  );
  addTearDown(store.close);
  await store.watch().first.timeout(const Duration(seconds: 10));
  return store;
}

// fake_cloud_firestore runs a transaction's writes straight away and never
// retries it; this one can also run a write of "another device" first, fail
// like an offline client or never finish. Batches can run such a write
// before they commit, and their deletes are recorded, since the fake (unlike
// Firestore) deletes a document's subcollections with it.
class _ScriptedFirestore extends FakeFirebaseFirestore {
  int transactions = 0;
  Future<void> Function()? beforeTransaction;
  Future<void> Function()? beforeBatch;
  final List<String> deleted = [];
  Object? failWith;
  FirebaseException? failReadOnWeb;
  bool hang = false;
  Completer<void>? hold;
  Future<Object?>? held;

  @override
  WriteBatch batch() => _ScriptedBatch(this, super.batch());

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactions++;
    await beforeTransaction?.call();
    final Object? failure = failWith;
    if (failure != null) {
      throw failure;
    }
    // Like cloud_firestore_web: the handler's read fails, and the error
    // reaches the caller wrapped in a JavaScript error (T-17 F1).
    final FirebaseException? readFailure = failReadOnWeb;
    if (readFailure != null) {
      try {
        await transactionHandler(_FailingTransaction(readFailure));
      } on Object catch (error) {
        throw _JsError('Error: Dart exception: $error');
      }
      throw StateError('the read did not fail');
    }
    if (hang) {
      return Completer<T>().future;
    }
    // A late transaction: it runs only once [hold] completes.
    final Completer<void>? gate = hold;
    if (gate != null) {
      final Future<T> late = gate.future.then(
        (_) => super.runTransaction(
          transactionHandler,
          timeout: timeout,
          maxAttempts: maxAttempts,
        ),
      );
      held = late;
      return late;
    }
    return super.runTransaction(
      transactionHandler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

class _FailingTransaction extends Fake implements Transaction {
  _FailingTransaction(this.failure);

  final FirebaseException failure;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async {
    throw failure;
  }
}

// What a rejected JavaScript promise becomes in Dart: not a
// FirebaseException.
class _JsError {
  _JsError(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ScriptedBatch implements WriteBatch {
  _ScriptedBatch(this._firestore, this._batch);

  final _ScriptedFirestore _firestore;
  final WriteBatch _batch;

  @override
  Future<void> commit() async {
    await _firestore.beforeBatch?.call();
    return _batch.commit();
  }

  @override
  void delete(DocumentReference document) {
    _firestore.deleted.add(document.path);
    _batch.delete(document);
  }

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    _batch.set(document, data, options);
  }

  @override
  void update<T>(DocumentReference<T> document, T data) {
    _batch.update(document, data);
  }
}

// A stored document without the store's `_createdAt` (tested on its own).
Future<Map<String, dynamic>> _doc(
  FakeFirebaseFirestore firestore,
  String path,
) async {
  return (await firestore.doc('users/$_uid/lists/$path').get()).data()!
    ..remove(FirestoreListStore.createdAtKey);
}

ListItem _kind(String id, Object kind) {
  return ListItem(
    id: id,
    listId: 'list-a',
    values: {'title': id, 'kind': kind},
    createdAt: _t0,
    updatedAt: _t0,
  );
}

const List<ListPatchOp> _toCounter = [
  ListPatchOp(PatchOpKind.changeFieldType, {'key': 'kind', 'type': 'counter'}),
];

Future<ListCatalog> _until(ListStore store, bool Function(ListCatalog c) test) {
  return store.watch().firstWhere(test).timeout(const Duration(seconds: 10));
}

ListDefinition _everything() {
  return ListDefinition.fromJson({
    'id': 'list-everything',
    'name': 'Everything',
    'icon': 'list',
    'color': '#43A047',
    'fields': [
      {
        'key': 'title',
        'type': 'text',
        'label': 'Title',
        'required': true,
        'primary': true,
      },
      {'key': 'notes', 'type': 'longText', 'label': 'Notes'},
      {'key': 'done', 'type': 'checkbox', 'label': 'Done'},
      {'key': 'on', 'type': 'toggle', 'label': 'On'},
      {'key': 'price', 'type': 'number', 'label': 'Price'},
      {'key': 'count', 'type': 'counter', 'label': 'Count'},
      {'key': 'stars', 'type': 'rating', 'label': 'Stars'},
      {'key': 'day', 'type': 'date', 'label': 'Day'},
      {'key': 'at', 'type': 'dateTime', 'label': 'At'},
      {
        'key': 'size',
        'type': 'enum',
        'label': 'Size',
        'options': [
          {'value': 's'},
          {'value': 'l'},
        ],
      },
      {'key': 'kind', 'type': 'category', 'label': 'Kind'},
      {'key': 'tags', 'type': 'tags', 'label': 'Tags'},
      {'key': 'link', 'type': 'url', 'label': 'Link'},
      {'key': 'steps', 'type': 'checklist', 'label': 'Steps'},
      {'key': 'repeat', 'type': 'recurrence', 'label': 'Repeat'},
    ],
    'view': {'kind': 'cards'},
    'updatedAt': _t0.toIso8601String(),
  });
}

ListItem _full(String id) {
  return ListItem(
    id: id,
    listId: 'list-everything',
    values: {
      'title': 'All of it',
      'notes': 'line one\nline two',
      'done': true,
      'on': false,
      'price': 2.5,
      'count': 3,
      'stars': 4,
      'day': '2026-03-01',
      'at': '2026-03-01T10:30:00.000Z',
      'size': 'l',
      'kind': 'home',
      'tags': ['a', 'b'],
      'link': 'https://example.com',
      'steps': [
        {
          'id': 's1',
          'title': 'First',
          'done': false,
          'createdAt': _t0.toIso8601String(),
          'updatedAt': _t0.toIso8601String(),
        },
      ],
      'repeat': {'frequency': 'custom', 'customDays': 3},
      // A key that is no field any more, and hidden values (D-10), one of
      // them a list inside the archived list.
      'oldKey': 'kept',
      ListPatch.legacyKey: {
        'tags': [
          ['x', 'y'],
          'z',
        ],
        'count': ['many'],
      },
    },
    createdAt: _t0,
    updatedAt: _t0.add(const Duration(minutes: 1)),
  );
}

ListItem _row(String listId, int n) {
  return ListItem(
    id: '$listId-item-$n',
    listId: listId,
    values: {'title': 'Item $n'},
    createdAt: _t0,
    updatedAt: _t0,
  );
}

ListDefinition _simple(String id) {
  return ListDefinition.fromJson({
    'id': id,
    'name': 'Simple',
    'icon': 'list',
    'color': '#43A047',
    'fields': [
      {
        'key': 'title',
        'type': 'text',
        'label': 'Title',
        'required': true,
        'primary': true,
      },
      {'key': 'kind', 'type': 'text', 'label': 'Kind'},
    ],
    'view': {'kind': 'cards'},
    'updatedAt': _t0.toIso8601String(),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<ListStore, Future<void> Function()> closers = {};

  listStoreContract('FirestoreListStore', () async {
    final FirestoreListStore store = FirestoreListStore(await _seeded(), _uid);
    closers[store] = store.close;
    return store;
  }, dispose: (store) => closers.remove(store)!());

  group('FirestoreListStore', () {
    test('lists come in creation order, then by id (Q-22 D)', () async {
      final FakeFirebaseFirestore firestore = FakeFirebaseFirestore();
      Future<void> put(String id, String? createdAt) {
        return firestore.doc('users/$_uid/lists/$id').set({
          ..._simple(id).toJson(),
          '_createdAt': ?createdAt,
        });
      }

      await put('list-c', '2026-03-01T00:00:00.001Z');
      await put('list-a', '2026-03-01T00:00:00.002Z');
      await put('list-b', '2026-03-01T00:00:00.001Z');
      await put('list-old', null);
      final FirestoreListStore store = await _loaded(firestore);

      expect(store.current.definitions.map((d) => d.id), [
        'list-old',
        'list-b',
        'list-c',
        'list-a',
      ]);
      // `_createdAt` belongs to the store, not to the definition.
      expect(store.current.definition('list-a')!.extra, isEmpty);

      expect(await store.createList(_simple('list-0')), isEmpty);
      final ListCatalog catalog = await _until(
        store,
        (c) => c.definition('list-0') != null,
      );
      expect(catalog.definitions.last.id, 'list-0');
    });

    test('create, delete and Undo complete before the server answers', () async {
      final DelayedAckFirestore firestore = DelayedAckFirestore();
      final FirestoreListStore store = await _loaded(firestore);
      firestore.holdAcks = true;
      const Duration local = Duration(seconds: 5);

      // Offline the server answers only once back online; the caller goes on
      // as soon as the device has the change (T-17 R3, D-5).
      expect(await store.createList(_simple('list-a')).timeout(local), isEmpty);
      expect(store.current.definition('list-a'), isNotNull);

      final DeletedList? deleted = await store
          .deleteList('list-a')
          .timeout(local);
      expect(deleted, isNotNull);
      expect(store.current.definition('list-a'), isNull);

      await store.restoreList(deleted!).timeout(local);
      expect(store.current.definition('list-a'), isNotNull);
      expect(firestore.acks, hasLength(3));
      expect(firestore.acks.where((ack) => ack.isCompleted), isEmpty);
    });

    test('a write the server rejects later is reported', () async {
      final DelayedAckFirestore firestore = DelayedAckFirestore();
      final FirestoreListStore store = await _loaded(firestore);
      final List<Object> failures = [];
      store.writeFailures.listen(failures.add);
      firestore.holdAcks = true;

      expect(await store.createList(_simple('list-a')), isEmpty);
      expect(failures, isEmpty);
      firestore.acks.single.completeError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      await pumpEventQueue();
      expect(failures.single, isA<FirebaseException>());
    });

    test('lists created at the same time are ordered by id', () async {
      final FakeFirebaseFirestore firestore = FakeFirebaseFirestore();
      for (final String id in ['list-b', 'list-c', 'list-a']) {
        await firestore.doc('users/$_uid/lists/$id').set({
          ..._simple(id).toJson(),
          '_createdAt': '2026-03-01T00:00:00.001Z',
        });
      }
      final FirestoreListStore store = await _loaded(firestore);

      expect(store.current.definitions.map((d) => d.id), [
        'list-a',
        'list-b',
        'list-c',
      ]);
    });

    test('a patch and an undone delete keep the list in its place', () async {
      final FakeFirebaseFirestore firestore = FakeFirebaseFirestore();
      // Explicit, distinct creation times: list-b first, although its id
      // sorts after list-a's (two DateTime.now calls can be equal, T-17 R4).
      const String createdAt = '2026-03-01T00:00:00.001Z';
      for (final (String id, String time) in [
        ('list-b', createdAt),
        ('list-a', '2026-03-01T00:00:00.002Z'),
      ]) {
        await firestore.doc('users/$_uid/lists/$id').set({
          ..._simple(id).toJson(),
          '_createdAt': time,
        });
      }
      final FirestoreListStore store = await _loaded(firestore);
      expect(store.current.definitions.map((d) => d.id), ['list-b', 'list-a']);

      final ListPatchResult? result = await store.patchList('list-b', const [
        ListPatchOp(PatchOpKind.setListInfo, {'name': 'Renamed'}),
      ]);
      expect(result!.isValid, isTrue);
      expect(
        (await firestore.doc('users/$_uid/lists/list-b').get())
            .data()!['_createdAt'],
        createdAt,
      );

      final DeletedList deleted = (await store.deleteList('list-b'))!;
      await _until(store, (c) => c.definitions.length == 1);
      await store.restoreList(deleted);
      final ListCatalog catalog = await _until(
        store,
        (c) => c.definitions.length == 2,
      );
      expect(catalog.definitions.map((d) => d.id), ['list-b', 'list-a']);
    });

    test('a list may use a template id: there are no built-ins', () async {
      final FirestoreListStore store = await _loaded(FakeFirebaseFirestore());

      expect(await store.createList(BuiltinTemplates.tasks()), isEmpty);
      await _until(store, (c) => c.definition(BuiltinTemplates.tasksId) != null);
      expect(await store.deleteList(BuiltinTemplates.tasksId), isNotNull);
    });

    test('stores the Q-5 layout: one document per list and per item', () async {
      final FakeFirebaseFirestore firestore = await _seeded();
      final FirestoreListStore store = await _loaded(firestore);
      final ListDefinition list = _simple('list-a');
      expect(await store.createList(list, items: [_row('list-a', 1)]), isEmpty);

      final listDoc = await firestore.doc('users/$_uid/lists/list-a').get();
      // Plus `_createdAt`, for the list order.
      expect(listDoc.data(), {
        ...list.toJson(),
        '_createdAt': isA<String>(),
      });
      final itemDoc = await firestore
          .doc('users/$_uid/lists/list-a/items/list-a-item-1')
          .get();
      // Plus `_rev`, the list revision the item was written for (Q-16).
      expect(itemDoc.data(), {
        ..._row('list-a', 1).toJson(),
        '_rev': list.schemaRevision,
      });
    });

    test(
      'an item with every field type, hidden keys and _legacy lists comes back equal',
      () async {
        final FakeFirebaseFirestore firestore = await _seeded();
        final FirestoreListStore store = await _loaded(firestore);
        expect(await store.createList(_everything()), isEmpty);
        await store.apply(ListChanges(saved: [_full('full')]));

        // Firestore takes no array directly inside an array.
        final stored = await firestore
            .doc('users/$_uid/lists/list-everything/items/full')
            .get();
        final Map legacy =
            (stored.data()!['values'] as Map)[ListPatch.legacyKey] as Map;
        expect(legacy['tags'], [
          {
            '__array': ['x', 'y'],
          },
          'z',
        ]);

        // A second store reads it from the documents alone.
        final FirestoreListStore reader = await _loaded(firestore);
        final ListItem back = reader.current.itemsOf('list-everything').single;
        expect(back.toJson(), _full('full').toJson());
        expect(
          reader.current.definition('list-everything')!.toJson(),
          _everything().toJson(),
        );
      },
    );

    // fake_cloud_firestore reruns every listener per document, so the full
    // cycle runs on a small batch limit and the real limit gets one create.
    test(
      'a change set larger than one batch of 500 writes is written whole',
      () async {
        final FakeFirebaseFirestore firestore = await _seeded();
        final FirestoreListStore store = await _loaded(firestore);
        const int count = FirestoreListStore.maxBatchWrites + 1;
        expect(
          await store.createList(
            _simple('list-big'),
            items: [for (int n = 0; n < count; n++) _row('list-big', n)],
          ),
          isEmpty,
        );
        await _until(store, (c) => c.itemsOf('list-big').length == count);
        expect(
          (await firestore.collection('users/$_uid/lists/list-big/items').get())
              .size,
          count,
        );
      },
    );

    test(
      'changes larger than one batch are saved, deleted and restored whole',
      () async {
        final FakeFirebaseFirestore firestore = await _seeded();
        final FirestoreListStore store = await _loaded(
          firestore,
          batchLimit: 10,
        );
        const int count = 10 * 2 + 7;
        final List<ListItem> items = [
          for (int n = 0; n < count; n++) _row('list-big', n),
        ];

        expect(
          await store.createList(_simple('list-big'), items: items),
          isEmpty,
        );
        await _until(store, (c) => c.itemsOf('list-big').length == count);
        expect(
          (await firestore.collection('users/$_uid/lists/list-big/items').get())
              .size,
          count,
        );

        await store.apply(
          ListChanges(
            saved: [
              for (final ListItem item in items)
                ListItem(
                  id: item.id,
                  listId: item.listId,
                  values: const {'title': 'Edited'},
                  createdAt: item.createdAt,
                  updatedAt: _t0.add(const Duration(hours: 1)),
                ),
            ],
          ),
        );
        await _until(
          store,
          (c) =>
              c.itemsOf('list-big').every((item) => item['title'] == 'Edited'),
        );

        final Future<void> allDeleted = firestore
            .collection('users/$_uid/lists/list-big/items')
            .snapshots()
            .firstWhere((snapshot) => snapshot.size == 0);
        final DeletedList? deleted = await store.deleteList('list-big');
        expect(deleted!.items, hasLength(count));
        await _until(store, (c) => c.definition('list-big') == null);
        // deleteList completes once the list is gone locally (T-17 R3). The
        // fake applies a batch one document at a time, so the other batches'
        // item deletes may still be running; Firestore applies each batch
        // whole and in order, so there Undo always comes after them. (The
        // fake's get() already reports no items once the list document is
        // gone; a listener from before the delete reports them as they
        // happen.)
        await allDeleted.timeout(const Duration(seconds: 10));

        await store.restoreList(deleted);
        await _until(store, (c) => c.itemsOf('list-big').length == count);
      },
    );

    test('a patch saves only the changed items', () async {
      final FakeFirebaseFirestore firestore = await _seeded();
      final FirestoreListStore store = await _loaded(firestore);
      final ListItem numbered = ListItem(
        id: 'n',
        listId: 'list-a',
        values: const {'title': 'n', 'kind': '3'},
        createdAt: _t0,
        updatedAt: _t0,
      );
      await store.createList(
        _simple('list-a'),
        items: [numbered, _row('list-a', 1)],
      );
      await _until(store, (c) => c.itemsOf('list-a').length == 2);

      final ListPatchResult? result = await store.patchList('list-a', const [
        ListPatchOp(PatchOpKind.changeFieldType, {
          'key': 'kind',
          'type': 'counter',
        }),
      ]);
      expect(result!.errors, isEmpty);
      final item = await firestore
          .doc('users/$_uid/lists/list-a/items/n')
          .get();
      expect((item.data()!['values'] as Map)['kind'], 3);
      final ListDefinition saved = ListDefinition.fromJson(
        (await firestore.doc('users/$_uid/lists/list-a').get()).data(),
      );
      expect(
        saved.schemaRevision,
        greaterThan(_simple('list-a').schemaRevision),
      );
    });

    test('an item moved to another list leaves its old document', () async {
      final FakeFirebaseFirestore firestore = await _seeded();
      final FirestoreListStore store = await _loaded(firestore);
      await store.createList(_simple('list-a'), items: [_row('list-a', 1)]);
      await store.createList(_simple('list-b'));
      await _until(
        store,
        (c) =>
            c.itemsOf('list-a').length == 1 && c.definition('list-b') != null,
      );

      final ListItem moved = ListItem(
        id: 'list-a-item-1',
        listId: 'list-b',
        values: const {'title': 'Item 1'},
        createdAt: _t0,
        updatedAt: _t0,
      );
      await store.apply(ListChanges(saved: [moved]));
      await _until(
        store,
        (c) => c.itemsOf('list-a').isEmpty && c.itemsOf('list-b').length == 1,
      );
      expect(
        (await firestore
                .doc('users/$_uid/lists/list-a/items/list-a-item-1')
                .get())
            .exists,
        isFalse,
      );
    });

    test(
      'malformed documents are skipped and reported; the rest loads (Q-8)',
      () async {
        final FakeFirebaseFirestore firestore = await _seeded();
        await firestore
            .doc('users/$_uid/lists/list-a')
            .set(_simple('list-a').toJson());
        final String items = 'users/$_uid/lists/list-a/items';
        await firestore.doc('$items/good').set({
          ..._row('list-a', 1).toJson(),
          'id': 'good',
        });
        final Map<String, dynamic> base = {..._row('list-a', 2).toJson()};
        await firestore.doc('$items/no-id').set({...base}..remove('id'));
        await firestore.doc('$items/bad-values').set({
          ...base,
          'id': 'bad-values',
          'values': 'x',
        });
        await firestore.doc('$items/bad-date').set({
          ...base,
          'id': 'bad-date',
          'createdAt': 7,
        });
        await firestore.doc('$items/other-id').set({
          ...base,
          'id': 'not-this-one',
        });
        await firestore.doc('$items/other-list').set({
          ...base,
          'id': 'other-list',
          'listId': 'list-b',
        });
        await firestore.doc('users/$_uid/lists/list-broken').set({
          'id': 'list-broken',
          'name': 3,
        });

        final List<String> skipped = [];
        final FirestoreListStore store = await _loaded(
          firestore,
          onSkipped: (path, error) => skipped.add(path),
        );

        expect(store.current.itemsOf('list-a').map((i) => i.id), ['good']);
        expect(store.current.definition('list-broken'), isNull);
        expect(store.current.definition(BuiltinTemplates.tasksId), isNotNull);
        expect(
          skipped,
          unorderedEquals([
            '$items/no-id',
            '$items/bad-values',
            '$items/bad-date',
            '$items/other-id',
            '$items/other-list',
            'users/$_uid/lists/list-broken',
          ]),
        );

        // Reported once, not again on the next change to the list.
        await store.apply(ListChanges(saved: [_row('list-a', 3)]));
        await _until(store, (c) => c.itemsOf('list-a').length == 2);
        expect(skipped, hasLength(6));
      },
    );

    // T-14 R3: Firestore does not delete a subcollection with its parent.
    test(
      'deleting a list removes its malformed item documents as well',
      () async {
        final _ScriptedFirestore firestore = await _seeded(
          _ScriptedFirestore(),
        );
        final FirestoreListStore store = await _loaded(firestore);
        await store.createList(
          _simple('list-a'),
          items: [_row('list-a', 1), _row('list-a', 2)],
        );
        final String items = 'users/$_uid/lists/list-a/items';
        final Map<String, dynamic> base = _row('list-a', 3).toJson();
        await firestore.doc('$items/bad-values').set({
          ...base,
          'id': 'bad-values',
          'values': 'x',
        });
        await firestore.doc('$items/bad-date').set({
          ...base,
          'id': 'bad-date',
          'createdAt': 7,
        });
        await _until(store, (c) => c.itemsOf('list-a').length == 2);
        await pumpEventQueue();

        final DeletedList? deleted = await store.deleteList('list-a');
        expect(
          deleted!.items.map((i) => i.id),
          unorderedEquals(['list-a-item-1', 'list-a-item-2']),
        );
        expect(
          firestore.deleted,
          unorderedEquals([
            for (final String id in [
              'list-a-item-1',
              'list-a-item-2',
              'bad-values',
              'bad-date',
            ])
              '$items/$id',
            'users/$_uid/lists/list-a',
          ]),
        );
        expect((await firestore.collection(items).get()).docs, isEmpty);
        expect(
          (await firestore.doc('users/$_uid/lists/list-a').get()).exists,
          isFalse,
        );
      },
    );

    test('emits nothing until every list has its items (D-12)', () async {
      final FakeFirebaseFirestore firestore = await _seeded();
      for (final String id in ['list-a', 'list-b', 'list-c']) {
        await firestore.doc('users/$_uid/lists/$id').set(_simple(id).toJson());
        for (int n = 0; n < 3; n++) {
          await firestore
              .doc('users/$_uid/lists/$id/items/$id-item-$n')
              .set(_row(id, n).toJson());
        }
      }
      final FirestoreListStore store = FirestoreListStore(firestore, _uid);
      addTearDown(store.close);
      expect(store.current.definitions, isEmpty);
      final List<ListCatalog> seen = [];
      final StreamSubscription<ListCatalog> subscription = store.watch().listen(
        seen.add,
      );
      addTearDown(subscription.cancel);

      await _until(store, (c) => true);
      await pumpEventQueue();
      expect(seen, isNotEmpty);
      for (final ListCatalog catalog in seen) {
        for (final String id in ['list-a', 'list-b', 'list-c']) {
          expect(catalog.itemsOf(id), hasLength(3));
        }
      }
    });

    test('another user\'s lists are not read', () async {
      final FakeFirebaseFirestore firestore = await _seeded();
      await firestore
          .doc('users/someone/lists/list-x')
          .set(_simple('list-x').toJson());
      final FirestoreListStore store = await _loaded(firestore);
      expect(store.current.definition('list-x'), isNull);
    });

    // Q-16: device B adds an item while device A patches the list; however
    // the two interleave, the item ends up fitting the new schema.
    test(
      'two clients: an item inserted during a patch is migrated as well',
      () async {
        final FakeFirebaseFirestore firestore = await _seeded();
        final FirestoreListStore a = await _loaded(firestore);
        await a.createList(
          _simple('list-a'),
          items: [
            ListItem(
              id: 'one',
              listId: 'list-a',
              values: const {'title': '1', 'kind': '1'},
              createdAt: _t0,
              updatedAt: _t0,
            ),
          ],
        );
        final FirestoreListStore b = await _loaded(firestore);
        await _until(b, (c) => c.itemsOf('list-a').length == 1);

        final Future<void> insert = b.apply(
          ListChanges(
            saved: [
              ListItem(
                id: 'two',
                listId: 'list-a',
                values: const {'title': '2', 'kind': '2'},
                createdAt: _t0,
                updatedAt: _t0,
              ),
            ],
          ),
        );
        final Future<ListPatchResult?> patch = a.patchList('list-a', const [
          ListPatchOp(PatchOpKind.changeFieldType, {
            'key': 'kind',
            'type': 'counter',
          }),
        ]);
        await Future.wait([insert, patch]);

        final ListCatalog done = await _until(
          a,
          (c) =>
              c.itemsOf('list-a').length == 2 &&
              c.itemsOf('list-a').every((i) => i['kind'] is int),
        );
        expect(
          done.itemsOf('list-a').map((i) => i['kind']),
          unorderedEquals([1, 2]),
        );
      },
    );

    test(
      'two clients: an item the transaction cannot see is repaired',
      () async {
        final _ScriptedFirestore firestore = await _seeded(
          _ScriptedFirestore(),
        );
        final FirestoreListStore a = await _loaded(firestore);
        await a.createList(_simple('list-a'), items: [_kind('one', '1')]);
        final FirestoreListStore b = await _loaded(firestore);
        await _until(b, (c) => c.itemsOf('list-a').length == 1);

        // B's insert lands after A has taken its item ids, before A's
        // transaction reads: the transaction does not see it.
        firestore.beforeTransaction = () async {
          firestore.beforeTransaction = null;
          await b.apply(ListChanges(saved: [_kind('two', '2')]));
        };
        final ListPatchResult? result = await a.patchList('list-a', _toCounter);
        expect(result!.errors, isEmpty);
        expect(result.items.map((i) => i.id), ['one']);

        for (final FirestoreListStore store in [a, b]) {
          await _until(
            store,
            (c) =>
                c.itemsOf('list-a').length == 2 &&
                c.itemsOf('list-a').every((i) => i['kind'] is int),
          );
        }
        final Map<String, dynamic> two = await _doc(
          firestore,
          'list-a/items/two',
        );
        expect((two['values'] as Map)['kind'], 2);
        expect(two['_rev'], result.definition.schemaRevision);
      },
    );

    test('a patch runs on the list as stored, not a stale cache', () async {
      final _ScriptedFirestore firestore = await _seeded(_ScriptedFirestore());
      final FirestoreListStore a = await _loaded(firestore);
      await a.createList(_simple('list-a'));
      await _until(a, (c) => c.definition('list-a') != null);

      // Another device adds a field just before A's transaction reads.
      final ListDefinition other = ListPatch.apply(
        _simple('list-a'),
        const [],
        const [
          ListPatchOp(PatchOpKind.addField, {
            'field': {'key': 'other', 'type': 'text', 'label': 'Other'},
          }),
        ],
        _t0,
      ).definition;
      firestore.beforeTransaction = () async {
        firestore.beforeTransaction = null;
        await firestore.doc('users/$_uid/lists/list-a').set(other.toJson());
      };
      final ListPatchResult? result = await a.patchList('list-a', const [
        ListPatchOp(PatchOpKind.addField, {
          'field': {'key': 'mine', 'type': 'text', 'label': 'Mine'},
        }),
      ]);
      expect(firestore.transactions, 1);
      expect(result!.errors, isEmpty);
      final ListDefinition stored = ListDefinition.fromJson(
        await _doc(firestore, 'list-a'),
      );
      expect(stored.fields.map((f) => f.key), containsAll(['other', 'mine']));
      expect(stored.schemaRevision, other.schemaRevision + 1);
    });

    test('an option added on another device meanwhile is kept', () async {
      final _ScriptedFirestore firestore = await _seeded(_ScriptedFirestore());
      final FirestoreListStore a = await _loaded(firestore);
      final ListDefinition list = ListDefinition.fromJson({
        ..._simple('list-a').toJson(),
        'fields': [
          ..._simple('list-a').toJson()['fields'] as List,
          {
            'key': 'room',
            'type': 'category',
            'label': 'Room',
            'options': [
              {'value': 'hall'},
            ],
          },
        ],
      });
      expect(await a.createList(list), isEmpty);
      await _until(a, (c) => c.definition('list-a') != null);

      // Another device adds "attic" just before A's transaction reads; A's
      // cache still has only "hall".
      final ListDefinition other = ListPatch.apply(list, const [], const [
        ListPatchOp(PatchOpKind.setOptions, {
          'key': 'room',
          'options': [
            {'value': 'hall'},
            {'value': 'attic'},
          ],
        }),
      ], _t0).definition;
      firestore.beforeTransaction = () async {
        firestore.beforeTransaction = null;
        await firestore.doc('users/$_uid/lists/list-a').set(other.toJson());
      };
      await a.addOption('list-a', 'room', 'cellar');
      final ListDefinition stored = ListDefinition.fromJson(
        await _doc(firestore, 'list-a'),
      );
      expect(stored.field('room')!.options.map((o) => o.value), [
        'hall',
        'attic',
        'cellar',
      ]);
    });

    test('a patch refused in the transaction writes nothing', () async {
      final _ScriptedFirestore firestore = await _seeded(_ScriptedFirestore());
      final FirestoreListStore store = await _loaded(firestore);
      await store.createList(_simple('list-a'), items: [_kind('one', 'x')]);
      await _until(store, (c) => c.itemsOf('list-a').length == 1);

      final ListPatchResult? result = await store.patchList('list-a', const [
        ListPatchOp(PatchOpKind.removeField, {'key': 'missing'}),
      ]);
      expect(result!.isValid, isFalse);
      expect(firestore.transactions, 1);
      expect(await _doc(firestore, 'list-a'), _simple('list-a').toJson());
    });

    test(
      'offline, a patch is applied to the cache and saved as a batch',
      () async {
        final _ScriptedFirestore firestore = await _seeded(
          _ScriptedFirestore(),
        );
        final FirestoreListStore store = await _loaded(firestore);
        await store.createList(
          _simple('list-a'),
          items: [_kind('one', '1'), _kind('two', 'many')],
        );
        await _until(store, (c) => c.itemsOf('list-a').length == 2);

        firestore.failWith = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        );
        final ListPatchResult? result = await store.patchList(
          'list-a',
          _toCounter,
        );
        expect(result!.errors, isEmpty);
        expect(result.hiddenValues, 1);

        final ListCatalog catalog = await _until(
          store,
          (c) =>
              c.definition('list-a')!.field('kind')!.type.wire == 'counter' &&
              c.itemsOf('list-a').any((i) => i['kind'] == 1) &&
              c.itemsOf('list-a').any((i) => i[ListPatch.legacyKey] != null),
        );
        expect(
          catalog
              .itemsOf('list-a')
              .firstWhere((i) => i.id == 'two')[ListPatch.legacyKey],
          {
            'kind': ['many'],
          },
        );
        final Map<String, dynamic> one = await _doc(
          firestore,
          'list-a/items/one',
        );
        expect(one['_rev'], result.definition.schemaRevision);

        // Adding a category works offline too.
        await store.createList(
          ListDefinition.fromJson({
            ..._simple('list-b').toJson(),
            'fields': [
              {
                'key': 'title',
                'type': 'text',
                'label': 'Title',
                'required': true,
                'primary': true,
              },
              {'key': 'kind', 'type': 'category', 'label': 'Kind'},
            ],
          }),
        );
        await _until(store, (c) => c.definition('list-b') != null);
        await store.addOption('list-b', 'kind', 'moss');
        await _until(
          store,
          (c) => c
              .definition('list-b')!
              .field('kind')!
              .options
              .any((o) => o.value == 'moss'),
        );
      },
    );

    test(
      'a transaction that does not finish in time falls back to a batch',
      () async {
        final _ScriptedFirestore firestore = await _seeded(
          _ScriptedFirestore(),
        );
        final FirestoreListStore store = await _loaded(
          firestore,
          transactionTimeout: const Duration(milliseconds: 50),
        );
        await store.createList(_simple('list-a'), items: [_kind('one', '1')]);
        await _until(store, (c) => c.itemsOf('list-a').length == 1);

        firestore.hang = true;
        final ListPatchResult? result = await store.patchList(
          'list-a',
          _toCounter,
        );
        expect(result!.errors, isEmpty);
        await _until(store, (c) => c.itemsOf('list-a').single['kind'] == 1);
      },
    );

    // T-17 F1: on web the offline read error arrives wrapped in a
    // JavaScript error; the fallback must still apply, without waiting for
    // the timeout.
    test('offline on web, a patch falls back to the cache at once', () async {
      final _ScriptedFirestore firestore = await _seeded(_ScriptedFirestore());
      final FirestoreListStore store = await _loaded(firestore);
      await store.createList(_simple('list-a'), items: [_kind('one', '1')]);
      await _until(store, (c) => c.itemsOf('list-a').length == 1);

      firestore.failReadOnWeb = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'Connection failed.',
      );
      final ListPatchResult? result = await store
          .patchList('list-a', const [
            ListPatchOp(PatchOpKind.setListInfo, {'name': 'Renamed offline'}),
          ])
          .timeout(const Duration(seconds: 2));
      expect(result!.errors, isEmpty);
      await _until(
        store,
        (c) => c.definition('list-a')!.name == 'Renamed offline',
      );
      expect((await _doc(firestore, 'list-a'))['name'], 'Renamed offline');
    });

    test(
      'on web, a read refused for another reason still fails the patch',
      () async {
        final _ScriptedFirestore firestore = await _seeded(
          _ScriptedFirestore(),
        );
        final FirestoreListStore store = await _loaded(firestore);
        await store.createList(_simple('list-a'));
        await _until(store, (c) => c.definition('list-a') != null);

        firestore.failReadOnWeb = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
        await expectLater(
          store.patchList('list-a', const [
            ListPatchOp(PatchOpKind.setListInfo, {'name': 'Not allowed'}),
          ]),
          throwsA(
            isA<FirebaseException>().having(
              (e) => e.code,
              'code',
              'permission-denied',
            ),
          ),
        );
        expect(store.current.definition('list-a')!.name, isNot('Not allowed'));
      },
    );

    // T-14 R2: moving fields is not idempotent. From [title, kind, size],
    // move title to 1 then kind to 2 gives [title, size, kind] once and
    // [size, title, kind] when applied again on top.
    test('a transaction that runs after the fallback does not apply the patch '
        'again', () async {
      final _ScriptedFirestore firestore = await _seeded(_ScriptedFirestore());
      final FirestoreListStore store = await _loaded(
        firestore,
        transactionTimeout: const Duration(milliseconds: 50),
      );
      final ListDefinition list = ListDefinition.fromJson({
        ..._simple('list-a').toJson(),
        'fields': [
          ..._simple('list-a').toJson()['fields'] as List,
          {'key': 'size', 'type': 'text', 'label': 'Size'},
        ],
      });
      expect(await store.createList(list), isEmpty);
      await _until(store, (c) => c.definition('list-a') != null);

      firestore.hold = Completer<void>();
      final ListPatchResult? result = await store.patchList('list-a', const [
        ListPatchOp(PatchOpKind.moveField, {'key': 'title', 'index': 1}),
        ListPatchOp(PatchOpKind.moveField, {'key': 'kind', 'index': 2}),
      ]);
      expect(result!.errors, isEmpty);
      const List<String> once = ['title', 'size', 'kind'];
      expect(result.definition.fields.map((f) => f.key), once);
      await _until(store, (c) => c.definition('list-a')!.schemaRevision == 2);

      // The transaction now runs, on the list the fallback saved.
      firestore.hold!.complete();
      await firestore.held;
      await pumpEventQueue();
      final ListDefinition stored = ListDefinition.fromJson(
        await _doc(firestore, 'list-a'),
      );
      expect(stored.fields.map((f) => f.key), once);
      expect(stored.schemaRevision, 2);
    });

    test('other Firestore errors are not taken for offline', () async {
      final _ScriptedFirestore firestore = await _seeded(_ScriptedFirestore());
      final FirestoreListStore store = await _loaded(firestore);
      await store.createList(_simple('list-a'));
      await _until(store, (c) => c.definition('list-a') != null);

      firestore.failWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      await expectLater(
        store.patchList('list-a', _toCounter),
        throwsA(isA<FirebaseException>()),
      );
      await pumpEventQueue();
      expect(await _doc(firestore, 'list-a'), _simple('list-a').toJson());
    });

    test(
      'a patch changing more items than one transaction holds saves them all',
      () async {
        final _ScriptedFirestore firestore = await _seeded(
          _ScriptedFirestore(),
        );
        final FirestoreListStore store = await _loaded(
          firestore,
          batchLimit: 10,
        );
        final List<ListItem> items = [
          for (int n = 0; n < 25; n++) _kind('i$n', '$n'),
        ];
        await store.createList(_simple('list-a'), items: items);
        await _until(store, (c) => c.itemsOf('list-a').length == 25);

        final ListPatchResult? result = await store.patchList(
          'list-a',
          _toCounter,
        );
        expect(result!.changedItemIds, hasLength(25));
        final QuerySnapshot<Map<String, dynamic>> stored = await firestore
            .collection('users/$_uid/lists/list-a/items')
            .get();
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in stored.docs) {
          expect((doc.data()['values'] as Map)['kind'], isA<int>());
          expect(doc.data()['_rev'], result.definition.schemaRevision);
        }
      },
    );

    test(
      'items written for an older revision are fitted to the fields and saved',
      () async {
        final FakeFirebaseFirestore firestore = await _seeded();
        // The list is at revision 2 with kind as a counter; the items were
        // written by a device that still had revision 1 (kind as text).
        final ListDefinition current = ListPatch.apply(
          _simple('list-a'),
          const [],
          _toCounter,
          _t0,
        ).definition;
        expect(current.schemaRevision, 2);
        await firestore.doc('users/$_uid/lists/list-a').set(current.toJson());
        final String items = 'users/$_uid/lists/list-a/items';
        await firestore.doc('$items/fits').set({
          ..._kind('fits', '3').toJson(),
          '_rev': 1,
        });
        await firestore.doc('$items/hides').set({
          ..._kind('hides', 'many').toJson(),
          '_rev': 1,
        });
        // No `_rev` at all counts as 0.
        await firestore.doc('$items/bare').set(_kind('bare', '4').toJson());
        // Up to date: left alone even though its value would convert.
        await firestore.doc('$items/current').set({
          ..._kind('current', '5').toJson(),
          '_rev': 2,
        });

        final FirestoreListStore store = await _loaded(firestore);
        final ListCatalog catalog = await _until(
          store,
          (c) =>
              c.itemsOf('list-a').where((i) => i['kind'] is int).length == 2 &&
              c.itemsOf('list-a').any((i) => i[ListPatch.legacyKey] != null),
        );
        expect(
          catalog.itemsOf('list-a').firstWhere((i) => i.id == 'hides').values,
          {
            'title': 'hides',
            ListPatch.legacyKey: {
              'kind': ['many'],
            },
          },
        );
        expect(
          catalog
              .itemsOf('list-a')
              .firstWhere((i) => i.id == 'current')['kind'],
          '5',
        );
        for (final String id in ['fits', 'hides', 'bare']) {
          expect(
            (await firestore.doc('$items/$id').get()).data()!['_rev'],
            2,
            reason: id,
          );
        }
        // A repair keeps the item's updatedAt: it is not a user edit.
        expect(
          catalog.itemsOf('list-a').firstWhere((i) => i.id == 'fits').updatedAt,
          _t0,
        );
      },
    );

    // T-14 R5: the outer shape is fine, so ListItem.fromJson takes it, but
    // the hidden values are not a map.
    test('a stale item with malformed hidden values is skipped; the rest is '
        'repaired', () async {
      final FakeFirebaseFirestore firestore = await _seeded();
      await firestore
          .doc('users/$_uid/lists/list-a')
          .set(
            ListPatch.apply(
              _simple('list-a'),
              const [],
              _toCounter,
              _t0,
            ).definition.toJson(),
          );
      final String items = 'users/$_uid/lists/list-a/items';
      await firestore.doc('$items/a-bad').set({
        ..._kind('a-bad', 'many').toJson(),
        'values': {'title': 'x', 'kind': 'many', ListPatch.legacyKey: 'bad'},
        '_rev': 1,
      });
      await firestore.doc('$items/b-good').set({
        ..._kind('b-good', '3').toJson(),
        '_rev': 1,
      });

      final List<String> skipped = [];
      final FirestoreListStore store = await _loaded(
        firestore,
        onSkipped: (path, error) => skipped.add(path),
      );
      await _until(
        store,
        (c) => c.itemsOf('list-a').any((i) => i['kind'] == 3),
      );
      expect(skipped, ['$items/a-bad']);
      expect(store.current.itemsOf('list-a').map((i) => i.id), ['b-good']);
      expect((await firestore.doc('$items/b-good').get()).data()!['_rev'], 2);
    });

    // T-14 R1: device B changes a stale item just before device A's repair
    // writes it, whether A writes in a batch or a transaction.
    group('two clients: the repair against a concurrent change', () {
      late _ScriptedFirestore firestore;
      const String items = 'users/$_uid/lists/list-a/items';

      // A's cache has `one` written for revision 1; the list is at 2.
      setUp(() async {
        firestore = await _seeded(_ScriptedFirestore());
        await firestore
            .doc('users/$_uid/lists/list-a')
            .set(
              ListPatch.apply(
                _simple('list-a'),
                const [],
                _toCounter,
                _t0,
              ).definition.toJson(),
            );
        await firestore.doc('$items/one').set({
          ..._kind('one', '3').toJson(),
          '_rev': 1,
        });
      });

      // Runs [change] once, before the first write A makes.
      Future<void> beforeFirstWrite(Future<void> Function() change) {
        final Completer<void> done = Completer<void>();
        Future<void> once() async {
          firestore.beforeTransaction = null;
          firestore.beforeBatch = null;
          await change();
          done.complete();
        }

        firestore.beforeTransaction = once;
        firestore.beforeBatch = once;
        return done.future;
      }

      test('an edit is kept and fitted, not overwritten', () async {
        final Future<void> raced = beforeFirstWrite(
          () => firestore.doc('$items/one').set({
            ...ListItem(
              id: 'one',
              listId: 'list-a',
              values: const {'title': 'edited on B', 'kind': '4'},
              createdAt: _t0,
              updatedAt: _t0.add(const Duration(hours: 1)),
            ).toJson(),
            '_rev': 1,
          }),
        );
        final FirestoreListStore a = await _loaded(firestore);
        await raced;
        await _until(
          a,
          (c) =>
              c.itemsOf('list-a').single['title'] == 'edited on B' &&
              c.itemsOf('list-a').single['kind'] == 4,
        );
        final Map<String, dynamic> stored = await _doc(
          firestore,
          'list-a/items/one',
        );
        expect(stored['values'], {'title': 'edited on B', 'kind': 4});
        expect(stored['_rev'], 2);
      });

      test('a repair that fails offline is tried again later', () async {
        firestore.failWith = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        );
        final FirestoreListStore a = await _loaded(firestore);
        await pumpEventQueue();
        expect(firestore.transactions, greaterThan(0));
        expect(a.current.itemsOf('list-a').single['kind'], '3');

        firestore.failWith = null;
        await a.apply(ListChanges(saved: [_kind('two', 5)]));
        await _until(
          a,
          (c) => c.itemsOf('list-a').every((i) => i['kind'] is int),
        );
        expect((await _doc(firestore, 'list-a/items/one'))['_rev'], 2);
      });

      test('a deleted item is not brought back', () async {
        final Future<void> raced = beforeFirstWrite(
          () => firestore.doc('$items/one').delete(),
        );
        final FirestoreListStore a = await _loaded(firestore);
        await raced;
        await pumpEventQueue();
        await _until(a, (c) => c.itemsOf('list-a').isEmpty);
        await pumpEventQueue();
        expect((await firestore.doc('$items/one').get()).exists, isFalse);
      });
    });

    // T-14 R1: the items a large patch saves after its transaction.
    test(
      'two clients: a large patch does not overwrite an edit or bring back a '
      'deleted item',
      () async {
        final _ScriptedFirestore firestore = await _seeded(
          _ScriptedFirestore(),
        );
        final FirestoreListStore a = await _loaded(firestore, batchLimit: 10);
        await a.createList(
          _simple('list-a'),
          items: [for (int n = 0; n < 25; n++) _kind('i$n', '$n')],
        );
        await _until(a, (c) => c.itemsOf('list-a').length == 25);

        // After A's transaction saved the definition, before A saves the
        // items: B edits i20 (with its old list) and deletes i21.
        const String items = 'users/$_uid/lists/list-a/items';
        bool raced = false;
        Future<void> afterFirst() async {
          firestore.beforeTransaction = null;
          firestore.beforeBatch = null;
          await firestore.doc('$items/i20').set({
            ...ListItem(
              id: 'i20',
              listId: 'list-a',
              values: const {'title': 'edited on B', 'kind': '99'},
              createdAt: _t0,
              updatedAt: _t0.add(const Duration(hours: 1)),
            ).toJson(),
            '_rev': 1,
          });
          await firestore.doc('$items/i21').delete();
          raced = true;
        }

        firestore.beforeTransaction = () async {
          firestore.beforeTransaction = afterFirst;
          firestore.beforeBatch = afterFirst;
        };
        final ListPatchResult? result = await a.patchList('list-a', _toCounter);
        expect(result!.changedItemIds, hasLength(25));
        expect(raced, isTrue);
        await pumpEventQueue();

        final QuerySnapshot<Map<String, dynamic>> stored = await firestore
            .collection(items)
            .get();
        expect(stored.docs.map((d) => d.id), isNot(contains('i21')));
        expect(stored.docs, hasLength(24));
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in stored.docs) {
          expect((doc.data()['values'] as Map)['kind'], isA<int>());
          expect(doc.data()['_rev'], result.definition.schemaRevision);
        }
        expect(stored.docs.firstWhere((d) => d.id == 'i20').data()['values'], {
          'title': 'edited on B',
          'kind': 99,
        });
      },
    );

    test('an item that already fits is not rewritten by the repair', () async {
      final FakeFirebaseFirestore firestore = await _seeded();
      await firestore
          .doc('users/$_uid/lists/list-a')
          .set(
            ListPatch.apply(
              _simple('list-a'),
              const [],
              _toCounter,
              _t0,
            ).definition.toJson(),
          );
      final String path = 'users/$_uid/lists/list-a/items/ok';
      await firestore.doc(path).set({..._kind('ok', 7).toJson(), '_rev': 1});

      final FirestoreListStore store = await _loaded(firestore);
      await pumpEventQueue();
      expect(store.current.itemsOf('list-a').single['kind'], 7);
      expect((await firestore.doc(path).get()).data()!['_rev'], 1);
    });
  });
}
