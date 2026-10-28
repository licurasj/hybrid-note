import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

// The signed-in Firebase user, whatever the sign-in method. The app keys
// everything on [uid] (D-13): the gate, the store and the starter lists.
@immutable
class AuthUser {
  const AuthUser({required this.uid, this.email, this.isAnonymous = false});

  final String uid;
  final String? email;
  final bool isAnonymous;

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.uid == uid &&
      other.email == email &&
      other.isAnonymous == isAnonymous;

  @override
  int get hashCode => Object.hash(uid, email, isAnonymous);
}

enum AuthFailure {
  // No connection to Google or Firebase.
  network,
  // The Google account gave no tokens to sign in to Firebase with.
  noTokens,
  // Anything else; [AuthException.cause] has the details.
  failed,
}

class AuthException implements Exception {
  const AuthException(this.reason, [this.cause]);

  final AuthFailure reason;
  final Object? cause;

  @override
  String toString() => 'AuthException(${reason.name}: $cause)';
}

// Firebase Auth is the only sign-in (T-17, Q-21 A). Android keeps the native
// Google account sheet and turns its tokens into a Firebase credential
// (Q-7 A); web uses the Firebase pop-up. Neither asks for a Drive scope.
// Firebase keeps the session on the device, so [restore] works offline.
//
// Another sign-in method (anonymous for the demo, T-18) is one more method
// here: [userChanges] reports any Firebase user, and [signOut] works for
// all of them.
class AuthService {
  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    bool usePopup = kIsWeb,
    this.clearCache,
  }) : _authOverride = auth,
       _googleOverride = googleSignIn,
       _usePopup = usePopup;

  final FirebaseAuth? _authOverride;
  final GoogleSignIn? _googleOverride;
  final bool _usePopup;

  // Runs after signing out, to delete the local Firestore cache (Q-25 A):
  // FirestoreSetup.clearCache. The caller closes the stores before signOut.
  final Future<void> Function()? clearCache;

  // Resolved on first use so constructing the service needs no Firebase app.
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  // Basic profile only: no Drive or other extra scope.
  late final GoogleSignIn _google = _googleOverride ?? GoogleSignIn();

  AuthUser? get currentUser => _userFrom(_auth.currentUser);

  // The signed-in user, null when signed out; emits the current state first.
  Stream<AuthUser?> get userChanges =>
      _auth.authStateChanges().map(_userFrom).distinct();

  // Waits for Firebase to load the saved session (web loads it async).
  Future<AuthUser?> restore() async {
    return _userFrom(await _auth.authStateChanges().first);
  }

  // Signs in with Google. Returns null when the user closes the sheet or
  // the pop-up; throws [AuthException] when signing in fails.
  Future<AuthUser?> signInWithGoogle() async {
    final AuthUser? signedIn = currentUser;
    if (signedIn != null) {
      return signedIn;
    }
    try {
      if (_usePopup) {
        await _auth.signInWithPopup(GoogleAuthProvider());
      } else {
        final GoogleSignInAccount? account = await _google.signIn();
        if (account == null) {
          return null;
        }
        final GoogleSignInAuthentication tokens = await account.authentication;
        if (tokens.idToken == null && tokens.accessToken == null) {
          throw const AuthException(AuthFailure.noTokens);
        }
        await _auth.signInWithCredential(
          GoogleAuthProvider.credential(
            idToken: tokens.idToken,
            accessToken: tokens.accessToken,
          ),
        );
      }
    } on AuthException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      if (_cancelCodes.contains(error.code)) {
        return null;
      }
      throw AuthException(
        error.code == 'network-request-failed'
            ? AuthFailure.network
            : AuthFailure.failed,
        error,
      );
    } on PlatformException catch (error) {
      if (error.code == GoogleSignIn.kSignInCanceledError) {
        return null;
      }
      throw AuthException(
        error.code == GoogleSignIn.kNetworkError
            ? AuthFailure.network
            : AuthFailure.failed,
        error,
      );
    } on Object catch (error) {
      throw AuthException(AuthFailure.failed, error);
    }
    return currentUser;
  }

  // Signs out of Firebase and, on Android, of the Google account (so the
  // sheet asks again), then clears the cache. Throws only when the Firebase
  // sign-out fails (a broken plugin): the user is then still signed in. A
  // failed Google sign-out is logged and does not stop it.
  //
  // Returns whether the cache was cleared. False means the user is signed
  // out but the previous account's data is still on the device; the caller
  // keeps that state and calls [clearLocalData] again (T-17 R1).
  Future<bool> signOut() async {
    await _auth.signOut();
    if (!_usePopup) {
      try {
        await _google.signOut();
      } on Object catch (error) {
        debugPrint('AuthService: Google sign-out failed: $error');
      }
    }
    return clearLocalData();
  }

  // Deletes the local Firestore cache (Q-25 A); true when it is gone (or
  // there is none to clear).
  Future<bool> clearLocalData() async {
    if (clearCache == null) {
      return true;
    }
    try {
      await clearCache!();
      return true;
    } on Object catch (error) {
      debugPrint('AuthService: clearing the cache failed: $error');
      return false;
    }
  }

  // The user closed the pop-up or opened another one.
  static const Set<String> _cancelCodes = {
    'popup-closed-by-user',
    'cancelled-popup-request',
    'web-context-canceled',
  };

  static AuthUser? _userFrom(User? user) {
    if (user == null) {
      return null;
    }
    return AuthUser(
      uid: user.uid,
      email: user.email,
      isAnonymous: user.isAnonymous,
    );
  }
}
