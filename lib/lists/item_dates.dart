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

  // A day as stored with No time.
  static String dayValue(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
