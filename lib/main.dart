import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/ai_service.dart';
import 'app/app_settings.dart';
import 'app/hybrid_note_app.dart';
import 'app/page_reload.dart';
import 'backend/auth_service.dart';
import 'backend/firestore_preferences.dart';
import 'backend/firestore_setup.dart';
import 'firebase_options.dart';

// The web App Check site key (Fraud Defense, formerly reCAPTCHA Enterprise;
// the console no longer offers reCAPTCHA v3), set at build time with
// --dart-define=RECAPTCHA_SITE_KEY (T-19 unit 6). The site key is public;
// Fraud Defense has no secret key. Without it the web build sends no App
// Check token and the function refuses web requests (web is on "enforce").
const String _recaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');

Future<void> main() => startApp();

// [afterInit] runs after Firebase is set up and before the app starts (the
// emulator entry points use it); [aiService] replaces the deployed AI
// function.
Future<void> startApp({
  Future<void> Function()? afterInit,
  AiService Function()? aiService,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _activateAppCheck();
  // Cache settings before anything touches Firestore (Q-25 A).
  final FirestoreSetup setup = FirestoreSetup(FirebaseFirestore.instance)
    ..configure();
  await afterInit?.call();
  final SharedPreferences preferences = await SharedPreferences.getInstance();

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AiService>(
          create: (_) => aiService?.call() ?? FunctionsAiService(),
        ),
      ],
      child: BlocProvider(
        create: (_) => AppSettingsCubit(preferences),
        child: HybridNoteApp(
          auth: AuthService(clearCache: setup.clearCache),
          openStore: (user) {
            final opened = setup.openStore(user.uid);
            return (store: opened.store, starter: opened.seeding);
          },
          openPreferences: (user) =>
              FirestorePreferencesSync(FirebaseFirestore.instance, user.uid),
          afterSignOut: setup.reloadAfterClear ? reloadPage : null,
        ),
      ),
    ),
  );
}

// App Check for the AI function (Q-34 1): Play Integrity on Android (the
// debug provider in debug builds) and Fraud Defense on web. The function
// decides per app whether a missing token is refused; a failure here never
// stops the app.
Future<void> _activateAppCheck() async {
  if (kIsWeb && _recaptchaSiteKey.isEmpty) {
    return;
  }
  try {
    await FirebaseAppCheck.instance.activate(
      providerWeb: kIsWeb
          ? ReCaptchaEnterpriseProvider(_recaptchaSiteKey)
          : null,
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
  } on Object catch (error) {
    developer.log('App Check not active: $error', name: 'main');
  }
}
