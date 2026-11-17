import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:hybrid_note/demo/demo_app.dart';
import 'package:hybrid_note/demo/demo_build.dart';
import 'package:hybrid_note/main.dart';

// Which start runs (T-18 unit 2a, Q-140): the real app unless DEMO_BUILD,
// and only the demo's start swaps in the in-memory preferences.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('without DEMO_BUILD main() starts the real app', () {
    expect(entryPoint(demo: false), same(startApp));
    expect(entryPoint(demo: true), same(startDemo));
  });

  // Run with --dart-define=DEMO_BUILD=true to check the demo build's start.
  test('main() starts the build it was compiled as', () {
    expect(entryPoint(), same(demoBuild ? startDemo : startApp));
  });

  // startApp itself needs Firebase and is not run here: it takes its
  // preferences from realPreferences, tested below. The real root without
  // DemoMode (account rows, Reminders, the account line) is in
  // preferences_screen_test.dart.
  group('the preferences store (T-18 M5)', () {
    late SharedPreferencesStorePlatform original;
    late InMemorySharedPreferencesStore phone;

    setUp(() {
      original = SharedPreferencesStorePlatform.instance;
      // Stands in for the phone's own store, with a value already saved.
      phone = InMemorySharedPreferencesStore.withData({
        'flutter.saved': 'on the phone',
      });
      SharedPreferencesStorePlatform.instance = phone;
      SharedPreferences.resetStatic();
    });

    tearDown(() {
      SharedPreferencesStorePlatform.instance = original;
      SharedPreferences.resetStatic();
    });

    test('the real start leaves the store alone and reads it', () async {
      final SharedPreferences preferences = await realPreferences();
      expect(SharedPreferencesStorePlatform.instance, same(phone));
      expect(preferences.getString('saved'), 'on the phone');
    });

    test('the demo start swaps in an empty in-memory store', () async {
      final SharedPreferences preferences = await demoPreferences();
      expect(SharedPreferencesStorePlatform.instance, isNot(same(phone)));
      expect(
        SharedPreferencesStorePlatform.instance,
        isA<InMemorySharedPreferencesStore>(),
      );
      expect(preferences.getString('saved'), isNull);
    });
  });
}
