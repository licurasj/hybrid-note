// T-13 unit 10, F1: Done on a ring writes through a server-checked
// transaction, and offline only queues the fields it changed, so it never
// brings back an item another phone deleted or puts back a date it moved.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:hybrid_note/reminders/reminder_background.dart';
import 'package:hybrid_note/reminders/ring_booker.dart';

const String _uid = 'user-1';
const String _date = '2026-03-10T15:00:00.000Z';
final ListDefinition _tasks = BuiltinTemplates.tasks();
final DateTime _t0 = DateTime.utc(2026, 3, 1);

// Offline: every transaction fails as the plugin does without a server, and
// a batch runs [beforeCommit] (another phone's write reaching the server
// first) before it commits. The ops each batch queued are recorded.
class _OfflineFirestore extends FakeFirebaseFirestore {
  bool offline = true;
  Future<void> Function()? beforeCommit;
  final List<String> ops = [];
  Future<void>? commit;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    if (offline) {
      throw FirebaseException(plugin: 'test', code: 'unavailable');
    }
    return super.runTransaction(
      transactionHandler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }

  @override
  WriteBatch batch() => _RecordingBatch(this, super.batch());
}

class _RecordingBatch implements WriteBatch {
  _RecordingBatch(this._firestore, this._batch);

  final _OfflineFirestore _firestore;
  final WriteBatch _batch;

  @override
  Future<void> commit() {
    final Future<void> done = () async {
      await _firestore.beforeCommit?.call();
      await _batch.commit();
    }();
    _firestore.commit = done;
    return done;
  }

  @override
  void delete(DocumentReference document) {
    _firestore.ops.add('delete ${document.id}');
    _batch.delete(document);
  }

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    _firestore.ops.add('set ${document.id}');
    _batch.set(document, data, options);
  }

  @override
  void update<T>(DocumentReference<T> document, T data) {
    _firestore.ops.add(
      'update ${document.id} ${(data as Map).keys.toList()..sort()}',
    );
    _batch.update(document, data);
  }
}

ListItem _task({String? repeat}) => ListItem(
  id: 'a',
  listId: _tasks.id,
  values: {
    'title': 'Call',
    'done': false,
    'reminderAt': _date,
    if (repeat != null) 'repeat': {'frequency': repeat},
  },
  createdAt: _t0,
  updatedAt: _t0,
);

DocumentReference<Map<String, dynamic>> _itemRef(
  FirebaseFirestore firestore, [
  String id = 'a',
]) => firestore.doc('users/$_uid/lists/${_tasks.id}/items/$id');

Future<_OfflineFirestore> _seeded({
  ListItem? item,
  AccountPreferences? preferences,
}) async {
  final _OfflineFirestore firestore = _OfflineFirestore();
  await firestore.doc('users/$_uid/lists/${_tasks.id}').set(_tasks.toJson());
  await _itemRef(
    firestore,
  ).set(FirestoreListStore.itemData(item ?? _task(), _tasks.schemaRevision));
  if (preferences != null) {
    await firestore
        .doc('users/$_uid/settings/preferences')
        .set(preferences.toJson());
  }
  return firestore;
}

const RingPayload _payload = RingPayload(
  key: 'k',
  listId: 'builtin.tasks',
  itemId: 'a',
  itemDate: _date,
  dueMs: 0,
  fingerprint: 'f',
);

Future<Map<String, dynamic>?> _stored(FirebaseFirestore firestore) async =>
    (await _itemRef(firestore).get()).data();

void main() {
  setUp(() {
    expect(_tasks.id, _payload.listId);
  });

  test('offline it queues only the changed fields, as an update', () async {
    final _OfflineFirestore firestore = await _seeded();
    expect(await doneFromRing(firestore, _uid, _payload), isNull);
    await firestore.commit;
    expect(firestore.ops, hasLength(1));
    expect(firestore.ops.single, startsWith('update a '));
    expect(firestore.ops.single, contains('values.done'));
    expect(firestore.ops.single, isNot(contains('reminderAt')));
    expect(firestore.ops.single, isNot(contains('title')));
    expect((await _stored(firestore))!['values']['done'], isTrue);
  });

  test('offline, a date moved on another phone stays moved', () async {
    final _OfflineFirestore firestore = await _seeded();
    firestore.beforeCommit = () => _itemRef(firestore).update({
      'values.reminderAt': '2026-03-12T15:00:00.000Z',
      'values.title': 'Call Bo',
    });
    await doneFromRing(firestore, _uid, _payload);
    await firestore.commit;
    final Map<String, dynamic> values = (await _stored(firestore))!['values'];
    expect(values['reminderAt'], '2026-03-12T15:00:00.000Z');
    expect(values['title'], 'Call Bo');
    expect(values['done'], isTrue);
  });

  test('offline, an item deleted on another phone stays deleted', () async {
    final _OfflineFirestore firestore = await _seeded();
    firestore.beforeCommit = () => _itemRef(firestore).delete();
    await doneFromRing(firestore, _uid, _payload);
    await expectLater(firestore.commit, throwsA(isA<FirebaseException>()));
    expect(await _stored(firestore), isNull);
  });

  test('offline on a list that clears at once it only ticks', () async {
    final _OfflineFirestore firestore = await _seeded(
      item: _task(repeat: 'daily'),
      preferences: const AccountPreferences(
        tickedItems: TickedItems.clearAtOnce,
      ),
    );
    await doneFromRing(firestore, _uid, _payload);
    await firestore.commit;
    expect(firestore.ops, hasLength(1));
    expect(firestore.ops.single, startsWith('update a '));
    expect((await _stored(firestore))!['values']['done'], isTrue);
    expect(
      (await firestore.collection('users/$_uid/lists/${_tasks.id}/items').get())
          .docs,
      hasLength(1),
    );
  });

  test(
    'online it clears at once in a transaction, the repeat comes again',
    () async {
      final _OfflineFirestore firestore =
          await _seeded(
              item: _task(repeat: 'daily'),
              preferences: const AccountPreferences(
                tickedItems: TickedItems.clearAtOnce,
              ),
            )
            ..offline = false;
      expect(await doneFromRing(firestore, _uid, _payload), isTrue);
      expect(firestore.ops, isEmpty);
      expect(await _stored(firestore), isNull);
      expect(
        (await firestore
                .collection('users/$_uid/lists/${_tasks.id}/items')
                .get())
            .docs,
        hasLength(1),
      );
    },
  );

  group('offlineFields', () {
    final Map<String, dynamic> stored = FirestoreListStore.itemData(
      _task(),
      _tasks.schemaRevision,
    );

    test('the changed fields only', () {
      final ListChanges changes = ListRules.setCompleted(
        _tasks,
        _task(),
        true,
        _t0.add(const Duration(hours: 1)),
      );
      final Map<String, Object?> fields = FirestoreListStore.offlineFields(
        _tasks,
        'a',
        stored,
        changes,
      )!;
      expect(fields.keys, containsAll(['values.done', 'updatedAt']));
      expect(fields.keys, isNot(contains('values')));
      expect(fields.keys, isNot(contains('values.reminderAt')));
      expect(fields.keys, isNot(contains('values.title')));
      expect(fields['values.done'], isTrue);
    });

    test('a removed field is deleted', () {
      final ListItem item = _task();
      final ListItem without = ListItem(
        id: item.id,
        listId: item.listId,
        values: {...item.values}..remove('reminderAt'),
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
      );
      final Map<String, Object?> fields = FirestoreListStore.offlineFields(
        _tasks,
        'a',
        stored,
        ListChanges(saved: [without]),
      )!;
      expect(fields['values.reminderAt'], isA<FieldValue>());
    });

    test('nothing for a clear, a delete or another item', () {
      final ListItem other = ListItem(
        id: 'b',
        listId: _tasks.id,
        values: const {'title': 'B'},
        createdAt: _t0,
        updatedAt: _t0,
      );
      for (final ListChanges changes in [
        const ListChanges(deletedIds: ['a']),
        ListChanges(saved: [other]),
        ListChanges(saved: [_task(), other]),
      ]) {
        expect(
          FirestoreListStore.offlineFields(_tasks, 'a', stored, changes),
          isNull,
        );
      }
    });
  });
}
