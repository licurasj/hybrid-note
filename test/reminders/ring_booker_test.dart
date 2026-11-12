import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_note/app/account_preferences.dart' show TimeFormat;
import 'package:intl/date_symbol_data_local.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/reminders/reminder_planner.dart';
import 'package:hybrid_note/reminders/reminder_text.dart';
import 'package:hybrid_note/reminders/ring_booker.dart';
import 'package:hybrid_note/reminders/ring_fence.dart';

// T-13 unit 3: the booker books only the difference from what is booked.
class FakeRingPlatform implements RingPlatform {
  final Map<int, RingRequest> rings = {};
  @override
  String look = 'look-1';
  final List<String> calls = [];
  RingPermissions granted = const RingPermissions(
    notifications: true,
    exact: true,
  );

  @override
  Future<List<BookedRing>> booked() async => [
    for (final RingRequest ring in rings.values)
      BookedRing(
        id: ring.id,
        payload: RingPayload.decode(ring.payload.encode()),
      ),
  ];

  // Runs as each ring is booked (another isolate signing out meanwhile).
  Future<void> Function(RingRequest request)? onBook;

  @override
  Future<void> book(RingRequest request) async {
    calls.add('book ${request.payload.key}');
    rings[request.id] = request;
    await onBook?.call(request);
  }

  @override
  Future<void> cancel(int id) async {
    calls.add('cancel ${rings[id]?.payload.key}');
    rings.remove(id);
  }

  // A cleanup that fails, or one that never ends (F3).
  Object? cancelAllError;
  bool cancelAllHangs = false;

  @override
  Future<void> cancelAll() async {
    calls.add('cancelAll');
    if (cancelAllHangs) {
      await Completer<void>().future;
    }
    final Object? error = cancelAllError;
    if (error != null) {
      throw error;
    }
    rings.clear();
  }

  int tidied = 0;

  @override
  Future<void> afterSync() async => tidied++;

  @override
  Future<RingPermissions> permissions() async => granted;

  @override
  Future<bool> requestNotifications() async => granted.notifications;

  @override
  Future<void> openExactAlarmSettings() async {}

  @override
  Future<void> openNotificationSettings() async {}

  final StreamController<RingPayload> tapped =
      StreamController<RingPayload>.broadcast();
  RingPayload? launched;

  @override
  Stream<RingPayload> get taps => tapped.stream;

  @override
  Future<RingPayload?> launchTap() async => launched;

  bool checking = false;

  @override
  Future<void> startBackgroundCheck() async => checking = true;

  @override
  Future<void> stopBackgroundCheck() async => checking = false;
}

PlannedRing ring(
  String item, {
  required DateTime at,
  String title = 'Call',
  String date = '2030-01-01T10:00:00.000Z',
}) => PlannedRing(
  key: 'tasks|$item|${at.millisecondsSinceEpoch}|atTime',
  listId: 'tasks',
  itemId: item,
  at: at,
  due: at,
  hasTime: true,
  itemDate: date,
  title: title,
  listName: 'Tasks',
  listColor: '#00A63E',
);

RingText text(PlannedRing ring) => (
  title: ring.title,
  body: '10:00',
  subText: ring.listName,
  color: 0xFF00A63E,
  done: 'Done',
);

void main() {
  final DateTime soon = DateTime.now().toUtc().add(const Duration(hours: 2));
  final DateTime later = soon.add(const Duration(days: 1));

  test('books new rings and leaves unchanged ones alone', () async {
    final FakeRingPlatform platform = FakeRingPlatform();
    final RingBooker booker = RingBooker(platform);
    await booker.sync([ring('a', at: soon), ring('b', at: later)], text);
    expect(platform.rings, hasLength(2));
    platform.calls.clear();

    await booker.sync([ring('a', at: soon), ring('b', at: later)], text);
    expect(platform.calls, isEmpty);
  });

  test('cancels rings no longer planned and rebooks changed ones', () async {
    final FakeRingPlatform platform = FakeRingPlatform();
    final RingBooker booker = RingBooker(platform);
    await booker.sync([ring('a', at: soon), ring('b', at: later)], text);
    platform.calls.clear();

    await booker.sync([ring('a', at: soon, title: 'Call Ann')], text);
    expect(platform.rings.values.single.text.title, 'Call Ann');
    expect(
      platform.calls,
      containsAll(<String>[
        'cancel ${ring('b', at: later).key}',
        'book ${ring('a', at: soon).key}',
      ]),
    );
  });

  test('a changed stored date or exactness books again', () async {
    final FakeRingPlatform platform = FakeRingPlatform();
    final RingBooker booker = RingBooker(platform);
    await booker.sync([ring('a', at: soon)], text);
    platform.calls.clear();
    await booker.sync([ring('a', at: soon, date: '2030-01-02')], text);
    expect(platform.calls, hasLength(2));

    platform.calls.clear();
    platform.granted = const RingPermissions(notifications: true, exact: false);
    await booker.sync([ring('a', at: soon, date: '2030-01-02')], text);
    expect(platform.rings.values.single.exact, isFalse);
  });

  test('a changed list colour or platform look books every ring again '
      '(T-13 unit 9: the new chime channel)', () async {
    final FakeRingPlatform platform = FakeRingPlatform();
    final RingBooker booker = RingBooker(platform);
    final List<PlannedRing> plan = [ring('a', at: soon), ring('b', at: later)];
    await booker.sync(plan, text);
    platform.calls.clear();

    platform.look = 'look-2';
    platform.tidied = 0;
    await booker.sync(plan, text);
    expect(platform.calls.where((call) => call.startsWith('book')), hasLength(2));
    // F6: the old look goes only after the rings were booked again.
    expect(platform.tidied, 1);

    platform.calls.clear();
    await booker.sync(
      plan,
      (planned) => (
        title: planned.title,
        body: '10:00',
        subText: planned.listName,
        color: 0xFFE5007E,
        done: 'Done',
      ),
    );
    expect(platform.calls.where((call) => call.startsWith('book')), hasLength(2));
    expect(platform.rings.values.first.text.color, 0xFFE5007E);
  });

  test('a time already passed is not booked', () async {
    final FakeRingPlatform platform = FakeRingPlatform();
    await RingBooker(platform).sync([
      ring('a', at: DateTime.now().toUtc().subtract(const Duration(minutes: 1))),
    ], text);
    expect(platform.rings, isEmpty);
  });

  test('syncs asked for meanwhile run once, with the latest plan', () async {
    final FakeRingPlatform platform = FakeRingPlatform();
    final RingBooker booker = RingBooker(platform);
    final Future<void> first = booker.sync([ring('a', at: soon)], text);
    booker.sync([ring('b', at: soon)], text);
    final Future<void> last = booker.sync([ring('c', at: soon)], text);
    await Future.wait([first, last]);
    expect(platform.rings.values.single.payload.itemId, 'c');
  });

  test('cancelAll leaves nothing booked', () async {
    final FakeRingPlatform platform = FakeRingPlatform();
    final RingBooker booker = RingBooker(platform);
    await booker.sync([ring('a', at: soon)], text);
    await booker.cancelAll();
    expect(platform.rings, isEmpty);
  });

  test('payload round-trips; ids are stable and positive', () {
    final PlannedRing planned = ring('a', at: soon);
    final RingPayload payload = RingPayload.of(planned, 'f');
    final RingPayload? back = RingPayload.decode(payload.encode());
    expect(back?.key, planned.key);
    expect(back?.itemDate, planned.itemDate);
    expect(back?.dueMs, planned.due.millisecondsSinceEpoch);
    expect(RingPayload.decode('not json'), isNull);
    expect(RingPayload.decode(null), isNull);
    expect(RingBooker.idOf(planned.key), RingBooker.idOf(planned.key));
    expect(RingBooker.idOf(planned.key), greaterThanOrEqualTo(0));
    expect(RingBooker.idOf(planned.key), lessThan(1 << 31));
  });

  test('the text shows the time alone on the day, else with the date', () async {
    await initializeDateFormatting('en');
    final AppLocalizations loc = lookupAppLocalizations(const Locale('en'));
    final DateTime due = DateTime(2030, 3, 5, 15, 30);
    PlannedRing at(DateTime when, {bool hasTime = true}) => PlannedRing(
      key: 'k',
      listId: 'tasks',
      itemId: 'a',
      at: when.toUtc(),
      due: due.toUtc(),
      hasTime: hasTime,
      itemDate: 'd',
      title: '',
      listName: 'Tasks',
      listColor: '#F5B800',
    );
    RingText of(PlannedRing ring) =>
        reminderText(ring, loc: loc, locale: 'en', format: TimeFormat.h24);

    expect(of(at(due)).body, '15:30');
    expect(of(at(due)).title, 'Tasks');
    expect(
      of(at(due.subtract(const Duration(days: 1)))).body,
      'Tue, Mar 5 15:30',
    );
    expect(of(at(due, hasTime: false)).body, 'Tue, Mar 5');
    // T-13 unit 9: the list's name beside the app's name, the list's
    // stored colour as the tint.
    expect(of(at(due)).subText, 'Tasks');
    expect(of(at(due)).color, 0xFFF5B800);
  });

  group('sign-out fence (T-13 unit 10, F2)', () {
    test('a sign-out while a pass books stops it and takes back its rings', () async {
      final FakeRingPlatform platform = FakeRingPlatform();
      final MemoryRingFence fence = MemoryRingFence();
      final RingBooker booker = RingBooker(platform, fence: fence);
      platform.onBook = (_) async {
        platform.onBook = null;
        await fence.signOut();
      };
      await booker.sync(
        [ring('a', at: soon), ring('b', at: later)],
        text,
        account: 'u1',
      );
      expect(platform.rings, isEmpty);
      expect(platform.calls.where((call) => call.startsWith('book')), hasLength(1));
    });

    test('a pass begun before a sign-out (the background check) books nothing', () async {
      final FakeRingPlatform platform = FakeRingPlatform();
      final MemoryRingFence fence = MemoryRingFence();
      final RingBooker worker = RingBooker(platform, fence: fence);
      final RingTicket entered = await fence.enter();
      // The app signs out while the worker reads the lists.
      await RingBooker(platform, fence: fence).signOut();
      await worker.sync([ring('a', at: soon)], text, entered: entered);
      expect(platform.rings, isEmpty);
      expect(platform.calls, ['cancelAll']);
      // A stopped pass leaves the old look alone.
      expect(platform.tidied, 0);
    });

    test('signOut cancels every ring and the background check', () async {
      final FakeRingPlatform platform = FakeRingPlatform();
      final MemoryRingFence fence = MemoryRingFence();
      final RingBooker booker = RingBooker(platform, fence: fence);
      platform.checking = true;
      await booker.sync([ring('a', at: soon)], text, account: 'u1');
      await booker.signOut();
      expect(platform.rings, isEmpty);
      expect(platform.checking, isFalse);
      // Until an account starts again, no pass books (T-13 unit 14, G3).
      await booker.sync([ring('a', at: soon)], text, account: 'u1');
      expect(platform.rings, isEmpty);
      // Signed in again, passes book as before.
      await booker.signIn();
      await booker.sync([ring('a', at: soon)], text, account: 'u2');
      expect(platform.rings.values.single.payload.account, 'u2');
    });

    test('a sign-out cleanup stuck behind a pass: cancelNow cancels at once, '
        'and a later end of the cleanup leaves a new account\'s rings '
        '(T-13 unit 14, G3)', () async {
      final FakeRingPlatform platform = FakeRingPlatform();
      final MemoryRingFence fence = MemoryRingFence();
      final RingBooker booker = RingBooker(platform, fence: fence);
      platform.checking = true;
      final Completer<void> stuck = Completer<void>();
      platform.onBook = (_) async {
        platform.onBook = null;
        await stuck.future;
      };
      final Future<void> pass = booker.sync(
        [ring('a', at: soon)],
        text,
        account: 'u1',
      );
      await pumpEventQueue();
      final Future<void> cleanup = booker.signOut();
      await expectLater(
        cleanup.timeout(const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()),
      );
      await booker.cancelNow();
      expect(platform.rings, isEmpty);
      expect(platform.checking, isFalse);
      // The next account starts and books; then the stuck pass ends.
      await booker.signIn();
      final Future<void> next = booker.sync(
        [ring('b', at: soon)],
        text,
        account: 'u2',
      );
      stuck.complete();
      await pass;
      await next;
      await cleanup;
      expect(platform.rings.values.single.payload.account, 'u2');
    });

    test('rings carry the account; a new account books them again', () async {
      final FakeRingPlatform platform = FakeRingPlatform();
      final RingBooker booker = RingBooker(platform);
      await booker.sync([ring('a', at: soon)], text, account: 'u1');
      platform.calls.clear();
      await booker.sync([ring('a', at: soon)], text, account: 'u2');
      expect(platform.calls, hasLength(2));
      final RingPayload? back = RingPayload.decode(
        platform.rings.values.single.payload.encode(),
      );
      expect(back?.account, 'u2');
      // A payload from before T-13 unit 10 has no account.
      expect(
        RingPayload.decode(
          RingPayload.of(ring('a', at: soon), 'f').encode(),
        )?.account,
        isNull,
      );
    });
  });

  test('a booked ring Android delivers late is kept, never booked anew '
      '(T-13 unit 10, F5)', () async {
    DateTime clock = DateTime.utc(2030, 1, 1, 8, 58);
    final FakeRingPlatform platform = FakeRingPlatform();
    final RingBooker booker = RingBooker(platform, clock: () => clock);
    final DateTime nine = DateTime.utc(2030, 1, 1, 9);
    await booker.sync([ring('a', at: nine)], text);
    expect(platform.rings, hasLength(1));
    platform.calls.clear();
    // 09:03, the inexact ring still pending; the plan keeps it (late).
    clock = DateTime.utc(2030, 1, 1, 9, 3);
    await booker.sync([ring('a', at: nine), ring('b', at: nine)], text);
    expect(platform.calls, isEmpty);
    expect(platform.rings.values.single.payload.itemId, 'a');
    // Out of the plan (past the late window, or ticked): cancelled.
    await booker.sync(const [], text);
    expect(platform.rings, isEmpty);
  });

  group('one booking owner (T-13 unit 10, F4)', () {
    test('a pass planned from an older read changes nothing', () async {
      final FakeRingPlatform platform = FakeRingPlatform();
      final MemoryRingFence fence = MemoryRingFence();
      final RingBooker worker = RingBooker(platform, fence: fence);
      final RingBooker app = RingBooker(platform, fence: fence);
      // The background check enters and reads the old date...
      final RingTicket old = await fence.enter();
      // ...while the open app books the new one.
      await app.sync([ring('a', at: later, date: 'new')], text);
      await worker.sync([ring('a', at: soon, date: 'old')], text, entered: old);
      expect(platform.rings.values.single.payload.itemDate, 'new');
    });

    test('a newer pass stops an older one between changes', () async {
      final FakeRingPlatform platform = FakeRingPlatform();
      final MemoryRingFence fence = MemoryRingFence();
      final RingBooker worker = RingBooker(platform, fence: fence);
      platform.onBook = (_) async {
        platform.onBook = null;
        await fence.begin();
      };
      await worker.sync([ring('a', at: soon), ring('b', at: later)], text);
      // It stopped after its first booking and kept it (no sign-out).
      expect(platform.rings, hasLength(1));
    });
  });
}
