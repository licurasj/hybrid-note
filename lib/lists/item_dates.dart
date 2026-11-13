import 'list_vocabulary.dart';

// Date values of items (T-13 unit 1, Q-91). A date field holds a day. A
// dateTime field holds a moment, or a day with No time: then the value is
// "YYYY-MM-DD", which is also what the AI writes into either type. Moments are
// stored as UTC ISO 8601 strings.
//
// A date field stores its day as "YYYY-MM-DD" too (T-13 unit 10, F7), the
// same day on every phone whatever its zone. Before, it stored the picked
// day's local midnight as a UTC moment; such a value is read by its UTC date
// (owner, 2026-11-11), which is the picked day in the owner's zone (west of
// UTC). It stays as stored until the item is saved again.
class ItemDates {
  static final RegExp _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  // A stored "YYYY-MM-DD" with no time in it.
  static bool isDayOnly(Object? raw) => raw is String && _day.hasMatch(raw.trim());

  // Whether this value of a field of this type carries a time to show and to
  // ring at. A date field never does.
  static bool hasTime(FieldType type, Object? raw) =>
      type == FieldType.dateTime && raw is String && !isDayOnly(raw);

  // The value in the phone's time zone; a day reads as its local midnight.
  // For a date field ([type] date) an older moment reads as the local
  // midnight of its UTC date (F7).
  static DateTime? local(Object? raw, [FieldType? type]) {
    if (raw is! String) {
      return null;
    }
    final DateTime? parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) {
      return null;
    }
    if (type == FieldType.date && !isDayOnly(raw)) {
      final DateTime utc = parsed.toUtc();
      return DateTime(utc.year, utc.month, utc.day);
    }
    return parsed.toLocal();
  }

  // A date the AI (or any other input) gave, stored as the sheet stores it
  // (T-13 unit 10, F8), worked out on the phone that makes the change: a
  // day stays "YYYY-MM-DD"; a time with no zone ("2026-11-13T15:00") is this
  // phone's wall clock and is stored as its UTC moment, so every phone rings
  // at the same instant; a time with a zone is stored in UTC. A date field
  // keeps only the day. A local time that does not exist (a spring-forward
  // gap) or exists twice (autumn) is read as Dart's DateTime reads it on the
  // phone: a gap moves on by its length (02:30 becomes 03:30), a doubled
  // time is one of the two. Anything else is left for validation.
  static Object? fromInput(Object? value, FieldType type) {
    if (value is! String) {
      return value;
    }
    final String text = value.trim();
    if (isDayOnly(text)) {
      return text;
    }
    final DateTime? parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return value;
    }
    if (type == FieldType.date) {
      // The day as written (in UTC when the text has a zone).
      return dayValue(parsed);
    }
    return parsed.toUtc().toIso8601String();
  }

  // A day as stored with No time.
  static String dayValue(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
