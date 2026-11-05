import 'dart:async';

import 'package:hybrid_note/app/account_preferences.dart';

// The account's preferences document as an app test scripts it. Only the writes
// it is told to refuse fail; with [offline] they stay open, as Firestore's do.
class ScriptedPreferencesSync implements AccountPreferencesSync {
  final StreamController<AccountPreferencesSnapshot> snapshots =
      StreamController<AccountPreferencesSnapshot>.broadcast();
  bool refuse = false;
  bool offline = false;

  void send(Map<String, Object?> data) {
    snapshots.add((data: data, fromCache: false));
  }

  @override
  Stream<AccountPreferencesSnapshot> watch() => snapshots.stream;

  @override
  Future<void> seed(Map<String, Object?> values) async {}

  @override
  Future<void> write(Map<String, Object?> changes) {
    if (offline) {
      return Completer<void>().future;
    }
    return refuse
        ? Future<void>.error(StateError('permission-denied'))
        : Future<void>.value();
  }
}
