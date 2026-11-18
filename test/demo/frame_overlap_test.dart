import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/demo/frame_overlap.dart';
import 'package:hybrid_note/demo/page_probe.dart';

// The parent page's keyboard over the demo's frame (T-18 unit 5, Q-147).
void main() {
  test('the frame below the visible area is covered', () {
    // A full-screen 844 tall frame; the keyboard leaves 500 visible.
    expect(
      frameBottomOverlap(frameBottom: 844, viewportTop: 0, viewportHeight: 500),
      344,
    );
    // The visual viewport scrolled down by 100 shows 100 more of the frame.
    expect(
      frameBottomOverlap(
        frameBottom: 844,
        viewportTop: 100,
        viewportHeight: 500,
      ),
      244,
    );
  });

  test('never less than 0', () {
    // No keyboard: the whole frame is visible.
    expect(
      frameBottomOverlap(frameBottom: 844, viewportTop: 0, viewportHeight: 844),
      0,
    );
    // A frame shorter than the visible area.
    expect(
      frameBottomOverlap(frameBottom: 600, viewportTop: 0, viewportHeight: 844),
      0,
    );
    expect(
      frameBottomOverlap(
        frameBottom: double.nan,
        viewportTop: 0,
        viewportHeight: 500,
      ),
      0,
    );
  });

  test('off the web there is no parent page to watch', () {
    expect(frameKeyboardInset(), isNull);
  });
}
