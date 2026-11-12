import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/app/app_settings.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/reminders/reminder_background.dart';
import 'package:hybrid_note/reminders/reminder_text.dart';
import 'package:hybrid_note/reminders/ring_booker.dart';
import 'package:hybrid_note/reminders/ring_fence.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ring_booker_test.dart' show FakeRingPlatform, ring, text;

// T-13 unit 10, F15: the background check (checkRingsInBackground) with its
// sign-in and reads passed in.
void main() {
  final DateTime now = DateTime.utc(2030, 3, 1, 8);
  final DateTime due = DateTime.utc(2030, 3, 4, 10);
  final AppLocalizations loc = lookupAppLocalizations(const Locale('en'));
  final ListCatalog catalog = ListCatalog(
    definitions: BuiltinTemplates.all(),
    items: [
      ListItem(
        id: 'dentist',
        listId: BuiltinTemplates.tasksId,
        values: {
          'title': 'Dentist',
          'done': false,
          'reminderAt': due.toIso8601String(),
        },
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );

  setUpAll(prepareReminderText);

  late FakeRingPlatform platform;
  late MemoryRingFence fence;
  late RingBooker booker;

  setUp(() {
    platform = FakeRingPlatform();
    fence = MemoryRingFence();
    booker = RingBooker(platform, fence: fence, clock: () => now);
  });

  Future<void> check({
    String? uid = 'owner',
    String? Function()? signedIn,
    Map<String, Object> stored = const {},
    Future<void> Function()? whileReading,
    RingBooker? by,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    await checkRingsWith(
      booker: by ?? booker,
      preferences: await SharedPreferences.getInstance(),
      loc: loc,
      signedIn: () async => signedIn != null ? signedIn() : uid,
      read: (_) async {
        await whileReading?.call();
        return (catalog: catalog, account: const AccountPreferences());
      },
      now: () => now,
    );
  }

  // A ring booked earlier, by the open app.
  Future<void> bookedBefore() => booker.sync(
    [ring('old', at: now.add(const Duration(days: 1)))],
    text,
    account: 'owner',
  );

  test('signed in, it books the lists\' reminders for the account', () async {
    await check();
    final RingRequest booked = platform.rings.values.single;
    expect(booked.payload.itemId, 'dentist');
    expect(booked.payload.account, 'owner');
    expect(booked.at, due);
  });

  test('signed out, it cancels every ring', () async {
    await bookedBefore();
    await check(uid: null);
    expect(platform.rings, isEmpty);
    expect(platform.calls.last, 'cancelAll');
  });

  test('Ring on this phone off books nothing and cancels', () async {
    await bookedBefore();
    await check(stored: {AppSettingsCubit.ringOnThisPhoneKey: false});
    expect(platform.rings, isEmpty);
    expect(platform.calls.where((c) => c == 'book tasks|dentist'), isEmpty);
  });

  test('a sign-out while it reads books nothing (F2)', () async {
    await check(whileReading: fence.signOut);
    expect(platform.rings, isEmpty);
  });

  test('a newer pass while it reads leaves the rings to it (F4)', () async {
    await bookedBefore();
    final List<String> before = [...platform.calls];
    await check(whileReading: () async => fence.begin());
    expect(platform.calls, before);
  });

  // T-13 unit 14, G3 (Codex X1).
  test('a check that enters after a sign-out, while Firebase still reports '
      'the departing user, books nothing until an account starts', () async {
    await fence.signOut();
    await check();
    expect(platform.rings, isEmpty);
    await booker.signIn();
    await check();
    expect(platform.rings.values.single.payload.account, 'owner');
  });

  test('a check whose account changed during the read books nothing (G3)', () async {
    int asked = 0;
    await check(signedIn: () => ++asked == 1 ? 'owner' : null);
    expect(platform.rings, isEmpty);
  });

  // T-13 unit 14, G11 (internal R2).
  test('a check whose read fails does not stop the open app\'s pass', () async {
    final RingBooker app = RingBooker(platform, fence: fence, clock: () => now);
    platform.onBook = (_) async {
      platform.onBook = null;
      SharedPreferences.setMockInitialValues(const {});
      await expectLater(
        checkRingsWith(
          booker: booker,
          preferences: await SharedPreferences.getInstance(),
          loc: loc,
          signedIn: () async => 'owner',
          read: (_) async => throw StateError('offline'),
          now: () => now,
        ),
        throwsStateError,
      );
    };
    await app.sync(
      [
        ring('a', at: now.add(const Duration(hours: 1))),
        ring('b', at: now.add(const Duration(hours: 2))),
      ],
      text,
      account: 'owner',
    );
    expect(platform.rings, hasLength(2));
  });
}
