import 'package:flutter/material.dart' show Offset, ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/app_settings.dart';

Future<AppSettingsCubit> _cubit([Map<String, Object> stored = const {}]) async {
  SharedPreferences.setMockInitialValues(stored);
  final AppSettingsCubit cubit = AppSettingsCubit(
    await SharedPreferences.getInstance(),
  );
  addTearDown(cubit.close);
  return cubit;
}

void main() {
  test('nothing stored: system language, system theme, default hub', () async {
    final AppSettingsCubit cubit = await _cubit();

    expect(cubit.state.localeCode, isNull);
    expect(cubit.state.themeMode, ThemeMode.system);
    expect(cubit.state.hubPosition, isNull);
  });

  test('stored settings are there from the start', () async {
    final AppSettingsCubit cubit = await _cubit({
      AppSettingsCubit.localeKey: 'de',
      AppSettingsCubit.themeModeKey: 'dark',
      AppSettingsCubit.hubXKey: 0.25,
      AppSettingsCubit.hubYKey: 0.75,
    });

    expect(cubit.state.localeCode, 'de');
    expect(cubit.state.themeMode, ThemeMode.dark);
    expect(cubit.state.hubPosition, const Offset(0.25, 0.75));
  });

  test('changes are emitted and survive a restart', () async {
    final AppSettingsCubit cubit = await _cubit();

    await cubit.setLocaleCode('ja');
    await cubit.setThemeMode(ThemeMode.dark);
    await cubit.setHubPosition(const Offset(0.1, 0.9));
    expect(cubit.state.localeCode, 'ja');
    expect(cubit.state.themeMode, ThemeMode.dark);
    expect(cubit.state.hubPosition, const Offset(0.1, 0.9));

    final AppSettingsCubit restarted = AppSettingsCubit(
      await SharedPreferences.getInstance(),
    );
    addTearDown(restarted.close);
    expect(restarted.state.localeCode, 'ja');
    expect(restarted.state.themeMode, ThemeMode.dark);
    expect(restarted.state.hubPosition, const Offset(0.1, 0.9));
  });

  test('back to the system language and theme', () async {
    final AppSettingsCubit cubit = await _cubit({
      AppSettingsCubit.localeKey: 'fr',
      AppSettingsCubit.themeModeKey: 'dark',
    });

    await cubit.setLocaleCode(null);
    await cubit.setThemeMode(ThemeMode.system);
    expect(cubit.state.localeCode, isNull);
    expect(cubit.state.themeMode, ThemeMode.system);

    final SharedPreferences stored = await SharedPreferences.getInstance();
    expect(stored.containsKey(AppSettingsCubit.localeKey), isFalse);
    expect(stored.getString(AppSettingsCubit.themeModeKey), 'system');
  });

  test('a phone that used the old switch keeps its choice', () async {
    final AppSettingsCubit dark = await _cubit({
      AppSettingsCubit.legacyDarkModeKey: true,
    });
    expect(dark.state.themeMode, ThemeMode.dark);

    final AppSettingsCubit light = await _cubit({
      AppSettingsCubit.legacyDarkModeKey: false,
    });
    expect(light.state.themeMode, ThemeMode.light);

    // A new choice wins over the old switch.
    await light.setThemeMode(ThemeMode.system);
    final AppSettingsCubit restarted = AppSettingsCubit(
      await SharedPreferences.getInstance(),
    );
    addTearDown(restarted.close);
    expect(restarted.state.themeMode, ThemeMode.system);
  });
}
