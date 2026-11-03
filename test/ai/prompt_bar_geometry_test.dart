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
}
