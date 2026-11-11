import 'package:flutter/foundation.dart';

import '../lists/item_dates.dart';
import '../lists/list_catalog.dart';
import '../lists/list_definition.dart';
import '../lists/list_item.dart';
import '../lists/list_rules.dart';
import '../lists/list_vocabulary.dart';
import 'reminder_settings.dart';

// One ring the phone should have booked (T-13 unit 2). [key] names it across
// plans, so booking only changes what differs; the rest is what the
// notification shows and what its tap and Done need.
@immutable
class PlannedRing {
  const PlannedRing({
    required this.key,
    required this.listId,
    required this.itemId,
    required this.at,
    required this.due,
    required this.hasTime,
    required this.itemDate,
    required this.title,
    required this.listName,
    required this.listColor,
  });

  final String key;
  final String listId;
  final String itemId;
  // When it rings, UTC.
  final DateTime at;
  // The occurrence it is for, UTC: the moment, or the day's local midnight
  // for a day with no time.
  final DateTime due;
  final bool hasTime;
  // The item's stored date when planned. Done does nothing when it has
  // changed since (T-13 unit 4).
  final String itemDate;
  final String title;
  final String listName;
  // The list's stored colour, #RRGGBB (the light value): the ring's tint
  // (T-13 unit 9).
  final String listColor;

  @override
  bool operator ==(Object other) =>
      other is PlannedRing &&
      other.key == key &&
      other.listId == listId &&
      other.itemId == itemId &&
      other.at == at &&
      other.due == due &&
      other.hasTime == hasTime &&
      other.itemDate == itemDate &&
      other.title == title &&
      other.listName == listName &&
      other.listColor == listColor;

  @override
  int get hashCode => Object.hash(
    key,
    listId,
    itemId,
    at,
    due,
    hasTime,
    itemDate,
    title,
    listName,
    listColor,
  );

  @override
  String toString() => 'PlannedRing($key at $at)';
}

// From the lists, the reminder settings and now to the rings this phone
// should have booked (Rules in tasks/T-13-reminders.md). Pure, so it is tested
// on its own and the booker only books the difference.
//
// - Lists ring through their date field marked as a reminder (Q-96).
// - Each picked lead is its own ring; none picked, no rings (Q-90).
// - A day with no time, or a date field, rings at the morning time on the
//   day, and the morning before as well when 1 day before is picked (Q-91).
// - A repeat rings at every occurrence ahead, ticked or not, as long as the
//   item is there with its repeat on (Q-92). A ticked item's own date does
//   not ring; nor does a ticked item without a repeat.
// - Only times after [now] (no catch-up), at most [horizon] ahead and the
//   [limit] soonest. With [late] it also plans the times up to [late] before
//   [now] (F5): the booker never books those, but keeps one still booked, so
//   an inexact ring Android delivers late is not cancelled first.
class ReminderPlanner {
  static const Duration horizon = Duration(days: 30);

  // How long a booked ring may be late and still ring (F5): inexact rings
  // wait for the phone's idle windows.
  static const Duration lateDelivery = Duration(hours: 2);
  static const int limit = 200;

  static List<PlannedRing> plan({
    required ListCatalog catalog,
    required ReminderSettings settings,
    required DateTime now,
    required String Function(ListDefinition list) listName,
    Duration horizon = ReminderPlanner.horizon,
    int limit = ReminderPlanner.limit,
    Duration late = Duration.zero,
  }) {
    final DateTime start = now.toUtc().subtract(late);
    final DateTime end = now.toUtc().add(horizon);
    final List<PlannedRing> rings = [];

    for (final ListDefinition list in catalog.definitions) {
      final FieldDefinition? field = list.fieldWithRole(FieldRole.reminder);
      if (field == null ||
          (field.type != FieldType.date && field.type != FieldType.dateTime)) {
        continue;
      }
      final Set<ReminderLead> leads = settings.leadsFor(list);
      if (leads.isEmpty) {
        continue;
      }
      final BehaviorDefinition? repeat = list.behaviors
          .where(
            (behavior) =>
                behavior.kind == BehaviorKind.recurOnClear &&
                behavior.stringParam('dateField') == field.key,
          )
          .firstOrNull;
      final String name = listName(list);

      for (final ListItem item in catalog.itemsOf(list.id)) {
        final Object? raw = item[field.key];
        final DateTime? local = ItemDates.local(raw, field.type);
        if (raw is! String || local == null) {
          continue;
        }
        final bool hasTime = ItemDates.hasTime(field.type, raw);
        final bool ticked = ListRules.isCompleted(list, item);
        final ({RecurrenceFrequency frequency, int? customDays})? recurrence =
            _recurrence(item, repeat);
        if (ticked && recurrence == null) {
          continue;
        }
        // A day's occurrence counts from its local midnight.
        final DateTime base = hasTime
            ? local
            : DateTime(local.year, local.month, local.day);
        final String title = _title(list, item);

        // The occurrences whose rings may fall in [start, end]: a ring is at
        // most a day and a morning before its occurrence.
        final DateTime earliest = start.subtract(const Duration(days: 2));
        for (int n = ticked ? 1 : 0; ; n++) {
          final DateTime? occurrence = n == 0
              ? base
              : recurrence == null
              ? null
              : ListRules.occurrence(
                  base,
                  recurrence.frequency,
                  recurrence.customDays,
                  n,
                );
          if (occurrence == null || occurrence.toUtc().isAfter(end.add(const Duration(days: 2)))) {
            break;
          }
          if (occurrence.toUtc().isBefore(earliest)) {
            if (n > 100000) {
              break;
            }
            continue;
          }
          for (final (ReminderLead lead, DateTime at) in _times(
            occurrence,
            hasTime,
            leads,
            settings.morningMinutes,
          )) {
            final DateTime atUtc = at.toUtc();
            if (!atUtc.isAfter(start) || atUtc.isAfter(end)) {
              continue;
            }
            final DateTime due = occurrence.toUtc();
            rings.add(
              PlannedRing(
                key:
                    '${list.id}|${item.id}|${due.millisecondsSinceEpoch}|${lead.wire}',
                listId: list.id,
                itemId: item.id,
                at: atUtc,
                due: due,
                hasTime: hasTime,
                itemDate: raw,
                title: title,
                listName: name,
                listColor: list.color,
              ),
            );
          }
        }
      }
    }

    rings.sort((a, b) {
      final int byTime = a.at.compareTo(b.at);
      return byTime != 0 ? byTime : a.key.compareTo(b.key);
    });
    return rings.length > limit ? rings.sublist(0, limit) : rings;
  }

  // The item's repeat, or null for none (or no repeat rule on the list).
  static ({RecurrenceFrequency frequency, int? customDays})? _recurrence(
    ListItem item,
    BehaviorDefinition? repeat,
  ) {
    final String? field = repeat?.stringParam('recurrenceField');
    final Object? value = field == null ? null : item[field];
    if (value is! Map) {
      return null;
    }
    final RecurrenceFrequency? frequency = enumFromWire(
      RecurrenceFrequency.values,
      value['frequency'],
    );
    if (frequency == null || frequency == RecurrenceFrequency.none) {
      return null;
    }
    final Object? days = value['customDays'];
    if (frequency == RecurrenceFrequency.custom && (days is! int || days <= 0)) {
      return null;
    }
    return (frequency: frequency, customDays: days is int ? days : null);
  }

  // When [occurrence] (local) rings for each lead. A day rings at the morning
  // time, once, and the morning before with 1 day before; the minute and hour
  // leads do not apply to it (Q-91).
  static List<(ReminderLead, DateTime)> _times(
    DateTime occurrence,
    bool hasTime,
    Set<ReminderLead> leads,
    int morningMinutes,
  ) {
    if (!hasTime) {
      DateTime morning(int dayOffset) => DateTime(
        occurrence.year,
        occurrence.month,
        occurrence.day + dayOffset,
        morningMinutes ~/ 60,
        morningMinutes % 60,
      );
      return [
        (ReminderLead.atTime, morning(0)),
        if (leads.contains(ReminderLead.day1)) (ReminderLead.day1, morning(-1)),
      ];
    }
    return [
      for (final ReminderLead lead in ReminderLead.values)
        if (leads.contains(lead))
          (
            lead,
            lead == ReminderLead.day1
                ? DateTime(
                    occurrence.year,
                    occurrence.month,
                    occurrence.day - 1,
                    occurrence.hour,
                    occurrence.minute,
                  )
                : occurrence.subtract(lead.before),
          ),
    ];
  }

  // The item's title: its primary field, else the first, as home shows it.
  static String _title(ListDefinition list, ListItem item) {
    if (list.fields.isEmpty) {
      return '';
    }
    final FieldDefinition field = list.fields.firstWhere(
      (field) => field.primary,
      orElse: () => list.fields.first,
    );
    final Object? value = item[field.key];
    return value is String ? value.trim() : value?.toString() ?? '';
  }
}
