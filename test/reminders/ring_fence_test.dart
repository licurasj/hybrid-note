import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_note/reminders/ring_fence.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The phone's fence (T-13 unit 10, F2 and F4; T-13 unit 14, G3 and G11).
void main() {
  late StoredRingFence fence;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    fence = StoredRingFence(await SharedPreferences.getInstance());
  });

  test('a pass begun now is current; a newer one supersedes it', () async {
    final RingTicket first = await fence.begin();
    expect(await fence.check(first), RingCheck.current);
    final RingTicket second = await fence.begin();
    expect(await fence.check(first), RingCheck.superseded);
    expect(await fence.check(second), RingCheck.current);
  });

  test('a sign-out fences older passes and every pass until sign-in', () async {
    final RingTicket before = await fence.begin();
    await fence.signOut();
    expect(await fence.check(before), RingCheck.signedOut);
    // A pass entering or beginning after the sign-out (G3).
    final RingTicket entered = await fence.enter();
    expect(await fence.check(await fence.begin()), RingCheck.signedOut);
    await fence.signIn();
    expect(await fence.check(await fence.begin(entered: entered)), RingCheck.signedOut);
    expect(await fence.check(await fence.begin()), RingCheck.current);
  });

  test('entering takes no pass; begun after a newer pass, it is superseded', () async {
    final RingTicket app = await fence.begin();
    final RingTicket entered = await fence.enter();
    // Entering (then a failed read) leaves the app's pass current (G11).
    expect(await fence.check(app), RingCheck.current);
    // A pass that began after the entry planned from a newer read (F4).
    final RingTicket newer = await fence.begin();
    expect(await fence.check(await fence.begin(entered: entered)), RingCheck.superseded);
    expect(await fence.check(newer), RingCheck.current);
    // With no pass since the entry, it begins and is current.
    final RingTicket again = await fence.enter();
    final RingTicket worker = await fence.begin(entered: again);
    expect(await fence.check(worker), RingCheck.current);
    expect(await fence.check(newer), RingCheck.superseded);
  });
}
