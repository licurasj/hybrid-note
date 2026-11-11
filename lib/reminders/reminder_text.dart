import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../app/account_preferences.dart' show TimeFormat;
import '../app/date_preferences.dart';
import '../l10n/generated/app_localizations.dart';
import '../lists/list_icons.dart';
import 'reminder_planner.dart';
import 'ring_booker.dart';

// What a ring shows (Q-97; look Proposed in T-13 unit 9): the item's title,
// then the time it is for, with the list's name beside the app's name and
// everything the system tints in the list's colour. A time on the ring's own
// day shows alone; another day shows with its date; a day with no time shows
// only its date.
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
    body: when,
    subText: ring.listName,
    // The stored (light) value: notifications have one colour for both
    // shades, and Android darkens or lightens a tint that would not read.
    color: listColor(ring.listColor).toARGB32(),
    done: loc.reminderDone,
  );
}

// The open app gets intl's date data from Flutter's localizations; the
// background check (its own isolate) must load it before reminderText,
// or DateFormat throws LocaleDataException (T-13 unit 4 AVD check).
Future<void> prepareReminderText() => initializeDateFormatting();
