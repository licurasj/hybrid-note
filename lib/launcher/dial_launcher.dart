import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/app_theme.dart';
import '../app_colors.dart';
import '../lists/list_icons.dart';
import 'launcher_geometry.dart';
import 'radial_launcher.dart' show LauncherNote, LauncherWedgePainter;

// Test hook for trying the dial with many lists on a phone without touching
// an account's data: a demo entry point (tool/demo_lists_main.dart) fills it
// before the app starts. These entries open and edit nothing. Empty in the
// app itself.
final List<LauncherNote> debugDialExtraNotes = [];

// The launcher as a dial (owner's design, T-16 unit 6, 2026-10-30 to
// 2026-11-03). Petal-shaped tabs in the list's colour stand around the hub;
// the most recent list opens on the screen's diagonal, reaching halfway to
// the far corner. The tab under the finger is selected and grows (owner,
// 2026-11-03: the finger always selects in the middle). At either end of
// the lists the outermost list and half the next are a scroll zone while
// more lists lie beyond: a finger held there scrolls the lists in, faster
// the deeper it is, and the list it is on (never the outermost) is
// selected as it comes into the hand. New list and Home (inside a list)
// ride at the two ends of the lists and stop as far out as they can without
// crossing the lines that continue the hub's outer edges along the screen,
// which leaves the lists more room. Far off the dial nothing is selected and
// letting go cancels. Rest the finger on a list and Edit slides out from
// behind its end; a short swipe outwards (wherever the finger is) selects
// it. Rest on the hub for Move.
//
// A quick tap on the hub (or Enter/Space on it, or a screen reader's tap)
// opens tap mode: tap a tab to open it, long-press or right-click to edit;
// the arrows (and the arrow keys) step through every entry, turning the dial
// to it; Enter opens and E edits the selected one; Esc closes.
class DialLauncher extends StatefulWidget {
  const DialLauncher({
    super.key,
    required this.notes,
    required this.onOpen,
    required this.onEdit,
    this.onNew,
    this.onHome,
    this.hubPosition,
    this.onHubMoved,
    this.config = const LauncherConfig(),
    this.hubTooltip = 'Lists',
    this.addLabel = 'New list',
    this.homeLabel = 'Home',
    this.editLabel = 'Edit',
    this.moveLabel = 'Move',
    this.previousLabel = 'Previous',
    this.nextLabel = 'Next',
    this.noteHint = 'Double-tap to open, long-press to edit',
    this.onOpenChanged,
  });

  final List<LauncherNote> notes;
  final ValueChanged<LauncherNote> onOpen;
  final ValueChanged<LauncherNote> onEdit;
  final VoidCallback? onNew;
  final VoidCallback? onHome;
  final Offset? hubPosition;
  final ValueChanged<Offset>? onHubMoved;
  final LauncherConfig config;
  final String hubTooltip;
  final String addLabel;
  final String homeLabel;
  final String editLabel;
  final String moveLabel;
  final String previousLabel;
  final String nextLabel;
  final String noteHint;
  // Told when the dial opens (pressed, tap mode or moving) and when it is
  // closed again, after the frame (T-19 unit 4: the AI bar keeps the hub
  // raised until then).
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<DialLauncher> createState() => _DialLauncherState();
}

enum _Mode { closed, hold, tap, moving }

enum _Kind { home, note, add }

class _Entry {
  const _Entry(this.kind, [this.note]);

  final _Kind kind;
  final LauncherNote? note;

  // Stays the same while the catalog changes around it.
  String get key => switch (kind) {
        _Kind.add => 'add',
        _Kind.home => 'home',
        _Kind.note => 'note:${note!.id}',
      };

  bool get isDemo => note != null && debugDialExtraNotes.contains(note);
}

class _DialLauncherState extends State<DialLauncher>
    with SingleTickerProviderStateMixin {
  _Mode _mode = _Mode.closed;
  late final Ticker _ticker;
  Duration _now = Duration.zero;
  Duration _lastTick = Duration.zero;
  Duration _openedAt = Duration.zero;
  final FocusNode _focusNode = FocusNode(debugLabel: 'DialLauncher');

  // New list first, the lists, then Home (inside a list); rebuilt only when
  // the notes or onHome change.
  List<_Entry> _entries = const [];

  Offset? _pointer;
  bool _leftHub = false;
  Offset? _restAnchor;
  Duration _restStart = Duration.zero;

  // The dial: which entry is selected; where it stands (the list position
  // on the diagonal), easing towards where scrolling has taken it; where the
  // emphasis is, easing towards the selected entry; and how far the selected
  // tab has grown (0 to 1).
  int? _selected;
  double _position = 0;
  double _scroll = 0;
  double _focus = 0;
  double _zoom = 0;
  // Which scroll zone the finger is in (-1 side, 1 bottom, 0 neither).
  int _edge = 0;
  // How fast the finger turns around the hub (radians a second, towards the
  // bottom edge positive), smoothed, and when and where it last moved.
  double _turnSpeed = 0;
  Duration? _turnAt;
  double _turnAngle = 0;

  // Where New list and Home stop (their outer sides), for this geometry.
  Object? _limitsKey;
  (double, double) _limits = (0, 0);

  // Edit or Move prompt.
  bool _editShown = false;
  bool _moveShown = false;
  Offset _promptAnchor = Offset.zero;
  Duration _promptAt = Duration.zero;
  double _progress = 0;
  bool _promptSelected = false;

  Offset? _movedHub;
  Offset _moveGrab = Offset.zero;

  LauncherGeometry? _geometry;

  LauncherConfig get _config => widget.config;
  double get _step => _config.dialStepDegrees * math.pi / 180;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _entries = _entriesOf(widget);
  }

  @override
  void didUpdateWidget(DialLauncher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hubPosition != widget.hubPosition) {
      _movedHub = null;
    }
    if (oldWidget.notes != widget.notes ||
        (oldWidget.onHome == null) != (widget.onHome == null)) {
      _reconcile(_entriesOf(widget));
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  bool _reportedOpen = false;

  void _reportOpen() {
    final bool open = _mode != _Mode.closed;
    final ValueChanged<bool>? report = widget.onOpenChanged;
    if (open == _reportedOpen) {
      return;
    }
    _reportedOpen = open;
    if (report != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => report(open));
    }
  }

  List<_Entry> _entriesOf(DialLauncher w) => [
        const _Entry(_Kind.add),
        for (final LauncherNote note in [...w.notes, ...debugDialExtraNotes])
          _Entry(_Kind.note, note),
        if (w.onHome != null) const _Entry(_Kind.home),
      ];

  // The catalog changed (another device, a sync) while the dial may be open:
  // keep the same entry selected and the dial where it stood, by entry
  // rather than by position; if the selected entry is gone, let it go.
  void _reconcile(List<_Entry> entries) {
    final List<_Entry> old = _entries;
    _entries = entries;
    int indexOf(String key) => entries.indexWhere((e) => e.key == key);
    final int? selected = _selected;
    if (selected != null && selected < old.length) {
      final int now = indexOf(old[selected].key);
      if (now >= 0) {
        _position += now - selected;
        _scroll += now - selected;
        _focus += now - selected;
        _selected = now;
      } else {
        _selected = _mode == _Mode.tap && _notes > 0 ? _firstList : null;
        _editShown = false;
      }
    } else {
      _selected = null;
    }
    double clampList(double x) =>
        x.clamp(_firstList.toDouble(), _lastList.toDouble()).toDouble();
    _position = clampList(_position);
    _scroll = clampList(_scroll);
  }

  int get _notes => _entries.length - (widget.onHome != null ? 2 : 1);

  // The most recent list stands on the diagonal when the dial opens.
  int get _firstList => _notes == 0 ? 0 : 1;
  int get _lastList => _notes;

  bool _isFixed(int index) => _entries[index].kind != _Kind.note;

  // New list and Home take a list's angle.
  double get _fixedWidth => _step;

  // --- Geometry, in the corner frame of LauncherGeometry -------------------

  (double, double) _frameHub(LauncherGeometry g) => (
        g.flipX ? g.size.width - g.hubCenter.dx : g.hubCenter.dx,
        g.flipY ? g.size.height - g.hubCenter.dy : g.hubCenter.dy,
      );

  // The screen diagonal from the hub to the far corner.
  double _diagonal(LauncherGeometry g) {
    final (double x, double y) = _frameHub(g);
    return math.atan2(y, -x);
  }

  double _halfDiagonal(LauncherGeometry g) {
    final (double x, double y) = _frameHub(g);
    return math.sqrt(x * x + y * y) / 2;
  }

  // Frame angle and distance of a screen point from the hub.
  (double, double) _polar(LauncherGeometry g, Offset point) {
    final double dx = (point.dx - g.hubCenter.dx) * (g.flipX ? -1 : 1);
    final double dy = (point.dy - g.hubCenter.dy) * (g.flipY ? -1 : 1);
    double angle = math.atan2(-dy, dx);
    if (angle < -math.pi / 2) {
      angle += 2 * math.pi;
    }
    return (angle, math.sqrt(dx * dx + dy * dy));
  }

  // Whether a finger is on the dial: within the quarter (or a little past
  // its edges, where holding scrolls) and not far beyond the longest tab.
  bool _onDial(LauncherGeometry g, double angle, double radius) {
    final double past = _config.dialOffDialDegrees * math.pi / 180;
    return angle >= math.pi / 2 - past &&
        angle <= math.pi + past &&
        radius <= _halfDiagonal(g) + 48;
  }

  // Angle offset from the diagonal of a point x lists away from the dial's
  // position; the selected entry gets dialSelectedSpread times the room.
  double _offset(double x) {
    final double selected =
        _step * (1 + (_config.dialSelectedSpread - 1) * _zoom);
    if (x.abs() <= 0.5) {
      return x * selected;
    }
    return x.sign * (selected / 2 + (x.abs() - 0.5) * _step);
  }

  // Where list `index` stands on the dial (its two sides). Later lists lie
  // towards the bottom (or top) edge, where the quarter has the most room
  // past the diagonal.
  (double, double) _turning(LauncherGeometry g, double index) {
    final double diagonal = _diagonal(g);
    final double d = index - _position;
    return (diagonal + _offset(d + 0.5), diagonal + _offset(d - 0.5));
  }

  // The lines that continue the hub's outer edges along the screen, which
  // New list and Home (at their longest) do not cross (owner, 2026-11-03):
  // the lowest angle of New list's outer side and the highest of Home's.
  (double, double) _edgeLimits(LauncherGeometry g) {
    final Object key = (g.size, g.hubCenter, _config);
    if (key == _limitsKey) {
      return _limits;
    }
    final double inner = _config.innerRadius;
    final double outer = _halfDiagonal(g);
    final double w = _fixedWidth;
    // How far a petal reaches towards the side edge (x) and the bottom
    // edge (y), from the hub's centre, as drawn (the tabs stand 7 and 4 dp
    // in from it, on the middle of the hub's two discs).
    (double, double) reach((double, double) sides) {
      final double Function(double) halfAt =
          _halfWidth(sides, inner, outer, 1);
      double x = -double.infinity;
      double y = -double.infinity;
      for (final Offset p in _outlinePoints(g, sides, inner, outer, halfAt)) {
        x = math.max(x, (p.dx - g.hubCenter.dx) * (g.flipX ? -1 : 1) - 7);
        y = math.max(y, (p.dy - g.hubCenter.dy) * (g.flipY ? -1 : 1) - 4);
      }
      return (x, y);
    }

    final double line = _config.hubRadius;
    double lo = math.pi / 2 - 0.8;
    double hi = math.pi / 2 + 0.8;
    for (int i = 0; i < 24; i++) {
      final double mid = (lo + hi) / 2;
      if (reach((mid + w, mid)).$1 > line) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final double addLow = hi;
    lo = math.pi - 0.8;
    hi = math.pi + 0.8;
    for (int i = 0; i < 24; i++) {
      final double mid = (lo + hi) / 2;
      if (reach((mid, mid - w)).$2 > line) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    _limitsKey = key;
    _limits = (addLow, lo);
    return _limits;
  }

  // The edges: where New list stops (its inner side) and where Home stops
  // (its inner side); the finger past either is at that edge.
  double _listsLow(LauncherGeometry g) => _edgeLimits(g).$1 + _fixedWidth;
  double _listsHigh(LauncherGeometry g) => _edgeLimits(g).$2 - _fixedWidth;

  // New list's sides: just before the first list, stopping at its limit.
  (double, double) _addSides(LauncherGeometry g) {
    final double start = _turning(g, _firstList.toDouble()).$2;
    final double low = _edgeLimits(g).$1;
    final double end = math.max(low, start - _fixedWidth);
    return (end + _fixedWidth, end);
  }

  // Home's sides: just after the last list, stopping at its limit.
  (double, double) _homeSides(LauncherGeometry g) {
    final double end = _turning(g, _lastList.toDouble()).$1;
    final double high = _edgeLimits(g).$2;
    final double start = math.min(high, end + _fixedWidth);
    return (start, start - _fixedWidth);
  }

  // An entry's two sides, the lists cut off where they meet New list and
  // Home; null when nothing of it shows.
  (double, double)? _sides(LauncherGeometry g, int index) {
    switch (_entries[index].kind) {
      case _Kind.add:
        return _addSides(g);
      case _Kind.home:
        return _homeSides(g);
      case _Kind.note:
        break;
    }
    final (double turnStart, double turnEnd) = _turning(g, index.toDouble());
    final double high =
        widget.onHome != null ? _homeSides(g).$2 : _edgeLimits(g).$2;
    final double start = math.min(high, turnStart);
    final double end = math.max(_addSides(g).$1, turnEnd);
    // A sliver cut off by New list or Home is not shown.
    return start - end > 0.3 * _step ? (start, end) : null;
  }

  // The far end of the lists' room: where Home stops, or the bottom edge's
  // limit on the home screen (no Home).
  double _roomHigh(LauncherGeometry g) =>
      widget.onHome != null ? _listsHigh(g) : _edgeLimits(g).$2;

  // The scroll zones: the outermost list and half the next at either end of
  // the lists' room (owner, 2026-11-03), and everything past them.
  double _zoneLow(LauncherGeometry g) =>
      _listsLow(g) + _config.dialEdgeZone * _step;
  double _zoneHigh(LauncherGeometry g) =>
      _roomHigh(g) - _config.dialEdgeZone * _step;

  // A finger swiping fast along the arc towards an end reaches that end's
  // zone sooner: it reaches as far ahead as the finger would turn in
  // dialEdgeLead, up to dialEdgeReach more steps.
  double _zoneAhead(int side) {
    final double toward = side < 0 ? -_turnSpeed : _turnSpeed;
    final double lead = _config.dialEdgeLead.inMicroseconds / 1e6;
    return (toward * lead).clamp(0, _config.dialEdgeReach * _step).toDouble();
  }

  // Whether lists still lie in or beyond a zone, to scroll in. Not once the
  // scroll is at its end that way: the end list then sits in the zone but
  // cannot come further, and is picked and edited like any other (owner,
  // 2026-11-04: the first list next to New list offered no Edit).
  bool _more(LauncherGeometry g, int side) {
    final double diagonal = _diagonal(g);
    return side < 0
        ? _scroll > _firstList + 1e-3 &&
              diagonal + (_firstList - _scroll) * _step < _zoneLow(g) - 1e-3
        : _scroll < _lastList - 1e-3 &&
              diagonal + (_lastList - _scroll) * _step > _zoneHigh(g) + 1e-3;
  }

  // The list in the hand while in a zone: the one under the finger, but
  // never the outermost one shown at that end, which only scrolls.
  int _inHand(LauncherGeometry g, double angle) {
    final double diagonal = _diagonal(g);
    int index = (_position + (angle - diagonal) / _step).round();
    if (_edge < 0) {
      final int outer =
          (_position - 0.5 + (_listsLow(g) - diagonal) / _step).floor() + 1;
      index = math.max(index, outer + 1);
    } else if (_edge > 0) {
      final int outer =
          (_position + 0.5 + (_roomHigh(g) - diagonal) / _step).ceil() - 1;
      index = math.min(index, outer - 1);
    }
    return index.clamp(_firstList, _lastList);
  }

  // 1 for the selected entry, less with distance from it.
  double _emphasis(int index) {
    if (_selected == index) {
      return lerpDouble(_config.dialFarLength, 1, _zoom)!;
    }
    final double near = _config.dialNeighbourLength;
    final double far = _config.dialFarLength;
    // New list and Home grow only when selected themselves.
    final double d = _isFixed(index)
        ? math.max(2, (index - _focus).abs())
        : (index - _focus).abs();
    final double profile = d <= 1
        ? lerpDouble(1, near, d)!
        : lerpDouble(near, far, math.min(1, d - 1))!;
    return far + (profile - far) * _zoom;
  }

  // 0 far from the selected entry, 1 on it.
  double _closeness(int index) {
    final double far = _config.dialFarLength;
    return ((_emphasis(index) - far) / (1 - far)).clamp(0, 1).toDouble();
  }

  double _grow() {
    if (_mode == _Mode.tap || _reduceMotion) {
      return 1;
    }
    final double t =
        (_now - _openedAt).inMicroseconds / AppMotion.standard.inMicroseconds;
    return AppMotion.curve.transform(t.clamp(0, 1).toDouble());
  }

  double _inner() => lerpDouble(
        _config.hubRadius * 0.4,
        _config.innerRadius,
        _grow(),
      )!;

  // A tab's end: its share of half the diagonal, but never off the screen
  // (with room for Edit past a list's end), now that the selected tab can be
  // anywhere in the fan rather than on the diagonal.
  double _outer(LauncherGeometry g, int index, double angle) {
    final double full = _halfDiagonal(g) - _config.innerRadius;
    final double outer =
        _inner() + full * _emphasis(index) * lerpDouble(0.18, 1, _grow())!;
    final (double x, double y) = _frameHub(g);
    // Towards the far side edge and the far top (or bottom) edge; the tabs
    // stand 7 and 4 dp in from the hub's centre.
    final double across = -math.cos(angle);
    final double up = math.sin(angle);
    double room = double.infinity;
    if (across > 1e-6) {
      room = math.min(room, (x - 7) / across);
    }
    if (up > 1e-6) {
      room = math.min(room, (y - 4) / up);
    }
    final double margin = _isFixed(index) ? 16 : 16 + _config.dialEditDepth;
    return math.min(outer, math.max(_inner() + 48, room - margin));
  }

  double _reveal() => _reduceMotion
      ? 1
      : AppMotion.curve.transform(
          ((_now - _promptAt).inMicroseconds /
                  _config.revealDuration.inMicroseconds)
              .clamp(0, 1)
              .toDouble(),
        );

  // The entry whose tab holds a frame angle, or the nearest shown one.
  int? _entryAt(LauncherGeometry g, double angle) {
    int? nearest;
    double best = double.infinity;
    for (int i = 0; i < _entries.length; i++) {
      final (double, double)? sides = _sides(g, i);
      if (sides == null) {
        continue;
      }
      if (angle <= sides.$1 && angle >= sides.$2) {
        return i;
      }
      final double gap =
          math.min((angle - sides.$1).abs(), (angle - sides.$2).abs());
      if (gap < best) {
        best = gap;
        nearest = i;
      }
    }
    return nearest;
  }

  double _towards(Offset finger, Offset from, Offset target) {
    const double hit = 26;
    final double remaining = (finger - target).distance;
    if (remaining <= hit) {
      return 1;
    }
    final double total = math.max((from - target).distance - hit, 1);
    return (1 - (remaining - hit) / total).clamp(0, 1).toDouble();
  }

  // --- Gestures -------------------------------------------------------------

  void _close() {
    _ticker.stop();
    setState(() {
      _mode = _Mode.closed;
      _selected = null;
      _zoom = 0;
      _editShown = false;
      _moveShown = false;
      _pointer = null;
    });
  }

  void _select(int? index) {
    if (index == _selected) {
      return;
    }
    _selected = index;
    _editShown = false;
    _restStart = _now;
    if (index != null) {
      HapticFeedback.selectionClick();
    }
  }

  // Keeps the ticker running for easing and timing; it stops by itself in
  // tap mode once the dial has settled.
  void _wake() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _now = Duration.zero;
      _openedAt = -AppMotion.standard;
      _promptAt = -_config.revealDuration;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final double seconds = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _now = elapsed;
    final LauncherGeometry? g = _geometry;
    final Offset? pointer = _pointer;

    // The dial turns to where scrolling has taken it, and the emphasis moves
    // to the selected entry (AppMotion.quick).
    final double t = _reduceMotion
        ? 1
        : 1 - math.exp(-seconds * 3e6 / AppMotion.quick.inMicroseconds);
    // The finger's turning speed fades once it stops moving.
    _turnSpeed *= math.exp(-seconds / 0.1);
    final int? selected = _selected;
    final double focusTarget = selected?.toDouble() ?? _focus;
    final double zoomTarget = selected == null ? 0 : 1;
    final double position = _position + (_scroll - _position) * t;
    final double focus = _focus + (focusTarget - _focus) * t;
    final double zoom = _zoom + (zoomTarget - _zoom) * t;
    final bool moving = (position - _position).abs() > 1e-4 ||
        (focus - _focus).abs() > 1e-4 ||
        (zoom - _zoom).abs() > 1e-4;
    final bool animating = moving ||
        _now - _openedAt <= AppMotion.standard ||
        (_editShown && _now - _promptAt <= _config.revealDuration);
    _position = moving ? position : _scroll;
    _focus = moving ? focus : focusTarget;
    _zoom = moving ? zoom : zoomTarget;

    bool changed = animating;
    if (_mode == _Mode.hold && g != null && pointer != null) {
      changed = _scrollAtEdge(g, pointer, seconds) || changed;
      changed = _offerPrompt(g, pointer) || changed;
    }
    if (changed) {
      setState(() {});
    } else if (_mode == _Mode.tap) {
      _ticker.stop();
    }
  }

  // A finger held in a scroll zone scrolls the lists in, smoothly and faster
  // the deeper it is, selecting the list coming into the hand; with no lists
  // left that way the zone ends and the tab under the finger (New list or
  // Home at the very end) is selected.
  bool _scrollAtEdge(LauncherGeometry g, Offset pointer, double seconds) {
    final int? selected = _selected;
    if (_edge == 0 || selected == null || _isFixed(selected)) {
      return false;
    }
    final (double angle, double _) = _polar(g, pointer);
    if (!_more(g, _edge)) {
      _edge = 0;
      _select(_pointed(g, angle));
      return true;
    }
    // 0 at the zone's inner border, 1 from the outermost list's far side.
    final double depth = (_edge < 0
            ? (_zoneLow(g) - angle) / (_zoneLow(g) - _listsLow(g))
            : (angle - _zoneHigh(g)) / (_roomHigh(g) - _zoneHigh(g)))
        .clamp(0, 1)
        .toDouble();
    // A swipe carries on at the finger's own speed if that is faster.
    final double swipe =
        math.max(0, _edge * _turnSpeed) / _step * _config.dialEdgeCarry;
    final double speed = math.max(
      lerpDouble(_config.dialEdgeSpeedMin, _config.dialEdgeSpeedMax, depth)!,
      swipe,
    );
    _scroll = (_scroll + _edge * speed * seconds)
        .clamp(_firstList.toDouble(), _lastList.toDouble())
        .toDouble();
    // The dial follows the scroll directly, so the lists flow steadily.
    _position = _scroll;
    _select(_inHand(g, angle));
    return true;
  }

  // After a rest: Edit on a list (not while at an edge, where the hold
  // scrolls), or Move on the hub.
  bool _offerPrompt(LauncherGeometry g, Offset pointer) {
    if (_editShown ||
        _moveShown ||
        _now - _restStart < _config.promptDelay) {
      return false;
    }
    final int? selected = _selected;
    final (double _, double radius) = _polar(g, pointer);
    if (selected != null &&
        _entries[selected].kind == _Kind.note &&
        !_entries[selected].isDemo &&
        radius > _config.hubRadius &&
        _edge == 0) {
      _editShown = true;
    } else if (selected == null &&
        !_leftHub &&
        widget.onHubMoved != null) {
      _moveShown = true;
    } else {
      return false;
    }
    _promptAnchor = pointer;
    _promptAt = _now;
    _progress = 0;
    _promptSelected = false;
    return true;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_mode == _Mode.tap) {
      _close();
      return;
    }
    _lastTick = Duration.zero;
    _now = Duration.zero;
    _ticker
      ..stop()
      ..start();
    setState(() {
      _mode = _Mode.hold;
      _openedAt = _now;
      _pointer = event.position;
      _leftHub = false;
      _restAnchor = event.position;
      _restStart = _now;
      _selected = null;
      _position = _firstList.toDouble();
      _scroll = _position;
      _focus = _position;
      _zoom = 0;
      _editShown = false;
      _moveShown = false;
      _edge = 0;
      _turnSpeed = 0;
      _turnAt = null;
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    final LauncherGeometry? g = _geometry;
    if (g == null) {
      return;
    }
    if (_mode == _Mode.moving) {
      setState(() {
        _movedHub = LauncherGeometry.clampHub(
          _config,
          g.size,
          event.position + _moveGrab,
        );
      });
      return;
    }
    if (_mode != _Mode.hold) {
      return;
    }

    final Offset finger = event.position;
    final (double angle, double radius) = _polar(g, finger);
    final bool onHub = radius <= _config.hubRadius;
    final Duration? last = _turnAt;
    if (last != null && event.timeStamp > last && !onHub) {
      final double seconds = (event.timeStamp - last).inMicroseconds / 1e6;
      final double speed = (angle - _turnAngle) / seconds;
      _turnSpeed += (speed - _turnSpeed) * math.min(1, seconds / 0.05);
    }
    _turnAt = event.timeStamp;
    _turnAngle = angle;
    setState(() {
      _pointer = finger;
      if (!onHub) {
        _leftHub = true;
      }
      if ((finger - (_restAnchor ?? finger)).distance >
          _config.moveTolerance) {
        _restAnchor = finger;
        _restStart = _now;
      }

      if (_moveShown) {
        final Offset target = g.movePromptCenter;
        _progress = _towards(finger, _promptAnchor, target);
        _promptSelected = _promptSelected
            ? _progress >= _config.promptUnselectAt
            : _progress >= _config.promptSelectAt;
        if (_promptSelected) {
          // The hub follows the finger from here; nothing else animates.
          _ticker.stop();
          _mode = _Mode.moving;
          _moveShown = false;
          _movedHub = g.hubCenter;
          _moveGrab = g.hubCenter - finger;
          HapticFeedback.mediumImpact();
        }
        return;
      }

      // Far off the dial: nothing is selected, and letting go cancels.
      if (!onHub && !_onDial(g, angle, radius)) {
        _select(null);
        _edge = 0;
        return;
      }

      if (_editShown) {
        // Edit is on the selected tab, which the finger may not be over
        // after turning the dial: the swipe counts outwards distance only.
        final (double anchorAngle, double anchorRadius) =
            _polar(g, _promptAnchor);
        _progress = ((radius - anchorRadius) / _config.dialEditSwipe)
            .clamp(0, 1)
            .toDouble();
        final bool was = _promptSelected;
        _promptSelected = was
            ? _progress >= _config.promptUnselectAt
            : _progress >= _config.promptSelectAt;
        if (_promptSelected && !was) {
          HapticFeedback.selectionClick();
        }
        // Pulling back in or turning away lets Edit go; the dial turns again.
        if (radius < anchorRadius - 30 ||
            (angle - anchorAngle).abs() > 1.5 * _step) {
          _editShown = false;
        }
        return;
      }

      if (onHub) {
        _select(null);
        _edge = 0;
        return;
      }
      _followEdge(g, angle);
    });
  }

  // In the middle the tab under the finger is selected; in a scroll zone the
  // list in the hand is, and holding scrolls (see _scrollAtEdge). New list
  // or Home pointed at straight from the hub stays picked while the finger
  // is on it.
  void _followEdge(LauncherGeometry g, double angle) {
    final double leave = _config.dialEdgeLeave * _step;
    final double low = _zoneLow(g) + _zoneAhead(-1);
    final double high = _zoneHigh(g) - _zoneAhead(1);
    int edge = switch (_edge) {
      -1 => angle < low + leave ? -1 : 0,
      1 => angle > high - leave ? 1 : 0,
      _ => angle < low ? -1 : (angle > high ? 1 : 0),
    };
    if (edge != 0 && !_more(g, edge)) {
      edge = 0;
    }
    _edge = edge;
    final int? selected = _selected;
    if (selected != null && _isFixed(selected)) {
      final (double, double)? sides = _sides(g, selected);
      final double keep = _config.dialSelectKeep * _step;
      if (sides != null &&
          angle <= sides.$1 + keep &&
          angle >= sides.$2 - keep) {
        return;
      }
    }
    if (_edge == 0 || selected == null) {
      _select(_pointed(g, angle));
    } else {
      _select(_inHand(g, angle));
    }
  }

  // The tab under the finger, keeping the selected one until the finger is
  // a little past its sides, so a border does not flicker.
  int? _pointed(LauncherGeometry g, double angle) {
    final int? current = _selected;
    if (current != null) {
      final (double, double)? sides = _sides(g, current);
      final double keep = _config.dialSelectKeep * _step;
      if (sides != null &&
          angle <= sides.$1 + keep &&
          angle >= sides.$2 - keep) {
        return current;
      }
    }
    return _entryAt(g, angle);
  }

  void _act(_Entry entry) {
    switch (entry.kind) {
      case _Kind.home:
        widget.onHome?.call();
      case _Kind.add:
        widget.onNew?.call();
      case _Kind.note:
        if (!entry.isDemo) {
          widget.onOpen(entry.note!);
        }
    }
  }

  void _edit(_Entry entry) {
    if (entry.note != null && !entry.isDemo) {
      widget.onEdit(entry.note!);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final LauncherGeometry? g = _geometry;
    if (_mode == _Mode.moving) {
      _ticker.stop();
      final Offset? dropped = _movedHub;
      setState(() => _mode = _Mode.closed);
      if (g != null && dropped != null) {
        widget.onHubMoved?.call(
          Offset(dropped.dx / g.size.width, dropped.dy / g.size.height),
        );
      }
      return;
    }
    if (_mode != _Mode.hold || g == null) {
      return;
    }
    final bool quickTap = !_leftHub &&
        !_moveShown &&
        _now - _openedAt <= _config.tapMaxDuration;
    if (quickTap) {
      _openTapMode();
      return;
    }

    final int? selected = _selected;
    final bool edit = _editShown && _promptSelected;
    final (double angle, double radius) = _polar(g, event.position);
    final bool onDial = _onDial(g, angle, radius);
    final List<_Entry> entries = _entries;
    _close();
    if (selected == null || selected >= entries.length) {
      return;
    }
    final _Entry entry = entries[selected];
    if (edit) {
      _edit(entry);
    } else if (radius > _config.hubRadius && onDial) {
      _act(entry);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_mode == _Mode.hold || _mode == _Mode.moving) {
      _close();
    }
  }

  // --- Tap mode and keyboard ------------------------------------------------

  void _openTapMode() {
    setState(() {
      _mode = _Mode.tap;
      _selected = _firstList;
      _position = _firstList.toDouble();
      _scroll = _position;
      _focus = _position;
      _zoom = 1;
      _editShown = false;
      _moveShown = false;
    });
    _wake();
    _focusNode.requestFocus();
  }

  // Steps the selection through every entry (New list, the lists, Home);
  // the dial turns to it.
  void _stepTap(int direction) {
    final int? selected = _selected;
    if (selected == null) {
      return;
    }
    final int next = (selected + direction).clamp(0, _entries.length - 1);
    if (next == selected) {
      return;
    }
    setState(() {
      _selected = next;
      _scroll = next.clamp(_firstList, _lastList).toDouble();
    });
    _wake();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    final bool activate = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space;
    if (_mode == _Mode.closed) {
      if (activate) {
        _openTapMode();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_mode != _Mode.tap) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      _stepTap(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      _stepTap(1);
      return KeyEventResult.handled;
    }
    final int? selected = _selected;
    if (selected == null) {
      return KeyEventResult.ignored;
    }
    final _Entry entry = _entries[selected];
    if (activate) {
      _close();
      _act(entry);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyE && entry.note != null) {
      _close();
      _edit(entry);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --- Drawing --------------------------------------------------------------

  // Half the tab's width at a distance from the hub (beyond its end too,
  // for Edit, which continues the tab).
  double Function(double) _halfWidth(
    (double, double) sides,
    double inner,
    double outer,
    double zoom,
  ) {
    final double root = _config.dialTabRoot;
    final double end = math.min(
      _config.dialTabCap + _config.dialTabGrow * zoom,
      (sides.$1 - sides.$2) * outer * 0.92,
    );
    return (double a) =>
        (root + (end - root) * (a - inner) / math.max(outer - inner, 1)) / 2;
  }

  // A tab's outline (the owner's pick of two shape experiments, 2026-11-03:
  // the petal) along the middle of `sides`, from `from` to `to`: a slim
  // wedge, narrow at the hub and widening to its share of the fan but no
  // more than a cap, so the gaps between tabs close without a tab getting
  // wide, with a round end.
  (Rect, List<Offset>) _outline(
    LauncherGeometry g,
    (double, double) sides,
    double from,
    double to,
    double Function(double) halfAt,
  ) {
    final List<Offset> outline = _outlinePoints(g, sides, from, to, halfAt);
    Rect bounds = Rect.fromPoints(outline.first, outline.first);
    for (final Offset point in outline) {
      bounds = bounds.expandToInclude(Rect.fromPoints(point, point));
    }
    bounds = bounds.inflate(2);
    return (bounds, [for (final Offset p in outline) p - bounds.topLeft]);
  }

  List<Offset> _outlinePoints(
    LauncherGeometry g,
    (double, double) sides,
    double from,
    double to,
    double Function(double) halfAt,
  ) {
    final double angle = (sides.$1 + sides.$2) / 2;
    final Offset origin = g.pointAt(angle, 0);
    final Offset along = g.pointAt(angle, 1) - origin;
    final Offset across = Offset(-along.dy, along.dx);
    final double half = halfAt(to);
    final double r = math.min(half, (to - from) / 2);
    final List<(double, double)> end = [
      for (int i = 0; i <= 12; i++)
        (
          to - r + r * math.cos(-math.pi / 2 + i * math.pi / 12),
          half * math.sin(-math.pi / 2 + i * math.pi / 12),
        ),
    ];
    final List<(double, double)> local = [
      (from, -halfAt(from)),
      ...end,
      (from, halfAt(from)),
    ];
    return [
      for (final (double a, double c) in local) origin + along * a + across * c,
    ];
  }

  // A text's height at the user's text size.
  double _lineHeight(TextScaler scaler, double fontSize) =>
      scaler.scale(fontSize) * 1.3 + 4;

  List<Widget> _entryWidgets(LauncherGeometry g, int index) {
    final (double, double)? sides = _sides(g, index);
    if (sides == null) {
      return const [];
    }
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final _Entry entry = _entries[index];
    final bool selected = _selected == index;
    final double angle = (sides.$1 + sides.$2) / 2;
    final double inner = _inner();
    final double outer = _outer(g, index, angle);
    final double zoom = _closeness(index);
    final double Function(double) halfAt =
        _halfWidth(sides, inner, outer, zoom);
    final (Rect bounds, List<Offset> outline) =
        _outline(g, sides, inner, outer, halfAt);

    // The tab takes its list's colour (New list blue, Home the text colour);
    // the disc is a ground-coloured hole with the icon in that colour.
    final (Color fill, IconData icon, String label) = switch (entry.kind) {
      _Kind.note => (
          resolveListColor(entry.note!.color, brightness),
          entry.note!.icon,
          entry.note!.label,
        ),
      _Kind.add => (AppColors.appBlue, Icons.add, widget.addLabel),
      _Kind.home => (neutrals.text, Icons.home_outlined, widget.homeLabel),
    };

    Widget wedge = CustomPaint(
      size: bounds.size,
      painter: LauncherWedgePainter(
        outline: outline,
        fill: fill,
        edge: neutrals.ground,
        shadow: selected,
        scale: outer,
      ),
    );
    if (_mode == _Mode.tap) {
      final bool editable = entry.note != null && !entry.isDemo;
      wedge = Semantics(
        button: true,
        selected: selected,
        label: entry.note?.semanticsLabel ?? label,
        hint: editable ? widget.noteHint : null,
        onTap: () {
          _close();
          _act(entry);
        },
        onLongPress: editable
            ? () {
                _close();
                _edit(entry);
              }
            : null,
        excludeSemantics: true,
        child: GestureDetector(
          // The fan's keys, so callers and tests reach entries the same way.
          key: ValueKey(switch (entry.kind) {
            _Kind.note => 'launcher-note-${entry.note!.id}',
            _Kind.add => 'launcher-add',
            _Kind.home => 'launcher-home',
          }),
          onTap: () {
            _close();
            _act(entry);
          },
          onLongPress: editable
              ? () {
                  _close();
                  _edit(entry);
                }
              : null,
          onSecondaryTap: editable
              ? () {
                  _close();
                  _edit(entry);
                }
              : null,
          child: wedge,
        ),
      );
    }

    final double discSize = 28 + 8 * zoom;
    final double fontSize = 15 + 6 * zoom;
    // The icon and name keep clear of the tab's end.
    final double end = outer - 18;
    final double labelEnd = end - discSize - 14;
    // The name at the user's text size where the petal is wide enough for
    // a useful length of it, else as large as fits, never smaller than its
    // design size; the tab carries the full name for screen readers. Text
    // starts where the tab is wide enough for it.
    double clearFor(double size) {
      double clear = _config.hubRadius + 22;
      while (clear < outer &&
          2 * halfAt(clear) < _lineHeight(TextScaler.noScaling, size)) {
        clear += 4;
      }
      return clear;
    }

    double shownSize = scaler.scale(fontSize);
    while (shownSize > fontSize &&
        labelEnd - math.max(inner, clearFor(shownSize)) < 72) {
      shownSize = math.max(fontSize, shownSize - 1);
    }
    final double lineHeight = _lineHeight(TextScaler.noScaling, shownSize);
    final double labelLength =
        math.min(labelEnd - math.max(inner, clearFor(shownSize)), 260);
    final double labelStart = labelEnd - labelLength;
    final bool outward = g.readsOutward(angle);
    final Offset labelCenter = g.pointAt(angle, (labelStart + labelEnd) / 2);
    final Offset discCenter = g.pointAt(angle, end - discSize / 2);
    final bool fits = 2 * halfAt(labelEnd) >= lineHeight;

    return [
      Positioned(
        key: ValueKey('dial-entry-$index'),
        left: bounds.left,
        top: bounds.top,
        child: wedge,
      ),
      // The name and icon are drawn on the tab; the tab itself carries the
      // full name for screen readers.
      if (labelLength > 30 && fits)
        Positioned(
          left: labelCenter.dx - labelLength / 2,
          top: labelCenter.dy - lineHeight / 2,
          width: labelLength,
          height: lineHeight,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Transform.rotate(
                angle: g.tabRotation(angle),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: outward ? TextAlign.right : TextAlign.left,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontFamily: AppFonts.sans,
                    fontSize: shownSize,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onColor(fill),
                  ),
                ),
              ),
            ),
          ),
        ),
      if (outer - inner > discSize + 20)
        Positioned(
          left: discCenter.dx - discSize / 2,
          top: discCenter.dy - discSize / 2,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Container(
                width: discSize,
                height: discSize,
                decoration: BoxDecoration(
                  color: neutrals.ground,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: discSize * 0.6, color: fill),
              ),
            ),
          ),
        ),
    ];
  }

  // Edit: a further piece of the selected tab beyond its end, sliding out
  // from behind it and filling with a deeper shade of the list's colour (the
  // tab already has the list's colour). Drawn under the tabs.
  List<Widget> _editWidgets(LauncherGeometry g) {
    final int? selected = _selected;
    if (!_editShown || selected == null) {
      return const [];
    }
    final (double, double)? sides = _sides(g, selected);
    final LauncherNote? note = _entries[selected].note;
    if (sides == null || note == null) {
      return const [];
    }
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final Color listColor = resolveListColor(note.color, brightness);
    final Color fill = Color.lerp(
      neutrals.promptDark,
      Color.lerp(listColor, Colors.black, 0.35)!,
      _progress,
    )!;
    final double angle = (sides.$1 + sides.$2) / 2;
    final double reveal = _reveal();
    // Edit continues the tab from behind its end (its inner part stays
    // hidden under the tab) and slides out as it is revealed.
    final double inner = _inner();
    final double outer = _outer(g, selected, angle);
    final double Function(double) halfAt =
        _halfWidth(sides, inner, outer, _closeness(selected));
    final double shown =
        _config.dialEditDepth * (1 + 0.22 * _progress) * reveal;
    final double tuck = halfAt(outer) + 2;
    final (Rect bounds, List<Offset> outline) = _outline(
      g,
      sides,
      outer - tuck,
      outer + math.max(shown, 1),
      halfAt,
    );
    final Offset center = g.pointAt(angle, outer + shown / 2);
    final TextStyle style = TextStyle(
      fontFamily: AppFonts.sans,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppColors.onColor(fill),
    );
    final TextPainter painter = TextPainter(
      text: TextSpan(text: widget.editLabel, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final double labelWidth = painter.width + 8;
    final double labelHeight = _lineHeight(scaler, 15);
    painter.dispose();
    return [
      Positioned(
        key: const ValueKey('dial-edit'),
        left: bounds.left,
        top: bounds.top,
        child: CustomPaint(
          size: bounds.size,
          painter: LauncherWedgePainter(
            outline: outline,
            fill: fill,
            edge: neutrals.ground,
            shadow: true,
            scale: shown,
          ),
        ),
      ),
      if (reveal > 0.6)
        Positioned(
          left: center.dx - labelWidth / 2,
          top: center.dy - labelHeight / 2,
          width: labelWidth,
          height: labelHeight,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: g.tabRotation(angle),
              child: Text(
                widget.editLabel,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
          ),
        ),
    ];
  }

  Widget _movePrompt(LauncherGeometry g) {
    final AppNeutrals neutrals =
        AppColors.neutrals(Theme.of(context).brightness);
    final Color fill =
        Color.lerp(neutrals.promptDark, AppColors.appBlue, _progress)!;
    final Offset center = g.movePromptCenter;
    return Positioned(
      key: const ValueKey('launcher-move-prompt'),
      left: center.dx - 50,
      top: center.dy - 20,
      width: 100,
      height: 40,
      child: Center(
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              widget.moveLabel,
              maxLines: 1,
              style: TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.onColor(fill),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Tap mode's arrows, just past the selected tab's end on either side,
  // pointing the way the dial turns.
  Widget _arrow(LauncherGeometry g, int direction) {
    final int? selected = _selected;
    final bool enabled = selected != null &&
        (direction < 0 ? selected > 0 : selected < _entries.length - 1);
    final double angle = _diagonal(g) + direction * 0.42;
    final double radius = _halfDiagonal(g) * 0.92;
    final Offset spot = g.pointAt(angle, radius);
    // The way a point turning towards larger angles moves on screen.
    final Offset turn = g.pointAt(angle + direction * 0.01, radius) - spot;
    final AppNeutrals neutrals =
        AppColors.neutrals(Theme.of(context).brightness);
    // A round button on the ground colour, so it reads over the screen.
    return Positioned(
      left: spot.dx - 24,
      top: spot.dy - 24,
      child: Material(
        color: neutrals.ground,
        shape: CircleBorder(side: BorderSide(color: neutrals.line)),
        elevation: 2,
        child: IconButton(
          key: ValueKey(direction < 0 ? 'launcher-prev' : 'launcher-next'),
          tooltip: direction < 0 ? widget.previousLabel : widget.nextLabel,
          onPressed: enabled ? () => _stepTap(direction) : null,
          color: neutrals.text,
          icon: Transform.rotate(
            angle: math.atan2(turn.dy, turn.dx),
            child: const Icon(Icons.arrow_forward),
          ),
        ),
      ),
    );
  }

  Widget _hub(LauncherGeometry g) {
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final double size = _config.hubRadius * 2;
    final Border ring = Border.all(
      color: neutrals.ground,
      width: 2.5,
      strokeAlign: BorderSide.strokeAlignOutside,
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: g.flipX ? 14 : -14,
            top: g.flipY ? 8 : -8,
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.appBlue,
                shape: BoxShape.circle,
                border: ring,
              ),
            ),
          ),
          Container(
            key: const ValueKey('launcher-hub'),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: neutrals.text,
              shape: BoxShape.circle,
              border: ring,
              boxShadow: AppShadows.floating(brightness),
            ),
            child: _mode == _Mode.moving
                ? Icon(Icons.open_with, color: neutrals.ground)
                : null,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _reportOpen();
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size size = constraints.biggest;
        final Offset? saved = widget.hubPosition;
        final LauncherGeometry g = LauncherGeometry(
          config: _config,
          size: size,
          noteCount: widget.notes.length,
          hubPosition: _movedHub ??
              (saved == null
                  ? null
                  : Offset(saved.dx * size.width, saved.dy * size.height)),
        );
        _geometry = g;
        final bool open = _mode == _Mode.hold || _mode == _Mode.tap;
        final int count = _entries.length;
        // Far entries first, the selected one last (on top).
        final List<int> order = [for (int i = 0; i < count; i++) i]
          ..sort(
            (a, b) => (b - _focus).abs().compareTo((a - _focus).abs()),
          );
        final double hub = _config.hubRadius;

        return Focus(
          focusNode: _focusNode,
          onKeyEvent: _onKey,
          // The hub and the tabs are the screen reader's nodes.
          includeSemantics: false,
          child: Stack(
            children: [
              if (_mode == _Mode.tap)
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('launcher-barrier'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: const SizedBox.expand(),
                  ),
                ),
              // The tabs stand on the middle of the hub's two discs.
              if (open)
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(g.flipX ? 7 : -7, g.flipY ? 4 : -4),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ..._editWidgets(g),
                        for (final int i in order) ..._entryWidgets(g, i),
                      ],
                    ),
                  ),
                ),
              if (_mode == _Mode.tap && count > 1) ...[
                _arrow(g, -1),
                _arrow(g, 1),
              ],
              if (_moveShown) _movePrompt(g),
              Positioned(
                left: g.hubCenter.dx - hub,
                top: g.hubCenter.dy - hub,
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: Semantics(
                    button: true,
                    label: widget.hubTooltip,
                    // A screen reader's tap opens (or closes) tap mode.
                    onTap: () => open ? _close() : _openTapMode(),
                    child: AnimatedScale(
                      scale: _mode == _Mode.moving ? 1.12 : 1,
                      duration:
                          _reduceMotion ? Duration.zero : AppMotion.standard,
                      curve: AppMotion.curve,
                      child: _hub(g),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
