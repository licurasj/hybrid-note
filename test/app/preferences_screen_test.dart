import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/app/app_settings.dart';
import 'package:hybrid_note/app/preferences_screen.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/home_screen.dart';

import '../support/fake_auth.dart';
import '../support/firestore_store.dart';

final Finder _hub = find.byKey(const ValueKey('launcher-hub'));
final Finder _settings = find.byKey(const ValueKey('settings'));

Future<void> _pumpApp(
  WidgetTester tester, {
  Map<String, Object> stored = const {},
  Size size = const Size(360, 780),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(stored);
  final FirestoreListStore store = await widgetTestStore(tester);
  await tester.pumpWidget(
    await testApp(
      auth: FakeAuthService(user: testUser),
      openStore: (_) => store,
    ),
  );
  await settle(tester);
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(_settings);
  await tester.pumpAndSettle();
}

Future<void> _openPreferences(WidgetTester tester) async {
  await _openSettings(tester);
  await tester.ensureVisible(
    find.byKey(const ValueKey('settings-preferences')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('settings-preferences')));
  await tester.pumpAndSettle();
}

AccountPreferencesCubit _account(WidgetTester tester) => tester
    .element(find.byType(HomeScreen, skipOffstage: false))
    .read<AccountPreferencesCubit>();

ThemeMode? _theme(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode;

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('Settings sheet', () {
    testWidgets(
      'theme, language, the AI choices, Preferences and the account',
      (WidgetTester tester) async {
        await _pumpApp(tester);
        await _openSettings(tester);

        final double theme = tester
            .getTopLeft(find.byKey(const ValueKey('settings-theme')))
            .dy;
        final double language = tester
            .getTopLeft(find.byKey(const ValueKey('settings-language')))
            .dy;
        final double preferences = tester
            .getTopLeft(find.byKey(const ValueKey('settings-preferences')))
            .dy;
        final double account = tester
            .getTopLeft(find.byKey(const ValueKey('settings-account')))
            .dy;
        expect(theme, lessThan(language));
        expect(language, lessThan(preferences));
        expect(preferences, lessThan(account));

        expect(find.byKey(const ValueKey('settings-dark-mode')), findsNothing);
        expect(
          find.byKey(const ValueKey('settings-ai-auto-apply')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('settings-ai-ask')), findsOneWidget);
      },
    );

    testWidgets('theme offers the three choices and stays per phone', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);
      await _openSettings(tester);
      expect(find.text('Follow the phone'), findsOneWidget);
      expect(_theme(tester), ThemeMode.system);

      await _tapKey(tester, 'settings-theme');
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      await _tapKey(tester, 'choice-ThemeMode.dark');
      expect(_theme(tester), ThemeMode.dark);
      // Back on the settings sheet, with the new value.
      expect(find.byKey(const ValueKey('settings-theme')), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      await _tapKey(tester, 'settings-theme');
      await _tapKey(tester, 'choice-ThemeMode.light');
      expect(_theme(tester), ThemeMode.light);

      await _tapKey(tester, 'settings-theme');
      await _tapKey(tester, 'choice-ThemeMode.system');
      expect(_theme(tester), ThemeMode.system);

      final SharedPreferences stored = await SharedPreferences.getInstance();
      expect(stored.getString(AppSettingsCubit.themeModeKey), 'system');
      expect(
        _account(tester).state.toJson().keys,
        isNot(contains('themeMode')),
      );
    });

    testWidgets('a screen reader gets the auto-apply switch with its name', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pumpApp(tester);
      await _openSettings(tester);

      expect(
        tester.getSemantics(find.byType(Switch).first),
        matchesSemantics(
          label: 'Apply AI changes without asking',
          hasToggledState: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('the AI choices work here and go to the account', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);
      final AccountPreferencesCubit cubit = _account(tester);
      await _openSettings(tester);

      await _tapKey(tester, 'settings-ai-auto-apply');
      expect(cubit.state.aiAutoApply, isTrue);

      final Finder slider = find.byKey(
        const ValueKey('settings-ai-ask-slider'),
      );
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final Rect rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.right - 12, rect.center.dy));
      await tester.pumpAndSettle();
      expect(cubit.state.aiAskLevel, AiAskLevel.less);
    });

    testWidgets('a theme dismissed without a choice stays', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, stored: {AppSettingsCubit.themeModeKey: 'dark'});
      await _openSettings(tester);
      await _tapKey(tester, 'settings-theme');

      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();

      expect(_theme(tester), ThemeMode.dark);
    });
  });

  group('Preferences page', () {
    testWidgets('opens above the shell; Back returns to Settings', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);
      await _openPreferences(tester);

      expect(find.byType(PreferencesScreen), findsOneWidget);
      expect(find.text('Preferences'), findsOneWidget);
      expect(_hub.hitTestable(), findsNothing);
      expect(find.byKey(const ValueKey('ai-bar')).hitTestable(), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(PreferencesScreen), findsNothing);
      expect(find.byKey(const ValueKey('settings-account')), findsOneWidget);
    });

    testWidgets('slides in from the side, with no fade', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);
      await _openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('settings-preferences')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        tester.getTopLeft(find.byType(PreferencesScreen)).dx,
        greaterThan(0),
      );
      expect(find.byType(FadeTransition), findsNothing);
    });

    testWidgets('the groups in order, with what the table lists', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);
      await _openPreferences(tester);

      final List<String> order = [
        'LISTS',
        'List order',
        'Start screen',
        'ITEMS',
        'Ticked items',
        'Confirm before deleting',
        'AI',
        'Show the AI bar',
        'GENERAL',
        'Vibration',
        'Time format',
        'Week starts on',
      ];
      double last = -1;
      for (final String text in order) {
        final Finder finder = find.text(text);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        expect(finder, findsOneWidget, reason: text);
        final double top =
            tester.getTopLeft(finder).dy +
            Scrollable.of(tester.element(finder)).position.pixels;
        expect(top, greaterThan(last), reason: text);
        last = top;
      }
      // What was in Settings before stays there.
      expect(find.text('Apply AI changes without asking'), findsNothing);
      expect(find.text('How often the AI checks with you'), findsNothing);
      expect(find.text('Language'), findsNothing);
      expect(find.text('Theme'), findsNothing);
    });

    testWidgets('each choice row stores its choice', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);
      await _openPreferences(tester);
      final AccountPreferencesCubit cubit = _account(tester);

      Future<void> choose(String row, String choice) async {
        await _tapKey(tester, row);
        await _tapKey(tester, choice);
      }

      await choose('preferences-list-order', 'choice-ListOrder.myOrder');
      expect(cubit.state.listOrder, ListOrder.myOrder);
      expect(find.text('My order'), findsOneWidget);
      await choose('preferences-list-order', 'choice-ListOrder.alphabetical');
      expect(cubit.state.listOrder, ListOrder.alphabetical);
      await choose(
        'preferences-start-screen',
        'choice-StartScreen.lastOpenList',
      );
      expect(cubit.state.startScreen, StartScreen.lastOpenList);
      await choose(
        'preferences-ticked-items',
        'choice-TickedItems.stayInPlace',
      );
      expect(cubit.state.tickedItems, TickedItems.stayInPlace);
      await choose('preferences-ticked-items', 'choice-TickedItems.hide');
      expect(cubit.state.tickedItems, TickedItems.hide);
      await choose('preferences-time-format', 'choice-TimeFormat.h24');
      expect(cubit.state.timeFormat, TimeFormat.h24);
      await choose('preferences-week-start', 'choice-WeekStart.sunday');
      expect(cubit.state.weekStart, WeekStart.sunday);
    });

    testWidgets(
      'a choice sheet marks the current one; dismissing changes nothing',
      (WidgetTester tester) async {
        await _pumpApp(tester);
        await _openPreferences(tester);
        await _tapKey(tester, 'preferences-week-start');

        expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
        final Finder current = find.byKey(
          const ValueKey('choice-WeekStart.followLanguage'),
        );
        expect(
          find.descendant(
            of: current,
            matching: find.byIcon(Icons.radio_button_checked),
          ),
          findsOneWidget,
        );

        await tester.tapAt(const Offset(180, 20));
        await tester.pumpAndSettle();
        expect(_account(tester).state.weekStart, WeekStart.followLanguage);
        expect(find.byType(PreferencesScreen), findsOneWidget);
      },
    );

    testWidgets('each switch flips from the row and from the switch', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);
      await _openPreferences(tester);
      final AccountPreferencesCubit cubit = _account(tester);

      await _tapKey(tester, 'preferences-confirm-delete');
      expect(cubit.state.confirmDelete, isTrue);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('preferences-confirm-delete')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      expect(cubit.state.confirmDelete, isFalse);

      await _tapKey(tester, 'preferences-show-ai-bar');
      expect(cubit.state.showAiBar, isFalse);
      await _tapKey(tester, 'preferences-vibration');
      expect(cubit.state.vibration, isFalse);
    });

    testWidgets('shows values the account already has', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);
      final AccountPreferencesCubit cubit = _account(tester);
      await cubit.setListOrder(ListOrder.alphabetical);
      await cubit.setTimeFormat(TimeFormat.h12);
      await _openPreferences(tester);

      expect(find.text('A to Z'), findsOneWidget);
      expect(find.text('12-hour'), findsOneWidget);

      // Another phone changes one while the page is open.
      await cubit.setListOrder(ListOrder.lastUsed);
      await tester.pumpAndSettle();
      expect(find.text('Last used'), findsOneWidget);
      expect(find.text('A to Z'), findsNothing);
    });

    testWidgets('in every language, at the smallest width, nothing overflows', (
      WidgetTester tester,
    ) async {
      for (final String locale in ['en', 'de', 'es', 'fr', 'ja', 'zh']) {
        await _pumpApp(
          tester,
          stored: {AppSettingsCubit.localeKey: locale},
          size: const Size(320, 640),
        );
        await _openSettings(tester);
        expect(tester.takeException(), isNull, reason: 'sheet $locale');
        final Finder row = find.byKey(const ValueKey('settings-preferences'));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(find.byType(PreferencesScreen), findsOneWidget, reason: locale);
        expect(tester.takeException(), isNull, reason: 'page $locale');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
