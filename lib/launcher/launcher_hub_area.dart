import 'package:flutter/material.dart';

import 'launcher_geometry.dart';

// Tells screens under the floating launcher where its hub sits, so their own
// corner controls (the list screen's add button) can keep clear of it. The
// shell puts it above its navigator; screens without it (tests, other hosts)
// lay out as before.
class LauncherHubArea extends InheritedWidget {
  const LauncherHubArea({
    super.key,
    required this.hubPosition,
    this.config = const LauncherConfig(),
    required super.child,
  });

  // Saved hub centre as a fraction of the screen, as RadialLauncher takes it;
  // null = the default spot.
  final Offset? hubPosition;
  final LauncherConfig config;

  static LauncherHubArea? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LauncherHubArea>();
  }

  // The hub's centre on a screen of `size` (the launcher fills the screen).
  Offset hubCenter(Size size) {
    final Offset? saved = hubPosition;
    return LauncherGeometry(
      config: config,
      size: size,
      noteCount: 0,
      hubPosition: saved == null
          ? null
          : Offset(saved.dx * size.width, saved.dy * size.height),
    ).hubCenter;
  }

  // Room the hub takes around its centre, with the blue disc behind it and
  // its ring.
  double get hubReach => config.hubRadius + 2.5 + 14;

  @override
  bool updateShouldNotify(LauncherHubArea oldWidget) =>
      hubPosition != oldWidget.hubPosition || config != oldWidget.config;
}

// Places a floating button just above the hub (below it when the hub is in
// the top half), centred on it and kept on screen.
class AboveHubButtonLocation extends FloatingActionButtonLocation {
  const AboveHubButtonLocation(this.area);

  final LauncherHubArea area;

  static const double gap = 12;

  // How far up from the screen's bottom the button's top sits, so a list
  // scrolled to its end can keep its last row clear of it; 0 when the button
  // sits below a hub in the top half.
  static double heightAboveBottom(
    LauncherHubArea area,
    Size screen,
    double buttonHeight,
  ) {
    final Offset hub = area.hubCenter(screen);
    if (hub.dy < screen.height / 2) return 0;
    final double top = (hub.dy - area.hubReach - gap - buttonHeight)
        .clamp(0, screen.height - buttonHeight)
        .toDouble();
    return screen.height - top;
  }

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final Size screen = scaffoldGeometry.scaffoldSize;
    final Size button = scaffoldGeometry.floatingActionButtonSize;
    final Offset hub = area.hubCenter(screen);
    final bool below = hub.dy < screen.height / 2;
    final double y = below
        ? hub.dy + area.hubReach + gap
        : hub.dy - area.hubReach - gap - button.height;
    final double x = (hub.dx - button.width / 2)
        .clamp(0, screen.width - button.width)
        .toDouble();
    return Offset(x, y.clamp(0, screen.height - button.height).toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is AboveHubButtonLocation &&
      other.area.hubPosition == area.hubPosition;

  @override
  int get hashCode => area.hubPosition.hashCode;
}
