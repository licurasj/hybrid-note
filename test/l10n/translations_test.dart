import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Text left in English in another language (T-21 unit 7). A value may equal
// the English only where it is listed here: the same word in that language.
void main() {
  const Set<String> everywhere = {
    'appTitle',
    'languageEnglish',
    'languageChinese',
    'languageJapanese',
    'languageFrench',
    'languageSpanish',
    'languageGerman',
  };
  const Map<String, Set<String>> sameWord = {
    'de': {'journal', 'status', 'typeText', 'typeUrl', 'preferencesVibration'},
    'es': {
      'listColor',
      'preferencesGeneral',
      // "5 min" and the like read the same (T-13).
      'reminderLead5m',
      'reminderLead10m',
      'reminderLead30m',
    },
    'fr': {
      'journal',
      'notes',
      'date',
      'description',
      'section',
      'type',
      'viewSectioned',
      'preferencesVibration',
      'reminderLead5m',
      'reminderLead10m',
      'reminderLead30m',
    },
    'ja': {'preferencesAi'},
    'zh': {'preferencesAi'},
  };

  Map<String, dynamic> arb(String language) {
    return jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
        as Map<String, dynamic>;
  }

  final Map<String, dynamic> english = arb('en');

  for (final String language in sameWord.keys) {
    test('$language has no text left in English', () {
      final Map<String, dynamic> texts = arb(language);
      final List<String> left = [
        for (final String key in english.keys)
          if (!key.startsWith('@') &&
              '${texts[key]}'.toLowerCase() ==
                  '${english[key]}'.toLowerCase() &&
              !everywhere.contains(key) &&
              !sameWord[language]!.contains(key))
            key,
      ];
      expect(left, isEmpty);
    });
  }
}
