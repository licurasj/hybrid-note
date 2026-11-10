import 'dart:ui';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Choices that belong to this device, not to the account: the app language
// and the theme (Q-46 A, Q-47 A), where the launcher hub sits, and whether
// reminders ring on this phone (T-13). What
// follows the account is in AccountPreferences.
class AppSettings {
  const AppSettings({
    this.localeCode,
    this.themeMode = ThemeMode.system,
    this.hubPosition,
    this.ringOnThisPhone = true,
  });

  // A language code such as "de"; null follows the system.
  final String? localeCode;
  final ThemeMode themeMode;
  // Launcher hub position as fractions of the screen; null = default corner.
  final Offset? hubPosition;
  // Off for a phone that should stay quiet; the account's reminders still
  // ring on its other phones (T-13).
  final bool ringOnThisPhone;

  AppSettings copyWith({
    String? localeCode,
    bool clearLocale = false,
    ThemeMode? themeMode,
    Offset? hubPosition,
    bool? ringOnThisPhone,
  }) {
    return AppSettings(
      localeCode: clearLocale ? null : localeCode ?? this.localeCode,
      themeMode: themeMode ?? this.themeMode,
      hubPosition: hubPosition ?? this.hubPosition,
      ringOnThisPhone: ringOnThisPhone ?? this.ringOnThisPhone,
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
  static const String themeModeKey = 'settings.themeMode';
  // The light or dark switch before Follow the phone; a phone that set it
  // keeps its choice.
  static const String legacyDarkModeKey = 'settings.darkMode';
  static const String hubXKey = 'settings.hubX';
  static const String hubYKey = 'settings.hubY';
  static const String ringOnThisPhoneKey = 'settings.ringOnThisPhone';
  // Whether this phone has asked for the reminder permissions (Q-94): once
  // per phone, the first time the open app has a ring to book.
  static const String remindersAskedKey = 'settings.remindersAsked';

  // Lists by when they were last opened, newest first. Per phone and per
  // user; the first is the last open list (Q-49, Q-50 a).
  static String recentListsKey(String uid) => 'settings.recentLists.$uid';

  static ThemeMode _readTheme(SharedPreferences preferences) {
    final String? stored = preferences.getString(themeModeKey);
    if (stored != null) {
      return ThemeMode.values.firstWhere(
        (mode) => mode.name == stored,
        orElse: () => ThemeMode.system,
      );
    }
    return switch (preferences.getBool(legacyDarkModeKey)) {
      true => ThemeMode.dark,
      false => ThemeMode.light,
      null => ThemeMode.system,
    };
  }

  static AppSettings _read(SharedPreferences preferences) {
    final double? hubX = preferences.getDouble(hubXKey);
    final double? hubY = preferences.getDouble(hubYKey);
    return AppSettings(
      localeCode: preferences.getString(localeKey),
      themeMode: _readTheme(preferences),
      hubPosition: hubX == null || hubY == null ? null : Offset(hubX, hubY),
      ringOnThisPhone: preferences.getBool(ringOnThisPhoneKey) ?? true,
    );
  }

  List<String> recentLists(String uid) =>
      preferences.getStringList(recentListsKey(uid)) ?? const [];

  Future<void> setRecentLists(String uid, List<String> listIds) async {
    await preferences.setStringList(recentListsKey(uid), listIds);
  }

  // Sign-out clears what this phone knows of the user (Q-25 A).
  Future<void> forgetRecentLists(String uid) async {
    await preferences.remove(recentListsKey(uid));
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

  Future<void> setThemeMode(ThemeMode mode) async {
    emit(state.copyWith(themeMode: mode));
    await preferences.setString(themeModeKey, mode.name);
  }

  Future<void> setRingOnThisPhone(bool value) async {
    emit(state.copyWith(ringOnThisPhone: value));
    await preferences.setBool(ringOnThisPhoneKey, value);
  }

  bool get remindersAsked => preferences.getBool(remindersAskedKey) ?? false;

  Future<void> setRemindersAsked() async {
    await preferences.setBool(remindersAskedKey, true);
  }

  Future<void> setHubPosition(Offset position) async {
    emit(state.copyWith(hubPosition: position));
    await preferences.setDouble(hubXKey, position.dx);
    await preferences.setDouble(hubYKey, position.dy);
  }
}
