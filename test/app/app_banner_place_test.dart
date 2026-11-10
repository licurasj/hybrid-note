// Where the banner sits (owner, 2026-11-09): just above the AI bar and as wide
// as it on a phone, moving with it; where the bar would be without it; never
// on the hub.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/app_banner.dart';
import 'package:hybrid_note/app/app_theme.dart';

void main() {
  const Size screen = Size(393, 852);

  test('just above the bar, exactly as wide as it', () {
    final place = bannerPlace(
      screen: screen,
      keyboard: 0,
      inset: 24,
      room: const BannerRoom(bar: Rect.fromLTRB(12, 764, 290, 816)),
    );
    expect(place.fill, isTrue);
    expect(place.left, 12);
    expect(place.width, 290 - 12);
    expect(place.bottom, 852 - 764 + AppBannerHost.gap);
  });

  test('moves up with the bar, the same gap above it', () {
    final low = bannerPlace(
      screen: screen,
      keyboard: 0,
      inset: 24,
      room: const BannerRoom(bar: Rect.fromLTRB(12, 764, 290, 816)),
    );
    final high = bannerPlace(
      screen: screen,
      keyboard: 300,
      inset: 24,
      room: const BannerRoom(bar: Rect.fromLTRB(12, 440, 381, 508)),
    );
    expect(high.bottom - low.bottom, 764 - 440);
    expect(high.width, 381 - 12);
  });

  test('without the bar, as wide as the bar would be, above the inset', () {
    final place = bannerPlace(
      screen: screen,
      keyboard: 0,
      inset: 24,
      room: const BannerRoom(laneLeft: 12, laneRight: 290),
    );
    expect(place.left, 12);
    expect(place.width, 290 - 12);
    expect(place.bottom, 24 + AppBannerHost.restGap);
    final typing = bannerPlace(
      screen: screen,
      keyboard: 300,
      inset: 24,
      room: const BannerRoom(laneLeft: 12, laneRight: 290),
    );
    expect(typing.bottom, 300 + 24 + AppBannerHost.restGap);
  });

  test('with nothing known, between the side margins', () {
    final place = bannerPlace(screen: screen, keyboard: 0, inset: 24);
    expect(place.left, AppShapes.sideMargin);
    expect(place.width, 393 - 2 * AppShapes.sideMargin);
  });

  test('a hub on its right: the same left edge, ending before the hub', () {
    final Rect hub = Rect.fromCircle(
      center: const Offset(340, 790),
      radius: 46,
    );
    final place = bannerPlace(
      screen: screen,
      keyboard: 0,
      inset: 24,
      room: BannerRoom(hub: hub, laneLeft: 12, laneRight: 381),
    );
    expect(place.left, 12);
    expect(place.left + place.width, lessThanOrEqualTo(hub.left));
    expect(place.bottom, 24 + AppBannerHost.restGap);
  });

  test('a hub on its left: above the hub, the same left edge', () {
    final Rect hub = Rect.fromCircle(center: const Offset(53, 790), radius: 46);
    final place = bannerPlace(
      screen: screen,
      keyboard: 0,
      inset: 24,
      room: BannerRoom(hub: hub, laneLeft: 12, laneRight: 381),
    );
    expect(place.left, 12);
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
      room: BannerRoom(hub: hub, laneLeft: 12, laneRight: 381),
    );
    expect(place.bottom, 24 + AppBannerHost.restGap);
    expect(place.width, 381 - 12);
  });

  test('on a wide screen, as wide as its words up to a limit, for now', () {
    final place = bannerPlace(
      screen: const Size(1024, 768),
      keyboard: 0,
      inset: 0,
      room: const BannerRoom(
        bar: Rect.fromLTRB(212, 704, 812, 756),
        laneLeft: 212,
        laneRight: 812,
        wide: true,
      ),
    );
    expect(place.fill, isFalse);
    expect(place.left, 212);
    expect(place.width, AppBannerHost.maxWidth);
  });
}
