// The banner comes out from behind the AI bar and goes back behind it (owner,
// 2026-11-09): nothing of it is drawn below the bar's top edge.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/app_banner.dart';

const Size _screen = Size(393, 852);
const Rect _bar = Rect.fromLTRB(12, 764, 290, 816);

Future<AppBannerController> _pump(
  WidgetTester tester, {
  BannerRoom? room,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final AppBannerController controller = AppBannerController()..room = room;
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: AppBannerHost(controller: controller, child: child!),
      ),
      home: const Scaffold(body: SizedBox.expand()),
    ),
  );
  return controller;
}

Finder get _banner => find.byKey(const ValueKey('app-banner'));

// The part of the banner that is drawn: its rect cut by the clip around it.
Rect _drawn(WidgetTester tester) {
  final Rect clip = tester.getRect(
    find.ancestor(of: _banner, matching: find.byType(ClipRect)).first,
  );
  return tester.getRect(_banner).intersect(clip);
}

void main() {
  testWidgets('it slides up from behind the bar to 8 px above it', (
    tester,
  ) async {
    final AppBannerController controller = await _pump(
      tester,
      room: const BannerRoom(bar: _bar),
    );
    controller.show('Cleared', actionLabel: 'Undo', onAction: () {});
    await tester.pump();
    // At the start it is all behind the bar: nothing drawn.
    final Rect start = _drawn(tester);
    expect(start.height <= 0 || start.isEmpty, isTrue);

    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      // Never drawn over the bar.
      expect(_drawn(tester).bottom, lessThanOrEqualTo(_bar.top + 0.01));
    }
    await tester.pumpAndSettle();
    expect(tester.getRect(_banner).bottom, _bar.top - AppBannerHost.gap);

    // It goes back down behind the bar.
    controller.dismiss();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_drawn(tester).bottom, lessThanOrEqualTo(_bar.top + 0.01));
    await tester.pumpAndSettle();
    expect(_banner, findsNothing);
  });

  testWidgets('with no bar it comes up from the bottom edge', (tester) async {
    final AppBannerController controller = await _pump(
      tester,
      room: const BannerRoom(laneLeft: 12, laneRight: 381),
    );
    controller.show('Cleared');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_drawn(tester).bottom, lessThanOrEqualTo(_screen.height));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(_banner).bottom,
      _screen.height - AppBannerHost.restGap,
    );
    controller.dismiss();
    await tester.pumpAndSettle();
  });

  testWidgets('with reduced motion it is just there', (tester) async {
    final AppBannerController controller = await _pump(
      tester,
      room: const BannerRoom(bar: _bar),
      reduceMotion: true,
    );
    controller.show('Cleared');
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(_banner).bottom, _bar.top - AppBannerHost.gap);
    controller.dismiss();
    await tester.pumpAndSettle();
  });
}
