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
// - From a sign-out until an account starts again on this phone (T-13 unit
//   14, G3), no pass may book at all: a background check that enters after
//   the sign-out, while Firebase still reports the departing user, is
//   fenced too.
// Kept in SharedPreferences, which every isolate of the app reads; each mark
// is a fresh random token, so two isolates never need to count together.
abstract class RingFence {
  // Marks taken by a pass before it reads the lists (the background check),
  // handed to [begin] once it has read them.
  Future<RingTicket> enter();

  // A pass begins, from a read made now or, with [entered] from [enter],
  // from a read made since then. A pass whose read fails never begins, so
  // it supersedes no one (T-13 unit 14, G11); one that another pass began
  // after it entered (planned from a newer read) begins superseded (F4).
  Future<RingTicket> begin({RingTicket? entered});

  // Whether [ticket]'s pass may still book.
  Future<RingCheck> check(RingTicket ticket);

  // Sign-out: every pass begun before now is fenced, and no pass may book
  // until [signIn].
  Future<void> signOut();

  // An account starts on this phone (the open app shows its lists).
  Future<void> signIn();

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
  Future<RingTicket> enter() async => const RingTicket('', '');

  @override
  Future<RingTicket> begin({RingTicket? entered}) async =>
      const RingTicket('', '');

  @override
  Future<RingCheck> check(RingTicket ticket) async => RingCheck.current;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signIn() async {}
}

// Marks no stored token ever equals: a pass that entered while signing out
// is fenced for good, one begun after a newer pass is superseded.
const String _signingOutMark = 'signing-out';
const String _supersededMark = 'superseded';

// The phone's fence, shared by the app and its background isolates.
class StoredRingFence implements RingFence {
  StoredRingFence(this._preferences);

  final SharedPreferences _preferences;

  static const String passKey = 'reminders.pass';
  static const String signOutKey = 'reminders.signOut';
  // True from a sign-out until an account starts again (G3).
  static const String signingOutKey = 'reminders.signingOut';

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

  String _mark() => (_preferences.getBool(signingOutKey) ?? false)
      ? _signingOutMark
      : _preferences.getString(signOutKey) ?? '';

  @override
  Future<RingTicket> enter() async {
    await _fresh();
    return RingTicket(_preferences.getString(passKey) ?? '', _mark());
  }

  // With [entered], the check that no pass began since and the new token
  // are two steps, so a pass in another isolate may begin between them; then
  // both book from reads of about the same time.
  @override
  Future<RingTicket> begin({RingTicket? entered}) async {
    await _fresh();
    final String mark = entered?.signOut ?? _mark();
    if (mark == _signingOutMark) {
      return const RingTicket('', _signingOutMark);
    }
    if (entered != null &&
        (_preferences.getString(passKey) ?? '') != entered.pass) {
      return RingTicket(_supersededMark, mark);
    }
    final String pass = _token();
    await _preferences.setString(passKey, pass);
    return RingTicket(pass, mark);
  }

  @override
  Future<RingCheck> check(RingTicket ticket) async {
    await _fresh();
    if ((_preferences.getBool(signingOutKey) ?? false) ||
        (_preferences.getString(signOutKey) ?? '') != ticket.signOut) {
      return RingCheck.signedOut;
    }
    if (_preferences.getString(passKey) != ticket.pass) {
      return RingCheck.superseded;
    }
    return RingCheck.current;
  }

  // The signing-out state goes first (G3): a pass entering between the two
  // writes is fenced by it.
  @override
  Future<void> signOut() async {
    await _preferences.setBool(signingOutKey, true);
    await _preferences.setString(signOutKey, _token());
  }

  @override
  Future<void> signIn() => _preferences.setBool(signingOutKey, false);
}

// A fence kept in memory, for tests: it fences as the stored one does.
class MemoryRingFence implements RingFence {
  int _pass = 0;
  int _signOut = 0;
  bool signingOut = false;

  String get _mark => signingOut ? _signingOutMark : '$_signOut';

  @override
  Future<RingTicket> enter() async => RingTicket('$_pass', _mark);

  @override
  Future<RingTicket> begin({RingTicket? entered}) async {
    final String mark = entered?.signOut ?? _mark;
    if (mark == _signingOutMark) {
      return const RingTicket('', _signingOutMark);
    }
    if (entered != null && entered.pass != '$_pass') {
      return RingTicket(_supersededMark, mark);
    }
    return RingTicket('${++_pass}', mark);
  }

  @override
  Future<RingCheck> check(RingTicket ticket) async {
    if (signingOut || ticket.signOut != '$_signOut') {
      return RingCheck.signedOut;
    }
    return ticket.pass == '$_pass' ? RingCheck.current : RingCheck.superseded;
  }

  @override
  Future<void> signOut() async {
    signingOut = true;
    _signOut++;
  }

  @override
  Future<void> signIn() async => signingOut = false;
}
