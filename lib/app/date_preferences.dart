import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

import 'account_preferences.dart';

// Times and calendars as the account's preferences say (Q-50 e, f).

// A time of day: the language's own format, or a fixed 12 or 24 hours.
DateFormat timeFormat(String locale, TimeFormat format) => switch (format) {
  TimeFormat.followLanguage => DateFormat.jm(locale),
  TimeFormat.h12 => DateFormat('h:mm a', locale),
  TimeFormat.h24 => DateFormat.Hm(locale),
};

// A date with its time, as the lists show it.
DateFormat dateTimeFormat(String locale, TimeFormat format) => switch (format) {
  TimeFormat.followLanguage => DateFormat.yMMMd(locale).add_jm(),
  TimeFormat.h12 => DateFormat.yMMMd(locale).addPattern('h:mm a'),
  TimeFormat.h24 => DateFormat.yMMMd(locale).add_Hm(),
};

// For showTimePicker's builder.
Widget timePickerIn(TimeFormat format, BuildContext context, Widget? child) {
  if (format == TimeFormat.followLanguage) {
    return child!;
  }
  return MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(alwaysUse24HourFormat: format == TimeFormat.h24),
    child: child!,
  );
}

// For showDatePicker's builder: the calendar starts its weeks on the chosen
// day. The only way to tell the date picker is firstDayOfWeekIndex in its
// MaterialLocalizations, so this gives it the same translations with that one
// value changed.
Widget datePickerIn(WeekStart start, BuildContext context, Widget? child) {
  if (start == WeekStart.followLanguage) {
    return child!;
  }
  return Localizations.override(
    context: context,
    delegates: [_WeekStartDelegate(start == WeekStart.sunday ? 0 : 1)],
    child: child,
  );
}

mixin _FirstDay on GlobalMaterialLocalizations {
  int firstDay = 0;

  @override
  int get firstDayOfWeekIndex => firstDay;
}

// One for each language the app ships (AppLocalizations.supportedLocales).
class _En = MaterialLocalizationEn with _FirstDay;
class _De = MaterialLocalizationDe with _FirstDay;
class _Es = MaterialLocalizationEs with _FirstDay;
class _Fr = MaterialLocalizationFr with _FirstDay;
class _Ja = MaterialLocalizationJa with _FirstDay;
class _Zh = MaterialLocalizationZh with _FirstDay;

class _WeekStartDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _WeekStartDelegate(this.firstDay);

  final int firstDay;

  @override
  bool isSupported(Locale locale) =>
      const {'en', 'de', 'es', 'fr', 'ja', 'zh'}.contains(locale.languageCode);

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    final String name = locale.languageCode;
    final DateFormat year = DateFormat.y(name);
    final DateFormat compact = DateFormat.yMd(name);
    final DateFormat short = DateFormat.yMMMd(name);
    final DateFormat medium = DateFormat.MMMEd(name);
    final DateFormat long = DateFormat.yMMMMEEEEd(name);
    final DateFormat yearMonth = DateFormat.yMMMM(name);
    final DateFormat monthDay = DateFormat.MMMd(name);
    final NumberFormat decimal = NumberFormat.decimalPattern(name);
    final NumberFormat twoDigits = NumberFormat('00', name);

    final _FirstDay localizations = switch (name) {
      'de' => _De(
        localeName: name,
        fullYearFormat: year,
        compactDateFormat: compact,
        shortDateFormat: short,
        mediumDateFormat: medium,
        longDateFormat: long,
        yearMonthFormat: yearMonth,
        shortMonthDayFormat: monthDay,
        decimalFormat: decimal,
        twoDigitZeroPaddedFormat: twoDigits,
      ),
      'es' => _Es(
        localeName: name,
        fullYearFormat: year,
        compactDateFormat: compact,
        shortDateFormat: short,
        mediumDateFormat: medium,
        longDateFormat: long,
        yearMonthFormat: yearMonth,
        shortMonthDayFormat: monthDay,
        decimalFormat: decimal,
        twoDigitZeroPaddedFormat: twoDigits,
      ),
      'fr' => _Fr(
        localeName: name,
        fullYearFormat: year,
        compactDateFormat: compact,
        shortDateFormat: short,
        mediumDateFormat: medium,
        longDateFormat: long,
        yearMonthFormat: yearMonth,
        shortMonthDayFormat: monthDay,
        decimalFormat: decimal,
        twoDigitZeroPaddedFormat: twoDigits,
      ),
      'ja' => _Ja(
        localeName: name,
        fullYearFormat: year,
        compactDateFormat: compact,
        shortDateFormat: short,
        mediumDateFormat: medium,
        longDateFormat: long,
        yearMonthFormat: yearMonth,
        shortMonthDayFormat: monthDay,
        decimalFormat: decimal,
        twoDigitZeroPaddedFormat: twoDigits,
      ),
      'zh' => _Zh(
        localeName: name,
        fullYearFormat: year,
        compactDateFormat: compact,
        shortDateFormat: short,
        mediumDateFormat: medium,
        longDateFormat: long,
        yearMonthFormat: yearMonth,
        shortMonthDayFormat: monthDay,
        decimalFormat: decimal,
        twoDigitZeroPaddedFormat: twoDigits,
      ),
      _ => _En(
        localeName: name,
        fullYearFormat: year,
        compactDateFormat: compact,
        shortDateFormat: short,
        mediumDateFormat: medium,
        longDateFormat: long,
        yearMonthFormat: yearMonth,
        shortMonthDayFormat: monthDay,
        decimalFormat: decimal,
        twoDigitZeroPaddedFormat: twoDigits,
      ),
    };
    return SynchronousFuture<MaterialLocalizations>(
      localizations..firstDay = firstDay,
    );
  }

  @override
  bool shouldReload(_WeekStartDelegate old) => old.firstDay != firstDay;
}
