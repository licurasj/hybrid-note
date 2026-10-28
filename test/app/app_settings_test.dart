import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/app_settings.dart';

Future<AppSettingsCubit> _cubit([Map<String, Object> stored = const {}]) async {
  SharedPreferences.setMockInitialValues(stored);
  final AppSettingsCubit cubit = AppSettingsCubit(await SharedPreferences.getInstance());
  addTearDown(cubit.close);
  return cubit;
}

void main() {
  test('nothing stored: system language, light mode, default hub', () async {
    final AppSettingsCubit cubit = await _cubit();

    expect(cubit.state.localeCode, isNull);
    expect(cubit.state.isDarkMode, isFalse);
    expect(cubit.state.hubPosition, isNull);
  });

  test('stored settings are there from the start', () async {
    final AppSettingsCubit cubit = await _cubit({
      AppSettingsCubit.localeKey: 'de',
      AppSettingsCubit.darkModeKey: true,
      AppSettingsCubit.hubXKey: 0.25,
      AppSettingsCubit.hubYKey: 0.75,
    });

    expect(cubit.state.localeCode, 'de');
    expect(cubit.state.isDarkMode, isTrue);
    expect(cubit.state.hubPosition, const Offset(0.25, 0.75));
  });

  test('changes are emitted and survive a restart', () async {
    final AppSettingsCubit cubit = await _cubit();

    await cubit.setLocaleCode('ja');
    await cubit.toggleDarkMode();
    await cubit.setHubPosition(const Offset(0.1, 0.9));
    expect(cubit.state.localeCode, 'ja');
    expect(cubit.state.isDarkMode, isTrue);
    expect(cubit.state.hubPosition, const Offset(0.1, 0.9));

    final AppSettingsCubit restarted = AppSettingsCubit(await SharedPreferences.getInstance());
    addTearDown(restarted.close);
    expect(restarted.state.localeCode, 'ja');
    expect(restarted.state.isDarkMode, isTrue);
    expect(restarted.state.hubPosition, const Offset(0.1, 0.9));
  });

  test('back to the system language and light mode', () async {
    final AppSettingsCubit cubit = await _cubit({
      AppSettingsCubit.localeKey: 'fr',
      AppSettingsCubit.darkModeKey: true,
    });

    await cubit.setLocaleCode(null);
    await cubit.toggleDarkMode();
    expect(cubit.state.localeCode, isNull);
    expect(cubit.state.isDarkMode, isFalse);

    final SharedPreferences stored = await SharedPreferences.getInstance();
    expect(stored.containsKey(AppSettingsCubit.localeKey), isFalse);
    expect(stored.getBool(AppSettingsCubit.darkModeKey), isFalse);
  });
}
