// The app on the local emulators with the AI bar (T-19 unit 4): Auth,
// Firestore and Functions, the function's fake provider and an emulator
// user, so nothing reaches the real project or a provider and no real
// account signs in. The lists live under the app's own project id in the
// Firestore emulator; the function runs as demo-hybrid-note (as its tests
// do), so it is called through a second Firebase app on that project, with
// the same emulator user signed in.
//
//   firebase emulators:start --project demo-hybrid-note \
//     --only auth,firestore,functions
//   flutter run -t tool/ai_emulator_main.dart
//
// The function needs aiAllowlist/{uid} {tier: owner} in the Firestore
// emulator (project demo-hybrid-note); the uid is printed at start.
// --dart-define=EMULATOR_HOST=... for another host than the Android
// emulator's view of the PC; AUTH_PORT, FIRESTORE_PORT and FUNCTIONS_PORT
// for emulators started on other ports (firebase --config with its own
// "emulators" ports), for example while another session holds the defaults.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:hybrid_note/ai/ai_service.dart';
import 'package:hybrid_note/firebase_options.dart';
import 'package:hybrid_note/main.dart' as app;

const String _host = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);

const int _authPort = int.fromEnvironment('AUTH_PORT', defaultValue: 9099);
const int _firestorePort = int.fromEnvironment('FIRESTORE_PORT', defaultValue: 8080);
const int _functionsPort = int.fromEnvironment('FUNCTIONS_PORT', defaultValue: 5001);

// An emulator-only user; it exists nowhere else.
const String _email = 'owner@hybrid-note.test';
const String _password = 'emulator-only';

Future<void> _signIn(FirebaseAuth auth) async {
  await auth.useAuthEmulator(_host, _authPort);
  try {
    await auth.signInWithEmailAndPassword(email: _email, password: _password);
  } on FirebaseAuthException {
    await auth.createUserWithEmailAndPassword(
      email: _email,
      password: _password,
    );
  }
}

Future<void> main() async {
  late final FirebaseApp aiApp;
  await app.startApp(
    afterInit: () async {
      FirebaseFirestore.instance.useFirestoreEmulator(_host, _firestorePort);
      await _signIn(FirebaseAuth.instance);
      aiApp = await Firebase.initializeApp(
        name: 'ai-emulator',
        options: DefaultFirebaseOptions.currentPlatform.copyWith(
          projectId: 'demo-hybrid-note',
        ),
      );
      final FirebaseAuth aiAuth = FirebaseAuth.instanceFor(app: aiApp);
      await _signIn(aiAuth);
      FirebaseFunctions.instanceFor(
        app: aiApp,
        region: 'us-central1',
      ).useFunctionsEmulator(_host, _functionsPort);
      debugPrint('AI emulator uid: ${aiAuth.currentUser?.uid}');
    },
    aiService: () => FunctionsAiService(
      FirebaseFunctions.instanceFor(app: aiApp, region: 'us-central1'),
    ),
  );
}
