import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../lists/list_catalog.dart';
import '../lists/list_definition.dart';
import '../lists/list_error.dart';
import '../lists/list_item.dart';
import '../lists/list_patch.dart';
import '../lists/list_rules.dart';
import '../lists/list_store.dart';

// ListStore over Firestore (Q-5 A): users/{uid}/lists/{listId} holds a
// definition and users/{uid}/lists/{listId}/items/{itemId} an item, each as
// its toJson(). There are no built-in lists (Q-22 D): the starter copies of
// the templates are ordinary lists, written once per account by
// starter_lists.dart. Lists come in the order they were created: each
// definition document carries the store's `_createdAt` (an ISO date, not
// part of the definition's JSON), then the id breaks ties.
//
// Reads come from one listener on the lists and one per list on its items.
// watch() emits nothing until the lists and every list's items have loaded
// (D-12); after that a change may arrive in steps. Documents that do not
// parse are skipped and reported, and the rest still loads (Q-8).
//
// Writes go out as batched writes of at most [batchLimit] documents, all
// committed at once so that offline they all queue in the local cache.
// createList, deleteList and restoreList complete once the local cache has
// the change, not when the server acknowledges it, which offline would wait
// until the device is back online (T-17 R3, D-5). If the server later
// rejects the write, Firestore undoes it locally and [writeFailures] reports
// it.
//
// AI writes (Q-51 to Q-53) never fall back to the cache, except adds and new
// lists, which overwrite nothing: they are transactions over the stored data,
// and without a server they are refused with needsConnection.
//
// A timer cannot stop a commit (R2 of the Codex re-review): the plugin collects
// a transaction's writes when its callback returns and the SDK commits them
// afterwards, and retries the callback if needed. So [transactionTimeout] gives
// up on an attempt only until its writes are handed over (_Attempt). After that
// the store waits for the real outcome for [commitTimeout], then reports it as
// unknown and writes nothing more, instead of falling back or saying that
// nothing changed.
//
// Patches (Q-16 B with C as the offline fallback): online, patchList runs a
// transaction over the list document as stored and every item the cache
// knows, so a concurrent patch from another device makes it retry rather
// than be overwritten. A transaction cannot query the items, so an item
// another device adds meanwhile is missed; and offline, where transactions
// fail, the ops are applied to the cache and saved as a queued batch. Both
// gaps are closed by the repair step: every item document carries `_rev`,
// the schemaRevision of its list when it was written, and an item found
// with a lower `_rev` has its values fitted to the current fields (what does
// not fit is hidden in `_legacy`, D-10) and is saved again. The repair, like
// the items a large patch saves after its transaction, runs in transactions
// over the items as stored and the list as stored, so it never writes over a
// newer edit or brings back a deleted item (T-14 R1). It waits until the
// lists are in sync with the server, since transactions need it.
class FirestoreListStore implements ListStore {
  FirestoreListStore(
    this.firestore,
    this.uid, {
    void Function(String path, Object error)? onSkipped,
    this.batchLimit = maxBatchWrites,
    this.transactionTimeout = const Duration(seconds: 10),
    this.commitTimeout = const Duration(seconds: 30),
    this.beforeHandOver,
    this.refitRetryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 10),
      Duration(seconds: 45),
    ],
  }) : _onSkipped = onSkipped ?? _log {
    _listsSubscription = _lists
        .snapshots(includeMetadataChanges: true)
        .listen(_onLists, onError: (Object error) => _log(_lists.path, error));
  }

  final FirebaseFirestore firestore;
  final String uid;
  final void Function(String path, Object error) _onSkipped;

  // Firestore's limit of writes in one batch; tests pass a smaller one.
  static const int maxBatchWrites = 500;
  final int batchLimit;

  // How long a transaction may take to reach the point of handing over its
  // writes. A patch then saves as a batch instead, and an AI write is refused.
  // An attempt that runs after that writes nothing, so nothing is applied twice
  // (T-14 R2).
  final Duration transactionTimeout;

  // How long a transaction that handed over its writes is waited for, after
  // [transactionTimeout] has passed (Q-58).
  final Duration commitTimeout;

  // Runs in a transaction just before it hands over its writes; tests use it
  // to cut the connection at that point.
  final Future<void> Function()? beforeHandOver;

  // The waits before trying items that could not be fitted again (Q-64).
  final List<Duration> refitRetryDelays;

  // Firestore error codes that mean the server cannot be reached.
  static const Set<String> _offlineCodes = {'unavailable', 'deadline-exceeded'};

  // The store-owned key on item documents: the schemaRevision of the list
  // the item was written for. Not part of the item's JSON.
  static const String _revKey = '_rev';

  // The store-owned key on definition documents: when the list was created.
  static const String createdAtKey = '_createdAt';

  // Firestore rejects an array directly inside an array, which a hidden
  // tags or checklist value in `_legacy` is (D-10). Such an inner list is
  // stored as {"__array": [...]}.
  static const String _arrayKey = '__array';

  CollectionReference<Map<String, dynamic>> get _lists =>
      firestore.collection('users').doc(uid).collection('lists');

  CollectionReference<Map<String, dynamic>> _itemsOf(String listId) =>
      _lists.doc(listId).collection('items');

  final Map<String, ListDefinition> _definitions = {};
  final Map<String, Map<String, ListItem>> _items = {};
  final Map<String, StreamSubscription<Object?>> _itemSubscriptions = {};
  late final StreamSubscription<Object?> _listsSubscription;
  // Each item's `_rev`, by list and item id.
  final Map<String, Map<String, int>> _revs = {};
  // Each list's `_createdAt`, kept after a delete so an undone delete puts
  // the list back in its place.
  final Map<String, DateTime> _createdAts = {};
  // The ids of every item document under each list, including the ones
  // skipped as malformed, so a list delete removes them all (T-14 R3).
  final Map<String, Set<String>> _docIds = {};
  // Whether the lists listener last had data from the local cache only.
  bool _fromCache = true;
  // What each item was last checked as for repair: the list revision and
  // the item's updatedAt, so a later stale write of it is checked again.
  final Map<String, String> _checked = {};
  // Lists whose items were reported as not updated, until a later try works.
  final Set<String> _notUpdatedReported = {};
  // Paths already reported, so a skipped document is logged once.
  final Set<String> _reported = {};

  bool _listsLoaded = false;
  final Completer<void> _ready = Completer<void>();
  ListCatalog? _catalog;
  final StreamController<ListCatalog> _changes =
      StreamController<ListCatalog>.broadcast();
  final StreamController<Object> _writeFailures =
      StreamController<Object>.broadcast();

  // List writes the server rejected after they completed for the caller
  // (createList, deleteList, restoreList); the app shows a snackbar.
  Stream<Object> get writeFailures => _writeFailures.stream;

  static const ListCatalog _empty = ListCatalog(definitions: [], items: []);

  static void _log(String path, Object error) {
    developer.log('skipped $path: $error', name: 'FirestoreListStore');
  }

  void _skip(String path, Object error) {
    if (_reported.add(path)) {
      _onSkipped(path, error);
    }
  }

  void _onLists(QuerySnapshot<Map<String, dynamic>> snapshot) {
    _fromCache = snapshot.metadata.isFromCache;
    if (_listsLoaded && snapshot.docChanges.isEmpty) {
      // Only the metadata changed, for example back online: repair what
      // could not be repaired before.
      _repair();
      return;
    }
    _definitions.clear();
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      try {
        final ListDefinition definition = _definitionFrom(doc.data());
        if (definition.id != doc.id) {
          throw FormatException('id "${definition.id}" is not the document id');
        }
        _definitions[doc.id] = definition;
        final DateTime? createdAt = _createdAtOf(doc.data());
        if (createdAt != null) {
          _createdAts[doc.id] = createdAt;
        }
        _reported.remove(doc.reference.path);
      } on Object catch (error) {
        _skip(doc.reference.path, error);
      }
    }

    for (final String listId in _itemSubscriptions.keys.toList()) {
      if (!_definitions.containsKey(listId)) {
        _itemSubscriptions.remove(listId)!.cancel();
        _items.remove(listId);
        _revs.remove(listId);
        _docIds.remove(listId);
      }
    }
    for (final String listId in _definitions.keys) {
      _itemSubscriptions.putIfAbsent(
        listId,
        () => _itemsOf(listId).snapshots().listen(
          (snapshot) => _onItems(listId, snapshot),
          onError: (Object error) => _log(_itemsOf(listId).path, error),
        ),
      );
    }
    _listsLoaded = true;
    _update();
  }

  void _onItems(String listId, QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (!_itemSubscriptions.containsKey(listId)) {
      return;
    }
    final Map<String, ListItem> items = {};
    final Map<String, int> revs = {};
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      try {
        final ListItem item = _itemFrom(doc.data());
        if (item.id != doc.id) {
          throw FormatException('id "${item.id}" is not the document id');
        }
        if (item.listId != listId) {
          throw FormatException('listId "${item.listId}" is not its list');
        }
        items[item.id] = item;
        final Object? rev = doc.data()[_revKey];
        revs[item.id] = rev is int ? rev : 0;
        _reported.remove(doc.reference.path);
      } on Object catch (error) {
        _skip(doc.reference.path, error);
      }
    }
    _items[listId] = items;
    _revs[listId] = revs;
    _docIds[listId] = {for (final doc in snapshot.docs) doc.id};
    _update();
  }

  static ListDefinition _definitionFrom(Map<String, dynamic> data) {
    return ListDefinition.fromJson(_decode(data)..remove(createdAtKey));
  }

  // The account's lists read once, from the server when online, else from
  // the cache, with no store open (the background check, T-13 unit 4).
  // Malformed documents are skipped, as the store skips them.
  static Future<ListCatalog> readOnce(
    FirebaseFirestore firestore,
    String uid,
  ) async {
    final QuerySnapshot<Map<String, dynamic>> lists = await firestore
        .collection('users')
        .doc(uid)
        .collection('lists')
        .get();
    final List<ListDefinition> definitions = [];
    final List<ListItem> items = [];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> list in lists.docs) {
      try {
        definitions.add(_definitionFrom(list.data()));
      } on Object catch (error) {
        developer.log('skipped ${list.reference.path}: $error');
        continue;
      }
      for (final QueryDocumentSnapshot<Map<String, dynamic>> item
          in (await list.reference.collection('items').get()).docs) {
        try {
          items.add(_itemFrom(item.data()));
        } on Object catch (error) {
          developer.log('skipped ${item.reference.path}: $error');
        }
      }
    }
    return ListCatalog(definitions: definitions, items: items);
  }

  static DateTime? _createdAtOf(Map<String, dynamic> data) {
    final Object? raw = data[createdAtKey];
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  static ListItem _itemFrom(Map<String, dynamic> data) {
    final ListItem item = ListItem.fromJson(_decode(data)..remove(_revKey));
    // Hidden values are a map (D-10); anything else could not be fitted or
    // patched, so the item is skipped like any malformed one (T-14 R5).
    final Object? legacy = item.values[ListPatch.legacyKey];
    if (legacy != null && legacy is! Map) {
      throw const FormatException('`_legacy` is not a map');
    }
    return item;
  }

  // Loaded once the lists and every list's items have arrived.
  bool get _isLoaded =>
      _ready.isCompleted ||
      (_listsLoaded && _definitions.keys.every(_items.containsKey));

  void _update() {
    if (!_isLoaded || _changes.isClosed) {
      return;
    }
    if (!_ready.isCompleted) {
      _ready.complete();
    }
    _catalog = _build();
    _changes.add(_catalog!);
    _repair();
  }

  // Fits every item written for an older revision of its list to the
  // current fields and saves the ones that changed. Each version of an item
  // is checked once per list revision, and again if its save failed. The
  // saves are not awaited.
  void _repair() {
    if (_fromCache) {
      return;
    }
    for (final MapEntry<String, Map<String, ListItem>> entry
        in _items.entries) {
      final String listId = entry.key;
      final ListDefinition? definition = _definitions[listId];
      if (definition == null) {
        continue;
      }
      final int revision = definition.schemaRevision;
      // The items to save, with the check each was marked with.
      final Map<String, String> due = {};
      for (final ListItem item in entry.value.values) {
        final String path = '$listId/${item.id}';
        final String check = '$revision ${item.updatedAt.toIso8601String()}';
        if ((_revs[listId]?[item.id] ?? 0) >= revision ||
            _checked[path] == check) {
          continue;
        }
        _checked[path] = check;
        try {
          if (_fit(definition, item) != null) {
            due[item.id] = check;
          }
        } on Object catch (error) {
          // Reported, and the other items are still repaired (T-14 R5).
          _skip(_itemsOf(listId).doc(item.id).path, error);
        }
      }
      if (due.isEmpty) {
        continue;
      }
      _refitRetrying(listId, due.keys.toList()).catchError((Object error) {
        _refitFailed(listId, error);
        // Checked again on the next change or reconnection.
        for (final MapEntry<String, String> failed in due.entries) {
          if (_checked['$listId/${failed.key}'] == failed.value) {
            _checked.remove('$listId/${failed.key}');
          }
        }
      });
    }
  }

  // _refit, tried again after each of [refitRetryDelays] if it fails: nothing
  // else may come along to set it off again (F3 of the last Codex pass, Q-64).
  Future<void> _refitRetrying(
    String listId,
    List<String> itemIds, {
    DateTime? touchedAt,
  }) async {
    for (int attempt = 0; ; attempt++) {
      try {
        await _refit(listId, itemIds, touchedAt: touchedAt);
        _notUpdatedReported.remove(listId);
        return;
      } on Object catch (error) {
        if (_closed || attempt >= refitRetryDelays.length) {
          rethrow;
        }
        _log('refit $listId, trying again', error);
      }
      await Future<void>.delayed(refitRetryDelays[attempt]);
      if (_closed) {
        return;
      }
    }
  }

  // Tells the app once per list, however many tries end this way. No connection
  // is not worth saying: coming back online sets off the repair step.
  void _refitFailed(String listId, Object error) {
    _log('refit $listId', error);
    if ((error is FirebaseException && _offlineCodes.contains(error.code)) ||
        _writeFailures.isClosed ||
        !_notUpdatedReported.add(listId)) {
      return;
    }
    _writeFailures.add(ItemsNotUpdated(listId));
  }

  // Fits the items as stored to the list as stored and saves the ones that
  // changed, in transactions of at most [batchLimit] items. An item that
  // was deleted meanwhile, or written for the current revision, is left
  // alone; one changed meanwhile makes the transaction run again on the
  // new data (T-14 R1). [touchedAt] is the updatedAt of an item a patch
  // changes; a plain repair keeps the item's own.
  Future<void> _refit(
    String listId,
    List<String> itemIds, {
    DateTime? touchedAt,
  }) async {
    for (int start = 0; start < itemIds.length; start += batchLimit) {
      final List<String> chunk = itemIds.skip(start).take(batchLimit).toList();
      await firestore.runTransaction((transaction) async {
        final Map<String, dynamic>? listData = (await transaction.get(
          _lists.doc(listId),
        )).data();
        if (listData == null) {
          return;
        }
        final ListDefinition definition = _definitionFrom(listData);
        final int revision = definition.schemaRevision;
        final List<ListItem> fitted = [];
        for (final String itemId in chunk) {
          final DocumentReference<Map<String, dynamic>> ref = _itemsOf(
            listId,
          ).doc(itemId);
          final Map<String, dynamic>? data = (await transaction.get(
            ref,
          )).data();
          final Object? rev = data?[_revKey];
          if (data == null || (rev is int && rev >= revision)) {
            continue;
          }
          try {
            final ListItem? item = _fit(definition, _itemFrom(data));
            if (item != null) {
              fitted.add(item);
            }
          } on Object catch (error) {
            _skip(ref.path, error);
          }
        }
        for (final ListItem item in fitted) {
          transaction.set(
            _itemsOf(listId).doc(item.id),
            itemData(
              touchedAt == null ? item : _touched(item, touchedAt),
              revision,
            ),
          );
        }
      });
    }
  }

  static ListItem _touched(ListItem item, DateTime at) {
    return ListItem(
      id: item.id,
      listId: item.listId,
      values: item.values,
      createdAt: item.createdAt,
      updatedAt: at,
    );
  }

  // The item with its values fitted to the definition's fields, or null
  // when they already fit. Values that cannot be converted are hidden in
  // `_legacy` (D-10), as ListPatch does when a field changes type.
  static ListItem? _fit(ListDefinition definition, ListItem item) {
    final Map<String, dynamic> values = Map<String, dynamic>.from(item.values);
    bool changed = false;
    for (final FieldDefinition field in definition.fields) {
      final Object? value = values[field.key];
      if (value == null) {
        continue;
      }
      final (bool ok, Object? converted) = ListPatch.convertValue(value, field);
      if (!ok) {
        final Map<String, dynamic> legacy = Map<String, dynamic>.from(
          values[ListPatch.legacyKey] as Map? ?? const {},
        );
        legacy[field.key] = [
          ...ListPatch.archivedValues(legacy, field.key),
          values.remove(field.key),
        ];
        values[ListPatch.legacyKey] = legacy;
        changed = true;
      } else if (converted != value) {
        if (converted == null) {
          values.remove(field.key);
        } else {
          values[field.key] = converted;
        }
        changed = true;
      }
    }
    if (!changed) {
      return null;
    }
    return ListItem(
      id: item.id,
      listId: item.listId,
      values: values,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
    );
  }

  // The lists by creation time, then id; a list without `_createdAt` comes
  // first.
  ListCatalog _build() {
    final DateTime unknown = DateTime.utc(0);
    final List<String> ids = _definitions.keys.toList()
      ..sort((a, b) {
        final int byTime = (_createdAts[a] ?? unknown).compareTo(
          _createdAts[b] ?? unknown,
        );
        return byTime != 0 ? byTime : a.compareTo(b);
      });
    final List<ListDefinition> definitions = [
      for (final String id in ids) _definitions[id]!,
    ];
    return ListCatalog(
      definitions: definitions,
      items: [
        for (final ListDefinition definition in definitions)
          ...?_items[definition.id]?.values,
      ],
    );
  }

  // Only the first call closes; a later one (also while the first is still
  // running) returns at once. The app closes a store when its user changes,
  // and tests close it again at tear-down.
  bool _closed = false;

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _listsSubscription.cancel();
    for (final StreamSubscription<Object?> subscription
        in _itemSubscriptions.values) {
      await subscription.cancel();
    }
    _itemSubscriptions.clear();
    await _changes.close();
    await _writeFailures.close();
  }

  // Empty until the initial load is complete.
  @override
  ListCatalog get current => _catalog ?? _empty;

  @override
  Stream<ListCatalog> watch() {
    late final StreamController<ListCatalog> controller;
    StreamSubscription<ListCatalog>? subscription;
    controller = StreamController<ListCatalog>(
      onListen: () {
        if (_catalog != null) {
          controller.add(_catalog!);
        }
        subscription = _changes.stream.listen(
          controller.add,
          onDone: controller.close,
        );
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  // The list an item is stored under, from the loaded catalog.
  String? _listOfItem(String itemId) {
    for (final MapEntry<String, Map<String, ListItem>> entry
        in _items.entries) {
      if (entry.value.containsKey(itemId)) {
        return entry.key;
      }
    }
    return null;
  }

  // Commits the writes in batches of at most [batchLimit], in order. The
  // batches are committed together rather than one after the other, so
  // offline they all go into the local cache at once.
  Future<void> _write(List<void Function(WriteBatch batch)> writes) async {
    final List<Future<void>> commits = [];
    for (int start = 0; start < writes.length; start += batchLimit) {
      final WriteBatch batch = firestore.batch();
      for (final void Function(WriteBatch batch) write
          in writes.skip(start).take(batchLimit)) {
        write(batch);
      }
      commits.add(batch.commit());
    }
    await Future.wait(commits);
  }

  // Commits [writes] and completes once the catalog shows them ([accepted]),
  // or once the commit settles if that comes first. A failed commit is
  // logged and reported on [writeFailures], also after this has completed.
  Future<void> _writeAccepted(
    String what,
    List<void Function(WriteBatch batch)> writes,
    bool Function(ListCatalog catalog) accepted,
  ) async {
    // Listening before the commit, so the local snapshot is not missed. It
    // ends without a match when the store closes.
    final Future<void> seen = _changes.stream
        .firstWhere(accepted)
        .then<void>((_) {}, onError: (Object _) {});
    final Future<void> acknowledged = _write(writes).catchError((
      Object error,
    ) {
      _log(what, error);
      if (!_writeFailures.isClosed) {
        _writeFailures.add(error);
      }
    });
    await Future.any([seen, acknowledged]);
  }

  void Function(WriteBatch batch) _setDefinition(ListDefinition definition) {
    return (batch) => batch.set(
      _lists.doc(definition.id),
      definitionData(definition, createdAt: _createdAts[definition.id]),
    );
  }

  // A definition document: the definition's JSON plus `_createdAt` when it
  // is known (a document written without one keeps having none).
  static Map<String, dynamic> definitionData(
    ListDefinition definition, {
    DateTime? createdAt,
  }) {
    return {
      ...(_encode(definition.toJson()) as Map<String, dynamic>),
      if (createdAt != null) createdAtKey: createdAt.toUtc().toIso8601String(),
    };
  }

  // An item document: the item's JSON plus `_rev`, the revision of the list
  // definition it was written for.
  static Map<String, dynamic> itemData(ListItem item, int revision) {
    return {
      ...(_encode(item.toJson()) as Map<String, dynamic>),
      _revKey: revision,
    };
  }

  void Function(WriteBatch batch) _setItem(ListItem item, int revision) {
    return (batch) => batch.set(
      _itemsOf(item.listId).doc(item.id),
      itemData(item, revision),
    );
  }

  // The revision an item write is made for: its list's, as cached. An item
  // of a list not loaded yet gets 0, so the repair step checks it.
  int _revisionOf(String listId) => _definitions[listId]?.schemaRevision ?? 0;

  // [item] fitted to its list's fields as cached, as the repair would fit it:
  // a write is stamped with that revision, so the repair never looks at it
  // again. An item put back from before a field change (Undo of a clear,
  // T-24 unit 7 D2) keeps what does not fit in `_legacy` (D-10).
  ListItem _fitted(ListItem item) {
    final ListDefinition? definition = _definitions[item.listId];
    if (definition == null) {
      return item;
    }
    try {
      return _fit(definition, item) ?? item;
    } on Object catch (error) {
      _log('fit ${item.listId}/${item.id}', error);
      return item;
    }
  }

  void Function(WriteBatch batch) _deleteItem(String listId, String itemId) {
    return (batch) => batch.delete(_itemsOf(listId).doc(itemId));
  }

  @override
  Future<void> apply(ListChanges changes) async {
    await _ready.future;
    final List<void Function(WriteBatch batch)> writes = [];
    for (final ListItem item in changes.saved) {
      // An item that moved to another list leaves its old document.
      final String? from = _listOfItem(item.id);
      if (from != null && from != item.listId) {
        writes.add(_deleteItem(from, item.id));
      }
      writes.add(_setItem(_fitted(item), _revisionOf(item.listId)));
    }
    for (final String itemId in changes.deletedIds) {
      final String? listId = _listOfItem(itemId);
      if (listId != null) {
        writes.add(_deleteItem(listId, itemId));
      }
    }
    await _write(writes);
  }

  Future<void> _changeOptions(
    String listId,
    String fieldKey,
    List<FieldOption> Function(List<FieldOption> options) change,
  ) async {
    await _ready.future;
    if (_definitions[listId]?.field(fieldKey) == null) {
      return;
    }
    // The options are worked out from the definition the patch is applied
    // to, so a transaction retried after another device's option change
    // keeps that change.
    await _patch(
      listId,
      (definition) => [
        ListPatchOp(PatchOpKind.setOptions, {
          'key': fieldKey,
          'options': change(
            definition.field(fieldKey)?.options ?? const [],
          ).map((option) => option.toJson()).toList(),
        }),
      ],
    );
  }

  @override
  Future<void> addOption(String listId, String fieldKey, String value) {
    return _changeOptions(
      listId,
      fieldKey,
      (options) => options.any((option) => option.value == value)
          ? options
          : [...options, FieldOption(value: value, label: value)],
    );
  }

  @override
  Future<void> removeOption(String listId, String fieldKey, String value) {
    return _changeOptions(
      listId,
      fieldKey,
      (options) => options.where((option) => option.value != value).toList(),
    );
  }

  // The listeners keep the catalog current; there is nothing to pull.
  @override
  Future<void> refresh() async {}

  @override
  Future<List<ListError>> createList(
    ListDefinition definition, {
    List<ListItem> items = const [],
  }) async {
    await _ready.future;
    if (_definitions.containsKey(definition.id)) {
      return [ListError(ListErrorCode.listExists, {'list': definition.id})];
    }
    // Item ids are unique across every list, since item deletes go by id.
    final Set<String> newIds = {};
    final List<ListError> errors = [
      ...definition.validate(),
      for (final ListItem item in items)
        if (!newIds.add(item.id))
          ListError(ListErrorCode.duplicateItemId, const {}, item.id)
        else if (_listOfItem(item.id) != null)
          ListError(ListErrorCode.itemIdTaken, const {}, item.id),
      for (final ListItem item in items)
        if (item.listId != definition.id)
          ListError(ListErrorCode.itemInOtherList, {'list': item.listId}, item.id)
        else
          for (final ListError error in item.validateAgainst(definition))
            error.forItem(item.id),
    ];
    if (errors.isEmpty) {
      _createdAts[definition.id] = DateTime.now().toUtc();
      await _writeAccepted(
        'create ${definition.id}',
        [
          _setDefinition(definition),
          for (final ListItem item in items)
            _setItem(item, definition.schemaRevision),
        ],
        (catalog) => catalog.definition(definition.id) != null,
      );
    }
    return errors;
  }

  // Q-16: a transaction online, the cached list as a queued batch when the
  // server cannot be reached. Items the transaction could not see are left
  // to the repair step.
  @override
  Future<ListPatchResult?> patchList(String listId, List<ListPatchOp> ops) {
    return _patch(listId, (_) => ops);
  }

  @override
  Future<ListPatchResult?> patchListAi(
    String listId,
    List<ListPatchOp> ops, {
    required ListDefinition previewed,
  }) async {
    await _ready.future;
    if (!_definitions.containsKey(listId)) {
      return null;
    }
    ListPatchResult refused(ListDefinition definition, ListErrorCode code) {
      return ListPatchResult(
        definition: definition,
        items: const [],
        changedItemIds: const {},
        hiddenValues: 0,
        errors: [ListError(code, {'list': listId})],
        definitionBefore: definition,
        itemsBefore: const [],
      );
    }

    return _timed<ListPatchResult?>(
      (attempt) => _patchInTransaction(
        listId,
        (_) => ops,
        attempt,
        refuse: (definition) => !definition.aiAllowed
            ? refused(definition, ListErrorCode.aiNotAllowed)
            : AiItemWrite.sameFields(definition, previewed)
            ? null
            : refused(definition, ListErrorCode.previewChanged),
      ),
      notHandedOver: () => refused(previewed, ListErrorCode.needsConnection),
      unknown: () => refused(previewed, ListErrorCode.outcomeUnknown),
    );
  }

  @override
  Future<AiWriteResult> applyAiItems(AiItemWrite write) async {
    await _ready.future;
    final String listId = write.listId;
    if (write.writes > batchLimit) {
      return AiWriteResult.refused(ListErrorCode.answerTooLarge, listId);
    }
    // Offline: an add overwrites nothing, so it may queue, checked against the
    // cache. Anything else needs the stored data (Q-53).
    AiWriteResult offline() {
      if (!write.addsOnly) {
        return AiWriteResult.refused(ListErrorCode.needsConnection, listId);
      }
      final AiWriteResult result = write.over(_definitions[listId], const {});
      if (result.isValid) {
        final int revision = _revisionOf(listId);
        // Not awaited, as in _patchCached.
        _write([
          for (final ListItem item in result.saved) _setItem(item, revision),
        ]).catchError((Object error) => _log('ai items $listId', error));
      }
      return result;
    }

    return _timed<AiWriteResult>(
      (attempt) => _applyAiInTransaction(write, attempt),
      notHandedOver: offline,
      unknown: () =>
          AiWriteResult.refused(ListErrorCode.outcomeUnknown, listId),
    );
  }

  Future<AiWriteResult> _applyAiInTransaction(
    AiItemWrite write,
    _Attempt attempt,
  ) {
    final String listId = write.listId;
    return _readingTransaction((transaction, read) async {
      final Map<String, dynamic>? data = await read(_lists.doc(listId));
      final Map<String, ListItem> items = {};
      for (final String id in write.touchedIds) {
        final Map<String, dynamic>? itemData = await read(
          _itemsOf(listId).doc(id),
        );
        if (itemData == null) {
          continue;
        }
        try {
          items[id] = _itemFrom(itemData);
        } on Object {
          // Malformed: not what the preview showed.
          return AiWriteResult.refused(ListErrorCode.previewChanged, listId);
        }
      }
      final ListDefinition? stored = data == null ? null : _definitionFrom(data);
      final AiWriteResult result = write.over(stored, items);
      if (!result.isValid || !await attempt.handOver(beforeHandOver)) {
        return result;
      }
      for (final ListItem item in result.saved) {
        transaction.set(
          _itemsOf(listId).doc(item.id),
          itemData(item, stored!.schemaRevision),
        );
      }
      for (final String id in result.deletedIds) {
        transaction.delete(_itemsOf(listId).doc(id));
      }
      return result;
    });
  }

  @override
  Future<List<ListError>> deleteCreatedList(CreatedList created) async {
    await _ready.future;
    final String listId = created.listId;
    List<ListError> refused(ListErrorCode code) => [
      ListError(code, {'list': listId}),
    ];
    Future<List<ListError>> run(_Attempt attempt) async {
      // A transaction cannot query, so the items are listed first; one added
      // between the two by another device stays behind, as in deleteList.
      final Set<String> ids = {
        for (final doc
            in (await _itemsOf(listId).get(const GetOptions(source: Source.server))).docs)
          doc.id,
      };
      if (ids.length + 1 > batchLimit) {
        return refused(ListErrorCode.undoTooLarge);
      }
      return _readingTransaction((transaction, read) async {
        final List<ListError> changed = refused(ListErrorCode.listChanged);
        final Map<String, dynamic>? data = await read(_lists.doc(listId));
        if (data == null) {
          return changed;
        }
        final List<ListItem> items = [];
        for (final String id in ids) {
          final Map<String, dynamic>? itemData = await read(_itemsOf(listId).doc(id));
          if (itemData == null) {
            continue;
          }
          try {
            items.add(_itemFrom(itemData));
          } on Object {
            return changed;
          }
        }
        if (!created.isCurrent(_definitionFrom(data), items)) {
          return changed;
        }
        if (!await attempt.handOver(beforeHandOver)) {
          return const <ListError>[];
        }
        for (final String id in ids) {
          transaction.delete(_itemsOf(listId).doc(id));
        }
        transaction.delete(_lists.doc(listId));
        return const <ListError>[];
      });
    }

    return _timed<List<ListError>>(
      run,
      notHandedOver: () => refused(ListErrorCode.needsConnection),
      unknown: () => refused(ListErrorCode.outcomeUnknown),
    );
  }

  // Runs [run] under the two time limits (see the class comment). Before the
  // attempt hands over its writes, running out of time or reaching no server
  // ends it with [notHandedOver]; a later callback then writes nothing. After
  // that only the transaction's own result counts, and if it is not there in
  // [commitTimeout], or the connection failed during the commit, [unknown].
  Future<T> _timed<T>(
    Future<T> Function(_Attempt attempt) run, {
    required FutureOr<T> Function() notHandedOver,
    required FutureOr<T> Function() unknown,
  }) {
    final Completer<T> result = Completer<T>();
    final _Attempt attempt = _Attempt();
    Timer? timer;
    void finish(FutureOr<T> Function() outcome) {
      if (result.isCompleted) {
        return;
      }
      timer?.cancel();
      attempt.stop();
      result.complete(outcome());
    }

    timer = Timer(transactionTimeout, () {
      if (!attempt.handedOver) {
        finish(notHandedOver);
      } else {
        timer = Timer(commitTimeout, () => finish(unknown));
      }
    });
    run(attempt).then(
      (value) {
        if (!result.isCompleted) {
          timer?.cancel();
          result.complete(value);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (result.isCompleted) {
          _log('late transaction', error);
        } else if (error is FirebaseException &&
            _offlineCodes.contains(error.code)) {
          finish(attempt.handedOver ? unknown : notHandedOver);
        } else {
          timer?.cancel();
          result.completeError(error, stack);
        }
      },
    );
    return result.future;
  }

  // A transaction whose [read]s report a failure on web as the
  // FirebaseException it was, not the JavaScript error the transaction turns
  // it into (T-17 F1).
  Future<T> _readingTransaction<T>(
    Future<T> Function(
      Transaction transaction,
      Future<Map<String, dynamic>?> Function(
        DocumentReference<Map<String, dynamic>> ref,
      ) read,
    ) body,
  ) async {
    FirebaseException? readError;
    try {
      return await firestore.runTransaction((transaction) async {
        readError = null;
        return body(transaction, (ref) async {
          try {
            return (await transaction.get(ref)).data();
          } on FirebaseException catch (error) {
            readError = error;
            rethrow;
          }
        });
      });
    } on FirebaseException {
      rethrow;
    } on Object {
      final FirebaseException? cause = readError;
      if (cause == null) {
        rethrow;
      }
      throw cause;
    }
  }

  // [opsFor] gives the ops for the definition they are applied to: the
  // stored one in the transaction, the cached one in the fallback.
  Future<ListPatchResult?> _patch(
    String listId,
    List<ListPatchOp> Function(ListDefinition definition) opsFor,
  ) async {
    await _ready.future;
    if (!_definitions.containsKey(listId)) {
      return null;
    }
    // If the outcome stays unknown the patch counts as what was handed over:
    // the read side shows the truth when it arrives.
    ListPatchResult? handedOver;
    return _timed<ListPatchResult?>(
      (attempt) => _patchInTransaction(
        listId,
        opsFor,
        attempt,
        onHandOver: (result) => handedOver = result,
      ),
      notHandedOver: () => _patchCached(listId, opsFor),
      unknown: () => handedOver,
    );
  }

  // Applies the ops to the list as stored and to every item the cache
  // knows, read again inside the transaction. A patch that changes more
  // items than fit in one transaction saves the definition in it and fits
  // the items to it afterwards, in transactions over the items as stored
  // (T-14 R1), which are not waited for (Q-59); the repair step covers an
  // interruption. An attempt that runs once [attempt] has stopped, after the
  // patch fell back to a batch, writes nothing: it would read the batch's result
  // and apply the ops a second time.
  Future<ListPatchResult?> _patchInTransaction(
    String listId,
    List<ListPatchOp> Function(ListDefinition definition) opsFor,
    _Attempt attempt, {
    ListPatchResult? Function(ListDefinition definition)? refuse,
    void Function(ListPatchResult result)? onHandOver,
  }) async {
    final List<String> itemIds = _items[listId]?.keys.toList() ?? const [];
    final DateTime now = DateTime.now().toUtc();
    List<String> later = const [];
    // On web, a read that fails inside the transaction (offline) reaches
    // the caller as a JavaScript error instead of the FirebaseException it
    // was, so the offline fallback would not see its code (T-17 F1). The
    // failed read of the last attempt is kept and thrown instead.
    FirebaseException? readError;
    Future<DocumentSnapshot<Map<String, dynamic>>> read(
      Transaction transaction,
      DocumentReference<Map<String, dynamic>> ref,
    ) async {
      try {
        return await transaction.get(ref);
      } on FirebaseException catch (error) {
        readError = error;
        rethrow;
      }
    }

    final ListPatchResult? result;
    try {
      result = await firestore.runTransaction((transaction) async {
        later = const [];
        readError = null;
        final DocumentSnapshot<Map<String, dynamic>> stored = await read(
          transaction,
          _lists.doc(listId),
        );
        final Map<String, dynamic>? data = stored.data();
        if (data == null) {
          return null;
        }
        final ListDefinition definition = _definitionFrom(data);
        final ListPatchResult? refused = refuse?.call(definition);
        if (refused != null) {
          return refused;
        }
        final List<ListItem> items = [];
        for (final String itemId in itemIds) {
          final Map<String, dynamic>? itemData = (await read(
            transaction,
            _itemsOf(listId).doc(itemId),
          )).data();
          if (itemData == null) {
            continue;
          }
          try {
            items.add(_itemFrom(itemData));
          } on Object {
            // Skipped and reported by the read side.
          }
        }
        final ListPatchResult result = ListPatch.apply(
          definition,
          items,
          opsFor(definition),
          now,
        );
        if (!result.isValid || !await attempt.handOver(beforeHandOver)) {
          return result;
        }
        onHandOver?.call(result);
        final int revision = result.definition.schemaRevision;
        final List<ListItem> changed = [
          for (final ListItem item in result.items)
            if (result.changedItemIds.contains(item.id)) item,
        ];
        transaction.set(
          _lists.doc(listId),
          definitionData(result.definition, createdAt: _createdAtOf(data)),
        );
        if (changed.length < batchLimit) {
          for (final ListItem item in changed) {
            transaction.set(
              _itemsOf(listId).doc(item.id),
              itemData(item, revision),
            );
          }
        } else {
          later = [for (final ListItem item in changed) item.id];
        }
        return result;
      });
    } on FirebaseException {
      rethrow;
    } on Object {
      final FirebaseException? cause = readError;
      if (cause == null) {
        rethrow;
      }
      throw cause;
    }
    if (result != null && later.isNotEmpty && !attempt.stopped) {
      final List<String> pending = later;
      unawaited(
        _refitRetrying(listId, pending, touchedAt: now).catchError(
          (Object error) => _refitFailed(listId, error),
        ),
      );
      return result.withItemsPending();
    }
    return result;
  }

  // The offline fallback (Q-16 C): the ops on the cached list, saved as a
  // batch that queues until the device is back online. If another device
  // changed the definition meanwhile, the later write wins.
  Future<ListPatchResult?> _patchCached(
    String listId,
    List<ListPatchOp> Function(ListDefinition definition) opsFor,
  ) async {
    final ListDefinition? definition = _definitions[listId];
    if (definition == null) {
      return null;
    }
    final ListPatchResult result = ListPatch.apply(
      definition,
      _items[listId]?.values.toList() ?? const [],
      opsFor(definition),
      DateTime.now().toUtc(),
    );
    if (result.isValid) {
      final int revision = result.definition.schemaRevision;
      // Not awaited: offline the commit only finishes once it reaches the
      // server, but the local cache and the read side have it at once.
      _write([
        _setDefinition(result.definition),
        for (final ListItem item in result.items)
          if (result.changedItemIds.contains(item.id)) _setItem(item, revision),
      ]).catchError((Object error) => _log('patch $listId', error));
    }
    return result;
  }

  // Deletes the items first and the list document last, so an interrupted
  // delete leaves the list visible rather than its items orphaned.
  @override
  Future<DeletedList?> deleteList(String listId) async {
    await _ready.future;
    final ListDefinition? definition = _definitions[listId];
    if (definition == null) {
      return null;
    }
    // Undo restores the valid items; the delete removes every document,
    // the malformed ones as well (T-14 R3). An item another device adds
    // meanwhile, before this device has seen it, stays behind unseen.
    final List<ListItem> items = _items[listId]?.values.toList() ?? const [];
    await _writeAccepted(
      'delete $listId',
      [
        for (final String itemId in {
          ...?_docIds[listId],
          for (final ListItem item in items) item.id,
        })
          _deleteItem(listId, itemId),
        (batch) => batch.delete(_lists.doc(listId)),
      ],
      (catalog) => catalog.definition(listId) == null,
    );
    return DeletedList(definition: definition, items: items);
  }

  @override
  Future<bool?> undoClear(
    String listId, {
    required List<ListItem> cleared,
    required List<ListItem> created,
  }) async {
    await _ready.future;
    // From the cache only: the server cannot be asked, so the caller's own
    // check decides (Q-101 offline Undo).
    if (_fromCache) {
      return null;
    }
    try {
      return await _readingTransaction<bool>((transaction, read) async {
        final Map<String, dynamic>? listData = await read(_lists.doc(listId));
        if (listData == null) {
          return false;
        }
        for (final ListItem item in cleared) {
          if (await read(_itemsOf(listId).doc(item.id)) != null) {
            return false;
          }
        }
        for (final ListItem item in created) {
          final Map<String, dynamic>? data = await read(
            _itemsOf(item.listId).doc(item.id),
          );
          if (data == null ||
              !ListSnapshot.sameJson(_itemFrom(data).values, item.values)) {
            return false;
          }
        }
        final ListDefinition definition = _definitionFrom(listData);
        for (final ListItem item in cleared) {
          transaction.set(
            _itemsOf(listId).doc(item.id),
            itemData(
              _fit(definition, item) ?? item,
              definition.schemaRevision,
            ),
          );
        }
        for (final ListItem item in created) {
          transaction.delete(_itemsOf(item.listId).doc(item.id));
        }
        return true;
      }).timeout(transactionTimeout);
    } on FirebaseException catch (error) {
      if (_offlineCodes.contains(error.code)) {
        return null;
      }
      rethrow;
    } on TimeoutException {
      // Its writes are the same as the fallback's, so a late commit does no
      // harm.
      return null;
    }
  }

  // Done on a ring (T-13 unit 4, plan's Sync safety for Done): [change] works
  // out the tick from a fresh copy of the item and its list, read from the
  // server in a transaction, so a ring booked before a change elsewhere ticks
  // what is there now. It needs no open store, so a background isolate can
  // call it. Returns true when written with the server, false when nothing
  // was written (the list or item is gone, or [change] gave nothing), and
  // null when offline: then the cached copies decide, and the write waits in
  // the cache to sync later, the same last-writer-wins as a tick on the list.
  static Future<bool?> applyFresh(
    FirebaseFirestore firestore,
    String uid, {
    required String listId,
    required String itemId,
    required ListChanges Function(ListDefinition definition, ListItem item)
    change,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final DocumentReference<Map<String, dynamic>> listRef = firestore
        .collection('users')
        .doc(uid)
        .collection('lists')
        .doc(listId);
    final DocumentReference<Map<String, dynamic>> itemRef = listRef
        .collection('items')
        .doc(itemId);
    void write(
      ListDefinition definition,
      ListChanges changes,
      void Function(DocumentReference<Map<String, dynamic>> ref, Object data)
      set,
      void Function(DocumentReference<Map<String, dynamic>> ref) delete,
    ) {
      for (final ListItem item in changes.saved) {
        set(
          listRef.parent.doc(item.listId).collection('items').doc(item.id),
          itemData(_fit(definition, item) ?? item, definition.schemaRevision),
        );
      }
      for (final String id in changes.deletedIds) {
        delete(listRef.collection('items').doc(id));
      }
    }

    try {
      return await firestore.runTransaction<bool>((transaction) async {
        final Map<String, dynamic>? listData = (await transaction.get(
          listRef,
        )).data();
        final Map<String, dynamic>? data = (await transaction.get(
          itemRef,
        )).data();
        if (listData == null || data == null) {
          return false;
        }
        final ListDefinition definition = _definitionFrom(listData);
        final ListChanges changes = change(definition, _itemFrom(data));
        if (changes.isEmpty) {
          return false;
        }
        write(
          definition,
          changes,
          (ref, data) => transaction.set(ref, data as Map<String, dynamic>),
          transaction.delete,
        );
        return true;
      }).timeout(timeout);
    } on FirebaseException catch (error) {
      if (!_offlineCodes.contains(error.code)) {
        rethrow;
      }
    } on TimeoutException {
      // Offline below. A late commit writes the same tick, and a cleared
      // repeat's copy has a fixed id, so both landing does no harm.
    }

    const GetOptions cache = GetOptions(source: Source.cache);
    final Map<String, dynamic>? listData;
    final Map<String, dynamic>? data;
    try {
      listData = (await listRef.get(cache)).data();
      data = (await itemRef.get(cache)).data();
    } on FirebaseException {
      // Not in the cache: nothing to go on.
      return false;
    }
    if (listData == null || data == null) {
      return false;
    }
    final ListDefinition definition = _definitionFrom(listData);
    final ListChanges changes = change(definition, _itemFrom(data));
    if (changes.isEmpty) {
      return false;
    }
    final WriteBatch batch = firestore.batch();
    write(
      definition,
      changes,
      (ref, data) => batch.set(ref, data as Map<String, dynamic>),
      batch.delete,
    );
    // Offline the commit completes only when the server has it; the write is
    // in the cache at once, which a cache read after it waits for.
    unawaited(
      batch.commit().catchError(
        (Object error) => developer.log('Done not synced: $error'),
      ),
    );
    try {
      await itemRef.get(cache);
    } on FirebaseException {
      // A deleted item may be absent from the cache; the write is queued.
    }
    return null;
  }

  @override
  Future<void> restoreList(DeletedList deleted) async {
    await _ready.future;
    final String listId = deleted.definition.id;
    await _writeAccepted(
      'restore $listId',
      [
        _setDefinition(deleted.definition),
        for (final ListItem item in deleted.items)
          _setItem(item, deleted.definition.schemaRevision),
      ],
      (catalog) => catalog.definition(listId) != null,
    );
  }

  // Q-35 A: a transaction over the list and the touched items as stored. Without
  // a server it is refused, not queued: a check against the cache could not
  // protect a newer change on another device (Q-53). One transaction holds every
  // write, so an undo touches fewer than [batchLimit] items (AI changes are far
  // smaller).
  @override
  Future<List<ListError>> restoreSnapshot(ListSnapshot snapshot) async {
    await _ready.future;
    // The restore is one transaction (the list plus every touched item), and
    // a transaction holds at most [batchLimit] writes; a patch that touched
    // more items (changeFieldType, removeField on a big list) is not undone
    // at all rather than in part (L13 of the T-19 unit 5 review).
    final int writes =
        snapshot.itemIds.length +
        (ListSnapshot.sameJson(snapshot.before.toJson(), snapshot.after.toJson()) ? 0 : 1);
    if (writes > batchLimit) {
      return [
        ListError(ListErrorCode.undoTooLarge, {'list': snapshot.listId}),
      ];
    }
    return _timed<List<ListError>>(
      (attempt) => _restoreInTransaction(snapshot, attempt),
      notHandedOver: () => _refusedRestore(ListErrorCode.needsConnection, snapshot),
      unknown: () => _refusedRestore(ListErrorCode.outcomeUnknown, snapshot),
    );
  }

  static List<ListError> _refusedRestore(ListErrorCode code, ListSnapshot snapshot) {
    return [ListError(code, {'list': snapshot.listId})];
  }

  static List<ListError> _changedSince(ListSnapshot snapshot) {
    return [ListError(ListErrorCode.listChanged, {'list': snapshot.listId})];
  }

  // An attempt that runs once [attempt] has stopped writes nothing, as in
  // _patchInTransaction (T-14 R2); so does one whose web read failed
  // (T-17 F1: the read error is thrown instead).
  Future<List<ListError>> _restoreInTransaction(
    ListSnapshot snapshot,
    _Attempt attempt,
  ) {
    final String listId = snapshot.listId;
    final DateTime now = DateTime.now().toUtc();
    return _readingTransaction((transaction, read) async {
      final Map<String, dynamic>? data = await read(_lists.doc(listId));
      final Map<String, ListItem> items = {};
      for (final String id in snapshot.itemIds) {
        final Map<String, dynamic>? itemData = await read(_itemsOf(listId).doc(id));
        if (itemData != null) {
          try {
            items[id] = _itemFrom(itemData);
          } on Object {
            // Malformed: not as the change left it.
            return _changedSince(snapshot);
          }
        }
      }
      final ListDefinition? current = data == null ? null : _definitionFrom(data);
      if (current == null || !snapshot.isCurrent(current, items)) {
        return _changedSince(snapshot);
      }
      if (!await attempt.handOver(beforeHandOver)) {
        return const <ListError>[];
      }
      final ListDefinition? definition = snapshot.restoredDefinition(current, now);
      final int revision = (definition ?? current).schemaRevision;
      if (definition != null) {
        transaction.set(
          _lists.doc(listId),
          definitionData(definition, createdAt: _createdAtOf(data!)),
        );
      }
      for (final String id in snapshot.itemIds) {
        final ListItem? item = snapshot.itemsBefore[id];
        if (item == null) {
          transaction.delete(_itemsOf(listId).doc(id));
        } else {
          transaction.set(_itemsOf(listId).doc(id), itemData(item, revision));
        }
      }
      return const <ListError>[];
    });
  }

  static Object? _encode(Object? value, {bool inList = false}) {
    if (value is Map) {
      return {
        for (final MapEntry<Object?, Object?> entry in value.entries)
          '${entry.key}': _encode(entry.value),
      };
    }
    if (value is List) {
      final List<Object?> list = [
        for (final Object? element in value) _encode(element, inList: true),
      ];
      return inList ? {_arrayKey: list} : list;
    }
    return value;
  }

  static Map<String, dynamic> _decode(Map<String, dynamic> data) {
    return _decodeValue(data) as Map<String, dynamic>;
  }

  static Object? _decodeValue(Object? value) {
    if (value is Map) {
      if (value.length == 1 && value[_arrayKey] is List) {
        return _decodeValue(value[_arrayKey]);
      }
      return <String, dynamic>{
        for (final MapEntry<Object?, Object?> entry in value.entries)
          '${entry.key}': _decodeValue(entry.value),
      };
    }
    if (value is List) {
      return [for (final Object? element in value) _decodeValue(element)];
    }
    return value;
  }
}

// One transaction under _timed's limits. Once it has handed over its writes, it
// stays that way through the SDK's retries: an earlier commit may have landed
// even if its answer was lost.
class _Attempt {
  bool handedOver = false;
  bool stopped = false;

  void stop() => stopped = true;

  // Whether the callback may write now; it must then write without another
  // await, so nothing can stop it between this check and its writes.
  Future<bool> handOver(Future<void> Function()? before) async {
    if (stopped) {
      return false;
    }
    if (before != null) {
      await before();
      if (stopped) {
        return false;
      }
    }
    handedOver = true;
    return true;
  }
}

// On writeFailures: a list's items could not be fitted to its new fields, after
// retrying (Q-64). They stay as they are until the next try at the next start.
class ItemsNotUpdated {
  const ItemsNotUpdated(this.listId);

  final String listId;
}
