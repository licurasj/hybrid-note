import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

// Who may book rings on this phone right now (T-13 unit 10, F2 and F4). The
// open app and the background check each book from their own read of the
// lists, in isolates of their own, so a pass checks its ticket before each
// change it makes:
// - A newer pass (begun after it, so planned from a newer read) supersedes
//   it: it stops, and the newer pass books what it planned.
// - A sign-out since it began fences it: it stops and takes back the rings
//   it booked, so no ring of a signed-out account is left booked.
// Kept in SharedPreferences, which every isolate of the app reads; each mark
// is a fresh random token, so two isolates never need to count together.
abstract class RingFence {
  // A pass begins; its ticket says when.
  Future<RingTicket> begin();

  // Whether [ticket]'s pass may still book.
  Future<RingCheck> check(RingTicket ticket);

  // Sign-out: every pass begun before now is fenced.
  Future<void> signOut();

  // No fence: every pass may always book (tests, and a booker made alone).
  static const RingFence none = _NoFence();
}

enum RingCheck { current, superseded, signedOut }

class RingTicket {
  const RingTicket(this.pass, this.signOut);

  final String pass;
  final String signOut;
}

class _NoFence implements RingFence {
  const _NoFence();

  @override
  Future<RingTicket> begin() async => const RingTicket('', '');

  @override
  Future<RingCheck> check(RingTicket ticket) async => RingCheck.current;

  @override
  Future<void> signOut() async {}
}

// The phone's fence, shared by the app and its background isolates.
class StoredRingFence implements RingFence {
  StoredRingFence(this._preferences);

  final SharedPreferences _preferences;

  static const String passKey = 'reminders.pass';
  static const String signOutKey = 'reminders.signOut';

  static final Random _random = Random();

  static String _token() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  // Another isolate may have written since this one last read.
  Future<void> _fresh() async {
    try {
      await _preferences.reload();
    } on Object {
      // The values read before stand.
    }
  }

  @override
  Future<RingTicket> begin() async {
    await _fresh();
    final String pass = _token();
    await _preferences.setString(passKey, pass);
    return RingTicket(pass, _preferences.getString(signOutKey) ?? '');
  }

  @override
  Future<RingCheck> check(RingTicket ticket) async {
    await _fresh();
    if ((_preferences.getString(signOutKey) ?? '') != ticket.signOut) {
      return RingCheck.signedOut;
    }
    if (_preferences.getString(passKey) != ticket.pass) {
      return RingCheck.superseded;
    }
    return RingCheck.current;
  }

  @override
  Future<void> signOut() => _preferences.setString(signOutKey, _token());
}

// A fence kept in memory, for tests: [signOut] and a newer [begin] fence
// older tickets as the stored one does.
class MemoryRingFence implements RingFence {
  int _pass = 0;
  int _signOut = 0;

  @override
  Future<RingTicket> begin() async => RingTicket('${++_pass}', '$_signOut');

  @override
  Future<RingCheck> check(RingTicket ticket) async {
    if (ticket.signOut != '$_signOut') {
      return RingCheck.signedOut;
    }
    return ticket.pass == '$_pass' ? RingCheck.current : RingCheck.superseded;
  }

  @override
  Future<void> signOut() async => _signOut++;
}
