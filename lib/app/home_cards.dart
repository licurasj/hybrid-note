import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import '../lists/list_catalog.dart';
import '../lists/list_definition.dart';
import '../lists/list_item.dart';
import '../lists/list_rules.dart';
import '../lists/list_vocabulary.dart';

// Suggestions only fill in: at most this many, and only up to [homeCardsFilled]
// cards in all. Pinned lists have no limit (Q-70).
const int homeMaxSuggestions = 3;
const int homeCardsFilled = 5;

// How far ahead a due item ranks a suggestion (the demo's ranking, Q-65).
const Duration homeDueHorizon = Duration(days: 7);

// The ids that still have a list. Reading skips the others anyway; writing
// goes through this so that they do not pile up in the account's document.
List<String> keepExistingIds(Iterable<String> ids, Iterable<String> existing) {
  final Set<String> lists = existing.toSet();
  return {
    for (final String id in ids)
      if (lists.contains(id)) id,
  }.toList();
}

// The pinned lists in home's order (Q-75). Until home has been arranged they
// follow the dial, whose order [dialOrder] holds. After that they keep the
// dragged order, and a list pinned since joins the end.
List<String> homePinnedOrder({
  required List<String> pins,
  required List<String> dialOrder,
  required List<String> homeOrder,
  required bool homeArranged,
}) {
  final Set<String> pinned = keepExistingIds(pins, dialOrder).toSet();
  if (!homeArranged) {
    return [
      for (final String id in dialOrder)
        if (pinned.contains(id)) id,
    ];
  }
  return {
    for (final String id in homeOrder)
      if (pinned.contains(id)) id,
    ...pinned,
  }.toList();
}

// The dial following a home drag (Q-75): the lists in [homeOrder] take that
// order among the places they already hold, and every other list stays put.
List<String> mergeHomeOrderIntoDial(
  List<String> dialOrder,
  List<String> homeOrder,
) {
  final Set<String> moved = keepExistingIds(homeOrder, dialOrder).toSet();
  final Iterator<String> next = moved.iterator;
  return [
    for (final String id in dialOrder)
      if (moved.contains(id)) (next..moveNext()).current else id,
  ];
}

// How many suggestions go with this many pinned lists (Q-70).
int homeSuggestionCount(int pinned) =>
    math.min(homeMaxSuggestions, math.max(0, homeCardsFilled - pinned));

// A card's open items, top first (Q-65): earliest due first, so overdue ones
// lead, then those with no due date by newest. Only a reminder is a due date; a
// journal entry's own date is not.
List<ListItem> homeTopItems(ListDefinition definition, List<ListItem> items) {
  final FieldDefinition? field = definition.fieldWithRole(FieldRole.reminder);
  DateTime? dueOf(ListItem item) {
    final Object? raw = field == null ? null : item[field.key];
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  final List<ListItem> open = items
      .where((item) => !ListRules.isCompleted(definition, item))
      .toList();
  return open..sort((a, b) {
    final int order = switch ((dueOf(a), dueOf(b))) {
      (final DateTime x, final DateTime y) => x.compareTo(y),
      (DateTime(), null) => -1,
      (null, DateTime()) => 1,
      _ => b.createdAt.compareTo(a.createdAt),
    };
    return order != 0 ? order : a.id.compareTo(b.id);
  });
}

// What a card offers, in its hold's prompts and its three dots (Q-76).
enum HomeCardAction { rearrange, edit, unpin, pin, remove, noSuggestions }

// [pinned] is null on a suggestion and false on an unfilled pin. There is
// nothing to rearrange with fewer than two pinned lists.
List<HomeCardAction> homeCardActions({
  required bool? pinned,
  required int pinnedLists,
}) => switch (pinned) {
  true => [
    if (pinnedLists >= 2) HomeCardAction.rearrange,
    HomeCardAction.edit,
    HomeCardAction.unpin,
  ],
  false => const [HomeCardAction.pin, HomeCardAction.edit],
  null => const [
    HomeCardAction.pin,
    HomeCardAction.edit,
    HomeCardAction.remove,
    HomeCardAction.noSuggestions,
  ],
};

// The prompts stand in one row above the finger, side by side, so that a hand
// coming from below covers none of them whichever hand it is (owner, 2026-11-06).
const double homePromptGap = 6;
const double homePromptMargin = 12;
// From the finger to the middle of the row.
const double homePromptRise = 68;
// The AI bar and the bottom of the screen.
const double homePromptBottomRoom = 110;
const double homePromptHeight = 40;
const double homePromptWrappedHeight = 46;
const double _promptLoosePadding = 14;
const double _promptTightPadding = 8;
// A prompt's border on both sides, and a little for rounding.
const double _promptExtraWidth = 4;

// How the labels fit one row: [wrapped] holds the prompts on two lines, and
// [widths] each prompt's whole width.
typedef HomePromptFit = ({
  double padding,
  Set<int> wrapped,
  double textScale,
  List<double> widths,
});

// [oneLine] and [broken] are the labels' widths on one line and at their best
// break. The first that fits [room] wins: roomy, then tighter, then the widest
// labels on two lines one by one, and last the text a little smaller.
HomePromptFit homePromptFit({
  required List<double> oneLine,
  required List<double> broken,
  required double room,
}) {
  final int count = oneLine.length;
  double total(Iterable<double> text, double padding) =>
      text.fold<double>(0, (sum, width) => sum + width) +
      count * (2 * padding + _promptExtraWidth) +
      (count - 1) * homePromptGap;
  HomePromptFit fit(
    List<double> text,
    double padding,
    Set<int> wrapped,
    double scale,
  ) => (
    padding: padding,
    wrapped: wrapped,
    textScale: scale,
    widths: [
      for (final double width in text)
        width * scale + 2 * padding + _promptExtraWidth,
    ],
  );

  if (total(oneLine, _promptLoosePadding) <= room) {
    return fit(oneLine, _promptLoosePadding, const {}, 1);
  }
  if (total(oneLine, _promptTightPadding) <= room) {
    return fit(oneLine, _promptTightPadding, const {}, 1);
  }
  final List<double> text = [...oneLine];
  final Set<int> wrapped = {};
  final List<int> widestFirst = [for (int i = 0; i < count; i++) i]
    ..sort((a, b) => oneLine[b].compareTo(oneLine[a]));
  for (final int i in widestFirst) {
    if (broken[i] < oneLine[i]) {
      text[i] = broken[i];
      wrapped.add(i);
      if (total(text, _promptTightPadding) <= room) {
        return fit(text, _promptTightPadding, wrapped, 1);
      }
    }
  }
  final double chrome = total(text.map((_) => 0.0), _promptTightPadding);
  final double scale =
      (room - chrome) / text.fold<double>(0, (sum, w) => sum + w);
  return fit(text, _promptTightPadding, wrapped, math.min(scale, 1));
}

// The row's places: centred on the finger, above it, kept on screen and off
// [avoid] (the hub). Only with no room above does it go below the finger.
List<Rect> homePromptRow({
  required Offset finger,
  required List<double> widths,
  required double height,
  required Size screen,
  required double top,
  required double bottom,
  Rect? avoid,
}) {
  final double half = height / 2;
  final double rowWidth =
      widths.fold<double>(0, (sum, width) => sum + width) +
      (widths.length - 1) * homePromptGap;
  final double leftmost = homePromptMargin;
  final double rightmost = math.max(
    leftmost,
    screen.width - homePromptMargin - rowWidth,
  );
  double left = (finger.dx - rowWidth / 2).clamp(leftmost, rightmost);
  double y = finger.dy - homePromptRise;
  if (y - half < top) {
    y = finger.dy + homePromptRise;
  }
  y = y.clamp(top + half, math.max(top + half, bottom - half));
  if (avoid != null) {
    Rect row() => Rect.fromLTWH(left, y - half, rowWidth, height);
    if (row().overlaps(avoid)) {
      // Beside the hub if it fits there, which keeps the row near the finger.
      final double beforeHub = avoid.left - 8 - rowWidth;
      final double afterHub = avoid.right + 8;
      if (beforeHub >= leftmost && beforeHub <= rightmost) {
        left = beforeHub;
      } else if (afterHub >= leftmost && afterHub <= rightmost) {
        left = afterHub;
      } else if (avoid.top - 8 - height >= top) {
        y = avoid.top - 8 - half;
      } else {
        y = math.max(y, avoid.bottom + 8 + half);
      }
    }
  }
  final List<Rect> rects = [];
  double x = left;
  for (final double width in widths) {
    rects.add(Rect.fromLTWH(x, y - half, width, height));
    x += width + homePromptGap;
  }
  return rects;
}

// How far the finger has come from [start] to the prompt: 1 once it is on it.
double homePromptProgress(Offset start, Offset finger, Rect prompt) {
  double away(Offset point) => Offset(
    math.max(math.max(prompt.left - point.dx, point.dx - prompt.right), 0),
    math.max(math.max(prompt.top - point.dy, point.dy - prompt.bottom), 0),
  ).distance;
  return (1 - away(finger) / math.max(away(start), 1)).clamp(0.0, 1.0);
}

// What home shows: pinned lists in [pinnedOrder], which any list without a
// pin has already left, and below them the suggestions (Q-70, Q-78, Q-79).
({List<ListDefinition> pinned, List<ListDefinition> suggested}) chooseHomeCards(
  ListCatalog catalog, {
  required List<String> pinnedOrder,
  required List<String> removed,
  required bool showSuggestions,
  required DateTime now,
}) {
  final List<ListDefinition> pinned = [
    for (final String id in pinnedOrder)
      if (catalog.definition(id) case final ListDefinition definition)
        definition,
  ];
  return (
    pinned: pinned,
    suggested: showSuggestions
        ? _suggestions(
            catalog,
            leftOut: {...pinnedOrder, ...removed},
            count: homeSuggestionCount(pinned.length),
            now: now,
          )
        : const [],
  );
}

// Lists with open items, soonest due within [homeDueHorizon] first, then the
// most recently changed. Equal ones keep the catalog's order.
List<ListDefinition> _suggestions(
  ListCatalog catalog, {
  required Set<String> leftOut,
  required int count,
  required DateTime now,
}) {
  final List<
    ({int place, ListDefinition list, DateTime? due, DateTime changed})
  >
  candidates = [];
  for (int place = 0; place < catalog.definitions.length; place++) {
    final ListDefinition definition = catalog.definitions[place];
    if (leftOut.contains(definition.id)) {
      continue;
    }
    final List<ListItem> open = catalog
        .itemsOf(definition.id)
        .where((item) => !ListRules.isCompleted(definition, item))
        .toList();
    if (open.isEmpty) {
      continue;
    }
    candidates.add((
      place: place,
      list: definition,
      due: _soonestDue(definition, open, now),
      changed: open
          .map((item) => item.updatedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b),
    ));
  }
  candidates.sort((a, b) {
    final DateTime? aDue = a.due;
    final DateTime? bDue = b.due;
    final int order = switch ((aDue, bDue)) {
      (final DateTime x, final DateTime y) => x.compareTo(y),
      (DateTime(), null) => -1,
      (null, DateTime()) => 1,
      _ => b.changed.compareTo(a.changed),
    };
    return order != 0 ? order : a.place.compareTo(b.place);
  });
  return [for (final candidate in candidates.take(count)) candidate.list];
}

// Overdue items count as the soonest of all.
DateTime? _soonestDue(
  ListDefinition definition,
  List<ListItem> open,
  DateTime now,
) {
  final FieldDefinition? field = definition.fieldWithRole(FieldRole.reminder);
  if (field == null) {
    return null;
  }
  final DateTime horizon = now.add(homeDueHorizon);
  DateTime? soonest;
  for (final ListItem item in open) {
    final Object? raw = item[field.key];
    final DateTime? date = raw is String ? DateTime.tryParse(raw) : null;
    if (date != null &&
        date.isBefore(horizon) &&
        (soonest == null || date.isBefore(soonest))) {
      soonest = date;
    }
  }
  return soonest;
}
