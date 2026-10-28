import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/app_theme.dart';
import '../app_colors.dart';
import '../lists/list_icons.dart';
import 'launcher_geometry.dart';

class LauncherNote {
  const LauncherNote({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.semanticsLabel,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
  // e.g. "Grocery, 4 items".
  final String semanticsLabel;
}

// Radial launcher (plan section 5) in direction A "Eclipse"
// (docs/AESTHETICS.md): the hub is a black disc over a blue one, lists are
// black pills with their colour disc, growing out from under the hub along
// their spokes; the tab under the finger is the biggest. Motion is translate
// and size only, and none with reduced motion.
// Fill the screen with it (it sits in a Stack). Lists fan out from the hub as
// long overlapping tabs, away from the nearest screen corner. Layout:
// LauncherGeometry. Every secondary action follows the interaction law in
// coordination/docs/INTERACTIONS.md: hold, a prompt slides out from behind its
// element, moving towards it fills it with colour, releasing on it acts.
//
// Hold mode: press the hub and drag onto a tab, release to open. Rest on a
// tab and "Edit" comes out past its outer end; slide onto it and release to
// edit, or release anywhere else on the way to open. "+" comes out from under
// the hub on every press; drag onto it for a new list. Rest on the hub and
// "Move" comes out below it; release on it to move the hub with the next drag.
// Release on the hub or off the fan to cancel; resting near either end of the
// fan scrolls it.
// Tap mode: a quick tap on the hub keeps the fan open with arrow buttons; tap
// a tab to open, long-press to edit; tap outside, the hub or Esc to close.
// Keys: left/right move focus, Enter opens, E edits, Esc closes.
class RadialLauncher extends StatefulWidget {
  const RadialLauncher({
    super.key,
    required this.notes,
    required this.onOpen,
    required this.onEdit,
    this.onNew,
    this.hubPosition,
    this.onHubMoved,
    this.config = const LauncherConfig(),
    this.hubTooltip = 'Lists',
    this.addLabel = 'New list',
    this.editLabel = 'Edit',
    this.moveLabel = 'Move',
    this.previousLabel = 'Previous',
    this.nextLabel = 'Next',
    this.noteHint = 'Double-tap to open, long-press to edit',
  });

  final List<LauncherNote> notes;
  final ValueChanged<LauncherNote> onOpen;
  final ValueChanged<LauncherNote> onEdit;
  // Null shows the "+" dimmed and inactive.
  final VoidCallback? onNew;
  // Saved hub centre as a fraction of the launcher's size; null = default.
  final Offset? hubPosition;
  // Receives the dropped hub centre as a fraction of the launcher's size.
  // Null turns the Move prompt off.
  final ValueChanged<Offset>? onHubMoved;
  final LauncherConfig config;
  final String hubTooltip;
  final String addLabel;
  final String editLabel;
  final String moveLabel;
  final String previousLabel;
  final String nextLabel;
  // Screen-reader hint on every tab in tap mode.
  final String noteHint;

  @override
  State<RadialLauncher> createState() => RadialLauncherState();
}

enum _Mode { closed, hold, tap, moveArmed, moving }

enum _PromptKind { edit, move }

// A prompt that has come out from under its element during a hold.
class _Prompt {
  _Prompt({
    required this.kind,
    required this.anchor,
    required this.shownAt,
    this.noteIndex,
  });

  final _PromptKind kind;
  // Where the finger was when the prompt appeared; progress is measured from
  // here to the prompt.
  final Offset anchor;
  final Duration shownAt;
  final int? noteIndex;
  double progress = 0;
  bool selected = false;
}

class RadialLauncherState extends State<RadialLauncher>
    with SingleTickerProviderStateMixin {
  _Mode _mode = _Mode.closed;
  double _scrollOffset = 0;
  LauncherTarget _hover = LauncherTarget.none;
  int _focusIndex = 0;

  // Hold-mode pointer tracking.
  Offset? _pointer;
  Offset? _restAnchor;
  Duration _restStart = Duration.zero;
  Duration _pressStart = Duration.zero;
  Duration _openedAt = Duration.zero;
  bool _leftHub = false;
  _Prompt? _prompt;
  double _addProgress = 0;

  // Hub dragged by the user, in pixels; wins over widget.hubPosition until
  // the parent catches up.
  Offset? _movedHub;
  Offset _moveGrab = Offset.zero;

  late final Ticker _ticker;
  Duration _now = Duration.zero;
  Duration _lastTick = Duration.zero;
  final FocusNode _focusNode = FocusNode(debugLabel: 'RadialLauncher');

  LauncherGeometry? _geometry;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(RadialLauncher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hubPosition != widget.hubPosition) {
      _movedHub = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get isOpen => _mode == _Mode.hold || _mode == _Mode.tap;

  void _close() {
    _ticker.stop();
    setState(() {
      _mode = _Mode.closed;
      _hover = LauncherTarget.none;
      _pointer = null;
      _prompt = null;
      _addProgress = 0;
    });
  }

  void _openTapMode() {
    setState(() {
      _mode = _Mode.tap;
      _focusIndex = _scrollOffset.round();
      _openedAt = _now;
    });
    _focusNode.requestFocus();
  }

  double _reveal(Duration since) {
    final int total = widget.config.revealDuration.inMicroseconds;
    if (total <= 0 || _reduceMotion) {
      return 1;
    }
    return AppMotion.curve.transform(
      ((_now - since).inMicroseconds / total).clamp(0, 1).toDouble(),
    );
  }

  // How far the finger has come from `from` towards `target`, 0 to 1; 1 once
  // it is within the prompt's hit radius.
  double _progress(Offset finger, Offset from, Offset target) {
    final double remaining = (finger - target).distance;
    if (remaining <= widget.config.promptHitRadius) {
      return 1;
    }
    final double total = math.max(
      (from - target).distance - widget.config.promptHitRadius,
      1,
    );
    return (1 - (remaining - widget.config.promptHitRadius) / total)
        .clamp(0, 1)
        .toDouble();
  }

  Offset _promptCenter(LauncherGeometry geometry, _Prompt prompt) {
    if (prompt.kind == _PromptKind.move) {
      return geometry.movePromptCenter;
    }
    final double angle = geometry.tabAngle(prompt.noteIndex!, _scrollOffset) ??
        geometry.slotAngle(0);
    return geometry.editPromptCenter(angle);
  }

  void _updatePrompt(LauncherGeometry geometry, Offset finger) {
    final _Prompt? prompt = _prompt;
    if (prompt == null) {
      return;
    }
    prompt.progress = _progress(finger, prompt.anchor, _promptCenter(geometry, prompt));
    final bool wasSelected = prompt.selected;
    prompt.selected = wasSelected
        ? prompt.progress >= widget.config.promptUnselectAt
        : prompt.progress >= widget.config.promptSelectAt;
    if (prompt.selected && !wasSelected) {
      HapticFeedback.selectionClick();
    }
  }

  void _onTick(Duration elapsed) {
    final double seconds = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _now = elapsed;
    final LauncherGeometry? geometry = _geometry;
    final Offset? pointer = _pointer;
    if (_mode != _Mode.hold || geometry == null || pointer == null) {
      return;
    }

    final double velocity = _prompt == null ? geometry.scrollVelocity(pointer) : 0;
    final bool scrolling = velocity != 0 &&
        geometry.clampOffset(_scrollOffset + velocity * seconds) != _scrollOffset;

    setState(() {
      if (scrolling) {
        _scrollOffset = geometry.clampOffset(_scrollOffset + velocity * seconds);
        _hover = geometry.hitTest(pointer, _scrollOffset);
        // Tabs sliding under a resting finger never bring up a prompt.
        _restAnchor = pointer;
        _restStart = _now;
        return;
      }

      if (_prompt != null || _now - _restStart < widget.config.promptDelay) {
        return;
      }

      if (_hover.kind == LauncherTargetKind.note) {
        _prompt = _Prompt(
          kind: _PromptKind.edit,
          anchor: pointer,
          shownAt: _now,
          noteIndex: _hover.noteIndex,
        );
      } else if (_hover == LauncherTarget.hub &&
          !_leftHub &&
          widget.onHubMoved != null) {
        _prompt = _Prompt(kind: _PromptKind.move, anchor: pointer, shownAt: _now);
      }
    });
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

    if (_mode == _Mode.moveArmed) {
      final LauncherGeometry? geometry = _geometry;
      setState(() {
        _mode = _Mode.moving;
        _moveGrab = (geometry?.hubCenter ?? event.position) - event.position;
        _movedHub = geometry?.hubCenter;
      });
      return;
    }

    setState(() {
      _mode = _Mode.hold;
      _pointer = event.position;
      _pressStart = _now;
      _openedAt = _now;
      _leftHub = false;
      _prompt = null;
      _addProgress = 0;
      _hover = LauncherTarget.hub;
      _restAnchor = event.position;
      _restStart = _now;
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    final LauncherGeometry? geometry = _geometry;
    if (geometry == null) {
      return;
    }

    if (_mode == _Mode.moving) {
      setState(() {
        _movedHub = LauncherGeometry.clampHub(
          widget.config,
          geometry.size,
          event.position + _moveGrab,
        );
      });
      return;
    }
    if (_mode != _Mode.hold) {
      return;
    }

    final Offset finger = event.position;
    final LauncherTarget target = geometry.hitTest(finger, _scrollOffset);

    setState(() {
      _pointer = finger;
      if (target != LauncherTarget.hub) {
        _leftHub = true;
      }
      _addProgress = _progress(finger, geometry.hubCenter, geometry.addCenter);

      final _Prompt? prompt = _prompt;
      if (prompt != null) {
        // Reaching another element lets the prompt go; the way to the prompt
        // (off the tab, between tab and prompt) keeps it.
        final bool otherTab = target.kind == LauncherTargetKind.note &&
            (prompt.kind == _PromptKind.move || target.noteIndex != prompt.noteIndex);
        final bool leftForAdd = target == LauncherTarget.add;
        if (otherTab || leftForAdd) {
          _prompt = null;
        } else {
          _updatePrompt(geometry, finger);
          return;
        }
      }

      if (target != _hover) {
        _hover = target;
        _restAnchor = finger;
        _restStart = _now;
        if (target.kind == LauncherTargetKind.note) {
          HapticFeedback.selectionClick();
        }
      } else if ((finger - (_restAnchor ?? finger)).distance >
          widget.config.moveTolerance) {
        // A prompt only comes after the finger has been still for a while.
        _restAnchor = finger;
        _restStart = _now;
      }
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_mode == _Mode.moving) {
      _ticker.stop();
      final LauncherGeometry? geometry = _geometry;
      final Offset? dropped = _movedHub;
      setState(() => _mode = _Mode.closed);
      if (geometry != null && dropped != null) {
        widget.onHubMoved?.call(
          Offset(
            dropped.dx / geometry.size.width,
            dropped.dy / geometry.size.height,
          ),
        );
      }
      return;
    }
    if (_mode != _Mode.hold) {
      return;
    }

    final LauncherTarget target = _hover;
    final _Prompt? prompt = _prompt;
    final bool quickTap = !_leftHub &&
        target == LauncherTarget.hub &&
        prompt == null &&
        _now - _pressStart <= widget.config.tapMaxDuration;
    _ticker.stop();

    if (quickTap) {
      _openTapMode();
      return;
    }

    if (prompt != null && prompt.kind == _PromptKind.move) {
      final bool move = prompt.selected;
      _close();
      if (move) {
        HapticFeedback.mediumImpact();
        setState(() => _mode = _Mode.moveArmed);
      }
      return;
    }

    if (prompt != null && prompt.kind == _PromptKind.edit) {
      final LauncherNote note = widget.notes[prompt.noteIndex!];
      final bool edit = prompt.selected;
      // Not on the prompt: act on what is under the finger, as if the prompt
      // had never appeared. Back on the tab opens it; on the hub, off the fan
      // or short of the prompt nothing happens.
      final LauncherGeometry? geometry = _geometry;
      final bool onTab = geometry != null &&
          geometry.hitTest(event.position, _scrollOffset) ==
              LauncherTarget(LauncherTargetKind.note, prompt.noteIndex);
      _close();
      if (edit) {
        widget.onEdit(note);
      } else if (onTab) {
        widget.onOpen(note);
      }
      return;
    }

    _close();
    switch (target.kind) {
      case LauncherTargetKind.note:
        widget.onOpen(widget.notes[target.noteIndex!]);
      case LauncherTargetKind.add:
        widget.onNew?.call();
      case LauncherTargetKind.hub:
      case LauncherTargetKind.none:
        break;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_mode == _Mode.hold || _mode == _Mode.moving) {
      _close();
    }
  }

  void _page(int direction) {
    final LauncherGeometry? geometry = _geometry;
    if (geometry == null) {
      return;
    }
    setState(() {
      _scrollOffset = geometry.clampOffset(
        _scrollOffset + direction * geometry.slotCount,
      );
      _focusIndex = _focusIndex.clamp(
        _scrollOffset.round(),
        _scrollOffset.round() + geometry.slotCount - 1,
      );
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (_mode == _Mode.moveArmed && key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (_mode != _Mode.tap) {
      return KeyEventResult.ignored;
    }
    final LauncherGeometry? geometry = _geometry;

    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (widget.notes.isEmpty || geometry == null) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      final int next = (_focusIndex + (key == LogicalKeyboardKey.arrowLeft ? -1 : 1))
          .clamp(0, widget.notes.length - 1);
      setState(() {
        _focusIndex = next;
        if (next < _scrollOffset) {
          _scrollOffset = geometry.clampOffset(next.toDouble());
        } else if (next >= _scrollOffset + geometry.slotCount) {
          _scrollOffset = geometry.clampOffset(
            (next - geometry.slotCount + 1).toDouble(),
          );
        }
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.keyE) {
      final LauncherNote note = widget.notes[_focusIndex];
      _close();
      key == LogicalKeyboardKey.enter ? widget.onOpen(note) : widget.onEdit(note);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // The tab the user is on: hovered or prompted in hold mode, focused in tap
  // mode.
  int? get _selectedIndex {
    if (_prompt?.kind == _PromptKind.edit) {
      return _prompt!.noteIndex;
    }
    if (_hover.kind == LauncherTargetKind.note) {
      return _hover.noteIndex;
    }
    return _mode == _Mode.tap ? _focusIndex : null;
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  // How far a tab has grown out from under the hub, 0 to 1. Tabs start one
  // after another (AppMotion.tabStagger) from the press; tap mode and reduced
  // motion show them whole.
  double _growth(double slot) {
    if (_mode == _Mode.tap || _reduceMotion) {
      return 1;
    }
    final Duration delay = AppMotion.tabStagger * math.max(0, slot.round());
    final double t = (_now - _openedAt - delay).inMicroseconds /
        AppMotion.standard.inMicroseconds;
    return AppMotion.curve.transform(t.clamp(0, 1).toDouble());
  }

  Widget _noteWidget(
    LauncherGeometry geometry,
    LauncherNote note,
    int index,
    double angle,
  ) {
    final LauncherConfig config = widget.config;
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final Color color = resolveListColor(note.color, brightness);
    final int? selectedIndex = _selectedIndex;
    final bool selected = selectedIndex == index;
    final bool neighbour =
        selectedIndex != null && (selectedIndex - index).abs() == 1;
    final bool outward = geometry.readsOutward(angle);
    // In the tab's own frame the hub end is on the left when its text reads
    // outward.
    final Alignment hubEnd =
        outward ? Alignment.centerLeft : Alignment.centerRight;

    // Growing out along the spoke: the inner end moves out from under the hub
    // while the tab lengthens.
    final double grow = _growth(index - _scrollOffset);
    final double inner =
        lerpDouble(config.hubRadius * 0.4, config.innerRadius, grow)!;
    final double stretch = lerpDouble(0.18, 1, grow)!;
    final Offset center =
        geometry.pointAt(angle, inner + config.tabLength * stretch / 2);

    const double disc = 30;
    final Widget mark = Container(
      width: disc,
      height: disc,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(note.icon, size: 17, color: AppColors.onColor(color)),
    );
    final Widget label = Flexible(
      child: Text(
        note.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: neutrals.ground,
        ),
      ),
    );

    // A pill in the text colour with the list's colour disc at its outer end,
    // where tabs no longer overlap; a thin ground-coloured ring keeps
    // overlapping tabs apart.
    Widget body = AnimatedScale(
      key: ValueKey('launcher-tab-scale-${note.id}'),
      scale: selected
          ? config.selectedTabScale
          : neighbour
              ? config.neighbourTabScale
              : 1,
      alignment: hubEnd,
      duration: _reduceMotion ? Duration.zero : AppMotion.quick,
      curve: AppMotion.curve,
      child: Container(
        width: config.tabLength,
        height: config.tabThickness,
        padding: EdgeInsets.only(left: outward ? 14 : 5, right: outward ? 5 : 14),
        decoration: BoxDecoration(
          color: neutrals.text,
          borderRadius: BorderRadius.circular(config.tabThickness / 2),
          border: Border.all(
            color: neutrals.ground,
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
          boxShadow: selected ? AppShadows.floating(brightness) : null,
        ),
        child: Row(
          mainAxisAlignment:
              outward ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: outward
              ? [label, const SizedBox(width: 10), mark]
              : [mark, const SizedBox(width: 10), label],
        ),
      ),
    );

    if (_mode == _Mode.tap) {
      body = Semantics(
        button: true,
        label: note.semanticsLabel,
        hint: widget.noteHint,
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('launcher-note-${note.id}'),
          onTap: () {
            _close();
            widget.onOpen(note);
          },
          onLongPress: () {
            _close();
            widget.onEdit(note);
          },
          onSecondaryTap: () {
            _close();
            widget.onEdit(note);
          },
          child: body,
        ),
      );
    }

    return Positioned(
      key: ValueKey('launcher-tab-${note.id}'),
      left: center.dx - config.tabLength / 2,
      top: center.dy - config.tabThickness / 2,
      child: Transform.rotate(
        angle: geometry.tabRotation(angle),
        child: Transform.scale(scaleX: stretch, child: body),
      ),
    );
  }

  // Tabs ordered for painting: the selected one last (on top), the others by
  // closeness to it, so the stack shifts as the finger moves along the fan.
  // The Edit prompt comes out from behind its own tab, so it is painted just
  // below that tab (and above the others, which would otherwise hide it).
  List<Widget> _tabs(LauncherGeometry geometry, {Widget? editPrompt}) {
    final List<(int, double)> visible = [
      for (int index = 0; index < widget.notes.length; index++)
        if (geometry.tabAngle(index, _scrollOffset) case final double angle)
          (index, angle),
    ];

    double focus = _selectedIndex?.toDouble() ?? -1;
    if (_selectedIndex == null && _pointer != null) {
      final double? position = geometry.fanPosition(_pointer!);
      if (position != null) {
        focus = position * geometry.slotCount - 0.5 + _scrollOffset;
      }
    }

    if (focus >= 0) {
      visible.sort(
        (a, b) => (b.$1 - focus).abs().compareTo((a.$1 - focus).abs()),
      );
    } else {
      // Nothing selected: later tabs overlap earlier ones.
      visible.sort((a, b) => a.$1.compareTo(b.$1));
    }

    final int? prompted =
        _prompt?.kind == _PromptKind.edit ? _prompt!.noteIndex : null;
    return [
      for (final (int index, double angle) in visible) ...[
        if (index == prompted && editPrompt != null) editPrompt,
        _noteWidget(geometry, widget.notes[index], index, angle),
      ],
    ];
  }

  // A prompt sliding out from `from` (behind its element) to `to`. It starts
  // dark, fills with `lit` and grows with `progress` (interaction law,
  // Q-17 A). Nothing fades.
  Positioned _promptPill({
    required Key key,
    required Offset from,
    required Offset to,
    required double reveal,
    required double progress,
    required Color lit,
    IconData? icon,
    String? label,
    bool enabled = true,
  }) {
    // The pill sizes to its label inside a fixed box centred on the prompt.
    const double box = 160;
    const double boxHeight = 40;
    final AppNeutrals neutrals =
        AppColors.neutrals(Theme.of(context).brightness);
    final Color fill = enabled
        ? Color.lerp(neutrals.promptDark, lit, progress)!
        : neutrals.line;
    final Color ink = enabled ? AppColors.onColor(fill) : neutrals.muted;
    final Offset center = Offset.lerp(from, to, reveal)!;

    final Widget pill = Transform.scale(
      scale: 1 + 0.28 * progress,
      child: Container(
        key: ValueKey('${(key as ValueKey<String>).value}-fill'),
        height: label == null ? 40 : 36,
        width: label == null ? 40 : null,
        constraints:
            label == null ? null : const BoxConstraints(minWidth: 72),
        padding: label == null
            ? null
            : const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(20),
        ),
        child: label == null
            ? Icon(icon, size: 20, color: ink)
            : Center(
                widthFactor: 1,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: AppFonts.sans,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
      ),
    );

    return Positioned(
      key: key,
      left: center.dx - box / 2,
      top: center.dy - boxHeight / 2,
      width: box,
      height: boxHeight,
      child: Center(child: pill),
    );
  }

  Widget _addWidget(LauncherGeometry geometry) {
    final bool enabled = widget.onNew != null;
    final Positioned pill = _promptPill(
      key: const ValueKey('launcher-add-prompt'),
      from: geometry.hubCenter,
      to: geometry.addCenter,
      // Tap mode (the accessible path) shows everything at once.
      reveal: _mode == _Mode.tap ? 1 : _reveal(_openedAt),
      progress: _mode == _Mode.tap ? 0 : (enabled ? _addProgress : 0),
      lit: AppColors.appBlue,
      icon: Icons.add,
      enabled: enabled,
    );

    if (_mode != _Mode.tap) {
      return pill;
    }
    // In tap mode the "+" is a plain button around the same pill.
    return Positioned(
      left: geometry.addCenter.dx - 24,
      top: geometry.addCenter.dy - 24,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.addLabel,
        excludeSemantics: true,
        child: GestureDetector(
          key: const ValueKey('launcher-add'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  _close();
                  widget.onNew!();
                }
              : null,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(child: pill.child),
          ),
        ),
      ),
    );
  }

  Widget? _promptWidget(LauncherGeometry geometry) {
    final _Prompt? prompt = _prompt;
    if (prompt == null) {
      return null;
    }

    if (prompt.kind == _PromptKind.move) {
      return _promptPill(
        key: const ValueKey('launcher-move-prompt'),
        from: geometry.hubCenter,
        to: geometry.movePromptCenter,
        reveal: _reveal(prompt.shownAt),
        progress: prompt.progress,
        lit: AppColors.appBlue,
        label: widget.moveLabel,
      );
    }

    final double? angle = geometry.tabAngle(prompt.noteIndex!, _scrollOffset);
    if (angle == null) {
      return null;
    }
    return _promptPill(
      key: const ValueKey('launcher-edit-prompt'),
      from: geometry.pointAt(angle, geometry.selectedOuterRadius - 30),
      to: geometry.editPromptCenter(angle),
      reveal: _reveal(prompt.shownAt),
      progress: prompt.progress,
      lit: resolveListColor(
        widget.notes[prompt.noteIndex!].color,
        Theme.of(context).brightness,
      ),
      label: widget.editLabel,
    );
  }

  // The eclipse: a disc in the text colour over a blue one that peeks out
  // towards the fan, with the one floating shadow.
  Widget _hub(LauncherGeometry geometry, bool moveMode) {
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final double size = widget.config.hubRadius * 2;
    final Offset back = Offset(
      geometry.flipX ? 14 : -14,
      geometry.flipY ? 8 : -8,
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: back.dx,
            top: back.dy,
            width: size,
            height: size,
            child: const DecoratedBox(
              key: ValueKey('launcher-hub-back'),
              decoration: BoxDecoration(
                color: AppColors.appBlue,
                shape: BoxShape.circle,
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
              boxShadow: AppShadows.floating(brightness),
            ),
            child: moveMode
                ? Icon(Icons.open_with, color: neutrals.ground)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _arrow(LauncherGeometry geometry, int direction) {
    final bool enabled = direction < 0
        ? _scrollOffset > 0
        : _scrollOffset < geometry.maxScrollOffset;
    // In the margins just past each end of the fan.
    final Offset spot = geometry.pointAt(
      geometry.slotAngle(direction < 0 ? -0.9 : geometry.slotCount - 0.1),
      widget.config.innerRadius + widget.config.tabLength / 2,
    );
    return Positioned(
      left: spot.dx - 24,
      top: spot.dy - 24,
      child: IconButton(
        key: ValueKey(direction < 0 ? 'launcher-prev' : 'launcher-next'),
        tooltip: direction < 0 ? widget.previousLabel : widget.nextLabel,
        icon: Icon(direction < 0 ? Icons.chevron_left : Icons.chevron_right),
        onPressed: enabled ? () => _page(direction) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size size = constraints.biggest;
        final Offset? saved = widget.hubPosition;
        final LauncherGeometry geometry = LauncherGeometry(
          config: widget.config,
          size: size,
          noteCount: widget.notes.length,
          hubPosition: _movedHub ??
              (saved == null
                  ? null
                  : Offset(saved.dx * size.width, saved.dy * size.height)),
        );
        _geometry = geometry;
        _scrollOffset = geometry.clampOffset(_scrollOffset);
        final Offset hubCenter = geometry.hubCenter;
        final double hub = widget.config.hubRadius;
        final bool moveMode = _mode == _Mode.moveArmed || _mode == _Mode.moving;
        final Widget? prompt = _promptWidget(geometry);

        return Focus(
          focusNode: _focusNode,
          onKeyEvent: _onKey,
          child: Stack(
            children: [
              if (_mode == _Mode.tap || _mode == _Mode.moveArmed)
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('launcher-barrier'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: const SizedBox.expand(),
                  ),
                ),
              if (isOpen) ...[
                ..._tabs(geometry, editPrompt: prompt),
                _addWidget(geometry),
                if (_mode == _Mode.tap && geometry.maxScrollOffset > 0) ...[
                  _arrow(geometry, -1),
                  _arrow(geometry, 1),
                ],
              ],
              if (_prompt?.kind == _PromptKind.move && prompt != null) prompt,
              if (_mode == _Mode.moveArmed)
                _promptPill(
                  key: const ValueKey('launcher-move-armed'),
                  from: geometry.movePromptCenter,
                  to: geometry.movePromptCenter,
                  reveal: 1,
                  progress: 1,
                  lit: AppColors.appBlue,
                  label: widget.moveLabel,
                ),
              Positioned(
                left: hubCenter.dx - hub,
                top: hubCenter.dy - hub,
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: Semantics(
                    button: true,
                    label: widget.hubTooltip,
                    onTap: () => isOpen ? _close() : _openTapMode(),
                    child: Tooltip(
                      message: widget.hubTooltip,
                      // Hover only: a hold on the hub is a gesture, not a
                      // request for the tooltip.
                      triggerMode: TooltipTriggerMode.manual,
                      child: AnimatedScale(
                        scale: moveMode ? 1.12 : 1,
                        duration:
                            _reduceMotion ? Duration.zero : AppMotion.standard,
                        curve: AppMotion.curve,
                        child: _hub(geometry, moveMode),
                      ),
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
