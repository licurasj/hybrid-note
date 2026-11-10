import 'item_dates.dart';
import 'list_definition.dart';
import 'list_item.dart';
import 'list_vocabulary.dart';

// What one user action does to a list: items to write and item ids to delete.
// Rules and screens produce these; a ListStore applies them.
class ListChanges {
  final List<ListItem> saved;
  final List<String> deletedIds;

  const ListChanges({
    this.saved = const [],
    this.deletedIds = const [],
  });

  bool get isEmpty => saved.isEmpty && deletedIds.isEmpty;
}

// Runs a definition's behaviours. Pure functions over items, so the same code
// works on today's storage and on Firestore later.
class ListRules {
  static FieldDefinition? _completion(ListDefinition definition) {
    return definition.fieldWithRole(FieldRole.completion);
  }

  // An item taken off home's Today rows by hand (Q-107): kept on the item, so
  // it syncs; the item is otherwise unchanged in its list. Keys starting with
  // "_" are never field keys.
  static const String homeHiddenKey = '_homeHidden';

  static bool isHiddenFromHome(ListItem item) => item[homeHiddenKey] == true;

  static ListChanges setHiddenFromHome(ListItem item, bool hidden, DateTime now) {
    final Map<String, dynamic> values = {...item.values};
    if (hidden) {
      values[homeHiddenKey] = true;
    } else {
      values.remove(homeHiddenKey);
    }
    return ListChanges(
      saved: [
        ListItem(
          id: item.id,
          listId: item.listId,
          values: values,
          createdAt: item.createdAt,
          updatedAt: now,
        ),
      ],
    );
  }

  static bool isCompleted(ListDefinition definition, ListItem item) {
    final FieldDefinition? completion = _completion(definition);
    return completion != null && item[completion.key] == true;
  }

  static ListItem withValues(
    ListItem item,
    Map<String, dynamic> changes,
    DateTime now,
  ) {
    return ListItem(
      id: item.id,
      listId: item.listId,
      values: {...item.values, ...changes},
      createdAt: item.createdAt,
      updatedAt: now,
    );
  }

  static ListChanges setCompleted(
    ListDefinition definition,
    ListItem item,
    bool done,
    DateTime now,
  ) {
    final FieldDefinition? completion = _completion(definition);
    if (completion == null) {
      return const ListChanges();
    }

    return ListChanges(saved: [withValues(item, {completion.key: done}, now)]);
  }

  // Moving an item to another section starts it fresh (not completed), as
  // the grocery list always did.
  static ListChanges moveTo(
    ListDefinition definition,
    ListItem item,
    String field,
    String value,
    DateTime now,
  ) {
    final FieldDefinition? completion = _completion(definition);
    return ListChanges(
      saved: [
        withValues(item, {
          field: value,
          if (completion != null) completion.key: false,
        }, now),
      ],
    );
  }

  static ListChanges moveAll(
    ListDefinition definition,
    List<ListItem> items,
    BehaviorDefinition behavior,
    DateTime now,
  ) {
    final String? field = behavior.stringParam('field');
    final String? from = behavior.stringParam('from');
    final String? to = behavior.stringParam('to');
    if (field == null || from == null || to == null) {
      return const ListChanges();
    }

    final List<ListItem> saved = [];
    for (final ListItem item in items) {
      if (item[field] == from) {
        saved.addAll(moveTo(definition, item, field, to, now).saved);
      }
    }

    return ListChanges(saved: saved);
  }

  // Keeps values consistent before saving: a repeat without a date to repeat
  // from is turned off, as the task list always did.
  static ListItem normalize(ListDefinition definition, ListItem item) {
    final Map<String, dynamic> values = Map<String, dynamic>.from(item.values);

    for (final BehaviorDefinition behavior in definition.behaviors) {
      if (behavior.kind != BehaviorKind.recurOnClear) {
        continue;
      }

      final String? dateField = behavior.stringParam('dateField');
      final String? recurrenceField = behavior.stringParam('recurrenceField');
      if (dateField != null &&
          recurrenceField != null &&
          values[dateField] == null &&
          values[recurrenceField] is Map) {
        values[recurrenceField] = {
          'frequency': RecurrenceFrequency.none.wire,
        };
      }
    }

    return ListItem(
      id: item.id,
      listId: item.listId,
      values: values,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
    );
  }

  // Removes completed items (only those `inScope` accepts, when given) and
  // runs copyOnClear and recurOnClear for each.
  static ListChanges clearCompleted(
    ListDefinition definition,
    List<ListItem> items,
    DateTime now, {
    bool Function(ListItem item)? inScope,
    String Function()? newId,
  }) {
    // A copy's id comes from its original (Codex review H2), as a repeat's
    // does: two phones clearing the same item write the same copy, not two.
    // Older copies keep their random ids. [newId] is for tests.
    final String Function(ListItem item) makeId = newId == null
        ? (item) => 'copy-${item.id}'
        : (_) => newId();
    final List<String> deletedIds = [];
    final List<ListItem> added = [];

    for (final ListItem item in items) {
      if (!isCompleted(definition, item) ||
          (inScope != null && !inScope(item))) {
        continue;
      }

      deletedIds.add(item.id);

      for (final BehaviorDefinition behavior in definition.behaviors) {
        final ListItem? created = switch (behavior.kind) {
          BehaviorKind.copyOnClear => _copyOnClear(
              definition,
              behavior,
              item,
              [...items.where((other) => !deletedIds.contains(other.id)), ...added],
              now,
              makeId,
            ),
          BehaviorKind.recurOnClear => _recurOnClear(
              definition,
              behavior,
              item,
              now,
            ),
          BehaviorKind.moveAll || BehaviorKind.clearCompleted => null,
        };

        if (created != null && !added.any((other) => other.id == created.id)) {
          added.add(created);
        }
      }
    }

    // A repeat can land on an id that already exists (cleared twice).
    final Set<String> existing = items.map((item) => item.id).toSet();
    return ListChanges(
      saved: added.where((item) => !existing.contains(item.id)).toList(),
      deletedIds: deletedIds,
    );
  }

  static ListItem? _copyOnClear(
    ListDefinition definition,
    BehaviorDefinition behavior,
    ListItem item,
    List<ListItem> remaining,
    DateTime now,
    String Function(ListItem item) makeId,
  ) {
    final String? when = behavior.stringParam('when');
    if (when == null || item[when] != true) {
      return null;
    }

    final Map<String, dynamic> where = behavior.mapParam('where');
    if (where.entries.any((entry) => item[entry.key] != entry.value)) {
      return null;
    }

    final Map<String, dynamic> setField = behavior.mapParam('setField');
    final String? dedupeBy = behavior.stringParam('dedupeBy');
    if (dedupeBy != null) {
      final String key = _normalized(item[dedupeBy]);
      final bool duplicate = remaining.any((other) {
        return !isCompleted(definition, other) &&
            setField.entries.every((entry) => other[entry.key] == entry.value) &&
            _normalized(other[dedupeBy]) == key;
      });
      if (duplicate) {
        return null;
      }
    }

    final FieldDefinition? completion = _completion(definition);
    return ListItem(
      id: makeId(item),
      listId: item.listId,
      // A copy is a new row on home, even if the item was hidden there.
      values: {
        ...item.values,
        ...setField,
        if (completion != null) completion.key: false,
      }..remove(homeHiddenKey),
      createdAt: now,
      updatedAt: now,
    );
  }

  static ListItem? _recurOnClear(
    ListDefinition definition,
    BehaviorDefinition behavior,
    ListItem item,
    DateTime now,
  ) {
    final String? dateField = behavior.stringParam('dateField');
    final String? recurrenceField = behavior.stringParam('recurrenceField');
    if (dateField == null || recurrenceField == null) {
      return null;
    }

    final Object? rawDate = item[dateField];
    final Object? recurrence = item[recurrenceField];
    if (rawDate is! String || recurrence is! Map) {
      return null;
    }

    final DateTime? date = DateTime.tryParse(rawDate);
    final RecurrenceFrequency? frequency = enumFromWire(
      RecurrenceFrequency.values,
      recurrence['frequency'],
    );
    if (date == null || frequency == null) {
      return null;
    }

    // A day with no time stays one (Q-91); a date field's day too.
    final bool dayOnly = ItemDates.isDayOnly(rawDate) ||
        definition.field(dateField)?.type == FieldType.date;
    final DateTime? next = nextOccurrence(
      date,
      frequency,
      recurrence['customDays'] as int?,
      now,
      dayOnly: dayOnly,
    );
    if (next == null) {
      return null;
    }

    // Deterministic id, so two devices clearing the same item create the
    // same next occurrence instead of two.
    final String nextId = 'repeat-${item.id}-${next.millisecondsSinceEpoch}';
    final FieldDefinition? completion = _completion(definition);
    // The next one shows on home even if this one was hidden there.
    final Map<String, dynamic> values = {
      ...item.values,
      dateField: ItemDates.isDayOnly(rawDate)
          ? ItemDates.dayValue(next.toLocal())
          : next.toIso8601String(),
      if (completion != null) completion.key: false,
    }..remove(homeHiddenKey);

    for (final FieldDefinition field in definition.fields) {
      final Object? subItems = values[field.key];
      if (field.type == FieldType.checklist && subItems is List) {
        values[field.key] = [
          for (final Object? entry in subItems)
            if (entry is Map)
              {
                ...entry,
                'id': '$nextId-subtask-${entry['id']}',
                'done': false,
                'createdAt': now.toIso8601String(),
                'updatedAt': now.toIso8601String(),
              },
        ];
      }
    }

    return ListItem(
      id: nextId,
      listId: item.listId,
      values: values,
      createdAt: now,
      updatedAt: now,
    );
  }

  // The first occurrence after `now`, stepping in the local time zone by
  // calendar days, so a daily 8:00 stays at 8:00 across a clock change.
  // Months and years clamp to the last day, counted from `from` each time, so
  // the 31st comes back on the 31st where the month has one. A day with no
  // time ([dayOnly], T-13 Q-91) stays due all day: today counts as after `now`.
  static DateTime? nextOccurrence(
    DateTime from,
    RecurrenceFrequency frequency,
    int? customDays,
    DateTime now, {
    bool dayOnly = false,
  }) {
    final DateTime local = from.toLocal();
    final DateTime localNow = now.toLocal();
    final DateTime today = DateTime(localNow.year, localNow.month, localNow.day);
    for (int n = 1; n <= 100000; n++) {
      final DateTime? next = occurrence(local, frequency, customDays, n);
      if (next == null) {
        return null;
      }
      final bool passed = dayOnly
          ? next.isBefore(today)
          : !next.toUtc().isAfter(now);
      if (!passed) {
        return next.toUtc();
      }
    }
    return null;
  }

  // The n-th occurrence after `local` (n = 1 is the next one), in local
  // time; null for no repeat. The reminder planner books from these too.
  static DateTime? occurrence(
    DateTime local,
    RecurrenceFrequency frequency,
    int? customDays,
    int n,
  ) {
    DateTime days(int count) => DateTime(
      local.year,
      local.month,
      local.day + count,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
    switch (frequency) {
      case RecurrenceFrequency.none:
        return null;
      case RecurrenceFrequency.daily:
        return days(n);
      case RecurrenceFrequency.weekly:
        return days(7 * n);
      case RecurrenceFrequency.monthly:
        return _clamped(local, local.year, local.month + n);
      case RecurrenceFrequency.yearly:
        return _clamped(local, local.year + n, local.month);
      case RecurrenceFrequency.custom:
        if (customDays == null || customDays <= 0) {
          return null;
        }
        return days(customDays * n);
    }
  }

  static DateTime _clamped(DateTime local, int year, int month) {
    final int maxDay = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      local.day > maxDay ? maxDay : local.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  }

  static String _normalized(Object? value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }
}
