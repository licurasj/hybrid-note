import 'package:flutter_test/flutter_test.dart';
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

  // This only checks the demo's swap. startApp itself needs Firebase and is
  // not run here; the real root without DemoMode, with its account rows,
  // Reminders section and account line, is in preferences_screen_test.dart.
  test('the demo start swaps in the in-memory preferences store', () async {
    final SharedPreferencesStorePlatform before =
        SharedPreferencesStorePlatform.instance;
    expect(before, isNot(isA<InMemorySharedPreferencesStore>()));
    addTearDown(() => SharedPreferencesStorePlatform.instance = before);

    await demoPreferences();
    expect(
      SharedPreferencesStorePlatform.instance,
      isA<InMemorySharedPreferencesStore>(),
    );
  });
}
