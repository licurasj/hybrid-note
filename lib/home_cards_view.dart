import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app/app_theme.dart';
import 'app_colors.dart';
import 'l10n/generated/app_localizations.dart';
import 'lists/list_definition.dart';
import 'lists/list_icons.dart';
import 'lists/list_item.dart';
import 'lists/list_labels.dart';
import 'lists/list_vocabulary.dart';

// How the home blob and the slanted pin look (docs/AESTHETICS.md, Marks).
const double _pinAngle = math.pi / 4;

// A list's card on home (Q-65): the blob with its disc and icon, the name, and
// the top open items with their dates. [pinned] is null on a suggestion, which
// has no pin; false is an unfilled pin, on a card that stays until the next
// refresh.
class HomeListCard extends StatelessWidget {
  const HomeListCard({
    super.key,
    required this.definition,
    required this.openItems,
    required this.pinned,
    this.onTap,
    this.onPin,
  });

  // The items a card shows (Q-65).
  static const int topItems = 3;

  final ListDefinition definition;
  final List<ListItem> openItems;
  final bool? pinned;
  final VoidCallback? onTap;
  final VoidCallback? onPin;

  static DateTime? _dateOf(ListDefinition definition, ListItem item) {
    FieldDefinition? field = definition.fieldWithRole(FieldRole.reminder);
    field ??= definition.fields
        .where(
          (candidate) =>
              candidate.type == FieldType.date ||
              candidate.type == FieldType.dateTime,
        )
        .firstOrNull;
    final Object? raw = field == null ? null : item[field.key];
    return raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
  }

  static String _titleOf(ListDefinition definition, ListItem item) {
    final Object? title =
        item[definition.fields
            .firstWhere(
              (field) => field.primary,
              orElse: () => definition.fields.first,
            )
            .key];
    return title is String ? title : '';
  }

  @override
  Widget build(BuildContext context) {
    final ListLabels labels = ListLabels(AppLocalizations.of(context));
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final AppTypography type = AppTypography.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();

    Widget itemRow(ListItem item) {
      final DateTime? date = _dateOf(definition, item);
      return Padding(
        padding: const EdgeInsets.only(top: 3, left: 18),
        child: Row(
          children: [
            Flexible(
              child: Text(
                _titleOf(definition, item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.row.copyWith(color: neutrals.text, fontSize: 13),
              ),
            ),
            if (date != null) ...[
              const SizedBox(width: 8),
              Text(
                DateFormat.MMMd(locale).format(date),
                softWrap: false,
                maxLines: 1,
                style: type.meta,
              ),
            ],
          ],
        ),
      );
    }

    return GestureDetector(
      key: ValueKey('home-card-${definition.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        // The name's row is 48 tall for the pin's touch target, which is the
        // rest of the 16 above it.
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 14),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: 88,
                height: 84,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      child: IgnorePointer(
                        child: HomeBlob(
                          seed: homeBlobSeed(definition.id),
                          color: listColor(
                            definition.color,
                            brightness: brightness,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 25,
                      top: 25,
                      width: 60,
                      height: 60,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: neutrals.text,
                        ),
                        child: Icon(
                          listIcon(definition.icon),
                          size: 27,
                          color: neutrals.ground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              labels.listName(definition),
                              maxLines: 1,
                              style: type.screenTitle.copyWith(
                                fontSize: 24,
                                height: 1.05,
                              ),
                            ),
                          ),
                        ),
                        if (pinned case final bool isPinned)
                          HomePinButton(
                            key: ValueKey('home-pin-${definition.id}'),
                            pinned: isPinned,
                            size: 18,
                            onPressed: onPin,
                          ),
                      ],
                    ),
                  ),
                  if (openItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 18),
                      child: Text(
                        labels.loc.homeNothingOpen,
                        style: type.row.copyWith(
                          color: neutrals.muted,
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    for (final ListItem item in openItems.take(topItems))
                      itemRow(item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The slanted pin, on a home card and in a list page's app bar.
class HomePinButton extends StatelessWidget {
  const HomePinButton({
    super.key,
    required this.pinned,
    required this.onPressed,
    this.size,
  });

  final bool pinned;
  final VoidCallback? onPressed;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final Color? color = size == null
        ? null
        : AppColors.neutrals(Theme.of(context).brightness).text;
    return IconButton(
      tooltip: pinned ? loc.homeUnpin : loc.homePin,
      isSelected: pinned,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Transform.rotate(
        angle: _pinAngle,
        child: Icon(
          pinned ? Icons.push_pin : Icons.push_pin_outlined,
          size: size,
          color: color,
        ),
      ),
    );
  }
}

// The same list keeps the same blob across app starts, which a String's
// hashCode does not promise (FNV-1a).
int homeBlobSeed(String listId) {
  int hash = 0x811c9dc5;
  for (final int unit in listId.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

// A flat, solid blob in the list's colour whose edge slowly swells and dips
// (docs/AESTHETICS.md, Motion). Reduced motion stops it, and it stops by itself
// while a page covers home, since a covered route's tickers are muted.
class HomeBlob extends StatefulWidget {
  const HomeBlob({super.key, required this.color, required this.seed});

  // Tests that settle cannot have something moving for ever on home; they run
  // with this on (test/flutter_test_config.dart).
  @visibleForTesting
  static bool stillForTests = false;

  static const double size = 84;

  final Color color;
  final int seed;

  @override
  State<HomeBlob> createState() => _HomeBlobState();
}

class _HomeBlobState extends State<HomeBlob>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: Duration(seconds: 7 + widget.seed % 7),
    // Each blob starts somewhere of its own, and is still there when stopped.
    value: (widget.seed % 100) / 100,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (HomeBlob.stillForTests || MediaQuery.disableAnimationsOf(context)) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) => CustomPaint(
        size: const Size.square(HomeBlob.size),
        painter: _BlobPainter(
          _loop.value * 2 * math.pi,
          widget.color,
          widget.seed,
        ),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.phase, this.color, this.seed);

  final double phase;
  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    final int f1 = 7 + seed % 5;
    final int f2 = 10 + (seed ~/ 5) % 6;
    final int f3 = 5 + (seed ~/ 30) % 5;
    final double p1 = (seed % 17) * 0.37;
    final double p2 = (seed % 13) * 0.51;
    final double amount = 1.3 + (seed % 7) * 0.15;
    const int points = 72;
    final Path path = Path();
    for (int i = 0; i <= points; i++) {
      final double angle = i / points * 2 * math.pi;
      final double edge =
          1 +
          amount * 0.045 * math.sin(f1 * angle + phase + p1) +
          amount * 0.04 * math.sin(f2 * angle - 2 * phase + p2) +
          amount * 0.03 * math.sin(f3 * angle + 3 * phase);
      final Offset point = Offset(
        size.width / 2 * 0.86 * edge * math.cos(angle),
        size.height / 2 * 0.86 * edge * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    // Stretched slightly toward the disc (down and right).
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(math.pi / 4);
    canvas.scale(1.16, 0.95);
    canvas.rotate(-math.pi / 4);
    canvas.drawPath(path..close(), Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.phase != phase || old.color != color || old.seed != seed;
}
