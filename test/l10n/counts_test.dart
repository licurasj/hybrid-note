import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/l10n/generated/app_localizations.dart';

// Counts that read as words (T-24 unit 7): one of something is singular, and
// "no lists with their own choice" is a sentence, not "0 lists".
void main() {
  AppLocalizations loc(String language) =>
      lookupAppLocalizations(Locale(language));

  test('a dial tab with one item says "1 item"', () {
    expect(loc('en').itemsCount('Grocery', 1), 'Grocery, 1 item');
    expect(loc('en').itemsCount('Grocery', 3), 'Grocery, 3 items');
    expect(loc('de').itemsCount('Einkauf', 1), 'Einkauf, 1 Eintrag');
    expect(loc('es').itemsCount('Compra', 1), 'Compra, 1 elemento');
    expect(loc('fr').itemsCount('Courses', 1), 'Courses, 1 élément');
  });

  test('one ticked item is singular in French and Spanish', () {
    expect(loc('fr').tickedCount(1), '1 coché');
    expect(loc('fr').tickedCount(2), '2 cochés');
    expect(loc('es').tickedCount(1), '1 marcado');
    expect(loc('es').tickedCount(2), '2 marcados');
  });

  test('no list with its own choice is a sentence in every language', () {
    for (final String language in ['en', 'de', 'es', 'fr', 'ja', 'zh']) {
      expect(
        loc(language).preferencesListsOwnCount(0),
        isNot(contains('0')),
        reason: language,
      );
    }
  });

  test('Japanese has different words for Items and Fields', () {
    expect(loc('ja').preferencesItems, isNot(loc('ja').fields));
  });
}
