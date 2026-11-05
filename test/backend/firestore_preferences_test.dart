import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/backend/firestore_preferences.dart';

const String _path = 'users/user-a/settings/preferences';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestorePreferencesSync sync;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    sync = FirestorePreferencesSync(firestore, 'user-a');
  });

  test('seed writes the values when the account has none', () async {
    await sync.seed({'vibration': false});

    expect((await firestore.doc(_path).get()).data(), {'vibration': false});
  });

  test('seed leaves stored preferences as they are', () async {
    await firestore.doc(_path).set({'vibration': true, 'newerKey': 1});

    await sync.seed({'vibration': false});

    expect((await firestore.doc(_path).get()).data(), {
      'vibration': true,
      'newerKey': 1,
    });
  });

  test('write changes its own keys and keeps the others', () async {
    await firestore.doc(_path).set({'vibration': true, 'newerKey': 1});

    await sync.write({'vibration': false});

    expect((await firestore.doc(_path).get()).data(), {
      'vibration': false,
      'newerKey': 1,
    });
  });

  test('watch reports no document, then the stored values', () async {
    final List<Map<String, Object?>?> seen = [];
    final subscription = sync.watch().listen((snapshot) {
      seen.add(snapshot.data);
    });
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(seen, [null]);

    await sync.write({'weekStart': 'monday'});
    await pumpEventQueue();
    expect(seen.last, {'weekStart': 'monday'});
  });

  test('each user has their own document', () async {
    await sync.write({'vibration': false});

    final other = await firestore
        .doc('users/user-b/settings/preferences')
        .get();
    expect(other.exists, isFalse);
  });
}
