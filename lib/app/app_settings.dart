import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Choices that belong to this device, not to the account (Q-24 A): the app
// language, dark mode, where the launcher hub sits, whether AI changes
// apply without asking (Q-40 A) and how often the AI asks first (Q-43).
class AppSettings {
  const AppSettings({
    this.localeCode,
    this.isDarkMode = false,
    this.hubPosition,
    this.aiAutoApply = false,
    this.aiAskLevel = AiAskLevel.balanced,
  });

  // A language code such as "de"; null follows the system.
  final String? localeCode;
  final bool isDarkMode;
  // Launcher hub position as fractions of the screen; null = default corner.
  final Offset? hubPosition;
  // The prompt bar applies every change at once, with Undo, instead of
  // showing Apply and Cancel.
  final bool aiAutoApply;
  final AiAskLevel aiAskLevel;

  AppSettings copyWith({
    String? localeCode,
    bool clearLocale = false,
    bool? isDarkMode,
    Offset? hubPosition,
    bool? aiAutoApply,
    AiAskLevel? aiAskLevel,
  }) {
    return AppSettings(
      localeCode: clearLocale ? null : localeCode ?? this.localeCode,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      hubPosition: hubPosition ?? this.hubPosition,
      aiAutoApply: aiAutoApply ?? this.aiAutoApply,
      aiAskLevel: aiAskLevel ?? this.aiAskLevel,
    );
  }
}

// How often the AI asks before acting (Q-43); the wire value goes with
// each request. Wording rules apply at balanced only.
enum AiAskLevel {
  more('more'),
  balanced('balanced'),
  less('less');

  const AiAskLevel(this.wire);

  final String wire;

  static AiAskLevel of(String? wire) => values.firstWhere(
    (level) => level.wire == wire,
    orElse: () => AiAskLevel.balanced,
  );
}

// Holds the settings and keeps them in shared_preferences, which works on
// Android and web. The preferences are loaded before the app starts
// (SharedPreferences.getInstance), so the first frame already has them.
class AppSettingsCubit extends Cubit<AppSettings> {
  AppSettingsCubit(this.preferences) : super(_read(preferences));

  final SharedPreferences preferences;

  static const String localeKey = 'settings.locale';
  static const String darkModeKey = 'settings.darkMode';
  static const String hubXKey = 'settings.hubX';
  static const String hubYKey = 'settings.hubY';
  static const String aiAutoApplyKey = 'settings.aiAutoApply';
  static const String aiAskLevelKey = 'settings.aiAskLevel';

  static AppSettings _read(SharedPreferences preferences) {
    final double? hubX = preferences.getDouble(hubXKey);
    final double? hubY = preferences.getDouble(hubYKey);
    return AppSettings(
      localeCode: preferences.getString(localeKey),
      isDarkMode: preferences.getBool(darkModeKey) ?? false,
      hubPosition: hubX == null || hubY == null ? null : Offset(hubX, hubY),
      aiAutoApply: preferences.getBool(aiAutoApplyKey) ?? false,
      aiAskLevel: AiAskLevel.of(preferences.getString(aiAskLevelKey)),
    );
  }

  Future<void> setLocaleCode(String? localeCode) async {
    emit(
      state.copyWith(localeCode: localeCode, clearLocale: localeCode == null),
    );
    if (localeCode == null) {
      await preferences.remove(localeKey);
    } else {
      await preferences.setString(localeKey, localeCode);
    }
  }

  Future<void> toggleDarkMode() async {
    final bool next = !state.isDarkMode;
    emit(state.copyWith(isDarkMode: next));
    await preferences.setBool(darkModeKey, next);
  }

  Future<void> setHubPosition(Offset position) async {
    emit(state.copyWith(hubPosition: position));
    await preferences.setDouble(hubXKey, position.dx);
    await preferences.setDouble(hubYKey, position.dy);
  }

  Future<void> setAiAutoApply(bool value) async {
    emit(state.copyWith(aiAutoApply: value));
    await preferences.setBool(aiAutoApplyKey, value);
  }

  Future<void> setAiAskLevel(AiAskLevel level) async {
    emit(state.copyWith(aiAskLevel: level));
    await preferences.setString(aiAskLevelKey, level.wire);
  }
}
