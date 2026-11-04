import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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

import '../support/firestore_store.dart';

// The time between a transaction's callback and its commit (R2 of the Codex
// re-review, Q-58). The real plugin collects the callback's writes and commits
// them afterwards; fake_cloud_firestore writes at once, so this fake keeps them
// back until the test lets them go, or fails like a lost connection.
const String _g = BuiltinTemplates.groceryId;
final DateTime _now = DateTime.utc(2026, 11, 4);

class _Held extends Fake implements Transaction {
  _Held(this.inner);

  final Transaction inner;
  final List<void Function()> writes = [];

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) => inner.get(documentReference);

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    writes.add(() => inner.set(documentReference, data, options));
    return this;
  }

  @override
  Transaction delete(DocumentReference<Object?> documentReference) {
    writes.add(() => inner.delete(documentReference));
    return this;
  }
}

class _LateCommit extends FakeFirebaseFirestore {
  Completer<void>? commitGate;
  // The commit fails as the connection drops, after the callback returned.
  bool commitFails = false;
  int commits = 0;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    return super.runTransaction(
      (transaction) async {
        final _Held held = _Held(transaction);
        final T value = await transactionHandler(held);
        await commitGate?.future;
        if (commitFails && held.writes.isNotEmpty) {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
        }
        if (held.writes.isNotEmpty) {
          commits++;
        }
        for (final void Function() write in held.writes) {
          write();
        }
        return value;
      },
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

ListItem _item(String id, String title) => ListItem(
  id: id,
  listId: _g,
  values: {'title': title, 'done': false},
  createdAt: _now,
  updatedAt: _now,
);

ListItem _edited(ListItem item, String title) => ListItem(
  id: item.id,
  listId: item.listId,
  values: {...item.values, 'title': title},
  createdAt: item.createdAt,
  updatedAt: item.updatedAt.add(const Duration(minutes: 1)),
);

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 20));

// Waits until the store's catalog shows [test].
Future<ListCatalog> _until(FirestoreListStore store, bool Function(ListCatalog) test) {
  return store.watch().firstWhere(test).timeout(const Duration(seconds: 5));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Duration limit = Duration(milliseconds: 40);
  const Duration commitLimit = Duration(milliseconds: 80);

  late _LateCommit firestore;
  late FirestoreListStore store;
  late ListDefinition definition;
  late ListItem milk;

  setUp(() async {
    firestore = _LateCommit();
    final FirestoreListStore seeded = await fakeFirestoreStore(
      firestore: firestore,
      items: [_item('a', 'Milk')],
      transactionTimeout: limit,
      commitTimeout: commitLimit,
    );
    store = seeded;
    definition = store.current.definition(_g)!;
    milk = store.current.itemsOf(_g).single;
  });

  // Holds the commit, and asserts [write] reports the outcome as unknown only
  // after the first limit, with nothing landed yet.
  Future<void> expectUnknown(Future<List<ListError>> Function() write) async {
    firestore.commitGate = Completer<void>();
    final Stopwatch watch = Stopwatch()..start();
    final List<ListError> errors = await write();
    expect(errors.single.code, ListErrorCode.outcomeUnknown);
    expect(watch.elapsed, greaterThanOrEqualTo(limit + commitLimit));
    expect(firestore.commits, 0);
    firestore.commitGate!.complete();
    firestore.commitGate = null;
    await _tick();
    expect(firestore.commits, 1);
  }

  group('a commit still under way when the time is up', () {
    test('an edit reports unknown, not "nothing was changed", and lands', () async {
      await expectUnknown(
        () async => (await store.applyAiItems(
          AiItemWrite(
            definition: definition,
            saved: [_edited(milk, 'Oat milk')],
            base: {milk.id: milk},
          ),
        )).errors,
      );
      await _until(store, (c) => c.itemsOf(_g).single['title'] == 'Oat milk');
    });

    test('an add reports unknown and does not write again as a batch', () async {
      await expectUnknown(
        () async => (await store.applyAiItems(
          AiItemWrite(definition: definition, saved: [_item('new', 'Eggs')]),
        )).errors,
      );
      final ListCatalog catalog = await _until(
        store,
        (c) => c.itemsOf(_g).length == 2,
      );
      expect(catalog.itemsOf(_g).map((i) => i.id), contains('new'));
    });

    test('nothing shows during the wait, and a retry finding the item edited refuses', () async {
      // Firestore itself fails a commit whose read documents changed; the add
      // now reads its own id, so that covers a retry after a lost answer.
      final ListItem added = _item('new', 'Eggs');
      final AiItemWrite write = AiItemWrite(definition: definition, saved: [added]);
      firestore.commitGate = Completer<void>();
      final Future<AiWriteResult> adding = store.applyAiItems(write);
      await _tick();
      expect(store.current.itemsOf(_g).map((i) => i.id), isNot(contains('new')));
      firestore.commitGate!.complete();
      firestore.commitGate = null;
      await adding;
      await _until(store, (c) => c.itemsOf(_g).length == 2);
      await store.apply(ListChanges(saved: [_edited(added, 'Mine')]));
      await _until(store, (c) => c.itemsOf(_g).any((i) => i['title'] == 'Mine'));
      final AiWriteResult retry = await store.applyAiItems(write);
      expect(retry.errors.single.code, ListErrorCode.previewChanged);
      await _tick();
      expect(
        store.current.itemsOf(_g).where((i) => i.id == 'new').single['title'],
        'Mine',
      );
    });

    test('a retry of an add that did land succeeds without a change', () async {
      final ListItem added = _item('new', 'Eggs');
      final AiItemWrite write = AiItemWrite(definition: definition, saved: [added]);
      expect((await store.applyAiItems(write)).errors, isEmpty);
      await _until(store, (c) => c.itemsOf(_g).length == 2);
      expect((await store.applyAiItems(write)).errors, isEmpty);
      expect(
        store.current.itemsOf(_g).where((i) => i.id == 'new').single['title'],
        'Eggs',
      );
    });

    test('an AI patch reports unknown and lands once', () async {
      await expectUnknown(
        () async => (await store.patchListAi(_g, const [
          ListPatchOp(PatchOpKind.setListInfo, {'name': 'Food'}),
        ], previewed: definition))!.errors,
      );
      final ListCatalog catalog = await _until(
        store,
        (c) => c.definition(_g)!.name == 'Food',
      );
      expect(
        catalog.definition(_g)!.schemaRevision,
        definition.schemaRevision + 1,
      );
    });

    test('an Undo reports unknown and lands', () async {
      final AiWriteResult applied = await store.applyAiItems(
        AiItemWrite(
          definition: definition,
          saved: [_edited(milk, 'Oat milk')],
          base: {milk.id: milk},
        ),
      );
      await _until(store, (c) => c.itemsOf(_g).single['title'] == 'Oat milk');
      firestore.commits = 0;
      await expectUnknown(() => store.restoreSnapshot(applied.snapshot!));
      await _until(store, (c) => c.itemsOf(_g).single['title'] == 'Milk');
    });

    test('a created list delete reports unknown and lands', () async {
      final ListDefinition books = ListDefinition.fromJson({
        ...definition.toJson(),
        'id': 'list-books',
        'name': 'Books',
      });
      expect(await store.createList(books), isEmpty);
      final ListDefinition stored = (await _until(
        store,
        (c) => c.definition('list-books') != null,
      )).definition('list-books')!;
      await expectUnknown(
        () => store.deleteCreatedList(CreatedList(stored, const [])),
      );
      await _until(store, (c) => c.definition('list-books') == null);
    });

    test('the list editor\'s patch is not applied a second time as a batch', () async {
      firestore.commitGate = Completer<void>();
      final ListPatchResult result = (await store.patchList(_g, const [
        ListPatchOp(PatchOpKind.setListInfo, {'name': 'Food'}),
      ]))!;
      // Reported as what was handed over.
      expect(result.isValid, isTrue);
      expect(result.definition.name, 'Food');
      expect(firestore.commits, 0);
      firestore.commitGate!.complete();
      firestore.commitGate = null;
      final ListCatalog catalog = await _until(
        store,
        (c) => c.definition(_g)!.name == 'Food',
      );
      await _tick();
      expect(firestore.commits, 1);
      expect(
        store.current.definition(_g)!.schemaRevision,
        catalog.definition(_g)!.schemaRevision,
      );
      expect(
        catalog.definition(_g)!.schemaRevision,
        definition.schemaRevision + 1,
      );
    });

    test('a commit that answers within the wait is simply the result', () async {
      firestore.commitGate = Completer<void>();
      final Future<AiWriteResult> writing = store.applyAiItems(
        AiItemWrite(
          definition: definition,
          saved: [_edited(milk, 'Oat milk')],
          base: {milk.id: milk},
        ),
      );
      await Future<void>.delayed(limit + const Duration(milliseconds: 20));
      firestore.commitGate!.complete();
      firestore.commitGate = null;
      expect((await writing).errors, isEmpty);
    });

    test('a connection lost during the commit is unknown too', () async {
      firestore.commitFails = true;
      final AiWriteResult result = await store.applyAiItems(
        AiItemWrite(definition: definition, saved: [_item('new', 'Eggs')]),
      );
      expect(result.errors.single.code, ListErrorCode.outcomeUnknown);
      await _tick();
      expect(store.current.itemsOf(_g).map((i) => i.id), isNot(contains('new')));
    });
  });

  group('time up before the writes are handed over', () {
    late Completer<void> held;

    Future<FirestoreListStore> holding() async {
      held = Completer<void>();
      return FirestoreListStore(
        firestore,
        testUid,
        transactionTimeout: limit,
        commitTimeout: commitLimit,
        beforeHandOver: () => held.future,
      )..watch();
    }

    test('nothing lands, and "nothing was changed" holds', () async {
      final FirestoreListStore slow = await holding();
      addTearDown(slow.close);
      await slow.watch().first;
      final AiWriteResult result = await slow.applyAiItems(
        AiItemWrite(
          definition: definition,
          saved: [_edited(milk, 'Oat milk')],
          base: {milk.id: milk},
        ),
      );
      expect(result.errors.single.code, ListErrorCode.needsConnection);
      held.complete();
      await _tick();
      expect(firestore.commits, 0);
      expect(store.current.itemsOf(_g).single['title'], 'Milk');
    });

    test('an add falls back to a batch, once', () async {
      final FirestoreListStore slow = await holding();
      addTearDown(slow.close);
      await slow.watch().first;
      final AiWriteResult result = await slow.applyAiItems(
        AiItemWrite(definition: definition, saved: [_item('new', 'Eggs')]),
      );
      expect(result.errors, isEmpty);
      await _until(store, (c) => c.itemsOf(_g).length == 2);
      await store.apply(ListChanges(saved: [_item('new', 'Mine')]));
      await _until(
        store,
        (c) => c.itemsOf(_g).any((i) => i['title'] == 'Mine'),
      );
      held.complete();
      await _tick();
      expect(firestore.commits, 0);
      expect(
        store.current.itemsOf(_g).where((i) => i.id == 'new').single['title'],
        'Mine',
      );
    });
  });
}
