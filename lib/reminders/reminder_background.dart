import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../app/account_preferences.dart';
import '../app/app_settings.dart';
import '../backend/firestore_list_store.dart';
import '../backend/firestore_setup.dart';
import '../firebase_options.dart';
import '../l10n/generated/app_localizations.dart';
import '../lists/list_catalog.dart';
import '../lists/list_labels.dart';
import 'local_ring_platform.dart';
import 'reminder_done.dart';
import 'reminder_planner.dart';
import 'reminder_text.dart';
import 'ring_booker.dart';
import 'ring_fence.dart';

// Reminder work with the app closed (T-13 unit 4): Done on a ring, and the
// background check about every 15 minutes that books again what changed on
// another phone (Q-93). Both run in a background isolate of their own, so
// they start Firebase themselves and read the signed-in user from the phone.

// The id of the Done button on a ring.
const String reminderDoneAction = 'done';

// The background check's work name; one per phone.
const String reminderCheckWork = 'reminder-check';

// Set by the emulator entry points (tool/) so the background isolates reach
// the same local emulators: "host|authPort|firestorePort". Never read in a
// release build.
const String reminderEmulatorKey = 'debug.reminderEmulators';

// The app's language as the phone has it, for texts made with no app open.
AppLocalizations reminderLocalizations(SharedPreferences preferences) {
  final String? code = preferences.getString(AppSettingsCubit.localeKey);
  final Locale locale = code != null
      ? Locale(code)
      : PlatformDispatcher.instance.locale;
  return lookupAppLocalizations(
    AppLocalizations.supportedLocales.any(
          (supported) => supported.languageCode == locale.languageCode,
        )
        ? Locale(locale.languageCode)
        : const Locale('en'),
  );
}

// Firebase in a background isolate, as the app sets it up; the signed-in
// user, or null when signed out.
Future<User?> _startFirebase(SharedPreferences preferences) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;
  try {
    // The app's process may have set these up already.
    FirestoreSetup(firestore).configure();
  } on Object catch (error) {
    debugPrint('Reminders: Firestore settings kept: $error');
  }
  final String? emulators = kReleaseMode
      ? null
      : preferences.getString(reminderEmulatorKey);
  if (emulators != null) {
    final List<String> parts = emulators.split('|');
    try {
      firestore.useFirestoreEmulator(parts[0], int.parse(parts[2]));
      await auth.useAuthEmulator(parts[0], int.parse(parts[1]));
    } on Object catch (error) {
      debugPrint('Reminders: emulators already set: $error');
    }
  }
  return auth.currentUser ??
      await auth
          .authStateChanges()
          .firstWhere((user) => user != null)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
}

// Done on a ring with the app closed or in the background (Q-97): ticks the
// item as a tick on its list does, checked against a fresh copy (the plan's
// Sync safety for Done). Signed out, or with the item gone or its date
// changed, it does nothing. The ring goes away either way.
@pragma('vm:entry-point')
Future<void> onRingActionInBackground(NotificationResponse response) async {
  if (response.actionId != reminderDoneAction) {
    return;
  }
  final RingPayload? payload = RingPayload.decode(response.payload);
  if (payload == null) {
    return;
  }
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final User? user = await _startFirebase(preferences);
  // Only for the account the ring was booked for (F2).
  if (user == null || payload.account != user.uid) {
    return;
  }
  await doneFromRing(FirebaseFirestore.instance, user.uid, payload);
  // Other rings of the same occurrence (another lead time) go too.
  final LocalRingPlatform platform = LocalRingPlatform(
    channelName: reminderLocalizations(preferences).preferencesReminders,
  );
  await platform.cancelOccurrence(payload);
}

// Done itself, also called from the open app. Returns the store's answer
// (FirestoreListStore.applyFresh).
Future<bool?> doneFromRing(
  FirebaseFirestore firestore,
  String uid,
  RingPayload payload,
) async {
  AccountPreferences preferences = const AccountPreferences();
  try {
    final Map<String, dynamic>? data = (await firestore
            .doc('users/$uid/settings/preferences')
            .get())
        .data();
    if (data != null) {
      preferences = AccountPreferences.fromJson(data);
    }
  } on FirebaseException catch (error) {
    debugPrint('Reminders: preferences not read: $error');
  }
  try {
    return await FirestoreListStore.applyFresh(
      firestore,
      uid,
      listId: payload.listId,
      itemId: payload.itemId,
      change: (definition, item) => ReminderDone.changes(
        definition: definition,
        item: item,
        itemDate: payload.itemDate,
        preferences: preferences,
        now: DateTime.now().toUtc(),
      ),
      offlineChange: (definition, item) => ReminderDone.changes(
        definition: definition,
        item: item,
        itemDate: payload.itemDate,
        preferences: preferences,
        now: DateTime.now().toUtc(),
        mayClear: false,
      ),
    );
  } on Object catch (error) {
    debugPrint('Reminders: Done not written: $error');
    return false;
  }
}

// The background check's entry point (workmanager).
@pragma('vm:entry-point')
void reminderCheckDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await checkRingsInBackground();
    } on Object catch (error) {
      debugPrint('Reminders: background check failed: $error');
    }
    // A failed check waits for the next one; no retry.
    return true;
  });
}

// Plans and books as the open app does (ReminderHost), from the lists read
// once. Signed out, it cancels every ring. Its pass begins before anything
// is read, so a sign-out or a newer pass meanwhile fences it (F2).
Future<void> checkRingsInBackground() async {
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final AppLocalizations loc = reminderLocalizations(preferences);
  await prepareReminderText();
  final RingBooker booker = RingBooker(
    LocalRingPlatform(channelName: loc.preferencesReminders),
    fence: StoredRingFence(preferences),
  );
  final RingTicket ticket = await booker.fence.begin();
  final User? user = await _startFirebase(preferences);
  if (user == null) {
    await booker.cancelAll();
    return;
  }
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final ListCatalog catalog = await FirestoreListStore.readOnce(
    firestore,
    user.uid,
  );
  final Map<String, dynamic>? data = (await firestore
          .doc('users/${user.uid}/settings/preferences')
          .get())
      .data();
  final AccountPreferences account = data == null
      ? const AccountPreferences()
      : AccountPreferences.fromJson(data);
  final bool ring =
      preferences.getBool(AppSettingsCubit.ringOnThisPhoneKey) ?? true;
  final ListLabels labels = ListLabels(loc);
  final String locale = loc.localeName.replaceAll('_', '-');
  final List<PlannedRing> rings = ring
      ? ReminderPlanner.plan(
          catalog: catalog,
          settings: account.reminders,
          now: DateTime.now(),
          listName: labels.listName,
          late: ReminderPlanner.lateDelivery,
        )
      : const [];
  await booker.sync(
    rings,
    (planned) => reminderText(
      planned,
      loc: loc,
      locale: locale,
      format: account.timeFormat,
    ),
    account: user.uid,
    ticket: ticket,
  );
}
