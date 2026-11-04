import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Choices that belong to this device, not to the account (Q-24 A): the app
// language, dark mode, where the launcher hub sits and whether AI changes
// apply without asking (Q-40 A).
class AppSettings {
  const AppSettings({
    this.localeCode,
    this.isDarkMode = false,
    this.hubPosition,
    this.aiAutoApply = false,
  });

  // A language code such as "de"; null follows the system.
  final String? localeCode;
  final bool isDarkMode;
  // Launcher hub position as fractions of the screen; null = default corner.
  final Offset? hubPosition;
  // The prompt bar applies every change at once, with Undo, instead of
  // showing Apply and Cancel.
  final bool aiAutoApply;

  AppSettings copyWith({
    String? localeCode,
    bool clearLocale = false,
    bool? isDarkMode,
    Offset? hubPosition,
    bool? aiAutoApply,
  }) {
    return AppSettings(
      localeCode: clearLocale ? null : localeCode ?? this.localeCode,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      hubPosition: hubPosition ?? this.hubPosition,
      aiAutoApply: aiAutoApply ?? this.aiAutoApply,
    );
  }
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

  static AppSettings _read(SharedPreferences preferences) {
    final double? hubX = preferences.getDouble(hubXKey);
    final double? hubY = preferences.getDouble(hubYKey);
    return AppSettings(
      localeCode: preferences.getString(localeKey),
      isDarkMode: preferences.getBool(darkModeKey) ?? false,
      hubPosition: hubX == null || hubY == null ? null : Offset(hubX, hubY),
      aiAutoApply: preferences.getBool(aiAutoApplyKey) ?? false,
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
}
