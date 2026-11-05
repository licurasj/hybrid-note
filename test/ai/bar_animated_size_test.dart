import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/ai/prompt_bar.dart';

// The AI bar's shadow must not stay cut off in a box after the hub moves: an
// AnimatedSize here is left clipped in about one run in thirty, by a rounding
// error of about 1e-14, when frames come unevenly as on a device.

const Duration _duration = Duration(milliseconds: 180);

Widget _app(GlobalKey key, double right, double height) => MaterialApp(
  home: Scaffold(
    body: Stack(
      children: [
        AnimatedPositioned(
          duration: _duration,
          curve: Curves.easeOutCubic,
          left: 12,
          right: right,
          bottom: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BarAnimatedSize(
                key: key,
                duration: _duration,
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: Container(
                  constraints: BoxConstraints(minHeight: height),
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  ),
);

bool _clips(RenderBox box) {
  try {
    expect(box, paints..clipRect());
    return true;
  } on TestFailure {
    return false;
  }
}

void main() {
  testWidgets('once the width has moved, it is never left clipped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final GlobalKey key = GlobalKey();
    int seed = 1;
    int next() => seed = (seed * 48271) % 2147483647;

    for (int run = 0; run < 400; run++) {
      final double right = 60 + (run % 40) * 1.37;
      await tester.pumpWidget(_app(key, right, 52));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(_app(key, right + 53.137, 52));
      for (int i = 0; i < 30; i++) {
        await tester.pump(Duration(microseconds: 9000 + next() % 16000));
      }
      await tester.pump(const Duration(milliseconds: 500));

      final RenderBox box =
          key.currentContext!.findRenderObject()! as RenderBox;
      expect(_clips(box), isFalse, reason: 'run $run');
    }
  });

  testWidgets('it still clips while really growing, and not once grown', (
    tester,
  ) async {
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(_app(key, 60, 52));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(_app(key, 60, 90));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final RenderBox box = key.currentContext!.findRenderObject()! as RenderBox;
    expect(box.size.height, lessThan(90));
    expect(_clips(box), isTrue);

    await tester.pump(const Duration(milliseconds: 400));
    expect(box.size.height, 90);
    expect(_clips(box), isFalse);
  });
}
