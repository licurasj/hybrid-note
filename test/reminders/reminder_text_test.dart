import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/reminders/reminder_planner.dart';
import 'package:hybrid_note/reminders/reminder_text.dart';

// T-13 unit 4 AVD check: the background check (its own isolate, no Flutter
// localizations loaded) threw LocaleDataException in reminderText and booked
// nothing. prepareReminderText loads intl's date data, as it now does first.
void main() {
  final PlannedRing ring = PlannedRing(
    key: 'l|i|0|atTime',
    listId: 'l',
    itemId: 'i',
    at: DateTime(2026, 11, 10, 15, 50),
    due: DateTime(2026, 11, 11, 15, 50),
    hasTime: true,
    itemDate: '2026-11-11T15:50:00',
    title: 'Call mum',
    listName: 'Tasks',
  );

  test(
    'reminderText formats in every app language after prepareReminderText',
    () async {
      await prepareReminderText();
      for (final Locale locale in AppLocalizations.supportedLocales) {
        final AppLocalizations loc = lookupAppLocalizations(locale);
        final text = reminderText(
          ring,
          loc: loc,
          locale: loc.localeName.replaceAll('_', '-'),
          format: TimeFormat.followLanguage,
        );
        expect(text.title, 'Call mum');
        expect(text.body, contains('Tasks'));
      }
    },
  );
}
