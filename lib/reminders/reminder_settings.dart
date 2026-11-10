import 'package:flutter/foundation.dart';

import '../lists/list_definition.dart';

// How early a reminder rings (T-13, Q-90): pick any of these; each pick is its
// own ring, and none picked means no rings. The wire values are what the
// synced preferences and a list's own choice (Q-117, Q-118) store.
enum ReminderLead {
  atTime('atTime', Duration.zero),
  minutes5('5m', Duration(minutes: 5)),
  minutes10('10m', Duration(minutes: 10)),
  minutes30('30m', Duration(minutes: 30)),
  hour1('1h', Duration(hours: 1)),
  // A calendar day before: the same wall-clock time the day before, also
  // over a clock change.
  day1('1d', Duration(days: 1));

  const ReminderLead(this.wire, this.before);

  final String wire;
  final Duration before;

  static const Set<ReminderLead> defaults = {atTime};

  static ReminderLead? maybeOf(Object? wire) {
    for (final ReminderLead lead in values) {
      if (lead.wire == wire) {
        return lead;
      }
    }
    return null;
  }

  // The picks in [raw] (a list of wire values), in this enum's order; unknown
  // values, from a newer build, are skipped. Null when [raw] is no list.
  static Set<ReminderLead>? setOf(Object? raw) {
    if (raw is! List) {
      return null;
    }
    final Set<Object?> wires = raw.toSet();
    return {
      for (final ReminderLead lead in values)
        if (wires.contains(lead.wire)) lead,
    };
  }

  // In this enum's order, so the same picks always store the same way.
  static List<String> wiresOf(Set<ReminderLead> leads) => [
    for (final ReminderLead lead in values)
      if (leads.contains(lead)) lead.wire,
  ];
}

// The reminder choices the planner needs: how early (general, and per list
// while lists may have their own) and the morning time for a day with no time
// (Q-91). Built from AccountPreferences.
@immutable
class ReminderSettings {
  const ReminderSettings({
    this.leads = ReminderLead.defaults,
    this.morningMinutes = defaultMorningMinutes,
    this.listsOwnLeads = true,
  });

  // 09:00 (Q-91).
  static const int defaultMorningMinutes = 9 * 60;

  final Set<ReminderLead> leads;
  // Minutes after midnight, local time.
  final int morningMinutes;
  final bool listsOwnLeads;

  // What [list] uses: its own picks while lists may have their own, else the
  // general ones (Q-117).
  Set<ReminderLead> leadsFor(ListDefinition list) {
    final Set<ReminderLead>? own = ReminderLead.setOf(list.ownReminderLeads);
    return listsOwnLeads && own != null ? own : leads;
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      setEquals(other.leads, leads) &&
      other.morningMinutes == morningMinutes &&
      other.listsOwnLeads == listsOwnLeads;

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(leads), morningMinutes, listsOwnLeads);
}
