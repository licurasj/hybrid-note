import 'package:cloud_firestore/cloud_firestore.dart';

import '../app/account_preferences.dart';

// The account's preferences in the one document
// users/{uid}/settings/preferences (Q-48 A). A write sets only its own keys,
// so two phones changing different preferences do not overwrite each other,
// and keys of a newer build stay.
class FirestorePreferencesSync implements AccountPreferencesSync {
  FirestorePreferencesSync(
    this.firestore,
    this.uid, {
    this.timeout = const Duration(seconds: 10),
  });

  final FirebaseFirestore firestore;
  final String uid;
  // How long a seeding may try to reach the server.
  final Duration timeout;

  DocumentReference<Map<String, dynamic>> get _document =>
      firestore.doc('users/$uid/settings/preferences');

  // With the metadata changes: the document staying absent gives no other
  // event when the server confirms it, and that is what starts a seeding.
  @override
  Stream<AccountPreferencesSnapshot> watch() {
    return _document
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) =>
              (data: snapshot.data(), fromCache: snapshot.metadata.isFromCache),
        );
  }

  // A transaction reads from the server, so two phones cannot both seed, and
  // one that started empty still sees what the other wrote.
  @override
  Future<void> seed(Map<String, Object?> values) {
    return firestore.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> stored = await transaction
          .get(_document);
      if (!stored.exists) {
        transaction.set(_document, values);
      }
    }, timeout: timeout);
  }

  @override
  Future<void> write(Map<String, Object?> changes) {
    return _document.set(changes, SetOptions(merge: true));
  }
}
