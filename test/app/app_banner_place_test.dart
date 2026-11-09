// Where the banner sits (owner, 2026-11-09): just above the AI bar from its
// left edge, moving with it; above the bottom inset without a bar; never on
// the hub.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/app_banner.dart';
import 'package:hybrid_note/app/app_theme.dart';

void main() {
  const Size screen = Size(393, 852);

  test('just above the bar, from its left edge', () {
    final place = bannerPlace(
      screen: screen,
      keyboard: 0,
      inset: 24,
      room: BannerRoom(bar: Rect.fromLTRB(12, 764, 290, 816)),
    );
    expect(place.left, 12);
    expect(place.bottom, 852 - 764 + AppBannerHost.gap);
    expect(place.maxWidth, lessThanOrEqualTo(AppBannerHost.maxWidth));
  });

  test('moves up with the bar, the same gap above it', () {
    final low = bannerPlace(
      screen: screen,
      keyboard: 0,
      inset: 24,
      room: BannerRoom(bar: Rect.fromLTRB(12, 764, 290, 816)),
    );
    final high = bannerPlace(
      screen: screen,
      keyboard: 300,
      inset: 24,
      room: BannerRoom(bar: Rect.fromLTRB(12, 440, 381, 508)),
    );
    expect(high.bottom - low.bottom, 764 - 440);
  });

  test(
    'without a bar, a small gap above the bottom inset and the keyboard',
    () {
      final place = bannerPlace(screen: screen, keyboard: 0, inset: 24);
      expect(place.left, AppShapes.sideMargin);
      expect(place.bottom, 24 + AppBannerHost.restGap);
      final typing = bannerPlace(screen: screen, keyboard: 300, inset: 24);
      expect(typing.bottom, 300 + 24 + AppBannerHost.restGap);
    },
  );

  test('beside the hub when there is room, ending before it', () {
    // No bar, the hub in the bottom right corner.
    final Rect hub = Rect.fromCircle(
      center: const Offset(340, 790),
      radius: 46,
    );
    final place = bannerPlace(
      screen: screen,
      keyboard: 0,
      inset: 24,
      room: BannerRoom(hub: hub),
    );
    expect(place.left, AppShapes.sideMargin);
    expect(place.left + place.maxWidth, lessThanOrEqualTo(hub.left));
    expect(place.bottom, 24 + AppBannerHost.restGap);
  });

  test('beside the hub on the left, starting after it', () {
    final Rect hub = Rect.fromCircle(center: const Offset(53, 790), radius: 46);
    final place = bannerPlace(
      screen: screen,
      keyboard: 0,
      inset: 24,
      room: BannerRoom(hub: hub),
    );
    expect(place.left, greaterThanOrEqualTo(hub.right));
    expect(place.maxWidth, greaterThanOrEqualTo(AppBannerHost.narrowest));
  });

  test('above the hub when beside it is too narrow', () {
    // The hub in the middle of the bottom edge.
    final Rect hub = Rect.fromCircle(
      center: const Offset(196, 790),
      radius: 46,
    );
    final place = bannerPlace(
      screen: screen,
      keyboard: 0,
      inset: 24,
      room: BannerRoom(hub: hub),
    );
    expect(place.bottom, 852 - hub.top + AppBannerHost.gap);
  });

  test('a hub far from the banner changes nothing', () {
    final Rect hub = Rect.fromCircle(
      center: const Offset(340, 300),
      radius: 46,
    );
    final place = bannerPlace(
      screen: screen,
      keyboard: 0,
      inset: 24,
      room: BannerRoom(hub: hub),
    );
    expect(place.bottom, 24 + AppBannerHost.restGap);
    expect(place.left, AppShapes.sideMargin);
  });
}
