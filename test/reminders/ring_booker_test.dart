import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_note/app/account_preferences.dart' show TimeFormat;
import 'package:intl/date_symbol_data_local.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/reminders/reminder_planner.dart';
import 'package:hybrid_note/reminders/reminder_text.dart';
import 'package:hybrid_note/reminders/ring_booker.dart';

// T-13 unit 3: the booker books only the difference from what is booked.
class FakeRingPlatform implements RingPlatform {
  final Map<int, RingRequest> rings = {};
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

  @override
  Future<void> book(RingRequest request) async {
    calls.add('book ${request.payload.key}');
    rings[request.id] = request;
  }

  @override
  Future<void> cancel(int id) async {
    calls.add('cancel ${rings[id]?.payload.key}');
    rings.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    calls.add('cancelAll');
    rings.clear();
  }

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
);

RingText text(PlannedRing ring) =>
    (title: ring.title, body: ring.listName, done: 'Done');

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
    );
    RingText of(PlannedRing ring) =>
        reminderText(ring, loc: loc, locale: 'en', format: TimeFormat.h24);

    expect(of(at(due)).body, 'Tasks · 15:30');
    expect(of(at(due)).title, 'Tasks');
    expect(
      of(at(due.subtract(const Duration(days: 1)))).body,
      'Tasks · Tue, Mar 5 15:30',
    );
    expect(of(at(due, hasTime: false)).body, 'Tasks · Tue, Mar 5');
  });
}
