import 'dart:async';

import 'package:flutter/material.dart';

import '../app_colors.dart';
import 'app_theme.dart';

// A short message that floats above the screens, such as "List deleted · Undo"
// (T-21 unit 3). Material's snackbar fades in when it floats, and nothing fades
// here (AESTHETICS Motion). This one slides up, looks like the AI bar's answer
// panel and sits above the hub and the bar. A new message replaces the current
// one at once.
class AppBannerController {
  // How long a message stays; one with an action gets longer to use it.
  static const Duration plainFor = Duration(seconds: 4);
  static const Duration withActionFor = Duration(seconds: 6);

  String? _text;
  String? _actionLabel;
  VoidCallback? _onAction;
  bool _showing = false;
  Timer? _timer;
  final ValueNotifier<int> _changes = ValueNotifier(0);

  Listenable get changes => _changes;

  String? get text => _text;
  String? get actionLabel => _actionLabel;
  bool get showing => _showing;

  void show(String text, {String? actionLabel, VoidCallback? onAction}) {
    _timer?.cancel();
    _text = text;
    _actionLabel = actionLabel;
    _onAction = onAction;
    _showing = true;
    _timer = Timer(actionLabel == null ? plainFor : withActionFor, dismiss);
    _changes.value++;
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
  }
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

  // Clear of the hub and the AI bar in their default place.
  static const double _bottom = 120;
  static const double _maxWidth = 600;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    return Stack(
      children: [
        child,
        ListenableBuilder(
          listenable: controller.changes,
          builder: (context, _) {
            final double rest =
                _bottom + media.padding.bottom + media.viewInsets.bottom;
            return AnimatedPositioned(
              duration: media.disableAnimations
                  ? Duration.zero
                  : AppMotion.standard,
              curve: AppMotion.curve,
              onEnd: controller._gone,
              left: AppShapes.sideMargin,
              right: AppShapes.sideMargin,
              // Far enough down to be off the screen when it has gone.
              bottom: controller.showing ? rest : -rest,
              child: controller.text == null
                  ? const SizedBox.shrink()
                  : _Banner(controller: controller),
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBannerHost._maxWidth),
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
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(controller.text!, style: type.row),
                    ),
                  ),
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
      ),
    );
  }
}
