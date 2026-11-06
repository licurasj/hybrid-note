import 'dart:math' as math;

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
