import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/ai/prompt_bar.dart';
import 'package:hybrid_note/launcher/launcher_hub_area.dart';

// The bar's place next to the hub (owner, 2026-11-03): full width unless
// the collapsed hub is in the way, for any hub spot.
void main() {
  const Size phone = Size(360, 780);

  LauncherHubArea hub(Offset? position) =>
      LauncherHubArea(hubPosition: position, child: const SizedBox());

  PromptBarGeometry place(Offset? position, {bool open = false}) =>
      PromptBarGeometry.of(phone, hub: hub(position), panelOpen: open);

  test('the default hub (56/72 dp from the corner): the bar stops short of '
      'it', () {
    final LauncherHubArea area = hub(null);
    final Offset centre = area.hubCenter(phone);
    expect(centre, const Offset(360 - 56, 780 - 72));
    final PromptBarGeometry geometry = place(null);
    expect(geometry.left, PromptBarGeometry.margin);
    expect(
      phone.width - geometry.right,
      centre.dx - area.hubReach - PromptBarGeometry.hubGap,
    );
    expect(geometry.bottom, PromptBarGeometry.margin);
  });

  test('a hub just above the bar (the other default being considered): full '
      'width; the open panel clears it', () {
    // Centre 72 dp + reach above the bar's top.
    const double barTop = PromptBarGeometry.margin + PromptBarGeometry.height;
    final double reach = hub(null).hubReach;
    final Offset above = Offset(
      (360 - 56) / 360,
      (780 - barTop - reach - 4) / 780,
    );
    final PromptBarGeometry closed = place(above);
    expect(closed.left, PromptBarGeometry.margin);
    expect(closed.right, PromptBarGeometry.margin);
    final PromptBarGeometry open = place(above, open: true);
    expect(open.right, greaterThan(PromptBarGeometry.margin));
  });

  test('a hub moved to the bottom left narrows the bar from the left', () {
    final PromptBarGeometry geometry = place(
      const Offset(56 / 360, (780 - 72) / 780),
    );
    expect(geometry.left, greaterThan(100));
    expect(geometry.right, PromptBarGeometry.margin);
  });

  test('a hub in the top half leaves the closed bar at full width', () {
    final PromptBarGeometry geometry = place(const Offset(0.8, 0.2));
    expect(geometry.left, PromptBarGeometry.margin);
    expect(geometry.right, PromptBarGeometry.margin);
  });

  test('without a hub (other hosts) the bar is full width above the system '
      'inset', () {
    final PromptBarGeometry geometry = PromptBarGeometry.of(
      phone,
      bottomInset: 24,
    );
    expect(geometry.left, PromptBarGeometry.margin);
    expect(geometry.right, PromptBarGeometry.margin);
    expect(geometry.bottom, PromptBarGeometry.margin + 24);
  });

  group('rest and focused (owner, 2026-11-03)', () {
    PromptBarGeometry at(Size size, {Offset? hubAt, bool focused = false}) =>
        PromptBarGeometry.of(size, hub: hub(hubAt), focused: focused);

    test('phones up to 430 dp look as before at rest: from the margin to '
        'just short of the hub', () {
      for (final double width in [360, 393, 412, 430]) {
        final Size size = Size(width, 800);
        final PromptBarGeometry g = at(size);
        final double hubX = hub(null).hubCenter(size).dx;
        expect(g.left, PromptBarGeometry.margin, reason: '$width');
        expect(
          width - g.right,
          hubX - hub(null).hubReach - PromptBarGeometry.hubGap,
          reason: '$width',
        );
        expect(g.hubLiftY, isNull);
      }
    });

    test(
      'focused on a phone: full width, the hub raised just above the bar',
      () {
        const Size size = Size(412, 800);
        final PromptBarGeometry g = at(size, focused: true);
        expect(g.left, PromptBarGeometry.margin);
        expect(g.right, PromptBarGeometry.margin);
        final double barTop =
            800 - PromptBarGeometry.margin - PromptBarGeometry.focusedHeight;
        expect(
          g.hubLiftY,
          barTop - PromptBarGeometry.hubGap - hub(null).hubReach,
        );
        // A taller field (four lines) raises it further.
        final PromptBarGeometry tall = PromptBarGeometry.of(
          size,
          hub: hub(null),
          focused: true,
          fieldHeight: 120,
        );
        expect(tall.hubLiftY, lessThan(g.hubLiftY!));
      },
    );

    test('a tablet: at most 600 dp, centred in the space beside the hub; '
        'focused it stays there and the hub does not move', () {
      const Size size = Size(800, 1280);
      final double hubX = hub(null).hubCenter(size).dx;
      final double freeEnd =
          hubX - hub(null).hubReach - PromptBarGeometry.hubGap;
      for (final bool focused in [false, true]) {
        final PromptBarGeometry g = at(size, focused: focused);
        final double width = 800 - g.left - g.right;
        expect(width, PromptBarGeometry.maxWidth);
        expect(
          g.left - PromptBarGeometry.margin,
          closeTo(freeEnd - (800 - g.right), 0.001),
        );
        expect(g.hubLiftY, isNull);
      }
    });

    test('very wide: centred on the screen when the hub is elsewhere', () {
      const Size size = Size(1400, 900);
      final PromptBarGeometry g = at(size, hubAt: const Offset(0.9, 0.2));
      expect(g.left, (1400 - PromptBarGeometry.maxWidth) / 2);
      expect(g.right, g.left);
    });

    test('the hub on the left: the bar keeps to its right at rest; focused '
        'it takes the full width and the hub rises', () {
      const Size size = Size(393, 800);
      const Offset left = Offset(56 / 393, (800 - 72) / 800);
      final PromptBarGeometry rest = at(size, hubAt: left);
      expect(rest.left, greaterThan(100));
      expect(rest.right, PromptBarGeometry.margin);
      final PromptBarGeometry focused = at(size, hubAt: left, focused: true);
      expect(focused.left, PromptBarGeometry.margin);
      expect(focused.right, PromptBarGeometry.margin);
      expect(focused.hubLiftY, isNotNull);
    });

    test('a hub that does not meet the focused bar stays where it is', () {
      final PromptBarGeometry g = at(
        const Size(412, 800),
        hubAt: const Offset(0.8, 0.3),
        focused: true,
      );
      expect(g.hubLiftY, isNull);
    });
  });
}
