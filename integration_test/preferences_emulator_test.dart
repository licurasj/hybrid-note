import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/backend/firestore_preferences.dart';
import 'package:hybrid_note/firebase_options.dart';

// Account preferences through the real cloud_firestore plugin against the
// Firebase emulators, with the project's firestore.rules (T-21 unit 1). Two
// Firebase apps stand for two phones of one account. It proves what the fakes
// cannot: the server's "no document" reaching the listener, sync between
// clients, the offline queue and the rules. Run it inside
// `firebase emulators:exec` as the runbook shows for the list store's suite.

final String _host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? '10.0.2.2'
    : '127.0.0.1';
const String _password = 'emulator-only-password';
const Duration _wait = Duration(seconds: 30);

late FirebaseFirestore _dbA;
late FirebaseAuth _authA;
late FirebaseFirestore _dbB;
late FirebaseAuth _authB;
int _users = 0;

// One emulator user, signed in on both phones.
Future<String> _newUser() async {
  final String email =
      'prefs${_users++}-${DateTime.now().microsecondsSinceEpoch}@example.test';
  final UserCredential credential = await _authA.createUserWithEmailAndPassword(
    email: email,
    password: _password,
  );
  await _authB.signInWithEmailAndPassword(email: email, password: _password);
  return credential.user!.uid;
}

// A phone: its own Firestore client, and a cubit that starts from [stored] in
// a fresh in-memory shared_preferences.
Future<AccountPreferencesCubit> _phone(
  FirebaseFirestore db,
  String uid,
  Map<String, Object> stored,
) async {
  SharedPreferences.setMockInitialValues(stored);
  final AccountPreferencesCubit cubit = AccountPreferencesCubit(
    await SharedPreferences.getInstance(),
    uid,
    sync: FirestorePreferencesSync(db, uid),
  );
  addTearDown(cubit.close);
  return cubit;
}

Future<void> _until(
  AccountPreferencesCubit cubit,
  bool Function(AccountPreferences preferences) test,
) async {
  if (test(cubit.state)) {
    return;
  }
  await cubit.stream.firstWhere(test).timeout(_wait);
}

Future<Map<String, dynamic>?> _server(FirebaseFirestore db, String uid) async {
  return (await db
          .doc('users/$uid/settings/preferences')
          .get(const GetOptions(source: Source.server)))
      .data();
}

Future<void> _serverHas(
  FirebaseFirestore db,
  String uid,
  bool Function(Map<String, dynamic> data) test,
) async {
  final Stopwatch watch = Stopwatch()..start();
  while (true) {
    final Map<String, dynamic>? data = await _server(db, uid);
    if (data != null && test(data)) {
      return;
    }
    if (watch.elapsed > _wait) {
      fail('the server did not get there: $data');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final FirebaseApp second = await Firebase.initializeApp(
      name: 'phone-b',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _dbA = FirebaseFirestore.instance;
    _authA = FirebaseAuth.instance;
    _dbB = FirebaseFirestore.instanceFor(app: second);
    _authB = FirebaseAuth.instanceFor(app: second);
    for (final FirebaseFirestore db in [_dbA, _dbB]) {
      db.useFirestoreEmulator(_host, 8080);
    }
    for (final FirebaseAuth auth in [_authA, _authB]) {
      await auth.useAuthEmulator(_host, 9099);
    }
  });

  tearDown(() async {
    await _dbA.enableNetwork();
    await _dbB.enableNetwork();
    await _authA.signOut();
    await _authB.signOut();
  });

  testWidgets('the first phone seeds the account from what it had', (_) async {
    final String uid = await _newUser();

    await _phone(_dbA, uid, {
      AccountPreferencesCubit.legacyAutoApplyKey: true,
      AccountPreferencesCubit.legacyAskLevelKey: 'less',
    });

    await _serverHas(_dbA, uid, (data) => data.isNotEmpty);
    final Map<String, dynamic>? stored = await _server(_dbA, uid);
    expect(stored!['aiAutoApply'], isTrue);
    expect(stored['aiAskLevel'], 'less');
  });

  testWidgets('a new phone takes the account\'s values, not its own', (
    _,
  ) async {
    final String uid = await _newUser();
    await _phone(_dbA, uid, {
      AccountPreferencesCubit.legacyAskLevelKey: 'less',
    });
    await _serverHas(_dbA, uid, (data) => data['aiAskLevel'] == 'less');

    final AccountPreferencesCubit phoneB = await _phone(_dbB, uid, {
      AccountPreferencesCubit.legacyAskLevelKey: 'more',
    });
    expect(phoneB.state.aiAskLevel, AiAskLevel.more);

    await _until(phoneB, (p) => p.aiAskLevel == AiAskLevel.less);
    expect((await _server(_dbB, uid))!['aiAskLevel'], 'less');
  });

  testWidgets('a change on one phone shows on the other', (_) async {
    final String uid = await _newUser();
    final AccountPreferencesCubit phoneA = await _phone(_dbA, uid, const {});
    await _serverHas(_dbA, uid, (data) => data.isNotEmpty);
    final AccountPreferencesCubit phoneB = await _phone(_dbB, uid, const {});
    await _until(phoneB, (p) => p == phoneA.state);

    final Stopwatch watch = Stopwatch()..start();
    await phoneA.setVibration(false);
    await _until(phoneB, (p) => !p.vibration);
    debugPrint(
      'MEASURE sync to the other phone: ${watch.elapsedMilliseconds} ms',
    );

    await phoneB.setMyListOrder(['b', 'a']);
    await _until(phoneA, (p) => p.myListOrder.length == 2);
    expect(phoneA.state.myListOrder, ['b', 'a']);
    expect(phoneA.state.vibration, isFalse);
  });

  testWidgets(
    'a phone that was offline catches up, and sends what it changed',
    (_) async {
      final String uid = await _newUser();
      final AccountPreferencesCubit phoneA = await _phone(_dbA, uid, const {});
      await _serverHas(_dbA, uid, (data) => data.isNotEmpty);
      final AccountPreferencesCubit phoneB = await _phone(_dbB, uid, const {});
      await _until(phoneB, (p) => p == phoneA.state);

      await _dbB.disableNetwork();
      // Done on the phone at once, though the server cannot be reached.
      await phoneB.setConfirmDelete(true);
      expect(phoneB.state.confirmDelete, isTrue);
      await phoneA.setVibration(false);
      await _serverHas(_dbA, uid, (data) => data['vibration'] == false);
      expect(phoneB.state.vibration, isTrue);
      expect((await _server(_dbA, uid))!['confirmDelete'], isFalse);

      await _dbB.enableNetwork();
      await _until(phoneB, (p) => !p.vibration);
      await _until(phoneA, (p) => p.confirmDelete);
      expect(phoneB.state.confirmDelete, isTrue);
    },
  );

  testWidgets(
    'offline on a new phone: nothing is seeded until the server answers',
    (_) async {
      final String uid = await _newUser();
      await _phone(_dbA, uid, {
        AccountPreferencesCubit.legacyAskLevelKey: 'less',
      });
      await _serverHas(_dbA, uid, (data) => data['aiAskLevel'] == 'less');

      await _dbB.disableNetwork();
      final AccountPreferencesCubit phoneB = await _phone(_dbB, uid, const {});
      await phoneB.setVibration(false);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(phoneB.state.aiAskLevel, AiAskLevel.balanced);
      expect((await _server(_dbA, uid))!['vibration'], isTrue);

      await _dbB.enableNetwork();
      await _until(phoneB, (p) => p.aiAskLevel == AiAskLevel.less);
      expect(phoneB.state.vibration, isFalse);
      await _serverHas(_dbA, uid, (data) => data['vibration'] == false);
      expect((await _server(_dbA, uid))!['aiAskLevel'], 'less');
    },
  );

  testWidgets('offline on the first phone: the seeding happens once back', (
    _,
  ) async {
    final String uid = await _newUser();

    await _dbA.disableNetwork();
    final AccountPreferencesCubit phoneA = await _phone(_dbA, uid, const {});
    await phoneA.setWeekStart(WeekStart.sunday);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(await _server(_dbB, uid), isNull);

    await _dbA.enableNetwork();
    await _serverHas(_dbB, uid, (data) => data['weekStart'] == 'sunday');
    expect(phoneA.state.weekStart, WeekStart.sunday);
  });

  testWidgets('two first phones at once: one seeding, each keeps its change', (
    _,
  ) async {
    final String uid = await _newUser();
    final AccountPreferencesCubit phoneA = await _phone(_dbA, uid, const {});
    final AccountPreferencesCubit phoneB = await _phone(_dbB, uid, const {});
    await phoneA.setVibration(false);
    await phoneB.setConfirmDelete(true);

    await _until(phoneA, (p) => p.confirmDelete && !p.vibration);
    await _until(phoneB, (p) => p.confirmDelete && !p.vibration);
    await _serverHas(
      _dbA,
      uid,
      (data) => data['vibration'] == false && data['confirmDelete'] == true,
    );
  });

  testWidgets('another user cannot read or change the document', (_) async {
    final String uid = await _newUser();
    await _phone(_dbA, uid, const {});
    await _serverHas(_dbA, uid, (data) => data.isNotEmpty);

    await _authB.signOut();
    await _authB.createUserWithEmailAndPassword(
      email:
          'intruder${_users++}-${DateTime.now().microsecondsSinceEpoch}@example.test',
      password: _password,
    );

    await expectLater(
      _server(_dbB, uid),
      throwsA(
        isA<FirebaseException>().having(
          (e) => e.code,
          'code',
          'permission-denied',
        ),
      ),
    );
    await expectLater(
      FirestorePreferencesSync(_dbB, uid).write({'vibration': false}),
      throwsA(
        isA<FirebaseException>().having(
          (e) => e.code,
          'code',
          'permission-denied',
        ),
      ),
    );
  });
}
