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
// 2026-11-03). Petal-shaped tabs in the list's colour turn around the hub so
// that the selected one always lies along the screen's diagonal and reaches
// halfway to the far corner, where the thumb does not cover its name.
// Pointing at a tab picks it and turns it to the diagonal; from there,
// turning the thumb by one step picks the next or previous list (the dial
// follows, the finger never chases it). Later lists lie towards the bottom
// (or top) edge. New list and Home (inside a list) ride at the two ends of
// the lists and stop at the side and bottom edges, so they stay in reach;
// holding the finger at an edge keeps stepping through the lists that way,
// then picks New list or Home. Far off the dial nothing is selected and
// letting go cancels. Rest the finger and Edit slides out from behind the
// selected tab's end; a short swipe outwards (wherever the finger is)
// selects it. Rest on the hub for Move.
//
// A quick tap on the hub (or Enter/Space on it, or a screen reader's tap)
// opens tap mode: tap a tab to open it, long-press or right-click to edit;
// the arrows (and the arrow keys) step the dial through every entry; Enter
// opens and E edits the selected one; Esc closes.
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

  // The dial: which entry is selected, where the dial stands (an entry
  // position, easing towards the selected one) and how far the selected tab
  // has grown (0 to 1).
  int? _selected;
  double _position = 0;
  double _zoom = 0;
  // Finger angle the next jog is measured from.
  double _ref = 0;
  // Which edge the finger is at after its first pick (-1 side, 1 bottom, 0
  // neither); whether New list or Home was picked there; and the stepping
  // while it holds: since when, when it last stepped, how often.
  int _edge = 0;
  bool _pickedAtEdge = false;
  Duration? _edgeSince;
  Duration _edgeStepped = Duration.zero;
  int _edgeSteps = 0;

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
        _selected = now;
      } else {
        _selected = _mode == _Mode.tap && _notes > 0 ? _firstList : null;
        _editShown = false;
        _pickedAtEdge = false;
      }
    } else {
      _selected = null;
    }
    _position = _position
        .clamp(_firstList.toDouble(), _lastList.toDouble())
        .toDouble();
  }

  int get _notes => _entries.length - (widget.onHome != null ? 2 : 1);

  // The most recent list stands on the diagonal when the dial opens.
  int get _firstList => _notes == 0 ? 0 : 1;
  int get _lastList => _notes;

  // New list and Home ride at the two ends of the lists and turn with them;
  // when the lists run past an edge of the corner's quarter they stop there,
  // so both stay in reach (owner, 2026-11-03).
  bool _isFixed(int index) => _entries[index].kind != _Kind.note;

  // The edges: the last step of the quarter at the side edge (where New
  // list stops) and at the bottom edge (where Home stops), and beyond.
  double get _listsLow => math.pi / 2 + _step;
  double get _listsHigh => math.pi - _step;

  // Where the dial heads: the selected list, or the nearest list while New
  // list or Home is selected.
  double get _target {
    final int? selected = _selected;
    if (selected == null || _notes == 0) {
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

  // Whether a finger is on the dial: within the quarter (or a little past
  // its edges, where holding scrolls) and not far beyond the longest tab.
  bool _onDial(LauncherGeometry g, double angle, double radius) {
    final double past = _config.dialOffDialDegrees * math.pi / 180;
    return angle >= math.pi / 2 - past &&
        angle <= math.pi + past &&
        radius <= _halfDiagonal(g) + 48;
  }

  // Angle offset from the diagonal of a point x entries away from the dial's
  // position; the selected entry gets dialSelectedSpread times the room.
  double _offset(double x) {
    final double selected =
        _step * (1 + (_config.dialSelectedSpread - 1) * _zoom);
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

  // Home's sides: after the last list, stopping at the bottom edge.
  (double, double) _homeSides(LauncherGeometry g) {
    final (double start, double end) = _turning(g, _entries.length - 1);
    final double pull = math.max(0, start - math.pi);
    return (start - pull, end - pull);
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
    final (double turnStart, double turnEnd) = _turning(g, index);
    final double high = widget.onHome != null ? _homeSides(g).$2 : math.pi;
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
    final double near = _config.dialNeighbourLength;
    final double far = _config.dialFarLength;
    final double d = (index - _position).abs();
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

  double _outer(LauncherGeometry g, int index) {
    final double full = _halfDiagonal(g) - _config.innerRadius;
    return _inner() + full * _emphasis(index) * lerpDouble(0.18, 1, _grow())!;
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

  void _select(int? index, double angle) {
    if (index == _selected) {
      return;
    }
    _selected = index;
    _ref = angle;
    _editShown = false;
    _restStart = _now;
    _pickedAtEdge = false;
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

    // The dial turns the selected entry to the diagonal (AppMotion.quick).
    final double t = _reduceMotion
        ? 1
        : 1 - math.exp(-seconds * 3e6 / AppMotion.quick.inMicroseconds);
    final int? selected = _selected;
    final double position =
        selected == null ? _position : _position + (_target - _position) * t;
    final double zoom = _zoom + ((selected == null ? 0 : 1) - _zoom) * t;
    final bool moving =
        (position - _position).abs() > 1e-4 || (zoom - _zoom).abs() > 1e-4;
    final bool animating = moving ||
        _now - _openedAt <= AppMotion.standard ||
        (_editShown && _now - _promptAt <= _config.revealDuration);
    _position = moving ? position : _target;
    _zoom = moving ? zoom : (selected == null ? 0 : 1);

    bool changed = animating;
    if (_mode == _Mode.hold && g != null && pointer != null) {
      changed = _scrollAtEdge(g, pointer) || changed;
      changed = _offerPrompt(g, pointer) || changed;
    }
    if (changed) {
      setState(() {});
    } else if (_mode == _Mode.tap) {
      _ticker.stop();
    }
  }

  // The finger at an edge keeps stepping through the lists that way, faster
  // the longer it holds, so many lists need no more room than the corner
  // has; past the last list it picks New list or Home (inside a list).
  bool _scrollAtEdge(LauncherGeometry g, Offset pointer) {
    final int? selected = _selected;
    final int next = (selected ?? 0) + _edge;
    if (_edge == 0 ||
        selected == null ||
        _isFixed(selected) ||
        next < 0 ||
        next >= _entries.length) {
      _edgeSince = null;
      _edgeSteps = 0;
      return false;
    }
    final Duration since = _edgeSince ??= _now;
    final Duration interval = Duration(
      microseconds: math.max(
        _config.dialEdgeFastest.inMicroseconds,
        _config.dialEdgeInterval.inMicroseconds - _edgeSteps * 30000,
      ),
    );
    final bool due = _edgeSteps == 0
        ? _now - since >= _config.dialEdgeDelay
        : _now - _edgeStepped >= interval;
    if (!due) {
      return false;
    }
    _select(next, _polar(g, pointer).$1);
    _pickedAtEdge = _isFixed(next);
    _edgeStepped = _now;
    _edgeSteps++;
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
      _zoom = 0;
      _editShown = false;
      _moveShown = false;
      _edgeSince = null;
      _edgeSteps = 0;
      _edge = 0;
      _pickedAtEdge = false;
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
        _select(null, angle);
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
      }
      if (_selected == null) {
        return;
      }
      _followEdge(angle);
      if (_edge != 0) {
        return;
      }
      // Back from an edge where it picked New list or Home: the list the
      // dial stands on.
      if (_pickedAtEdge) {
        if (_notes > 0) {
          _select(_position.round().clamp(_firstList, _lastList), angle);
        }
        return;
      }
      _jog(angle);
    });
  }

  // Which edge the finger is at, with a little more needed to leave one; at
  // an edge with no lists left that way, New list or Home is picked at once.
  void _followEdge(double angle) {
    final double leave = _config.dialEdgeLeave * _step;
    final int edge = switch (_edge) {
      -1 => angle < _listsLow + leave ? -1 : 0,
      1 => angle > _listsHigh - leave ? 1 : 0,
      _ => angle < _listsLow ? -1 : (angle > _listsHigh ? 1 : 0),
    };
    if (edge != _edge) {
      _edge = edge;
      _edgeSince = null;
      _edgeSteps = 0;
    }
    final int selected = _selected!;
    final int next = selected + _edge;
    if (_edge != 0 &&
        !_isFixed(selected) &&
        next >= 0 &&
        next < _entries.length &&
        _isFixed(next)) {
      _select(next, angle);
      _pickedAtEdge = true;
    }
  }

  // Turning the thumb picks the next or previous list, one step at a time;
  // the dial follows. From New list or Home it steps onto the nearest list.
  void _jog(double angle) {
    double jog = (angle - _ref) / _step;
    int index = _selected!;
    final double at = _config.dialJogAt;
    while (jog >= at && index < _lastList) {
      index++;
      _ref += _step;
      jog -= 1;
    }
    while (jog <= -at && index > _firstList) {
      index--;
      _ref -= _step;
      jog += 1;
    }
    if (jog.abs() >= at) {
      // At either end: nothing more to pick, start counting afresh.
      _ref = angle;
    }
    if (index != _selected) {
      final double ref = _ref;
      _select(index, angle);
      _ref = ref;
    }
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
    setState(() => _selected = next);
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
    final double outer = _outer(g, index);
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
    final double outer = _outer(g, selected);
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
            (a, b) => (b - _position).abs().compareTo((a - _position).abs()),
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
