import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:hybrid_note/demo/demo_app.dart';
import 'package:hybrid_note/main.dart';

// Which start runs (T-18 unit 2a, Q-140): the real app unless DEMO_BUILD,
// and only the demo's start swaps in the in-memory preferences.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('without DEMO_BUILD main() starts the real app', () {
    expect(entryPoint(), same(startApp));
    expect(entryPoint(demo: true), same(startDemo));
  });

  test('the real path leaves the preferences store alone', () async {
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
