// T-13 unit 10, F15 (C13): daily rings across the spring and autumn clock
// changes of the zone the tests run in. The planner works in the phone's
// local time, so the test finds that zone's 2026 changes and plans across
// each; a zone without clock changes skips it. On Linux or macOS run it in a
// named zone with TZ (`TZ=Europe/Berlin flutter test test/reminders/
// reminder_dst_test.dart`); on Windows TZ shifts only the base offset and the
// change dates stay the machine's.
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/reminders/reminder_planner.dart';
import 'package:hybrid_note/reminders/reminder_settings.dart';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// Each local day of 2026 whose noon has a different offset from the
// day before: the day of a clock change.
List<DateTime> _changes() {
  final List<DateTime> days = [];
  for (int day = 1; day < 366; day++) {
    final DateTime noon = DateTime(2026, 1, day, 12);
    final DateTime before = DateTime(2026, 1, day - 1, 12);
    if (noon.timeZoneOffset != before.timeZoneOffset) {
      days.add(DateTime(noon.year, noon.month, noon.day));
    }
  }
  return days;
}

List<PlannedRing> _daily(
  DateTime first, {
  required DateTime now,
  Set<ReminderLead> leads = ReminderLead.defaults,
}) => ReminderPlanner.plan(
  catalog: ListCatalog(
    definitions: [BuiltinTemplates.tasks()],
    items: [
      ListItem(
        id: 'pill',
        listId: BuiltinTemplates.tasksId,
        values: {
          'title': 'Pill',
          'done': false,
          'reminderAt': first.toUtc().toIso8601String(),
          'repeat': {'frequency': 'daily'},
        },
        createdAt: now.toUtc(),
        updatedAt: now.toUtc(),
      ),
    ],
  ),
  settings: ReminderSettings(leads: leads),
  now: now,
  listName: (list) => list.id,
  horizon: const Duration(days: 6),
);

void main() {
  final List<DateTime> changes = _changes();
  final String zone =
      '${DateTime(2026).timeZoneName} (UTC${DateTime(2026).timeZoneOffset.inHours})';
  final Object skip = changes.length == 2
      ? false
      : 'zone $zone has no spring and autumn change in 2026';

  for (final (int index, String season) in [(0, 'spring'), (1, 'autumn')]) {
    group('$season clock change in $zone', () {
      DateTime change() => changes[index];
      // Wall-clock times: a Duration added across the change would shift.
      DateTime day(int offset, [int hour = 0, int minute = 0]) => DateTime(
        change().year,
        change().month,
        change().day + offset,
        hour,
        minute,
      );

      test('a daily 08:00 rings at 08:00 local on every day', () {
        final List<PlannedRing> rings = _daily(day(-3, 8), now: day(-2, 9));
        final List<DateTime> local = [
          for (final PlannedRing ring in rings) ring.at.toLocal(),
        ];
        expect(local, [
          for (int offset = -1; offset <= 4; offset++) day(offset, 8),
        ]);
        expect(local.every((at) => at.hour == 8 && at.minute == 0), isTrue);
        // In UTC one gap is 23 hours (spring) or 25 hours (autumn).
        final Set<Duration> gaps = {
          for (int i = 1; i < rings.length; i++)
            rings[i].at.difference(rings[i - 1].at),
        };
        expect(gaps, {
          const Duration(hours: 24),
          Duration(hours: index == 0 ? 23 : 25),
        });
      }, skip: skip);

      test('1 day before keeps the wall-clock time over the change', () {
        final List<PlannedRing> rings = _daily(
          day(-3, 8),
          now: day(-2, 9),
          leads: {ReminderLead.day1},
        );
        expect(
          rings.every((ring) {
            final DateTime at = ring.at.toLocal();
            return at.hour == 8 && at.minute == 0;
          }),
          isTrue,
        );
        expect(rings, isNotEmpty);
      }, skip: skip);

      test('a time in the skipped or repeated hour rings once that day', () {
        // 02:30 is skipped in spring and 01:30 comes twice in autumn in
        // most zones; either way the day gets one ring.
        final int hour = index == 0 ? 2 : 1;
        final List<PlannedRing> rings = _daily(
          day(-3, hour, 30),
          now: day(-2, 9),
        );
        final List<PlannedRing> onTheDay = [
          for (final PlannedRing ring in rings)
            if (_sameDay(ring.at.toLocal(), change())) ring,
        ];
        expect(onTheDay, hasLength(1));
        expect(onTheDay.single.at.toLocal().isBefore(day(0, hour)), isFalse);
      }, skip: skip);
    });
  }
}
