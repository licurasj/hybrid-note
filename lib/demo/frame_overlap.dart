import 'dart:math' as math;

// How much of the demo's frame the portfolio page's on-screen keyboard
// covers (T-18 unit 5, Q-147). In the portfolio's phone dialog the keyboard
// shrinks the page's visual viewport, not the frame, so the demo sees no
// keyboard of its own. All three values are in the page's layout-viewport
// coordinates (CSS px): [frameBottom] the frame element's bottom edge,
// [viewportTop] and [viewportHeight] the visual viewport's offsetTop and
// height. The part of the frame below the visible area is covered; never
// less than 0.
double frameBottomOverlap({
  required double frameBottom,
  required double viewportTop,
  required double viewportHeight,
}) {
  final double covered = frameBottom - (viewportTop + viewportHeight);
  if (covered.isNaN) {
    return 0;
  }
  return math.max(0, covered);
}
