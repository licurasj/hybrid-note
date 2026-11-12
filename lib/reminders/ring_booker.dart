import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'reminder_planner.dart';
import 'ring_fence.dart';

// What the phone's notification system can do for the booker (T-13 unit 3).
// On Android it is flutter_local_notifications (LocalRingPlatform); tests use
// a fake. Off Android there is none and nothing is booked (Q-95).
abstract class RingPlatform {
  // How booked rings sound and look beyond their text, such as the channel
  // they ring on (T-13 unit 9). When it changes, every ring is booked again.
  String get look;

  // The rings booked now, with the payload each was booked with.
  Future<List<BookedRing>> booked();

  Future<void> book(RingRequest request);

  Future<void> cancel(int id);

  Future<void> cancelAll();

  // After a pass that was not stopped: what older looks left behind may go
  // (F6: the old channel). Every ring booked on it was cancelled and booked
  // again in that pass, as its fingerprint holds [look] (T-13 unit 14, G16).
  Future<void> afterSync();

  // When the phone last started, while RingBootReceiver (android/) has not
  // yet handled that start; null once it has, or when unknown (T-13 unit 14,
  // G2). Until then the rings stored from before it are the receiver's, to
  // show as missed: a pass leaves them booked.
  Future<DateTime?> bootNotHandled();

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
    this.account,
  });

  factory RingPayload.of(
    PlannedRing ring,
    String fingerprint, {
    String? account,
  }) => RingPayload(
    key: ring.key,
    listId: ring.listId,
    itemId: ring.itemId,
    itemDate: ring.itemDate,
    dueMs: ring.due.millisecondsSinceEpoch,
    fingerprint: fingerprint,
    account: account,
  );

  final String key;
  final String listId;
  final String itemId;
  // The item's stored date when booked: Done does nothing if it changed.
  final String itemDate;
  final int dueMs;
  // Everything the ring shows or how it rings; a change books it again.
  final String fingerprint;
  // The signed-in account the ring was booked for (F2): Done does nothing
  // for another. Null on rings booked before T-13 unit 10.
  final String? account;

  String encode() => jsonEncode({
    'k': key,
    'l': listId,
    'i': itemId,
    'd': itemDate,
    'u': dueMs,
    'f': fingerprint,
    'a': ?account,
  });

  // The time the ring was booked for: the first part of [fingerprint]
  // (RingBooker); null if unreadable.
  int? get atMs => int.tryParse(fingerprint.split('\u0000').first);

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
      final Object? account = json['a'];
      if (key is! String ||
          listId is! String ||
          itemId is! String ||
          itemDate is! String ||
          dueMs is! int ||
          fingerprint is! String ||
          (account != null && account is! String)) {
        return null;
      }
      return RingPayload(
        key: key,
        listId: listId,
        itemId: itemId,
        itemDate: itemDate,
        dueMs: dueMs,
        fingerprint: fingerprint,
        account: account as String?,
      );
    } on FormatException {
      return null;
    }
  }
}

// What a ring shows (T-13 unit 9): the item's title, the time under it and
// the list's name in the header beside the app's name ([subText]), all tinted
// in the list's [color] (ARGB). [done] is the Done button's label (T-13 unit 4),
// null for no Done: a list with nothing to tick (F9).
typedef RingText = ({
  String title,
  String body,
  String subText,
  int color,
  String? done,
});

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
//
// Each sync is a pass under [fence] (F2, F4): a sign-out since the pass
// began stops it before its next change, and it takes back what it booked,
// so a pass in another isolate (the background check) cannot leave a
// signed-out phone ringing. A pass begun later, here or in another isolate,
// planned from a newer read, so it stops the older one, which leaves the
// rest to it.
//
// A pass checks between changes, so an older pass may still make one change
// after a newer one read what is booked; the next pass (a list change, the
// next open or check) puts that right.
class RingBooker {
  RingBooker(
    this.platform, {
    this.fence = RingFence.none,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RingPlatform platform;
  final RingFence fence;
  final DateTime Function() _clock;

  Future<void>? _running;
  _SyncRequest? _next;
  // Counts [signIn]s; [_signedIn] is the latest, awaited before a pass.
  int _session = 0;
  Future<void>? _signedIn;

  // Books [rings] for the signed-in [account], each shown as [text] says.
  // [entered] is from [RingFence.enter], when the pass took its marks before
  // the lists were read (the background check); the pass begins when it
  // runs, after the read.
  Future<void> sync(
    List<PlannedRing> rings,
    RingText Function(PlannedRing ring) text, {
    String? account,
    RingTicket? entered,
  }) {
    _next = _SyncRequest(rings, text, account, entered);
    return _running ??= _drain();
  }

  // Signed out (the background check finds no user): nothing stays booked.
  Future<void> cancelAll() async {
    _next = null;
    await _running;
    await cancelNow();
  }

  // Cancels every ring and the background check without waiting for a pass
  // here (T-13 unit 14, G3: after a sign-out cleanup that timed out).
  Future<void> cancelNow() async {
    _next = null;
    await platform.cancelAll();
    await platform.stopBackgroundCheck();
  }

  // An account starts on this phone (ReminderHost): passes may book again
  // after a sign-out (G3).
  Future<void> signIn() {
    _session++;
    return _signedIn = fence.signIn();
  }

  // Sign-out on this phone: fences every pass, here and in other isolates,
  // then cancels every ring and the background check. A pass running here
  // stops at its next change, so the wait for it is short. If an account
  // started before that wait ended (a sign-out cleanup that timed out), its
  // rings stay.
  Future<void> signOut() async {
    _next = null;
    final int session = _session;
    await fence.signOut();
    await _running;
    if (session != _session) {
      return;
    }
    await cancelNow();
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
    await _signedIn;
    final RingTicket ticket = await fence.begin(entered: request.entered);
    final List<int> bookedHere = [];
    // False once this pass must stop; after a sign-out it first takes back
    // what it booked.
    Future<bool> mayGoOn() async {
      final RingCheck check = await fence.check(ticket);
      if (check == RingCheck.current) {
        return true;
      }
      if (check == RingCheck.superseded) {
        return false;
      }
      for (final int id in bookedHere) {
        try {
          await platform.cancel(id);
        } on Object catch (error) {
          debugPrint('Reminder not taken back: $error');
        }
      }
      return false;
    }

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
        text.subText,
        text.color,
        text.done,
        ring.itemDate,
        permissions.exact,
        platform.look,
        request.account ?? '',
      ].join('\u0000');
      wanted[id] = RingRequest(
        id: id,
        at: ring.at,
        text: text,
        payload: RingPayload.of(ring, fingerprint, account: request.account),
        exact: permissions.exact,
      );
    }

    // Before the boot receiver ran (BOOT_COMPLETED can come minutes after
    // the app opens), the rings from before the boot are left to it (G2).
    final DateTime? boot = await _bootNotHandled();
    for (final BookedRing ring in booked.values) {
      final int? atMs = ring.payload?.atMs;
      if (boot != null &&
          atMs != null &&
          atMs < boot.millisecondsSinceEpoch) {
        continue;
      }
      final RingRequest? want = wanted[ring.id];
      if (want == null ||
          ring.payload?.key != want.payload.key ||
          ring.payload?.fingerprint != want.payload.fingerprint) {
        if (!await mayGoOn()) {
          return;
        }
        await platform.cancel(ring.id);
      }
    }
    final DateTime now = _clock().toUtc();
    for (final RingRequest want in wanted.values) {
      final BookedRing? ring = booked[want.id];
      if (ring != null &&
          ring.payload?.key == want.payload.key &&
          ring.payload?.fingerprint == want.payload.fingerprint) {
        continue;
      }
      // A time already passed is never booked (no catch-up); one booked
      // before stays above, while the plan has it (F5: late delivery).
      if (!want.at.isAfter(now)) {
        continue;
      }
      if (!await mayGoOn()) {
        return;
      }
      try {
        await platform.book(want);
        bookedHere.add(want.id);
      } on Object catch (error) {
        debugPrint('Reminder not booked: $error');
      }
      // A sign-out while it was booked takes it back.
      if (!await mayGoOn()) {
        return;
      }
    }
    if (await fence.check(ticket) == RingCheck.current) {
      try {
        await platform.afterSync();
      } on Object catch (error) {
        debugPrint('Reminders: not tidied: $error');
      }
    }
  }

  Future<DateTime?> _bootNotHandled() async {
    try {
      return await platform.bootNotHandled();
    } on Object catch (error) {
      debugPrint('Reminders: boot not known: $error');
      return null;
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
  _SyncRequest(this.rings, this.text, this.account, this.entered);

  final List<PlannedRing> rings;
  final RingText Function(PlannedRing ring) text;
  final String? account;
  final RingTicket? entered;
}
