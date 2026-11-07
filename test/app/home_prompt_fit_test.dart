import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/home_cards.dart';
import 'package:hybrid_note/home_cards_view.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';

// The hold's longest row, a suggestion's four prompts, in the app's real font and
// every language, on a small phone and the everyday sizes (owner, 2026-11-06).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final FontLoader geist = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/geist/Geist-SemiBold.ttf'));
    await geist.load();
  });

  HomePromptFit fitted(String language, double width, {double text = 1}) {
    final AppLocalizations loc = lookupAppLocalizations(Locale(language));
    final measured = homePromptMeasure(
      [loc.homePinShort, loc.edit, loc.homeRemove, loc.homeNoSuggestions],
      TextDirection.ltr,
      TextScaler.linear(text),
    );
    return homePromptFit(
      oneLine: measured.oneLine,
      broken: measured.broken,
      room: width - 2 * homePromptMargin,
    );
  }

  for (final double width in const [360.0, 393.0, 412.0]) {
    test('English stays on one line at $width', () {
      final HomePromptFit fit = fitted('en', width);
      expect(fit.wrapped, isEmpty);
      expect(fit.textScale, 1);
    });

    for (final String language in const ['de', 'es', 'fr', 'ja', 'zh']) {
      test('$language fits one row at $width with text near its size', () {
        final HomePromptFit fit = fitted(language, width);
        expect(fit.textScale, greaterThan(0.85));
        expect(
          fit.widths.fold<double>(0, (sum, w) => sum + w) + 3 * homePromptGap,
          lessThanOrEqualTo(width - 2 * homePromptMargin + 0.01),
        );
      });
    }
  }

  test('large text never runs past the room', () {
    final HomePromptFit fit = fitted('de', 360, text: 2);
    expect(
      fit.widths.fold<double>(0, (sum, w) => sum + w) + 3 * homePromptGap,
      lessThanOrEqualTo(360 - 2 * homePromptMargin + 0.01),
    );
  });
}
