import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../ai/ai_service.dart';
import '../firebase_options.dart';
import '../main.dart' show activateAppCheck;
import 'firebase_scripts.dart';

// The demo's AI (T-18 unit 2b). Nothing of Firebase runs until the first
// send, which the AI bar makes only after the AI notice was accepted. That
// send starts Firebase and App Check, signs in anonymously (tier `demo` on
// the function) and then calls aiCommand like the real app.

// What the lazy service needs from Firebase; a fake in tests.
abstract interface class DemoAiBackend {
  // Firebase and App Check; called once, again only after a failure.
  Future<void> start();

  bool get signedIn;

  // A new anonymous account.
  Future<void> signIn();

  // Drops the account this page holds, for example one the clean-up job
  // deleted on the server.
  Future<void> signOut();

  // The function, for the account now signed in.
  AiService get service;
}

class LazyAiService implements AiService {
  LazyAiService(this._backend);

  final DemoAiBackend _backend;
  Future<void>? _started;
  Future<void>? _signingIn;

  @override
  Future<AiAnswer> send(AiRequest request) async {
    await _ready();
    try {
      return await _backend.service.send(request);
    } on AiRefusal catch (refusal) {
      if (!_needsSignIn(refusal)) {
        rethrow;
      }
      // The anonymous account is gone (the clean-up job deletes accounts
      // older than 24 hours, and then the token no longer refreshes): sign
      // in again, once. The function refuses a missing sign-in before it
      // counts anything, so the retry is not counted twice.
      developer.log('demo AI: signing in again', name: 'DemoAi');
      await _backend.signOut();
      await _signIn();
      return _backend.service.send(request);
    }
  }

  Future<void> _ready() async {
    try {
      await (_started ??= _backend.start());
    } on Object catch (error) {
      developer.log('demo AI: Firebase did not start: $error', name: 'DemoAi');
      _started = null;
      throw const AiRefusal('unavailable');
    }
    if (!_backend.signedIn) {
      await _signIn();
    }
  }

  Future<void> _signIn() async {
    try {
      await (_signingIn ??= _backend.signIn().whenComplete(
        () => _signingIn = null,
      ));
    } on Object catch (error) {
      developer.log(
        'demo AI: anonymous sign-in failed: $error',
        name: 'DemoAi',
      );
      throw const AiRefusal('unavailable');
    }
  }

  static bool _needsSignIn(AiRefusal refusal) =>
      refusal.reason == 'signIn' || refusal.reason == 'unauthenticated';
}

// Local emulators instead of the project, for checks only (T-18 unit 3):
// --dart-define=DEMO_EMULATOR_HOST=localhost, with AUTH_PORT and
// FUNCTIONS_PORT for emulators on other ports. The function then runs as
// demo-hybrid-note, as in its tests. Empty in the portfolio build, so the
// compiler drops this path.
const String _emulatorHost = String.fromEnvironment('DEMO_EMULATOR_HOST');
const int _authPort = int.fromEnvironment('AUTH_PORT', defaultValue: 9099);
const int _functionsPort = int.fromEnvironment(
  'FUNCTIONS_PORT',
  defaultValue: 5001,
);

class FirebaseDemoAiBackend implements DemoAiBackend {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  late final AiService _service = FunctionsAiService();

  @override
  Future<void> start() async {
    // The demo uses no Firestore, so its Firebase JS bundle is not loaded.
    skipFirebaseScripts(const ['firestore']);
    final FirebaseOptions options = DefaultFirebaseOptions.currentPlatform;
    if (_emulatorHost.isEmpty) {
      await Firebase.initializeApp(options: options);
      await activateAppCheck();
      await _restored();
      return;
    }
    await Firebase.initializeApp(
      options: options.copyWith(projectId: 'demo-hybrid-note'),
    );
    await activateAppCheck();
    await _auth.useAuthEmulator(_emulatorHost, _authPort);
    FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).useFunctionsEmulator(_emulatorHost, _functionsPort);
    await _restored();
  }

  // On web the account saved by an earlier visit loads after initializeApp;
  // the first auth state is the restored one (or none), so [signedIn] is
  // read only after it and a late restore makes no second account (T-18 M8).
  Future<void> _restored() => _auth.authStateChanges().first;

  @override
  bool get signedIn => _auth.currentUser != null;

  @override
  Future<void> signIn() => _auth.signInAnonymously();

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  AiService get service => _service;
}
