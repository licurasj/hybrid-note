import 'dart:math' as math;
import 'dart:ui';

// Tunable numbers for the launchers (plan section 5). They need tuning on a
// real phone (Q-3), so they all live here. The dial (DialLauncher, the
// default since T-16 unit 6) uses the hub, prompt and tap settings and the
// dial* ones; the fan settings below are for RadialLauncher, kept behind
// --dart-define=FAN_LAUNCHER=true.
//
// Fan layout, described for a hub nearest the bottom-right corner: list tabs
// fan out to the hub's upper left as wedges that share the quarter between
// them. The fan starts `startMarginDegrees` above the bottom edge (the first
// wedge lies along it) and turns clockwise until `endMarginDegrees` before
// the right edge. The tab under the finger widens and pushes its neighbours
// aside (`selectedSpread`). The last `addDegrees` of the fan are the New list
// ("+") wedge and, while a list is open, the first `homeDegrees` are the Home
// wedge; neither scrolls. Tabs start behind the hub. For a hub nearer another
// corner the whole layout is mirrored so the fan always opens away from that
// corner.
class LauncherConfig {
  const LauncherConfig({
    this.hubRadius = 32,
    this.defaultHubInsetX = 56,
    this.defaultHubInsetY = 72,
    this.screenMargin = 48,
    this.addDegrees = 12,
    this.homeDegrees = 12,
    this.startMarginDegrees = 0,
    this.endMarginDegrees = 0,
    this.overscrollDegrees = 20,
    this.innerRadius = 24,
    this.tabLength = 150,
    this.visibleTabs = 4,
    this.promptDelay = const Duration(milliseconds: 1200),
    this.revealDuration = const Duration(milliseconds: 250),
    this.editGap = 4,
    this.editDepth = 36,
    this.promptHitRadius = 26,
    this.promptSelectAt = 0.8,
    this.promptUnselectAt = 0.6,
    this.moveTolerance = 8,
    this.endZoneFraction = 0.15,
    this.maxScrollSpeed = 4,
    this.tapMaxDuration = const Duration(milliseconds: 250),
    this.selectedTabScale = 1.3,
    this.neighbourTabScale = 1.08,
    this.selectedSpread = 2.0,
    this.dialStepDegrees = 12,
    this.dialSelectedSpread = 1.0,
    this.dialNeighbourLength = 0.8,
    this.dialFarLength = 0.68,
    this.dialTabRoot = 16,
    this.dialTabCap = 56,
    this.dialTabGrow = 14,
    this.dialSelectKeep = 0.15,
    this.dialEdgeLeave = 0.25,
    this.dialEdgeDelay = const Duration(milliseconds: 350),
    this.dialEdgeInterval = const Duration(milliseconds: 280),
    this.dialEdgeFastest = const Duration(milliseconds: 110),
    this.dialOffDialDegrees = 30,
    this.dialEditDepth = 40,
    this.dialEditSwipe = 28,
  });

  final double hubRadius;
  // Where the hub starts before the user moves it, measured from the
  // bottom-right corner.
  final double defaultHubInsetX;
  final double defaultHubInsetY;
  // A moved hub stays at least this far from every screen edge (and never
  // closer than its own disc and the blue one behind it allow).
  final double screenMargin;
  // Angles of the New list wedge at the end of the fan and the Home wedge at
  // its start.
  final double addDegrees;
  final double homeDegrees;
  // Gaps between the fan and the edge it starts from (bottom or top) and the
  // edge it ends at (right or left).
  final double startMarginDegrees;
  final double endMarginDegrees;
  // Past either end of the fan, this far still scrolls it.
  final double overscrollDegrees;
  // Tabs start at this distance from the hub centre (behind the hub when
  // smaller than hubRadius) and run outward.
  final double innerRadius;
  final double tabLength;
  // Tabs shown across the fan at once.
  final int visibleTabs;
  // How long a finger must rest (on a tab, or on the hub) before the Edit or
  // Move prompt appears (interaction law, coordination/docs/INTERACTIONS.md).
  final Duration promptDelay;
  // How long a prompt takes to slide out from under its element.
  final Duration revealDuration;
  // The Edit prompt is a further piece of its tab's wedge: this far past the
  // selected tab's outer end, and this deep.
  final double editGap;
  final double editDepth;
  // A finger this close to a prompt's centre has reached it.
  final double promptHitRadius;
  // Progress at which a prompt counts as selected, and below which it lets go
  // again (the gap avoids flicker).
  final double promptSelectAt;
  final double promptUnselectAt;
  // Movement (logical pixels) that still counts as resting.
  final double moveTolerance;
  // Share of the fan at each end that auto-scrolls.
  final double endZoneFraction;
  // Auto-scroll speed at the very end of a zone, in tabs per second.
  final double maxScrollSpeed;
  // A press released on the hub faster than this opens tap mode.
  final Duration tapMaxDuration;
  // The tab under the finger is the biggest and its neighbours grow a little,
  // scaled from their hub end (docs/AESTHETICS.md, Motion).
  final double selectedTabScale;
  final double neighbourTabScale;
  // The selected tab's angle compared with an unselected one; its neighbours
  // widen a little too and the rest give up the room.
  final double selectedSpread;

  // The dial (owner's choices on the phone, T-16 unit 6, 2026-10-30 to
  // 2026-11-03). Each tab takes this angle, the selected one this many times
  // as much (1: no wider, owner 2026-11-03). The selected tab reaches half
  // the screen diagonal; its neighbours and the rest reach these shares of
  // that.
  final double dialStepDegrees;
  final double dialSelectedSpread;
  final double dialNeighbourLength;
  final double dialFarLength;
  // Petal widths: at the hub, the cap at the end, and how much the selected
  // tab's cap adds.
  final double dialTabRoot;
  final double dialTabCap;
  final double dialTabGrow;
  // The selected tab stays selected until the finger is this many steps
  // past its sides.
  final double dialSelectKeep;
  // At an edge the hold keeps stepping: first after the delay, then every
  // interval, shortening to the fastest. Leaving an edge takes this many
  // steps more, so the selection does not flicker on its border.
  final double dialEdgeLeave;
  final Duration dialEdgeDelay;
  final Duration dialEdgeInterval;
  final Duration dialEdgeFastest;
  // Further than this past either edge (or past the longest tab) the finger
  // is off the dial: nothing is selected, and letting go cancels.
  final double dialOffDialDegrees;
  // Edit shows this far beyond the selected tab's end; a swipe this far
  // outwards selects it.
  final double dialEditDepth;
  final double dialEditSwipe;

  double get outerRadius => innerRadius + tabLength;
}

enum LauncherTargetKind { none, hub, note, add, home }

class LauncherTarget {
  const LauncherTarget(this.kind, [this.noteIndex]);

  static const LauncherTarget none = LauncherTarget(LauncherTargetKind.none);
  static const LauncherTarget hub = LauncherTarget(LauncherTargetKind.hub);
  static const LauncherTarget add = LauncherTarget(LauncherTargetKind.add);
  static const LauncherTarget home = LauncherTarget(LauncherTargetKind.home);

  final LauncherTargetKind kind;
  // Index into the full tab strip (not the visible slot).
  final int? noteIndex;

  @override
  bool operator ==(Object other) {
    return other is LauncherTarget &&
        other.kind == kind &&
        other.noteIndex == noteIndex;
  }

  @override
  int get hashCode => Object.hash(kind, noteIndex);
}

// Computes everything in a frame where the nearest corner is bottom-right,
// then flips points back to the screen. Angles are radians in that frame,
// 0 = pointing right, positive = up (screen y grows down).
class LauncherGeometry {
  LauncherGeometry({
    required this.config,
    required this.size,
    required this.noteCount,
    Offset? hubPosition,
    this.focus,
    this.focusAmount = 1,
    this.showHome = false,
  }) : hubCenter = clampHub(config, size, hubPosition ?? defaultHub(config, size));

  final LauncherConfig config;
  final Size size;
  final int noteCount;
  final Offset hubCenter;
  // The selected tab's slot (index minus scroll offset, may be fractional
  // while it moves) and how far the fan has spread around it, 0 to 1. Null
  // keeps every tab the same width.
  final double? focus;
  final double focusAmount;
  // Whether the fan starts with the Home wedge (a list is open).
  final bool showHome;

  static const double _degree = math.pi / 180;

  static Offset defaultHub(LauncherConfig config, Size size) {
    return Offset(
      size.width - config.defaultHubInsetX,
      size.height - config.defaultHubInsetY,
    );
  }

  // Keeps the hub and the blue disc behind it on screen.
  static Offset clampHub(LauncherConfig config, Size size, Offset hub) {
    final double margin = math.max(config.screenMargin, config.hubRadius + 16);
    return Offset(
      hub.dx.clamp(margin, math.max(margin, size.width - margin)).toDouble(),
      hub.dy.clamp(margin, math.max(margin, size.height - margin)).toDouble(),
    );
  }

  // Which corner the hub is nearest decides the mirroring.
  bool get flipX => hubCenter.dx < size.width / 2;
  bool get flipY => hubCenter.dy < size.height / 2;

  Offset _flip(Offset point) {
    return Offset(
      flipX ? size.width - point.dx : point.dx,
      flipY ? size.height - point.dy : point.dy,
    );
  }

  Offset get _hubFrame => _flip(hubCenter);

  double get startAngle => math.pi - config.startMarginDegrees * _degree;
  double get endAngle => math.pi / 2 + config.endMarginDegrees * _degree;
  // Where the lists begin (after the Home wedge, when shown) and end (where
  // the New list wedge begins).
  double get listStartAngle =>
      startAngle - (showHome ? config.homeDegrees * _degree : 0);
  double get listEndAngle => endAngle + config.addDegrees * _degree;
  double get _span => listStartAngle - listEndAngle;

  // The Home wedge's sides and the middle of it (meaningful with showHome).
  (double, double) get homeSides => (startAngle, listStartAngle);

  Offset get homeCenter => pointAt(
        (startAngle + listStartAngle) / 2,
        config.innerRadius + config.tabLength / 2,
      );

  // The New list wedge's sides and the middle of it.
  (double, double) get addSides => (listEndAngle, endAngle);

  Offset get addCenter => pointAt(
        (listEndAngle + endAngle) / 2,
        config.innerRadius + config.tabLength / 2,
      );

  // Outer end of the selected tab, which is scaled up from its hub end.
  double get selectedOuterRadius =>
      config.innerRadius + config.tabLength * config.selectedTabScale;

  // Middle of the Edit segment when nothing pulls it in.
  double get editRadius =>
      selectedOuterRadius + config.editGap + config.editDepth / 2;

  // Edit prompt: just past the outer end of the (selected, enlarged) tab,
  // along its spoke; pulled in along the spoke when that is off screen.
  Offset editPromptCenter(double angle) {
    const double margin = 40;
    bool fits(Offset point) =>
        point.dx >= margin &&
        point.dx <= size.width - margin &&
        point.dy >= margin &&
        point.dy <= size.height - margin;
    double radius = editRadius;
    while (!fits(pointAt(angle, radius)) && radius > selectedOuterRadius) {
      radius -= 2;
    }
    return _keepOnScreen(pointAt(angle, radius));
  }

  // Move prompt: below and inward of the hub in the corner frame, under the
  // first wedge (which lies along the hub's level), clear of the hub itself.
  Offset get movePromptCenter {
    return _keepOnScreen(
      _flip(_hubFrame + Offset(-(config.hubRadius + 40), 40)),
    );
  }

  Offset _keepOnScreen(Offset point) {
    const double margin = 24;
    return Offset(
      point.dx.clamp(margin, math.max(margin, size.width - margin)).toDouble(),
      point.dy.clamp(margin, math.max(margin, size.height - margin)).toDouble(),
    );
  }

  int get slotCount => math.max(1, config.visibleTabs);

  double get maxScrollOffset => math.max(0, noteCount - slotCount).toDouble();

  double get _step => _span / slotCount;

  // The spread around the focus is a triangular bump in angular density over
  // slot coordinates (0 = start of the fan, slotCount = end): the focused
  // tab gets `selectedSpread` times the room of a far one. _bumpArea is the
  // bump's integral up to x.
  static const double _bumpWidth = 1.5;

  // Over its own slot the focused tab gets 1 - 1 / (4 x _bumpWidth) of the
  // bump's peak, so the peak is raised to make the ratio come out exact.
  double get _bumpHeight => focus == null
      ? 0
      : (config.selectedSpread - 1) / (1 - 1 / (4 * _bumpWidth)) * focusAmount;

  double _bumpArea(double x) {
    final double u = (x - (focus ?? 0) - 0.5) / _bumpWidth;
    if (u <= -1) {
      return 0;
    }
    if (u <= 0) {
      return _bumpWidth * (1 + u) * (1 + u) / 2;
    }
    if (u < 1) {
      return _bumpWidth * (1 - (1 - u) * (1 - u) / 2);
    }
    return _bumpWidth;
  }

  // Maps an even slot coordinate to where it lands once the fan has spread
  // around the focus; both ends of the fan stay put.
  double _warp(double x) {
    final double k = _bumpHeight;
    if (k == 0) {
      return x;
    }
    final double total =
        slotCount + k * (_bumpArea(slotCount.toDouble()) - _bumpArea(0));
    return (x + k * (_bumpArea(x) - _bumpArea(0))) * slotCount / total;
  }

  double _unwarp(double warped) {
    if (_bumpHeight == 0) {
      return warped;
    }
    double low = -slotCount.toDouble();
    double high = 2.0 * slotCount;
    for (int i = 0; i < 40; i++) {
      final double mid = (low + high) / 2;
      if (_warp(mid) < warped) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return (low + high) / 2;
  }

  // Frame angle of a slot coordinate.
  double _edgeAngle(double x) => listStartAngle - _warp(x) * _step;

  // Frame angle of a (possibly fractional) slot's centre line.
  double slotAngle(double slot) => _edgeAngle(slot + 0.5);

  // Frame angles of a tab's two sides (towards the start, towards the end),
  // cut off at the ends of the fan; null when nothing of it is in view.
  (double, double)? tabSides(int noteIndex, double scrollOffset) {
    final double slot = noteIndex - scrollOffset;
    final double from = math.max(0, slot);
    final double to = math.min(slotCount.toDouble(), slot + 1);
    if (to - from <= 0.02) {
      return null;
    }
    return (_edgeAngle(from), _edgeAngle(to));
  }

  // Length scale of the tab in a (possibly fractional) slot: the focused one
  // the most, its neighbours a little, the rest not at all.
  double tabScale(double slot) {
    final double? focused = focus;
    if (focused == null) {
      return 1;
    }
    final double d = (slot - focused).abs();
    final double scale = d <= 1
        ? lerpDouble(config.selectedTabScale, config.neighbourTabScale, d)!
        : lerpDouble(config.neighbourTabScale, 1, math.min(1, d - 1))!;
    return 1 + (scale - 1) * focusAmount;
  }

  Offset pointAt(double angle, double radius) {
    return _flip(
      _hubFrame + Offset(math.cos(angle), -math.sin(angle)) * radius,
    );
  }

  // Unit vector on screen pointing from the hub outward along a spoke.
  Offset _outward(double angle) {
    return Offset(
      (flipX ? -1 : 1) * math.cos(angle),
      (flipY ? 1 : -1) * math.sin(angle),
    );
  }

  // True when a tab's text reads from the hub outward, false when it reads
  // towards the hub; whichever keeps the text left-to-right.
  bool readsOutward(double angle) => _outward(angle).dx >= 0;

  // Screen rotation (clockwise radians) laying a tab along its spoke with
  // its text upright.
  double tabRotation(double angle) {
    final Offset out = _outward(angle);
    final Offset reading = readsOutward(angle) ? out : -out;
    return math.atan2(reading.dy, reading.dx);
  }

  // Middle of the part of a tab that is in view, or null when none is.
  double? tabAngle(int noteIndex, double scrollOffset) {
    final (double, double)? sides = tabSides(noteIndex, scrollOffset);
    return sides == null ? null : (sides.$1 + sides.$2) / 2;
  }

  // Centre of a tab in the strip, or null when scrolled out of view.
  Offset? tabCenter(int noteIndex, double scrollOffset) {
    final double? angle = tabAngle(noteIndex, scrollOffset);
    return angle == null
        ? null
        : pointAt(angle, config.innerRadius + config.tabLength / 2);
  }

  // Position along the fan: 0 at the start, 1 at the end; may run past both
  // ends into the margins. Null outside the band the tabs occupy.
  double? fanPosition(Offset point) {
    final Offset local = _flip(point) - _hubFrame;
    final double distance = local.distance;
    if (distance < config.innerRadius - 40 ||
        distance > selectedOuterRadius + 40) {
      return null;
    }

    double angle = math.atan2(-local.dy, local.dx);
    if (angle < -math.pi / 2) {
      angle += 2 * math.pi;
    }
    return (listStartAngle - angle) / _span;
  }

  LauncherTarget hitTest(Offset point, double scrollOffset) {
    if ((point - hubCenter).distance <= config.hubRadius) {
      return LauncherTarget.hub;
    }
    final double? position = fanPosition(point);
    if (position == null) {
      return LauncherTarget.none;
    }
    if (position < 0) {
      return showHome && position >= (listStartAngle - startAngle) / _span
          ? LauncherTarget.home
          : LauncherTarget.none;
    }
    if (position > 1) {
      return position <= (listStartAngle - endAngle) / _span
          ? LauncherTarget.add
          : LauncherTarget.none;
    }

    final int slot =
        _unwarp(position * slotCount).floor().clamp(0, slotCount - 1);
    final int noteIndex = (slot + scrollOffset).round();
    if (noteIndex < 0 || noteIndex >= noteCount) {
      return LauncherTarget.none;
    }
    return LauncherTarget(LauncherTargetKind.note, noteIndex);
  }

  // Auto-scroll velocity (tabs per second): negative near the start of the
  // lists (strongest in the margin beyond them, unless Home is there),
  // positive near their end. The New list and Home wedges never scroll.
  double scrollVelocity(Offset point) {
    final double? position = fanPosition(point);
    if (position == null || maxScrollOffset == 0) {
      return 0;
    }

    final double zone = config.endZoneFraction;
    final double margin = config.overscrollDegrees * _degree / _span;
    if (position < (showHome ? 0 : -margin) || position > 1) {
      return 0;
    }
    if (position < zone) {
      return -config.maxScrollSpeed * math.min(1, 1 - position / zone);
    }
    if (position > 1 - zone) {
      return config.maxScrollSpeed * math.min(1, (position - (1 - zone)) / zone);
    }
    return 0;
  }

  double clampOffset(double offset) {
    return offset.clamp(0, maxScrollOffset).toDouble();
  }
}
