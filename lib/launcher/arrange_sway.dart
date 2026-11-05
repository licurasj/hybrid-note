import 'dart:math' as math;

// The slow sway of things that can be dragged in an arrange state (Q-49, owner
// 2026-11-05; the dial now, home's Rearrange in T-22): each one leans gently
// from side to side, a little out of step with its neighbours. Callers skip it
// under reduced motion. Amount and speed are being tuned with the owner on the
// phone; the period is here, the amount with each caller.
const Duration arrangeSwayPeriod = Duration(milliseconds: 2600);

// From -1 to 1 at [now], for the thing at [index].
double arrangeSway(Duration now, int index) {
  final double turns =
      now.inMicroseconds / arrangeSwayPeriod.inMicroseconds + index * 0.15;
  return math.sin(2 * math.pi * turns);
}
