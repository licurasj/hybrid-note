import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_colors.dart';
import 'app_theme.dart';

// A short message that floats above the screens, such as "List deleted · Undo"
// (T-21 unit 3). Material's snackbar fades in when it floats, and nothing fades
// here (AESTHETICS Motion). This one slides up and looks like the AI bar's
// answer panel. It sits just above the AI bar, from the bar's left edge, and
// keeps clear of the hub (owner, 2026-11-09). A new message replaces the
// current one at once.
class AppBannerController {
  // How long a message stays; one with an action gets longer to use it.
  static const Duration plainFor = Duration(seconds: 4);
  static const Duration withActionFor = Duration(seconds: 6);

  String? _text;
  String? _actionLabel;
  VoidCallback? _onAction;
  bool _showing = false;
  int _serial = 0;
  bool _disposed = false;
  Timer? _timer;
  final ValueNotifier<int> _changes = ValueNotifier(0);
  final ValueNotifier<BannerRoom?> _room = ValueNotifier(null);

  Listenable get changes => _changes;

  // What the banner keeps clear of, from the shell; null where there is no
  // shell (tests, other hosts).
  BannerRoom? get room => _room.value;
  set room(BannerRoom? room) => _room.value = room;

  String? get text => _text;
  String? get actionLabel => _actionLabel;
  bool get showing => _showing;

  // Shows [text] and returns its number, which [dismissIf] takes to remove
  // just this message and not one shown after it.
  int show(String text, {String? actionLabel, VoidCallback? onAction}) {
    _timer?.cancel();
    _serial++;
    _text = text;
    _actionLabel = actionLabel;
    _onAction = onAction;
    _showing = true;
    _timer = Timer(actionLabel == null ? plainFor : withActionFor, dismiss);
    _changes.value++;
    return _serial;
  }

  // Whether message [serial] is still on screen.
  bool isShowing(int serial) => _showing && _serial == serial;

  void dismissIf(int serial) {
    if (_serial == serial) {
      dismiss();
    }
  }

  void dismiss() {
    _timer?.cancel();
    if (_showing) {
      _showing = false;
      _changes.value++;
    }
  }

  // The banner has slid away: nothing of it stays on the page.
  void _gone() {
    // With reduced motion the slide ends inside the build that started it,
    // so the change waits for the build to finish.
    scheduleMicrotask(() {
      if (!_disposed && !_showing && _text != null) {
        _text = null;
        _changes.value++;
      }
    });
  }

  void act() {
    final VoidCallback? action = _onAction;
    dismiss();
    action?.call();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _changes.dispose();
    _room.dispose();
  }
}

// Where the AI bar and the hub are on the screen, in global coordinates, so
// the banner can sit above the bar, as wide as it, and off the hub. [bar] is
// null while the bar is hidden; [laneLeft] and [laneRight] are the bar's edges
// all the same, where it would be. [wide] when the bar is at its widest (a
// wide screen), where the banner stays as wide as its words for now.
@immutable
class BannerRoom {
  const BannerRoom({
    this.bar,
    this.hub,
    this.laneLeft,
    this.laneRight,
    this.wide = false,
  });

  final Rect? bar;
  final Rect? hub;
  final double? laneLeft;
  final double? laneRight;
  final bool wide;

  @override
  bool operator ==(Object other) =>
      other is BannerRoom &&
      other.bar == bar &&
      other.hub == hub &&
      other.laneLeft == laneLeft &&
      other.laneRight == laneRight &&
      other.wide == wide;

  @override
  int get hashCode => Object.hash(bar, hub, laneLeft, laneRight, wide);
}

// Where the banner goes: its left edge, its width (its widest when [fill] is
// false), and its bottom edge from the bottom of the screen. [screen] is the
// whole screen, [keyboard] the keyboard's height and [inset] the system's
// bottom padding. On a phone it is exactly as wide as the AI bar, lined up
// with it (owner, 2026-11-09).
@visibleForTesting
({double left, double width, double bottom, bool fill}) bannerPlace({
  required Size screen,
  required double keyboard,
  required double inset,
  BannerRoom? room,
}) {
  const double gap = AppBannerHost.gap;
  final double floor = screen.height - keyboard;
  final double left = room?.bar?.left ?? room?.laneLeft ?? AppShapes.sideMargin;
  double right =
      room?.bar?.right ??
      room?.laneRight ??
      screen.width - AppShapes.sideMargin;
  final bool fill = !(room?.wide ?? false);
  if (!fill) {
    right = math.min(right, left + AppBannerHost.maxWidth);
  }
  // The y of the banner's bottom edge.
  double bottomY = floor - math.max(inset, 0) - AppBannerHost.restGap;
  final Rect? bar = room?.bar;
  if (bar != null) {
    bottomY = bar.top - gap;
  }
  final Rect? hub = room?.hub;
  if (hub != null) {
    final Rect banner = Rect.fromLTRB(
      left,
      bottomY - AppBannerHost.tallest,
      right,
      bottomY,
    ).inflate(gap);
    if (banner.overlaps(hub)) {
      // From the same left edge, it ends before a hub on its right when that
      // leaves room enough; otherwise it goes above the hub.
      final bool hubRight = hub.center.dx >= (left + right) / 2;
      if (hubRight && hub.left - gap - left >= AppBannerHost.narrowest) {
        right = hub.left - gap;
      } else {
        bottomY = hub.top - gap;
      }
    }
  }
  return (
    left: left,
    width: math.max(0, right - left),
    bottom: screen.height - bottomY,
    fill: fill,
  );
}

// [child] with the banner over it. It goes in MaterialApp.builder, so it is
// above every page and sheet.
class AppBannerHost extends StatelessWidget {
  const AppBannerHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final AppBannerController controller;
  final Widget child;

  // Between the banner and the bar or the hub under it.
  static const double gap = 8;
  // Above the bottom inset when there is no bar, as the bar's own margin.
  static const double restGap = 12;
  // On a wide screen, as wide as its words, up to this.
  static const double maxWidth = 340;
  // Narrower than this beside the hub, it goes above it instead.
  static const double narrowest = 220;
  // Its height with two lines of text, for keeping clear of the hub.
  static const double tallest = 76;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    return Stack(
      children: [
        child,
        ListenableBuilder(
          listenable: Listenable.merge([controller.changes, controller._room]),
          builder: (context, _) {
            final place = bannerPlace(
              screen: media.size,
              keyboard: media.viewInsets.bottom,
              inset: media.padding.bottom,
              room: controller.room,
            );
            // It comes out from behind the AI bar and goes back behind it
            // (owner, 2026-11-09): drawn only above the bar's top edge (or,
            // without the bar, above the bottom edge), it slides up from
            // there, so it never passes in front of the bar. With reduced
            // motion it is just there, and just gone.
            final double edge =
                controller.room?.bar?.top ??
                media.size.height - media.viewInsets.bottom;
            return Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: math.max(0, edge),
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [_slide(media, place, edge)],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _slide(
    MediaQueryData media,
    ({double left, double width, double bottom, bool fill}) place,
    double edge,
  ) {
    return AnimatedPositioned(
      duration: media.disableAnimations ? Duration.zero : AppMotion.standard,
      curve: AppMotion.curve,
      onEnd: controller._gone,
      left: place.left,
      // Measured from the edge it hides behind; when gone, all of it
      // is below that edge.
      bottom: controller.showing
          ? place.bottom - (media.size.height - edge)
          : -(tallest + 24),
      child: controller.text == null
          ? const SizedBox.shrink()
          : place.fill
          ? SizedBox(
              width: place.width,
              child: _Banner(controller: controller, fill: true),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: place.width),
              child: _Banner(controller: controller, fill: false),
            ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.controller, required this.fill});

  final AppBannerController controller;
  // As wide as it is given, or as its words.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals n = AppColors.neutrals(brightness);
    final AppTypography type = AppTypography.of(context);
    final String? action = controller.actionLabel;

    final Widget banner = Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('app-banner'),
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(18, 4, 8, 4),
        decoration: BoxDecoration(
          color: n.ground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: n.line),
          boxShadow: AppShadows.floating(brightness),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            children: [
              Flexible(
                // Filling, Undo goes to the far end.
                fit: fill ? FlexFit.tight : FlexFit.loose,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(controller.text!, style: type.row),
                ),
              ),
              const SizedBox(width: 4),
              if (action != null)
                TextButton(
                  key: const ValueKey('app-banner-action'),
                  onPressed: controller.showing ? controller.act : null,
                  child: Text(action),
                ),
            ],
          ),
        ),
      ),
    );
    return fill ? banner : IntrinsicWidth(child: banner);
  }
}
