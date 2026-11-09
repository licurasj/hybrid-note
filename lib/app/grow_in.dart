import 'package:flutter/widgets.dart';

import 'app_theme.dart';

// A button that comes and goes in its own spot (interaction law rule 7,
// Q-105): it grows out from its leading edge when shown and shrinks back when
// hidden, so the buttons beside it never jump. Nothing fades. With reduced
// motion it appears and goes at once.
//
// Place it after the buttons that must stay put (to the right in a
// left-aligned bar, to the left in a right-aligned one) so its growing
// takes room only from empty space.
class GrowIn extends StatefulWidget {
  const GrowIn({
    super.key,
    required this.shown,
    required this.child,
    this.alignment = AlignmentDirectional.centerStart,
    this.vertical = true,
  });

  final bool shown;
  final Widget child;

  // Where the child is anchored while it grows: the side next to the buttons
  // that stay.
  final AlignmentGeometry alignment;

  // Also grow in height, so a bar that had no buttons opens smoothly instead
  // of pushing what is below down at once. Off where the height is fixed (the
  // top bar).
  final bool vertical;

  @override
  State<GrowIn> createState() => _GrowInState();
}

class _GrowInState extends State<GrowIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
    value: widget.shown ? 1 : 0,
  );
  late final Animation<double> _size = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.curve,
    reverseCurve: AppMotion.curve.flipped,
  );

  // The child last shown, kept on screen while it shrinks away.
  late Widget _child = widget.child;

  @override
  void didUpdateWidget(GrowIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shown) {
      _child = widget.child;
    }
    if (widget.shown == oldWidget.shown) {
      return;
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = widget.shown ? 1 : 0;
    } else if (widget.shown) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _size,
      builder: (context, child) {
        final double factor = _size.value;
        if (factor == 0) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: Align(
            alignment: widget.alignment,
            widthFactor: factor,
            heightFactor: widget.vertical ? factor : 1,
            child: child,
          ),
        );
      },
      // A hidden button cannot be tapped while it shrinks.
      child: IgnorePointer(ignoring: !widget.shown, child: _child),
    );
  }
}
