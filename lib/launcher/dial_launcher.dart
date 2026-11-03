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

// Prototype (T-16 unit 6, owner's idea, 2026-10-30): the launcher as a dial.
// Long tabs in a narrow fan turn around the hub so that the selected one
// always lies along the screen's diagonal and reaches halfway to the far
// corner, where the thumb does not cover its name. Pointing at a tab picks
// it and turns it to the diagonal; from there, turning the thumb by one step
// picks the next or previous one (the dial follows, the finger never chases
// it). Later lists lie towards the bottom (or top) edge. New list and Home
// (inside a list) ride at the two ends of the lists and stop at the side and
// bottom edges, so they stay in reach; holding the thumb next to either
// keeps stepping through the lists that way. Tabs take their
// list's colour. Rest the finger and Edit slides out from behind the
// selected tab's end; a short swipe outwards (wherever the finger is)
// selects it. Rest on the hub for Move.
// Same parameters as RadialLauncher.
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

  @override
  State<DialLauncher> createState() => _DialLauncherState();
}

enum _Mode { closed, hold, tap, moving }

// Test switch for the owner's phone (2026-11-03): --dart-define=
// DIAL_DEMO_LISTS=n adds n made-up lists to the dial only, to try scrolling
// without touching the account's data. They open nothing.
const int _demoListCount = int.fromEnvironment('DIAL_DEMO_LISTS');
const List<(String, Color)> _demoLists = [
  ('Books', Color(0xFF3D5AFE)),
  ('Recipes', Color(0xFFE64A19)),
  ('Gifts', Color(0xFFC2185B)),
  ('Travel', Color(0xFF00897B)),
  ('Gym', Color(0xFF5D4037)),
  ('Movies', Color(0xFF7B1FA2)),
  ('Ideas', Color(0xFFF5B800)),
  ('Errands', Color(0xFF2E7D32)),
  ('Garden', Color(0xFF00ACC1)),
  ('Music', Color(0xFFD81B60)),
  ('Packing', Color(0xFF6D4C41)),
  ('Projects', Color(0xFF1E88E5)),
];

enum _Kind { home, note, add }

class _Entry {
  const _Entry(this.kind, [this.note]);

  final _Kind kind;
  final LauncherNote? note;
}

class _DialLauncherState extends State<DialLauncher>
    with SingleTickerProviderStateMixin {
  // Angle per unselected tab, and how many times wider the selected one is.
  static const double _step = 12 * math.pi / 180;
  static const double _spread = 1.25;
  // Edit: how far it shows beyond the tab's end, and how far outwards the
  // finger swipes to select it.
  static const double _editDepth = 40;
  static const double _editSwipe = 28;
  // Tab widths: at the hub, the cap at the end, and how much the selected
  // tab's cap adds.
  static const double _tabRoot = 16;
  static const double _tabCap = 56;
  static const double _tabGrow = 14;
  // Turning the thumb this many steps picks the next tab.
  static const double _jogAt = 0.6;
  // Holding in the end zone (this many steps of the lists' room next to New
  // list or Home) keeps stepping: first after the delay, then every
  // interval, shortening to the fastest.
  static const double _endZone = 0.6;
  static const Duration _endDelay = Duration(milliseconds: 350);
  static const Duration _endInterval = Duration(milliseconds: 280);
  static const Duration _endFastest = Duration(milliseconds: 110);

  _Mode _mode = _Mode.closed;
  late final Ticker _ticker;
  Duration _now = Duration.zero;
  Duration _lastTick = Duration.zero;
  Duration _openedAt = Duration.zero;

  Offset? _pointer;
  bool _leftHub = false;
  Offset? _restAnchor;
  Duration _restStart = Duration.zero;

  // The dial: which entry is selected, where the dial stands (an entry
  // position, easing towards the selected one) and how far the selected tab
  // has grown (0 to 1).
  int? _selected;
  double _position = 0;
  double _zoom = 0;
  // Finger angle the next jog is measured from.
  double _ref = 0;
  // Holding in an end zone: since when, when it last stepped, how often.
  Duration? _endSince;
  Duration _endStepped = Duration.zero;
  int _endSteps = 0;

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

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(DialLauncher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hubPosition != widget.hubPosition) {
      _movedHub = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  // New list comes first, just above the first list (towards the upright
  // edge); Home (inside a list) last, towards the bottom edge, as in the fan.
  List<_Entry> get _entries => [
        const _Entry(_Kind.add),
        for (final LauncherNote note in _notes) _Entry(_Kind.note, note),
        if (widget.onHome != null) const _Entry(_Kind.home),
      ];

  List<LauncherNote> get _notes => [
        ...widget.notes,
        for (int i = 0; i < _demoListCount; i++)
          LauncherNote(
            id: 'demo-$i',
            label: _demoLists[i % _demoLists.length].$1,
            icon: Icons.list,
            color: _demoLists[i % _demoLists.length].$2,
            semanticsLabel: _demoLists[i % _demoLists.length].$1,
          ),
      ];

  // The most recent list stands on the diagonal when the dial opens.
  int get _firstList => _notes.isEmpty ? 0 : 1;
  int get _lastList => _notes.length;

  // New list and Home ride at the two ends of the lists and turn with them;
  // when the lists run past an edge of the corner's quarter they stop there,
  // so both stay in reach (owner, 2026-11-03).
  bool _isFixed(int index) => _entries[index].kind != _Kind.note;

  // Where New list and Home stop: the end zones for scrolling lie next to
  // these.
  double get _listsLow => math.pi / 2 + _step;
  double get _listsHigh => math.pi - (widget.onHome != null ? _step : 0);

  // Whether the finger picked New list or Home where it stopped at an edge
  // (leaving it goes back to the list the dial stands on).
  bool _edgePick = false;

  // Where the dial heads: the selected list, or the nearest list while New
  // list or Home is selected.
  double get _target {
    final int? selected = _selected;
    if (selected == null || _notes.isEmpty) {
      return _position;
    }
    return selected.clamp(_firstList, _lastList).toDouble();
  }

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

  // Angle offset from the diagonal of a point x entries away from the dial's
  // position; the selected entry gets `_spread` times the room.
  double _offset(double x) {
    final double selected = _step * (1 + (_spread - 1) * _zoom);
    if (x.abs() <= 0.5) {
      return x * selected;
    }
    return x.sign * (selected / 2 + (x.abs() - 0.5) * _step);
  }

  // Where an entry would stand on the turning dial. Later entries lie
  // towards the bottom (or top) edge, where the quarter has the most room
  // past the diagonal.
  (double, double) _turning(LauncherGeometry g, int index) {
    final double diagonal = _diagonal(g);
    final double d = index - _position;
    return (diagonal + _offset(d + 0.5), diagonal + _offset(d - 0.5));
  }

  // New list's sides: before the first list, stopping at the side edge.
  (double, double) _addSides(LauncherGeometry g) {
    final (double start, double end) = _turning(g, 0);
    final double push = math.max(0, math.pi / 2 - end);
    return (start + push, end + push);
  }

  bool _addAtEdge(LauncherGeometry g) =>
      _turning(g, 0).$2 <= math.pi / 2 + 0.001;

  // Home's sides: after the last list, stopping at the bottom edge.
  (double, double) _homeSides(LauncherGeometry g) {
    final (double start, double end) = _turning(g, _entries.length - 1);
    final double pull = math.max(0, start - math.pi);
    return (start - pull, end - pull);
  }

  bool _homeAtEdge(LauncherGeometry g) =>
      widget.onHome != null &&
      _turning(g, _entries.length - 1).$1 >= math.pi - 0.001;

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
    final (double turnStart, double turnEnd) = _turning(g, index);
    final double high =
        widget.onHome != null ? _homeSides(g).$2 : math.pi;
    final double start = math.min(high, turnStart);
    final double end = math.max(_addSides(g).$1, turnEnd);
    // A sliver cut off by New list or Home is not shown.
    return start - end > 0.3 * _step ? (start, end) : null;
  }

  // 1 for the selected entry, less with distance from it.
  double _emphasis(int index) {
    if (_isFixed(index) && _selected == index) {
      return 1;
    }
    final double d = (index - _position).abs();
    final double profile = d <= 1
        ? lerpDouble(1, 0.8, d)!
        : lerpDouble(0.8, 0.68, math.min(1, d - 1))!;
    return 0.68 + (profile - 0.68) * _zoom;
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
        widget.config.hubRadius * 0.4,
        widget.config.innerRadius,
        _grow(),
      )!;

  double _outer(LauncherGeometry g, int index) {
    final double full = _halfDiagonal(g) - widget.config.innerRadius;
    return _inner() + full * _emphasis(index) * lerpDouble(0.18, 1, _grow())!;
  }

  // The entry whose wedge holds a frame angle, or the nearest shown one.
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

  void _select(int? index, double angle) {
    if (index == _selected) {
      return;
    }
    _selected = index;
    _ref = angle;
    _editShown = false;
    _restStart = _now;
    if (index != null) {
      HapticFeedback.selectionClick();
    }
  }

  void _onTick(Duration elapsed) {
    final double seconds = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _now = elapsed;
    final LauncherGeometry? g = _geometry;
    final Offset? pointer = _pointer;
    setState(() {
      // The dial turns the selected entry to the diagonal (AppMotion.quick).
      final double t = _reduceMotion
          ? 1
          : 1 - math.exp(-seconds * 3e6 / AppMotion.quick.inMicroseconds);
      final int? selected = _selected;
      if (selected != null) {
        _position += (_target - _position) * t;
      }
      _zoom += ((selected == null ? 0 : 1) - _zoom) * t;

      if (_mode != _Mode.hold || g == null || pointer == null) {
        return;
      }
      _scrollAtEnds(g, pointer);
      if (_editShown ||
          _moveShown ||
          _now - _restStart < widget.config.promptDelay) {
        return;
      }
      final (double _, double radius) = _polar(g, pointer);
      // No Edit while holding in an end zone (that hold scrolls).
      if (selected != null &&
          _entries[selected].kind == _Kind.note &&
          radius > widget.config.hubRadius &&
          _endDirection(g, pointer) == 0) {
        _editShown = true;
        _promptAnchor = pointer;
        _promptAt = _now;
        _progress = 0;
        _promptSelected = false;
      } else if (selected == null &&
          !_leftHub &&
          widget.onHubMoved != null) {
        _moveShown = true;
        _promptAnchor = pointer;
        _promptAt = _now;
        _progress = 0;
        _promptSelected = false;
      }
    });
  }

  // Holding the finger in the end zone next to New list or Home keeps
  // stepping through the lists that way, faster the longer it holds, so many
  // lists need no more room than the corner has.
  void _scrollAtEnds(LauncherGeometry g, Offset pointer) {
    final int? selected = _selected;
    final int direction = _endDirection(g, pointer);
    final (double angle, double _) = _polar(g, pointer);
    final int next = (selected ?? 0) + direction;
    if (direction == 0 || next < _firstList || next > _lastList) {
      _endSince = null;
      _endSteps = 0;
      return;
    }
    final Duration since = _endSince ??= _now;
    final Duration interval = Duration(
      microseconds: math.max(
        _endFastest.inMicroseconds,
        _endInterval.inMicroseconds - _endSteps * 30000,
      ),
    );
    final bool due = _endSteps == 0
        ? _now - since >= _endDelay
        : _now - _endStepped >= interval;
    if (due) {
      _select(next, angle);
      _endStepped = _now;
      _endSteps++;
    }
  }

  // -1 or 1 while the finger is in the end zone next to New list or Home
  // with a list selected, else 0.
  int _endDirection(LauncherGeometry g, Offset pointer) {
    final int? selected = _selected;
    final (double angle, double radius) = _polar(g, pointer);
    if (selected == null ||
        _isFixed(selected) ||
        _editShown ||
        radius <= widget.config.hubRadius) {
      return 0;
    }
    if (angle >= _listsLow && angle < _listsLow + _endZone * _step) {
      return -1;
    }
    if (angle <= _listsHigh && angle > _listsHigh - _endZone * _step) {
      return 1;
    }
    return 0;
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
      _zoom = 0;
      _editShown = false;
      _moveShown = false;
      _endSince = null;
      _endSteps = 0;
      _edgePick = false;
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
          widget.config,
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
    final bool onHub = radius <= widget.config.hubRadius;
    setState(() {
      _pointer = finger;
      if (!onHub) {
        _leftHub = true;
      }
      if ((finger - (_restAnchor ?? finger)).distance >
          widget.config.moveTolerance) {
        _restAnchor = finger;
        _restStart = _now;
      }

      if (_moveShown) {
        final Offset target = g.movePromptCenter;
        _progress = _towards(finger, _promptAnchor, target);
        _promptSelected = _promptSelected
            ? _progress >= widget.config.promptUnselectAt
            : _progress >= widget.config.promptSelectAt;
        if (_promptSelected) {
          _mode = _Mode.moving;
          _moveShown = false;
          _movedHub = g.hubCenter;
          _moveGrab = g.hubCenter - finger;
          HapticFeedback.mediumImpact();
        }
        return;
      }

      if (_editShown) {
        // Edit is on the selected tab, which the finger may not be over
        // after turning the dial: the swipe counts outwards distance only.
        final (double anchorAngle, double anchorRadius) =
            _polar(g, _promptAnchor);
        _progress =
            ((radius - anchorRadius) / _editSwipe).clamp(0, 1).toDouble();
        final bool was = _promptSelected;
        _promptSelected = was
            ? _progress >= widget.config.promptUnselectAt
            : _progress >= widget.config.promptSelectAt;
        if (_promptSelected && !was) {
          HapticFeedback.selectionClick();
        }
        // Pulling back in or turning away lets Edit go; the dial turns again.
        if (radius < anchorRadius - 30 ||
            (angle - anchorAngle).abs() > 1.5 * _step) {
          _editShown = false;
          _ref = angle;
        }
        return;
      }

      if (onHub) {
        _select(null, angle);
        return;
      }
      if (_selected == null) {
        // Pointing picks the tab under the finger.
        _select(_entryAt(g, angle), angle);
        return;
      }
      // New list or Home stopped at an edge: the finger there picks it;
      // leaving it goes back to the list the dial stands on.
      if (angle < _listsLow && _addAtEdge(g)) {
        _select(0, angle);
        _edgePick = true;
        return;
      }
      if (angle > _listsHigh && _homeAtEdge(g)) {
        _select(_entries.length - 1, angle);
        _edgePick = true;
        return;
      }
      if (_edgePick) {
        _edgePick = false;
        if (_notes.isNotEmpty) {
          _select(_position.round().clamp(_firstList, _lastList), angle);
        }
        return;
      }
      // Turning the thumb picks the next or previous entry, one step at a
      // time; the dial follows (New list and Home are the ends).
      double jog = (angle - _ref) / _step;
      int index = _selected!;
      while (jog >= _jogAt && index < _entries.length - 1) {
        index++;
        _ref += _step;
        jog -= 1;
      }
      while (jog <= -_jogAt && index > 0) {
        index--;
        _ref -= _step;
        jog += 1;
      }
      if (jog.abs() >= _jogAt) {
        // At either end: nothing more to pick, start counting afresh.
        _ref = angle;
      }
      if (index != _selected) {
        final double ref = _ref;
        _select(index, angle);
        _ref = ref;
      }
    });
  }

  void _act(_Entry entry) {
    switch (entry.kind) {
      case _Kind.home:
        widget.onHome?.call();
      case _Kind.add:
        widget.onNew?.call();
      case _Kind.note:
        if (!_isDemo(entry)) {
          widget.onOpen(entry.note!);
        }
    }
  }

  bool _isDemo(_Entry entry) => entry.note?.id.startsWith('demo-') ?? false;

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
        _now - _openedAt <= widget.config.tapMaxDuration;
    if (quickTap) {
      _ticker.stop();
      setState(() {
        _mode = _Mode.tap;
        _selected = _firstList;
        _position = _firstList.toDouble();
        _zoom = 1;
      });
      return;
    }

    final int? selected = _selected;
    final bool edit = _editShown && _promptSelected;
    final (double _, double radius) = _polar(g, event.position);
    final List<_Entry> entries = _entries;
    _close();
    if (selected == null) {
      return;
    }
    final _Entry entry = entries[selected];
    if (edit && entry.note != null) {
      if (!_isDemo(entry)) {
        widget.onEdit(entry.note!);
      }
    } else if (radius > widget.config.hubRadius) {
      _act(entry);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_mode == _Mode.hold || _mode == _Mode.moving) {
      _close();
    }
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
    final double end = math.min(
      _tabCap + _tabGrow * zoom,
      (sides.$1 - sides.$2) * outer * 0.92,
    );
    return (double a) =>
        (_tabRoot +
            (end - _tabRoot) * (a - inner) / math.max(outer - inner, 1)) /
        2;
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
    final List<Offset> outline = [
      for (final (double a, double c) in local) origin + along * a + across * c,
    ];
    Rect bounds = Rect.fromPoints(outline.first, outline.first);
    for (final Offset point in outline) {
      bounds = bounds.expandToInclude(Rect.fromPoints(point, point));
    }
    bounds = bounds.inflate(2);
    return (bounds, [for (final Offset p in outline) p - bounds.topLeft]);
  }

  List<Widget> _entryWidgets(LauncherGeometry g, int index) {
    final (double, double)? sides = _sides(g, index);
    if (sides == null) {
      return const [];
    }
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final _Entry entry = _entries[index];
    final bool selected = _selected == index;
    final double angle = (sides.$1 + sides.$2) / 2;
    final double inner = _inner();
    final double outer = _outer(g, index);
    // 0 far from the selected entry, 1 on it.
    final double zoom =
        ((_emphasis(index) - 0.68) / 0.32).clamp(0, 1).toDouble();
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
    final Color disc = neutrals.ground;
    final Color glyph = fill;

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
      wedge = GestureDetector(
        onTap: () {
          _close();
          _act(entry);
        },
        onLongPress: entry.note == null || _isDemo(entry)
            ? null
            : () {
                _close();
                widget.onEdit(entry.note!);
              },
        child: wedge,
      );
    }

    final double discSize = 28 + 8 * zoom;
    final double fontSize = 15 + 6 * zoom;
    // The icon and name keep clear of the tab's end.
    final double end = outer - 18;
    final double labelEnd = end - discSize - 14;
    // Text starts where the tab is wide enough for it.
    double clear = widget.config.hubRadius + 22;
    while (clear < outer && 2 * halfAt(clear) < fontSize + 6) {
      clear += 4;
    }
    final double labelLength =
        math.min(labelEnd - math.max(inner, clear), 260);
    final double labelStart = labelEnd - labelLength;
    final bool outward = g.readsOutward(angle);
    final Offset labelCenter = g.pointAt(angle, (labelStart + labelEnd) / 2);
    final Offset discCenter = g.pointAt(angle, end - discSize / 2);
    final bool fits = 2 * halfAt(labelEnd) > fontSize + 4;

    return [
      Positioned(
        key: ValueKey('dial-entry-$index'),
        left: bounds.left,
        top: bounds.top,
        child: wedge,
      ),
      if (labelLength > 30 && fits)
        Positioned(
          left: labelCenter.dx - labelLength / 2,
          top: labelCenter.dy - (fontSize + 8) / 2,
          width: labelLength,
          height: fontSize + 8,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: g.tabRotation(angle),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: outward ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onColor(fill),
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
            child: Container(
              width: discSize,
              height: discSize,
              decoration: BoxDecoration(color: disc, shape: BoxShape.circle),
              child: Icon(icon, size: discSize * 0.6, color: glyph),
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
    final Color listColor = resolveListColor(note.color, brightness);
    final Color fill = Color.lerp(
      neutrals.promptDark,
      Color.lerp(listColor, Colors.black, 0.35)!,
      _progress,
    )!;
    final double angle = (sides.$1 + sides.$2) / 2;
    final double reveal = _reduceMotion
        ? 1
        : AppMotion.curve.transform(
            ((_now - _promptAt).inMicroseconds /
                    widget.config.revealDuration.inMicroseconds)
                .clamp(0, 1)
                .toDouble(),
          );
    // Edit continues the tab from behind its end (its inner part stays
    // hidden under the tab) and slides out as it is revealed.
    final double inner = _inner();
    final double outer = _outer(g, selected);
    final double zoom =
        ((_emphasis(selected) - 0.68) / 0.32).clamp(0, 1).toDouble();
    final double Function(double) halfAt =
        _halfWidth(sides, inner, outer, zoom);
    final double shown = _editDepth * (1 + 0.22 * _progress) * reveal;
    final double tuck = halfAt(outer) + 2;
    final (Rect bounds, List<Offset> outline) = _outline(
      g,
      sides,
      outer - tuck,
      outer + math.max(shown, 1),
      halfAt,
    );
    final Offset center = g.pointAt(angle, outer + shown / 2);
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
          left: center.dx - 40,
          top: center.dy - 11,
          width: 80,
          height: 22,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: g.tabRotation(angle),
              child: Text(
                widget.editLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onColor(fill),
                ),
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

  Widget _hub(LauncherGeometry g) {
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final double size = widget.config.hubRadius * 2;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size size = constraints.biggest;
        final Offset? saved = widget.hubPosition;
        final LauncherGeometry g = LauncherGeometry(
          config: widget.config,
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
            (a, b) =>
                (b - _position).abs().compareTo((a - _position).abs()),
          );
        final double hub = widget.config.hubRadius;

        return Stack(
          children: [
            if (_mode == _Mode.tap)
              Positioned.fill(
                child: GestureDetector(
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
        );
      },
    );
  }
}
