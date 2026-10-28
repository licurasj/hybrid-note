import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:hybrid_note/backend/auth_service.dart';
import 'package:hybrid_note/backend/firestore_setup.dart';

class FakeUser implements User {
  FakeUser(this.uid, {this.email, this.isAnonymous = false});

  @override
  final String uid;

  @override
  final String? email;

  @override
  final bool isAnonymous;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUserCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Records what the service asks of Firebase Auth; [fail] makes sign-in
// throw that error.
class FakeFirebaseAuth implements FirebaseAuth {
  FakeFirebaseAuth({User? user, this.fail}) : _user = user;

  User? _user;
  Object? fail;
  final List<AuthCredential> credentials = [];
  final List<AuthProvider> popups = [];
  final List<String> calls = [];
  final StreamController<User?> _changes = StreamController<User?>.broadcast();

  set user(User? user) {
    _user = user;
    _changes.add(user);
  }

  @override
  User? get currentUser => _user;

  @override
  Stream<User?> authStateChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    credentials.add(credential);
    if (fail != null) {
      throw fail!;
    }
    user = FakeUser('google-uid', email: 'owner@example.com');
    return FakeUserCredential();
  }

  @override
  Future<UserCredential> signInWithPopup(AuthProvider provider) async {
    popups.add(provider);
    if (fail != null) {
      throw fail!;
    }
    user = FakeUser('google-uid', email: 'owner@example.com');
    return FakeUserCredential();
  }

  @override
  Future<void> signOut() async {
    calls.add('firebase.signOut');
    user = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTokens implements GoogleSignInAuthentication {
  FakeTokens({this.idToken, this.accessToken});

  @override
  final String? idToken;

  @override
  final String? accessToken;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeGoogleAccount implements GoogleSignInAccount {
  FakeGoogleAccount(this.tokens);

  final FakeTokens tokens;

  @override
  Future<GoogleSignInAuthentication> get authentication async => tokens;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The account sheet: returns [account] (null = the user closed it) or
// throws [fail].
class FakeGoogleSignIn implements GoogleSignIn {
  FakeGoogleSignIn({this.account, this.fail, this.calls});

  GoogleSignInAccount? account;
  Object? fail;
  final List<String>? calls;

  @override
  Future<GoogleSignInAccount?> signIn() async {
    if (fail != null) {
      throw fail!;
    }
    return account;
  }

  @override
  Future<GoogleSignInAccount?> signOut() async {
    calls?.add('google.signOut');
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService on Android (account sheet + credential)', () {
    test('turns the account tokens into a Firebase sign-in', () async {
      final FakeFirebaseAuth auth = FakeFirebaseAuth();
      final AuthService service = AuthService(
        auth: auth,
        usePopup: false,
        googleSignIn: FakeGoogleSignIn(
          account: FakeGoogleAccount(
            FakeTokens(idToken: 'id-1', accessToken: 'access-1'),
          ),
        ),
      );

      final AuthUser? user = await service.signInWithGoogle();

      expect(
        user,
        const AuthUser(uid: 'google-uid', email: 'owner@example.com'),
      );
      expect(service.currentUser, user);
      final OAuthCredential credential =
          auth.credentials.single as OAuthCredential;
      expect(credential.providerId, 'google.com');
      expect(credential.idToken, 'id-1');
      expect(credential.accessToken, 'access-1');
    });

    test('asks Google for no extra scope (no Drive)', () async {
      const MethodChannel channel = MethodChannel(
        'plugins.flutter.io/google_sign_in',
      );
      final List<MethodCall> calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final AuthService service = AuthService(
        auth: FakeFirebaseAuth(),
        usePopup: false,
      );

      // The real GoogleSignIn: the sheet returns no account here.
      expect(await service.signInWithGoogle(), isNull);

      final MethodCall init = calls.firstWhere((c) => c.method == 'init');
      expect((init.arguments as Map)['scopes'], isEmpty);
      expect(calls.map((c) => c.method), contains('signIn'));
    });

    test('a closed sheet is not an error and does not call Firebase', () async {
      final FakeFirebaseAuth auth = FakeFirebaseAuth();
      for (final GoogleSignIn google in [
        FakeGoogleSignIn(),
        FakeGoogleSignIn(
          fail: PlatformException(code: GoogleSignIn.kSignInCanceledError),
        ),
      ]) {
        final AuthService service = AuthService(
          auth: auth,
          usePopup: false,
          googleSignIn: google,
        );
        expect(await service.signInWithGoogle(), isNull);
      }
      expect(auth.credentials, isEmpty);
    });

    test('failures reach the caller with a reason', () async {
      Future<AuthFailure?> reasonOf(AuthService service) async {
        try {
          await service.signInWithGoogle();
          return null;
        } on AuthException catch (error) {
          return error.reason;
        }
      }

      FakeGoogleSignIn sheet() => FakeGoogleSignIn(
        account: FakeGoogleAccount(FakeTokens(idToken: 'id-1')),
      );

      expect(
        await reasonOf(
          AuthService(
            auth: FakeFirebaseAuth(),
            usePopup: false,
            googleSignIn: FakeGoogleSignIn(
              account: FakeGoogleAccount(FakeTokens()),
            ),
          ),
        ),
        AuthFailure.noTokens,
      );
      expect(
        await reasonOf(
          AuthService(
            auth: FakeFirebaseAuth(
              fail: FirebaseAuthException(code: 'network-request-failed'),
            ),
            usePopup: false,
            googleSignIn: sheet(),
          ),
        ),
        AuthFailure.network,
      );
      expect(
        await reasonOf(
          AuthService(
            auth: FakeFirebaseAuth(),
            usePopup: false,
            googleSignIn: FakeGoogleSignIn(
              fail: PlatformException(code: GoogleSignIn.kNetworkError),
            ),
          ),
        ),
        AuthFailure.network,
      );
      expect(
        await reasonOf(
          AuthService(
            auth: FakeFirebaseAuth(
              fail: FirebaseAuthException(code: 'invalid-credential'),
            ),
            usePopup: false,
            googleSignIn: sheet(),
          ),
        ),
        AuthFailure.failed,
      );
    });
  });

  group('AuthService on web (pop-up)', () {
    test('the pop-up asks Google for no extra scope', () async {
      final FakeFirebaseAuth auth = FakeFirebaseAuth();
      final AuthService service = AuthService(auth: auth, usePopup: true);

      expect((await service.signInWithGoogle())!.uid, 'google-uid');

      final GoogleAuthProvider provider =
          auth.popups.single as GoogleAuthProvider;
      expect(provider.scopes, isEmpty);
    });

    test('a closed pop-up is not an error', () async {
      final AuthService service = AuthService(
        auth: FakeFirebaseAuth(
          fail: FirebaseAuthException(code: 'popup-closed-by-user'),
        ),
        usePopup: true,
      );

      expect(await service.signInWithGoogle(), isNull);
    });
  });

  group('AuthService: any Firebase user (D-13)', () {
    test('restore and userChanges report the user by uid, anonymous too',
        () async {
      final FakeFirebaseAuth auth = FakeFirebaseAuth(
        user: FakeUser('anon-uid', isAnonymous: true),
      );
      final AuthService service = AuthService(auth: auth);

      expect(
        await service.restore(),
        const AuthUser(uid: 'anon-uid', isAnonymous: true),
      );
      final List<AuthUser?> seen = [];
      final StreamSubscription<AuthUser?> subscription = service.userChanges
          .listen(seen.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      auth.user = null;
      await pumpEventQueue();
      expect(seen, [const AuthUser(uid: 'anon-uid', isAnonymous: true), null]);
      expect(await AuthService(auth: FakeFirebaseAuth()).restore(), isNull);
    });

    test('an anonymous user reaches their starter lists', () async {
      final AuthService service = AuthService(
        auth: FakeFirebaseAuth(user: FakeUser('anon-uid', isAnonymous: true)),
      );
      final FakeFirebaseFirestore firestore = FakeFirebaseFirestore();

      final AuthUser user = (await service.restore())!;
      final opened = FirestoreSetup(firestore).openStore(user.uid);
      addTearDown(opened.store.close);

      expect(await opened.starter, isTrue);
      await opened.store
          .watch()
          .firstWhere((c) => c.definitions.length == 4)
          .timeout(const Duration(seconds: 10));
      expect(
        (await firestore.collection('users/anon-uid/lists').get()).docs,
        hasLength(4),
      );
    });

    test('signOut signs out of Firebase and Google, then clears the cache',
        () async {
      final List<String> calls = [];
      final FakeFirebaseAuth auth = FakeFirebaseAuth(
        user: FakeUser('google-uid'),
      );
      final AuthService service = AuthService(
        auth: auth,
        usePopup: false,
        googleSignIn: FakeGoogleSignIn(calls: calls),
        clearCache: () async => calls.add('clearCache'),
      );

      expect(await service.signOut(), isTrue);

      expect([...auth.calls, ...calls], [
        'firebase.signOut',
        'google.signOut',
        'clearCache',
      ]);
      expect(service.currentUser, isNull);
    });

    test('a failed cache clear is reported, and clearing can be retried',
        () async {
      final FakeFirebaseAuth auth = FakeFirebaseAuth(
        user: FakeUser('anon-uid', isAnonymous: true),
      );
      int attempts = 0;
      final AuthService service = AuthService(
        auth: auth,
        usePopup: true,
        clearCache: () async {
          if (++attempts == 1) {
            throw StateError('the database is open in another tab');
          }
        },
      );

      // Signed out of Firebase, but the cache is still there (T-17 R1).
      expect(await service.signOut(), isFalse);
      expect(auth.calls, ['firebase.signOut']);
      expect(service.currentUser, isNull);

      expect(await service.clearLocalData(), isTrue);
      expect(attempts, 2);
    });
  });
}
