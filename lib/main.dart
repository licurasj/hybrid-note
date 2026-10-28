import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_settings.dart';
import 'app/hybrid_note_app.dart';
import 'app/page_reload.dart';
import 'backend/auth_service.dart';
import 'backend/firestore_setup.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Cache settings before anything touches Firestore (Q-25 A).
  final FirestoreSetup setup = FirestoreSetup(FirebaseFirestore.instance)
    ..configure();
  final SharedPreferences preferences = await SharedPreferences.getInstance();

  runApp(
    BlocProvider(
      create: (_) => AppSettingsCubit(preferences),
      child: HybridNoteApp(
        auth: AuthService(clearCache: setup.clearCache),
        openStore: (user) {
          final opened = setup.openStore(user.uid);
          return (store: opened.store, starter: opened.seeding);
        },
        afterSignOut: setup.reloadAfterClear ? reloadPage : null,
      ),
    ),
  );
}
