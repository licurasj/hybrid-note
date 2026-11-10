import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'reminder_planner.dart';

// What the phone's notification system can do for the booker (T-13 unit 3).
// On Android it is flutter_local_notifications (LocalRingPlatform); tests use
// a fake. Off Android there is none and nothing is booked (Q-95).
abstract class RingPlatform {
  // The rings booked now, with the payload each was booked with.
  Future<List<BookedRing>> booked();

  Future<void> book(RingRequest request);

  Future<void> cancel(int id);

  Future<void> cancelAll();

  Future<RingPermissions> permissions();

  // The system's notifications popup (Android 13 and later); true if allowed.
  Future<bool> requestNotifications();

  // Opens the system's Alarms & reminders switch for this app.
  Future<void> openExactAlarmSettings();

  // Opens the system's notification settings for this app.
  Future<void> openNotificationSettings();

  // Taps on a ring while the app runs (T-13 unit 4): the ring's payload.
  Stream<RingPayload> get taps;

  // The ring whose tap started the app, if one did.
  Future<RingPayload?> launchTap();

  // The background check that books again with the app closed (Q-93).
  Future<void> startBackgroundCheck();

  Future<void> stopBackgroundCheck();
}

@immutable
class RingPermissions {
  const RingPermissions({required this.notifications, required this.exact});

  // Notifications may show at all.
  final bool notifications;
  // Alarms & reminders is on: rings come at the minute, else inexact and late.
  final bool exact;

  @override
  bool operator ==(Object other) =>
      other is RingPermissions &&
      other.notifications == notifications &&
      other.exact == exact;

  @override
  int get hashCode => Object.hash(notifications, exact);
}

// One ring as booked: its notification id and the payload that says which
// planned ring it is.
@immutable
class BookedRing {
  const BookedRing({required this.id, required this.payload});

  final int id;
  final RingPayload? payload;
}

// What a booked ring carries, read back by the booker (to book only the
// difference) and by its tap and Done (T-13 unit 4).
@immutable
class RingPayload {
  const RingPayload({
    required this.key,
    required this.listId,
    required this.itemId,
    required this.itemDate,
    required this.dueMs,
    required this.fingerprint,
  });

  factory RingPayload.of(PlannedRing ring, String fingerprint) => RingPayload(
    key: ring.key,
    listId: ring.listId,
    itemId: ring.itemId,
    itemDate: ring.itemDate,
    dueMs: ring.due.millisecondsSinceEpoch,
    fingerprint: fingerprint,
  );

  final String key;
  final String listId;
  final String itemId;
  // The item's stored date when booked: Done does nothing if it changed.
  final String itemDate;
  final int dueMs;
  // Everything the ring shows or how it rings; a change books it again.
  final String fingerprint;

  String encode() => jsonEncode({
    'k': key,
    'l': listId,
    'i': itemId,
    'd': itemDate,
    'u': dueMs,
    'f': fingerprint,
  });

  // Null for a payload this app did not write.
  static RingPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final Object? json = jsonDecode(raw);
      if (json is! Map) {
        return null;
      }
      final Object? key = json['k'];
      final Object? listId = json['l'];
      final Object? itemId = json['i'];
      final Object? itemDate = json['d'];
      final Object? dueMs = json['u'];
      final Object? fingerprint = json['f'];
      if (key is! String ||
          listId is! String ||
          itemId is! String ||
          itemDate is! String ||
          dueMs is! int ||
          fingerprint is! String) {
        return null;
      }
      return RingPayload(
        key: key,
        listId: listId,
        itemId: itemId,
        itemDate: itemDate,
        dueMs: dueMs,
        fingerprint: fingerprint,
      );
    } on FormatException {
      return null;
    }
  }
}

// What a ring shows: the item's title, then the list's name and the time.
// [done] is the Done button's label (T-13 unit 4).
typedef RingText = ({String title, String body, String done});

// One ring to book.
@immutable
class RingRequest {
  const RingRequest({
    required this.id,
    required this.at,
    required this.text,
    required this.payload,
    required this.exact,
  });

  final int id;
  // UTC.
  final DateTime at;
  final RingText text;
  final RingPayload payload;
  final bool exact;
}

// Books the planned rings on the phone, changing only what differs from what
// is booked (T-13 unit 3): rings no longer planned are cancelled, new or
// changed ones are booked. A ring's notification id comes from its key, so
// the same ring keeps its id across plans and phones' restarts. One sync runs
// at a time; a sync asked for meanwhile runs once after it, with the latest
// plan.
class RingBooker {
  RingBooker(this.platform);

  final RingPlatform platform;

  Future<void>? _running;
  _SyncRequest? _next;

  // Books [rings], each shown as [text] says.
  Future<void> sync(
    List<PlannedRing> rings,
    RingText Function(PlannedRing ring) text,
  ) {
    _next = _SyncRequest(rings, text);
    return _running ??= _drain();
  }

  // Sign-out, or Ring on this phone off: nothing stays booked.
  Future<void> cancelAll() async {
    _next = null;
    await _running;
    await platform.cancelAll();
    await platform.stopBackgroundCheck();
  }

  Future<void> _drain() async {
    try {
      while (_next != null) {
        final _SyncRequest request = _next!;
        _next = null;
        await _sync(request);
      }
    } finally {
      _running = null;
    }
  }

  Future<void> _sync(_SyncRequest request) async {
    final RingPermissions permissions = await platform.permissions();
    final Map<int, BookedRing> booked = {
      for (final BookedRing ring in await platform.booked()) ring.id: ring,
    };
    final Map<int, RingRequest> wanted = {};
    for (final PlannedRing ring in request.rings) {
      final int id = idOf(ring.key);
      if (wanted.containsKey(id)) {
        // Two keys on one id: the sooner one wins (the plan is sorted).
        continue;
      }
      final RingText text = request.text(ring);
      final String fingerprint = [
        ring.at.millisecondsSinceEpoch,
        text.title,
        text.body,
        text.done,
        ring.itemDate,
        permissions.exact,
      ].join('\u0000');
      wanted[id] = RingRequest(
        id: id,
        at: ring.at,
        text: text,
        payload: RingPayload.of(ring, fingerprint),
        exact: permissions.exact,
      );
    }

    for (final BookedRing ring in booked.values) {
      final RingRequest? want = wanted[ring.id];
      if (want == null ||
          ring.payload?.key != want.payload.key ||
          ring.payload?.fingerprint != want.payload.fingerprint) {
        await platform.cancel(ring.id);
      }
    }
    final DateTime now = DateTime.now().toUtc();
    for (final RingRequest want in wanted.values) {
      final BookedRing? ring = booked[want.id];
      if (ring != null &&
          ring.payload?.key == want.payload.key &&
          ring.payload?.fingerprint == want.payload.fingerprint) {
        continue;
      }
      // A time that passed while planning rings no more (no catch-up).
      if (!want.at.isAfter(now)) {
        continue;
      }
      try {
        await platform.book(want);
      } on Object catch (error) {
        debugPrint('Reminder not booked: $error');
      }
    }
  }

  // A notification id for [key]: FNV-1a, kept positive and in 32 bits.
  static int idOf(String key) {
    int hash = 0x811c9dc5;
    for (final int unit in utf8.encode(key)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }
}

class _SyncRequest {
  _SyncRequest(this.rings, this.text);

  final List<PlannedRing> rings;
  final RingText Function(PlannedRing ring) text;
}
