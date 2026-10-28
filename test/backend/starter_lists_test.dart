import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/backend/firestore_setup.dart';
import 'package:hybrid_note/backend/starter_lists.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_patch.dart';
import 'package:hybrid_note/lists/list_store.dart';

const String _uid = 'user-1';
final DateTime _t0 = DateTime.utc(2026, 3, 1);

final List<String> _templateIds = [
  for (final definition in BuiltinTemplates.all()) definition.id,
];

Future<ListCatalog> _until(ListStore store, bool Function(ListCatalog c) test) {
  return store.watch().firstWhere(test).timeout(const Duration(seconds: 10));
}

Future<FirestoreListStore> _loaded(FirebaseFirestore firestore) async {
  final FirestoreListStore store = FirestoreListStore(firestore, _uid);
  addTearDown(store.close);
  await store.watch().first.timeout(const Duration(seconds: 10));
  return store;
}

// A Firestore that cannot reach the server for transactions.
class _OfflineFirestore extends FakeFirebaseFirestore {
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
  }
}

// Fails the first [failures] transactions like an unreachable server.
class _FlakyFirestore extends FakeFirebaseFirestore {
  int failures = 0;
  int transactions = 0;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactions++;
    if (failures > 0) {
      failures--;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return super.runTransaction(
      transactionHandler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

void main() {
  group('StarterLists (Q-22 D)', () {
    test('a new account gets the marker and a copy of each template', () async {
      final FakeFirebaseFirestore firestore = FakeFirebaseFirestore();

      expect(await StarterLists.ensure(firestore, _uid, now: _t0), isTrue);

      final marker = await StarterLists.marker(firestore, _uid).get();
      expect(marker.data(), {'starterSeededAt': _t0.toIso8601String()});
      final FirestoreListStore store = await _loaded(firestore);
      final ListCatalog catalog = store.current;
      // In template order, with fresh ids and the template's id kept.
      expect(catalog.definitions.map((d) => d.templateId), _templateIds);
      for (final definition in catalog.definitions) {
        expect(definition.id, startsWith('list-'));
        expect(_templateIds, isNot(contains(definition.id)));
        expect(definition.nameKey, isNotNull);
        expect(definition.updatedAt, _t0);
      }
      expect(catalog.items, isEmpty);
    });

    test('seeds once: not again, not after a delete, not on a restart', () async {
      final FakeFirebaseFirestore firestore = FakeFirebaseFirestore();
      expect(await StarterLists.ensure(firestore, _uid), isTrue);
      expect(await StarterLists.ensure(firestore, _uid), isFalse);

      final FirestoreListStore store = await _loaded(firestore);
      final String first = store.current.definitions.first.id;
      expect(await store.deleteList(first), isNotNull);
      await _until(store, (c) => c.definitions.length == 3);
      await store.close();

      // A restart: the app opens the store through the setup again.
      final setup = FirestoreSetup(firestore).openStore(_uid);
      addTearDown(setup.store.close);
      expect(await setup.starter, isFalse);
      final ListCatalog catalog = await _until(
        setup.store,
        (c) => c.definitions.length == 3,
      );
      expect(catalog.definitions.map((d) => d.id), isNot(contains(first)));
    });

    test('the copies are ordinary lists: patched and deleted like any', () async {
      final FakeFirebaseFirestore firestore = FakeFirebaseFirestore();
      await StarterLists.ensure(firestore, _uid);
      final FirestoreListStore store = await _loaded(firestore);
      final String grocery = store.current.definitions
          .firstWhere((d) => d.templateId == BuiltinTemplates.groceryId)
          .id;

      final ListPatchResult? result = await store.patchList(grocery, const [
        ListPatchOp(PatchOpKind.setListInfo, {'name': 'Shop'}),
        ListPatchOp(PatchOpKind.removeField, {'key': 'description'}),
      ]);
      expect(result!.isValid, isTrue, reason: '${result.errors}');
      await _until(store, (c) => c.definition(grocery)!.name == 'Shop');
      for (final definition in store.current.definitions.toList()) {
        expect(await store.deleteList(definition.id), isNotNull);
      }
      await _until(store, (c) => c.definitions.isEmpty);
    });

    test('each user is seeded on their own, sample items with fresh ids', () async {
      final FakeFirebaseFirestore firestore = FakeFirebaseFirestore();
      final Map<String, List<ListItem>> samples = {
        BuiltinTemplates.tasksId: [
          ListItem(
            id: 'sample',
            listId: BuiltinTemplates.tasksId,
            values: const {'title': 'Water the plants', 'done': false},
            createdAt: _t0,
            updatedAt: _t0,
          ),
        ],
      };

      for (final String uid in ['user-a', 'user-b']) {
        expect(
          await StarterLists.ensure(firestore, uid, sampleItems: samples),
          isTrue,
        );
      }

      final List<String> itemIds = [];
      for (final String uid in ['user-a', 'user-b']) {
        final lists = await firestore.collection('users/$uid/lists').get();
        expect(lists.docs, hasLength(4));
        final tasks = lists.docs.singleWhere(
          (doc) => doc.data()['templateId'] == BuiltinTemplates.tasksId,
        );
        final items = await tasks.reference.collection('items').get();
        final data = items.docs.single.data();
        expect(data['listId'], tasks.id);
        expect(data['values'], {'title': 'Water the plants', 'done': false});
        expect(data['_rev'], isA<int>());
        itemIds.add(items.docs.single.id);
      }
      expect(itemIds.toSet(), hasLength(2));
      expect(itemIds, isNot(contains('sample')));
    });

    test('offline: nothing is written, the error is reported, the store '
        'still opens, and the next open seeds', () async {
      final _OfflineFirestore offline = _OfflineFirestore();
      final List<Object> errors = [];

      final opened = FirestoreSetup(offline).openStore(
        _uid,
        onSeedError: errors.add,
      );
      addTearDown(opened.store.close);
      expect(await opened.starter, isNull);
      expect(errors.single, isA<FirebaseException>());
      await opened.store.watch().first;
      expect(opened.store.current.definitions, isEmpty);
      expect((await StarterLists.marker(offline, _uid).get()).exists, isFalse);

      final FakeFirebaseFirestore online = FakeFirebaseFirestore();
      final again = FirestoreSetup(online).openStore(_uid);
      addTearDown(again.store.close);
      expect(await again.starter, isTrue);
      await _until(again.store, (c) => c.definitions.length == 4);
    });

    test('a failed seeding waits for Try again: no retry by itself (Q-27)',
        () async {
      final _FlakyFirestore firestore = _FlakyFirestore()..failures = 1;
      final opened = FirestoreSetup(firestore).openStore(
        _uid,
        onSeedError: (_) {},
      );
      addTearDown(opened.store.close);

      expect(await opened.starter, isNull);
      expect(opened.seeding.status, StarterStatus.failed);
      await pumpEventQueue();
      expect(firestore.transactions, 1);

      expect(await opened.seeding.retry(), isTrue);
      expect(opened.seeding.status, StarterStatus.done);
      await _until(opened.store, (c) => c.definitions.length == 4);
    });

    test('Start empty writes the marker only: no starter lists later',
        () async {
      final _FlakyFirestore firestore = _FlakyFirestore()..failures = 1;
      final opened = FirestoreSetup(firestore).openStore(
        _uid,
        onSeedError: (_) {},
      );
      addTearDown(opened.store.close);
      expect(await opened.starter, isNull);

      expect(await opened.seeding.startEmpty(), isTrue);
      expect(opened.seeding.status, StarterStatus.done);
      expect(
        (await StarterLists.marker(firestore, _uid).get()).data(),
        contains(StarterLists.seededAtKey),
      );
      // A later start (or Try again) finds the marker and writes nothing.
      expect(await StarterLists.ensure(firestore, _uid), isFalse);
      expect(
        (await firestore.collection('users/$_uid/lists').get()).docs,
        isEmpty,
      );
    });
  });
}
