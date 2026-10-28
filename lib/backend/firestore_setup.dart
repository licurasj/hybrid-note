import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../lists/list_item.dart';
import 'firestore_list_store.dart';
import 'starter_lists.dart';

// Firestore for the app (Q-25 A, offline-first): the cache is on for
// Android and web, lists open from it, and sign-out clears it.
class FirestoreSetup {
  FirestoreSetup(this.firestore, {this.isWeb = kIsWeb});

  final FirebaseFirestore firestore;
  final bool isWeb;

  // Applies the cache settings. Firestore fixes its settings at first use,
  // so this must run before the first listener or read; main() calls it
  // right after Firebase.initializeApp. Android has persistence on by
  // default, web does not.
  void configure() {
    firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  // Opens the store for [uid] and writes the starter lists if the account
  // has none yet (StarterLists). The store opens at once from the cache;
  // seeding runs alongside, and its lists arrive through the store's
  // listener. [starter] completes with true when this call seeded, false
  // when the account was seeded before, and null when seeding failed (for
  // example offline); the failure goes to [onSeedError]. Then [seeding]
  // stays failed until the user tries again or starts empty (Q-27); the
  // next open tries again too.
  ({FirestoreListStore store, Future<bool?> starter, StarterSeeding seeding})
  openStore(
    String uid, {
    void Function(Object error)? onSeedError,
    void Function(String path, Object error)? onSkipped,
    Map<String, List<ListItem>> sampleItems = const {},
  }) {
    final FirestoreListStore store = FirestoreListStore(
      firestore,
      uid,
      onSkipped: onSkipped,
    );
    final StarterSeeding seeding = StarterSeeding(
      ({required bool empty}) => StarterLists.ensure(
        firestore,
        uid,
        templates: empty ? const [] : null,
        sampleItems: empty ? const {} : sampleItems,
      ),
      onError: onSeedError ?? _logSeedError,
    );
    return (store: store, starter: seeding.start(), seeding: seeding);
  }

  static void _logSeedError(Object error) {
    developer.log('starter lists not written: $error', name: 'FirestoreSetup');
  }

  // Deletes the local cache, including writes not yet sent. Close every
  // store first: the instance is terminated, which ends its listeners.
  //
  // On Android the next use starts a fresh instance with the same settings.
  // On web the plugin keeps the terminated instance, so Firestore cannot be
  // used again until the page reloads ([reloadAfterClear]).
  Future<void> clearCache() async {
    await firestore.terminate();
    await firestore.clearPersistence();
  }

  bool get reloadAfterClear => isWeb;
}

enum StarterStatus { running, done, failed }

// Writing one account's starter lists, as the home sees it. When it fails
// (no connection, Firebase unavailable, the daily quota, a rules bug) it is
// not retried by itself (Q-27): the home shows a note with "Try again"
// ([retry]) and "Start empty" ([startEmpty]: the marker without lists, so
// the starter lists never appear later).
class StarterSeeding {
  StarterSeeding(this._seed, {void Function(Object error)? onError})
    : _onError = onError ?? FirestoreSetup._logSeedError;

  // Nothing to write, for a store opened without seeding (tests).
  StarterSeeding.done()
    : _seed = null,
      _onError = FirestoreSetup._logSeedError {
    _status.value = StarterStatus.done;
  }

  final Future<bool> Function({required bool empty})? _seed;
  final void Function(Object error) _onError;

  final ValueNotifier<StarterStatus> _status = ValueNotifier(
    StarterStatus.running,
  );
  StarterStatus get status => _status.value;
  // For the home's note; not a Listenable itself, so it can be provided as
  // a plain value.
  ValueListenable<StarterStatus> get changes => _status;

  // True when this call wrote the lists, false when the account had them,
  // null when it failed.
  Future<bool?> start() => _run(empty: false);

  Future<bool?> retry() => _run(empty: false);

  Future<bool?> startEmpty() => _run(empty: true);

  Future<bool?> _run({required bool empty}) async {
    final Future<bool> Function({required bool empty})? seed = _seed;
    if (seed == null) {
      return false;
    }
    _set(StarterStatus.running);
    try {
      final bool seeded = await seed(empty: empty);
      _set(StarterStatus.done);
      return seeded;
    } on Object catch (error) {
      _onError(error);
      _set(StarterStatus.failed);
      return null;
    }
  }

  void _set(StarterStatus status) => _status.value = status;
}
