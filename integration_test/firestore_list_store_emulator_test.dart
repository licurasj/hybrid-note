import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/backend/firestore_setup.dart';
import 'package:hybrid_note/backend/starter_lists.dart';
import 'package:hybrid_note/firebase_options.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_patch.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:hybrid_note/lists/list_store.dart';

import '../test/lists/list_store_contract_test.dart' show listStoreContract;

// FirestoreListStore through the real cloud_firestore plugin against the
// Firebase emulators, with the project's firestore.rules (T-14 unit 4, Q-10
// full suite). It proves what fake_cloud_firestore cannot: the nested-array
// encoding, offline transactions, real contention, write limits and the
// repair under the rules. Run it inside `firebase emulators:exec` as the
// runbook shows; MEASURE lines report timings.

// The host machine as the device sees it.
final String _host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? '10.0.2.2'
    : '127.0.0.1';
const String _password = 'emulator-only-password';
final DateTime _t0 = DateTime.utc(2026, 3, 1);
const Duration _wait = Duration(seconds: 30);

late FirebaseFirestore _db;
late FirebaseAuth _auth;
late FirebaseFirestore _db2;
late FirebaseAuth _auth2;
int _users = 0;

// Signs the default app in as a new emulator user; returns its uid and
// email.
Future<(String, String)> _newUser() async {
  final String email =
      'user${_users++}-${DateTime.now().microsecondsSinceEpoch}@example.test';
  await _auth.signOut();
  final UserCredential credential = await _auth.createUserWithEmailAndPassword(
    email: email,
    password: _password,
  );
  return (credential.user!.uid, email);
}

// The four built-in definitions, as the Block B switch-over writes them.
Future<void> _seed(String uid) async {
  for (final ListDefinition definition in BuiltinTemplates.all()) {
    await _db.doc('users/$uid/lists/${definition.id}').set(definition.toJson());
  }
}

Future<FirestoreListStore> _loaded(
  FirebaseFirestore db,
  String uid, {
  Duration transactionTimeout = const Duration(seconds: 10),
  void Function(String path, Object error)? onSkipped,
}) async {
  final FirestoreListStore store = FirestoreListStore(
    db,
    uid,
    transactionTimeout: transactionTimeout,
    onSkipped: onSkipped,
  );
  addTearDown(store.close);
  await store.watch().first.timeout(_wait);
  return store;
}

Future<ListCatalog> _until(
  ListStore store,
  bool Function(ListCatalog catalog) test,
) {
  return store.watch().firstWhere(test).timeout(_wait);
}

Future<Map<String, dynamic>?> _server(FirebaseFirestore db, String path) async {
  return (await db.doc(path).get(const GetOptions(source: Source.server)))
      .data();
}

// Polls the server until [test] holds.
Future<void> _eventually(
  Future<bool> Function() test, {
  Duration timeout = _wait,
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!await test()) {
    if (watch.elapsed > timeout) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

ListDefinition _garden(String id) {
  return ListDefinition.fromJson({
    'id': id,
    'name': 'Garden',
    'icon': 'local_florist',
    'color': '#43A047',
    'fields': [
      {
        'key': 'title',
        'type': 'text',
        'label': 'Title',
        'required': true,
        'primary': true,
      },
      {
        'key': 'kind',
        'type': 'category',
        'label': 'Kind',
        'options': [
          {'value': 'fern'},
          {'value': 'cactus'},
        ],
      },
      {'key': 'n', 'type': 'number', 'label': 'N'},
      {'key': 'tags', 'type': 'tags', 'label': 'Tags'},
    ],
    'view': {'kind': 'cards'},
    'updatedAt': _t0.toIso8601String(),
  });
}

ListItem _row(String listId, String id, {Map<String, dynamic>? values}) {
  return ListItem(
    id: id,
    listId: listId,
    values: values ?? {'title': id},
    createdAt: _t0,
    updatedAt: _t0,
  );
}

// Patches a list while offline: measures how a bare transaction ends and how
// long patchList takes, then checks the patch reaches the server once back
// online.
Future<void> _offlinePatch(
  FirestoreListStore store,
  String uid, {
  required String label,
  required Future<void> Function() goOffline,
  required Future<void> Function() goOnline,
}) async {
  expect(await store.createList(_garden('garden')), isEmpty);
  await _until(store, (c) => c.definition('garden') != null);
  final DocumentReference<Map<String, dynamic>> ref = _db.doc(
    'users/$uid/lists/garden',
  );
  bool hasMoss(Map<String, dynamic>? data) => ListDefinition.fromJson(
    data!,
  ).field('kind')!.options.any((o) => o.value == 'moss');

  await goOffline();
  try {
    final Stopwatch watch = Stopwatch()..start();
    String outcome;
    try {
      // Reads the list and writes it back unchanged, as a patch does.
      final bool found = await _db
          .runTransaction((transaction) async {
            final DocumentSnapshot<Map<String, dynamic>> snapshot =
                await transaction.get(ref);
            if (snapshot.exists) {
              transaction.set(ref, snapshot.data()!);
            }
            return snapshot.exists;
          })
          .timeout(const Duration(seconds: 60));
      outcome = 'succeeded (list ${found ? 'found' : 'NOT found'})';
    } on FirebaseException catch (error) {
      outcome = 'FirebaseException ${error.code}';
    } on TimeoutException {
      outcome = 'no answer within 60 s';
    }
    _measure(
      'offline ($label, $defaultTargetPlatform) transaction: $outcome after '
      '${watch.elapsedMilliseconds} ms',
    );

    watch.reset();
    await store.addOption('garden', 'kind', 'moss');
    _measure(
      'offline ($label) addOption returned after '
      '${watch.elapsedMilliseconds} ms',
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 12)));
    await Future<void>.delayed(const Duration(seconds: 3));
    final bool shown = hasMoss(store.current.definition('garden')!.toJson());
    final bool cached = hasMoss(
      (await ref.get(const GetOptions(source: Source.cache))).data(),
    );
    _measure(
      'offline ($label) 3 s later: read side shows it $shown, local cache '
      'has it $cached',
    );
  } finally {
    await goOnline();
  }
  final Stopwatch back = Stopwatch()..start();
  // The network may take a while to come back; a failed read means "not yet".
  await _eventually(() async {
    try {
      return hasMoss(await _server(_db, ref.path));
    } on FirebaseException {
      return false;
    }
  }, timeout: const Duration(seconds: 120));
  _measure(
    'offline ($label) patch on the server ${back.elapsedMilliseconds} ms '
    'after going online',
  );
}

// Waits until a server read fails, i.e. the device has lost its network.
Future<void> _untilServerUnreachable(String uid) async {
  await _eventually(() async {
    try {
      await _server(
        _db,
        'users/$uid/lists/garden',
      ).timeout(const Duration(seconds: 3));
      return false;
    } on Object {
      return true;
    }
  }, timeout: const Duration(seconds: 120));
}

void _measure(String what) => debugPrint('MEASURE $what');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final FirebaseApp second = await Firebase.initializeApp(
      name: 'second-device',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _db = FirebaseFirestore.instance;
    _auth = FirebaseAuth.instance;
    _db2 = FirebaseFirestore.instanceFor(app: second);
    _auth2 = FirebaseAuth.instanceFor(app: second);
    for (final FirebaseFirestore db in [_db, _db2]) {
      db.useFirestoreEmulator(_host, 8080);
    }
    for (final FirebaseAuth auth in [_auth, _auth2]) {
      await auth.useAuthEmulator(_host, 9099);
    }
  });

  final Map<ListStore, Future<void> Function()> closers = {};
  listStoreContract(
    'FirestoreListStore on the emulator',
    () async {
      final (String uid, _) = await _newUser();
      await _seed(uid);
      final FirestoreListStore store = FirestoreListStore(_db, uid);
      closers[store] = store.close;
      return store;
    },
    dispose: (store) => closers.remove(store)!(),
  );

  group('FirestoreListStore on the emulator', () {
    test('the rules keep each user to their own tree', () async {
      final (String a, _) = await _newUser();
      await _seed(a);
      final (String b, _) = await _newUser();
      await expectLater(
        _server(_db, 'users/$a/lists/${BuiltinTemplates.tasksId}'),
        throwsA(
          isA<FirebaseException>().having(
            (e) => e.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      await _seed(b);
      final List<String> skipped = [];
      final FirestoreListStore store = await _loaded(
        _db,
        b,
        onSkipped: (path, _) => skipped.add(path),
      );
      expect(store.current.definitions, hasLength(4));
      expect(skipped, isEmpty);
    });

    test('nested arrays: refused as such, stored as {"__array": ...}, read '
        'back equal', () async {
      final (String uid, _) = await _newUser();
      await _seed(uid);

      // Real Firestore refuses an array directly inside an array.
      await expectLater(
        _db.doc('users/$uid/lists/raw').set({
          'nested': [
            ['a'],
          ],
        }),
        throwsA(anything),
      );

      final FirestoreListStore store = await _loaded(_db, uid);
      expect(await store.createList(_garden('garden')), isEmpty);
      await store.apply(
        ListChanges(
          saved: [
            _row(
              'garden',
              'fern',
              values: {
                'title': 'fern',
                'tags': ['green', 'shade'],
              },
            ),
          ],
        ),
      );
      await _until(store, (c) => c.itemsOf('garden').length == 1);

      // tags -> number does not convert, so the value is hidden in _legacy
      // as a list inside a list (D-10).
      final ListPatchResult? result = await store.patchList('garden', [
        ListPatchOp(PatchOpKind.changeFieldType, {
          'key': 'tags',
          'type': 'number',
        }),
      ]);
      expect(result?.isValid, isTrue);
      final ListCatalog patched = await _until(
        store,
        (c) =>
            c.itemsOf('garden').single.values.containsKey(ListPatch.legacyKey),
      );
      final Map<String, dynamic> values = patched
          .itemsOf('garden')
          .single
          .values;
      expect(values[ListPatch.legacyKey], {
        'tags': [
          ['green', 'shade'],
        ],
      });

      final Map<String, dynamic>? stored = await _server(
        _db,
        'users/$uid/lists/garden/items/fern',
      );
      expect((stored!['values'] as Map)[ListPatch.legacyKey], {
        'tags': [
          {
            '__array': ['green', 'shade'],
          },
        ],
      });

      // A second device reads it back equal.
      final String email = _auth.currentUser!.email!;
      await _auth2.signInWithEmailAndPassword(
        email: email,
        password: _password,
      );
      final FirestoreListStore other = await _loaded(_db2, uid);
      expect(other.current.itemsOf('garden').single.values, values);
      await _auth2.signOut();
    });

    test('offline (disableNetwork): a patch returns at once and lands when '
        'back online', () async {
      final (String uid, _) = await _newUser();
      await _seed(uid);
      final FirestoreListStore store = await _loaded(_db, uid);
      await _offlinePatch(
        store,
        uid,
        label: 'disableNetwork',
        goOffline: _db.disableNetwork,
        goOnline: _db.enableNetwork,
      );
    });

    // Needs the host to switch the device's airplane mode when it sees the
    // HOST lines; the runbook has the command. Off unless
    // --dart-define=AIRPLANE=true.
    test(
      'offline (airplane mode): a patch returns in time and lands when back '
      'online',
      () async {
        final (String uid, _) = await _newUser();
        await _seed(uid);
        final FirestoreListStore store = await _loaded(_db, uid);
        await _offlinePatch(
          store,
          uid,
          label: 'airplane mode',
          goOffline: () async {
            debugPrint('HOST airplane-mode enable');
            await _untilServerUnreachable(uid);
          },
          goOnline: () async => debugPrint('HOST airplane-mode disable'),
        );
      },
      skip: !const bool.fromEnvironment('AIRPLANE'),
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test('unreachable server: how fast a transaction fails', () async {
      // An app whose emulator address has nothing listening, like a device
      // with a network but no route to Firestore.
      final FirebaseApp app = await Firebase.initializeApp(
        name: 'unreachable',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final FirebaseFirestore db = FirebaseFirestore.instanceFor(app: app)
        ..useFirestoreEmulator(_host, 8089);
      final Stopwatch watch = Stopwatch()..start();
      String outcome;
      try {
        await db
            .runTransaction((t) => t.get(db.doc('users/x/lists/y')))
            .timeout(const Duration(seconds: 60));
        outcome = 'succeeded';
      } on FirebaseException catch (error) {
        outcome = 'FirebaseException ${error.code}';
      } on TimeoutException {
        outcome = 'no answer within 60 s';
      }
      _measure(
        'unreachable-server transaction ($defaultTargetPlatform): $outcome '
        'after ${watch.elapsedMilliseconds} ms',
      );
    });

    test('two devices patching one list at once: both patches land', () async {
      final (String uid, String email) = await _newUser();
      await _seed(uid);
      await _auth2.signInWithEmailAndPassword(
        email: email,
        password: _password,
      );
      final FirestoreListStore one = await _loaded(_db, uid);
      expect(await one.createList(_garden('garden')), isEmpty);
      final FirestoreListStore two = await _loaded(_db2, uid);
      await _until(two, (c) => c.definition('garden') != null);
      final int before = one.current.definition('garden')!.schemaRevision;

      final List<ListPatchResult?> results = await Future.wait([
        one.patchList('garden', [
          ListPatchOp(PatchOpKind.renameField, {
            'key': 'title',
            'label': 'Plant',
          }),
        ]),
        two.patchList('garden', [
          ListPatchOp(PatchOpKind.addField, {
            'field': {'key': 'notes', 'type': 'longText', 'label': 'Notes'},
          }),
        ]),
      ]);
      expect(results.every((r) => r!.isValid), isTrue);

      final ListDefinition stored = ListDefinition.fromJson(
        (await _server(_db, 'users/$uid/lists/garden'))!,
      );
      expect(stored.field('title')!.label, 'Plant');
      expect(stored.field('notes'), isNotNull);
      expect(stored.schemaRevision, before + 2);

      // Options too: each device adds one at the same time.
      await Future.wait([
        one.addOption('garden', 'kind', 'moss'),
        two.addOption('garden', 'kind', 'ivy'),
      ]);
      final ListDefinition withOptions = ListDefinition.fromJson(
        (await _server(_db, 'users/$uid/lists/garden'))!,
      );
      expect(
        withOptions.field('kind')!.options.map((o) => o.value),
        containsAll(['fern', 'cactus', 'moss', 'ivy']),
      );
      await _auth2.signOut();
    });

    test('a patch whose transaction times out and commits later does no '
        'harm', () async {
      final (String uid, _) = await _newUser();
      await _seed(uid);
      final FirestoreListStore store = await _loaded(
        _db,
        uid,
        transactionTimeout: const Duration(milliseconds: 1),
      );
      expect(await store.createList(_garden('garden')), isEmpty);
      await _until(store, (c) => c.definition('garden') != null);

      // Moving fields is not idempotent (T-14 R2): applied twice, the order
      // differs from applying it once.
      final ListPatchResult? result = await store.patchList('garden', [
        ListPatchOp(PatchOpKind.moveField, {'key': 'title', 'index': 1}),
        ListPatchOp(PatchOpKind.moveField, {'key': 'kind', 'index': 2}),
      ]);
      expect(result?.isValid, isTrue);
      final List<String> once = [
        for (final FieldDefinition field in result!.definition.fields)
          field.key,
      ];
      // Let the late transaction finish: it writes nothing.
      await Future<void>.delayed(const Duration(seconds: 5));
      final ListDefinition stored = ListDefinition.fromJson(
        (await _server(_db, 'users/$uid/lists/garden'))!,
      );
      expect(stored.fields.map((f) => f.key), once);
      expect(stored.schemaRevision, result.definition.schemaRevision);
      expect(stored.validate(), isEmpty);
    });

    test('more than 500 writes: chunked batches and a large patch', () async {
      final (String uid, _) = await _newUser();
      await _seed(uid);
      // The 600-item transaction takes close to the app's 10 s on the
      // emulator; a longer timeout keeps this test on the transaction path
      // instead of falling back by chance (T-17 unit 5b).
      final FirestoreListStore store = await _loaded(
        _db,
        uid,
        transactionTimeout: const Duration(seconds: 60),
      );
      const int count = 600;
      final List<ListItem> rows = [
        for (int i = 0; i < count; i++)
          _row('big', 'r$i', values: {'title': 'r$i', 'n': i}),
      ];
      final Stopwatch watch = Stopwatch()..start();
      expect(await store.createList(_garden('big'), items: rows), isEmpty);
      await _until(store, (c) => c.itemsOf('big').length == count);
      _measure('createList with $count items: ${watch.elapsedMilliseconds} ms');

      // number -> text changes every item: the definition goes in the
      // transaction, the items in batches after it.
      watch.reset();
      final ListPatchResult? result = await store.patchList('big', [
        ListPatchOp(PatchOpKind.changeFieldType, {'key': 'n', 'type': 'text'}),
      ]);
      _measure('patch of $count items: ${watch.elapsedMilliseconds} ms');
      expect(result?.isValid, isTrue);
      final int revision = result!.definition.schemaRevision;
      final QuerySnapshot<Map<String, dynamic>> items = await _db
          .collection('users/$uid/lists/big/items')
          .get(const GetOptions(source: Source.server));
      expect(items.docs, hasLength(count));
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in items.docs) {
        expect((doc.data()['values'] as Map)['n'], isA<String>());
        expect(doc.data()['_rev'], revision);
      }

      // Probes, not assertions: does the server take more than 500 writes
      // in one batch or one transaction? The store never asks it to.
      final WriteBatch batch = _db.batch();
      for (int i = 0; i < 501; i++) {
        batch.set(
          _db.doc('users/$uid/lists/big/items/p$i'),
          _row('big', 'p$i').toJson(),
        );
      }
      String outcome;
      try {
        await batch.commit();
        outcome = 'accepted';
      } on FirebaseException catch (error) {
        outcome = 'refused (${error.code})';
      }
      _measure('a batch of 501 writes on the emulator: $outcome');
      try {
        await _db.runTransaction((transaction) async {
          for (int i = 0; i < 501; i++) {
            transaction.set(
              _db.doc('users/$uid/lists/big/items/q$i'),
              _row('big', 'q$i').toJson(),
            );
          }
        });
        outcome = 'accepted';
      } on FirebaseException catch (error) {
        outcome = 'refused (${error.code})';
      }
      _measure('a transaction of 501 writes on the emulator: $outcome');
    });

    // T-14 R3: Firestore keeps a subcollection when its parent is deleted.
    test('deleting a list leaves no item documents, malformed ones '
        'included', () async {
      final (String uid, _) = await _newUser();
      await _seed(uid);
      final List<String> skipped = [];
      final FirestoreListStore store = await _loaded(
        _db,
        uid,
        onSkipped: (path, _) => skipped.add(path),
      );
      expect(
        await store.createList(
          _garden('garden'),
          items: [_row('garden', 'fern'), _row('garden', 'ivy')],
        ),
        isEmpty,
      );
      // Passes the rules, but the read side skips it.
      await _db.doc('users/$uid/lists/garden/items/bad').set({
        ..._row('garden', 'bad').toJson(),
        'createdAt': 'not a date',
      });
      await _until(store, (c) => c.itemsOf('garden').length == 2);
      await _eventually(() async => skipped.isNotEmpty);

      final DeletedList? deleted = await store.deleteList('garden');
      expect(deleted!.items.map((i) => i.id), unorderedEquals(['fern', 'ivy']));
      final QuerySnapshot<Map<String, dynamic>> left = await _db
          .collection('users/$uid/lists/garden/items')
          .get(const GetOptions(source: Source.server));
      expect(left.docs, isEmpty);
    });

    test('the repair rewrites a late stale item under the rules', () async {
      final (String uid, _) = await _newUser();
      await _seed(uid);
      final FirestoreListStore store = await _loaded(_db, uid);
      expect(await store.createList(_garden('garden')), isEmpty);
      await _until(store, (c) => c.definition('garden') != null);
      final int old = store.current.definition('garden')!.schemaRevision;
      final ListPatchResult? result = await store.patchList('garden', [
        ListPatchOp(PatchOpKind.changeFieldType, {'key': 'n', 'type': 'text'}),
      ]);
      final int revision = result!.definition.schemaRevision;
      await _until(
        store,
        (c) => c.definition('garden')!.schemaRevision == revision,
      );

      // An offline device delivers an item written for the old schema.
      await _db.doc('users/$uid/lists/garden/items/late').set({
        ..._row('garden', 'late', values: {'title': 'late', 'n': 7}).toJson(),
        '_rev': old,
      });
      await _eventually(() async {
        final Map<String, dynamic>? data = await _server(
          _db,
          'users/$uid/lists/garden/items/late',
        );
        return data!['_rev'] == revision && (data['values'] as Map)['n'] == '7';
      });
    });
  });

  group('T-17 starter lists and cache on the emulator', () {
    test('seeding once under the rules; a second device with an empty cache '
        'sees the marker and writes nothing (Q-22 D)', () async {
      final (String uid, String email) = await _newUser();
      final Stopwatch watch = Stopwatch()..start();
      expect(await StarterLists.ensure(_db, uid), isTrue);
      _measure('seeding a new account took ${watch.elapsedMilliseconds} ms');
      final FirestoreListStore store = await _loaded(_db, uid);
      final ListCatalog catalog = await _until(
        store,
        (c) => c.definitions.length == 4,
      );
      final List<String> ids = [for (final d in catalog.definitions) d.id];
      expect(catalog.definitions.map((d) => d.templateId), [
        for (final d in BuiltinTemplates.all()) d.id,
      ]);
      // A starter list deleted on the first device.
      expect(await store.deleteList(ids.first), isNotNull);
      await _eventually(
        () async => await _server(_db, 'users/$uid/lists/${ids.first}') == null,
      );

      // The second device: same user, nothing of theirs in its cache.
      await _auth2.signOut();
      await _auth2.signInWithEmailAndPassword(email: email, password: _password);
      Object? cached;
      try {
        cached = (await _db2
                .doc('users/$uid')
                .get(const GetOptions(source: Source.cache)))
            .data();
      } on FirebaseException {
        cached = null;
      }
      expect(cached, isNull);
      watch.reset();
      expect(await StarterLists.ensure(_db2, uid), isFalse);
      _measure(
        'second device, empty cache: marker found in '
        '${watch.elapsedMilliseconds} ms',
      );
      final lists = await _db2
          .collection('users/$uid/lists')
          .get(const GetOptions(source: Source.server));
      expect(lists.docs.map((d) => d.id).toSet(), ids.skip(1).toSet());
      // And the marker is now in its cache, so the next start needs no
      // server.
      final DocumentSnapshot<Map<String, dynamic>> marker = await _db2
          .doc('users/$uid')
          .get(const GetOptions(source: Source.cache));
      expect(marker.exists, isTrue);
      watch.reset();
      expect(await StarterLists.ensure(_db2, uid), isFalse);
      _measure('next start: marker from cache in ${watch.elapsedMilliseconds} ms');
      await _auth2.signOut();
    });

    test('openStore with the app settings; clearCache empties the cache and '
        'the instance works again', () async {
      final FirebaseApp app = await Firebase.initializeApp(
        name: 'clear-cache-${DateTime.now().microsecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final FirebaseFirestore db = FirebaseFirestore.instanceFor(app: app);
      final FirebaseAuth auth = FirebaseAuth.instanceFor(app: app);
      final FirestoreSetup setup = FirestoreSetup(db)..configure();
      db.useFirestoreEmulator(_host, 8080);
      await auth.useAuthEmulator(_host, 9099);
      expect(db.settings.persistenceEnabled, isTrue);
      final UserCredential credential = await auth
          .createUserWithEmailAndPassword(
            email: 'clear-${DateTime.now().microsecondsSinceEpoch}@example.test',
            password: _password,
          );
      final String uid = credential.user!.uid;

      final opened = setup.openStore(uid);
      expect(await opened.starter, isTrue);
      await _until(opened.store, (c) => c.definitions.length == 4);
      final String listId = opened.store.current.definitions.first.id;
      expect(
        (await db
                .doc('users/$uid/lists/$listId')
                .get(const GetOptions(source: Source.cache)))
            .exists,
        isTrue,
      );

      // Sign-out order: close the store, sign out, clear the cache.
      await opened.store.close();
      await auth.signOut();
      final Stopwatch watch = Stopwatch()..start();
      await setup.clearCache();
      _measure('clearCache took ${watch.elapsedMilliseconds} ms');

      bool inCache;
      try {
        inCache = (await db
                .doc('users/$uid/lists/$listId')
                .get(const GetOptions(source: Source.cache)))
            .exists;
      } on FirebaseException {
        inCache = false;
      }
      expect(inCache, isFalse);
      // Signed in again, the same instance reads from the server.
      await auth.signInWithEmailAndPassword(
        email: credential.user!.email!,
        password: _password,
      );
      final FirestoreListStore again = await _loaded(db, uid);
      await _until(again, (c) => c.definitions.length == 4);
      await auth.signOut();
    });
  });
}
