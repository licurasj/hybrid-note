import 'package:intl/intl.dart';

import '../app/account_preferences.dart' show TimeFormat;
import '../app/date_preferences.dart';
import '../l10n/generated/app_localizations.dart';
import 'reminder_planner.dart';
import 'ring_booker.dart';

// What a ring shows (Q-97): the item's title, then its list's name and the
// time it is for. A time on the ring's own day shows alone; another day
// shows with its date; a day with no time shows only its date.
RingText reminderText(
  PlannedRing ring, {
  required AppLocalizations loc,
  required String locale,
  required TimeFormat format,
}) {
  final DateTime due = ring.due.toLocal();
  final DateTime at = ring.at.toLocal();
  final bool sameDay =
      due.year == at.year && due.month == at.month && due.day == at.day;
  final DateFormat time = timeFormat(locale, format);
  final String when = !ring.hasTime
      ? DateFormat.MMMEd(locale).format(due)
      : sameDay
      ? time.format(due)
      : DateFormat.MMMEd(locale).addPattern(time.pattern).format(due);
  return (
    title: ring.title.isEmpty ? ring.listName : ring.title,
    body: loc.reminderBody(ring.listName, when),
  );
}
