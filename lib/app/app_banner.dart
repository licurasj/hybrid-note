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
    if (!_showing && _text != null) {
      _text = null;
      _changes.value++;
    }
  }

  void act() {
    final VoidCallback? action = _onAction;
    dismiss();
    action?.call();
  }

  void dispose() {
    _timer?.cancel();
    _changes.dispose();
    _room.dispose();
  }
}

// Where the AI bar and the hub are on the screen, in global coordinates, so
// the banner can sit above the bar and off the hub. [bar] is null while the
// bar is hidden.
@immutable
class BannerRoom {
  const BannerRoom({this.bar, this.hub});

  final Rect? bar;
  final Rect? hub;

  @override
  bool operator ==(Object other) =>
      other is BannerRoom && other.bar == bar && other.hub == hub;

  @override
  int get hashCode => Object.hash(bar, hub);
}

// Where the banner goes: its left edge, its widest and its bottom edge from
// the bottom of the screen. [screen] is the whole screen, [keyboard] the
// keyboard's height and [inset] the system's bottom padding.
@visibleForTesting
({double left, double maxWidth, double bottom}) bannerPlace({
  required Size screen,
  required double keyboard,
  required double inset,
  BannerRoom? room,
}) {
  const double gap = AppBannerHost.gap;
  final double floor = screen.height - keyboard;
  double left = AppShapes.sideMargin;
  // The y of the banner's bottom edge.
  double bottomY = floor - math.max(inset, 0) - AppBannerHost.restGap;
  final Rect? bar = room?.bar;
  if (bar != null) {
    left = bar.left;
    bottomY = bar.top - gap;
  }
  double right = math.min(
    left + AppBannerHost.maxWidth,
    screen.width - AppShapes.sideMargin,
  );
  final Rect? hub = room?.hub;
  if (hub != null) {
    final Rect banner = Rect.fromLTRB(
      left,
      bottomY - AppBannerHost.tallest,
      right,
      bottomY,
    ).inflate(gap);
    if (banner.overlaps(hub)) {
      // Beside the hub when that leaves room enough, else above it.
      final bool hubRight = hub.center.dx >= (left + right) / 2;
      final double besideLeft = hubRight ? left : hub.right + gap;
      final double besideRight = hubRight ? hub.left - gap : right;
      if (besideRight - besideLeft >= AppBannerHost.narrowest) {
        left = besideLeft;
        right = besideRight;
      } else {
        bottomY = hub.top - gap;
      }
    }
  }
  return (
    left: left,
    maxWidth: math.max(0, right - left),
    bottom: screen.height - bottomY,
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
  // As wide as its words, up to this.
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
            return AnimatedPositioned(
              duration: media.disableAnimations
                  ? Duration.zero
                  : AppMotion.standard,
              curve: AppMotion.curve,
              onEnd: controller._gone,
              left: place.left,
              // Far enough down to be off the screen when it has gone.
              bottom: controller.showing ? place.bottom : -(tallest + 24),
              child: controller.text == null
                  ? const SizedBox.shrink()
                  : ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: place.maxWidth),
                      child: _Banner(controller: controller),
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.controller});

  final AppBannerController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals n = AppColors.neutrals(brightness);
    final AppTypography type = AppTypography.of(context);
    final String? action = controller.actionLabel;

    return IntrinsicWidth(
      child: Semantics(
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
      ),
    );
  }
}
