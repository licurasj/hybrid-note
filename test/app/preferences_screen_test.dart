import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/app/app_settings.dart';
import 'package:hybrid_note/app/preferences_screen.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/home_screen.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_patch.dart';

import '../support/fake_auth.dart';
import '../support/firestore_store.dart';

final Finder _hub = find.byKey(const ValueKey('launcher-hub'));
final Finder _settings = find.byKey(const ValueKey('settings'));

Future<FirestoreListStore> _pumpApp(
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
  return store;
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

      // Section headings above the rows, in sentence case (the owner's
      // hierarchy note, 2026-11-09). "Home" is also a Start screen choice.
      expect(find.text('Home'), findsNWidgets(2));
      final List<String> order = [
        'Start screen',
        'Home shows',
        'Show suggestions',
        'Lists and dial',
        'Dial list order',
        'Home list order',
        'Same as dial',
        'Items',
        'Ticked items',
        'Confirm before deleting',
        'AI',
        'Show the AI bar',
        'General',
        'Time format',
        'Week starts on',
        'Vibration',
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

      // On the page, one tap (T-24, Q-112): no pop-up.
      Future<void> choose(String row, String choice) async {
        await _tapKey(tester, choice);
        expect(find.byType(BottomSheet), findsNothing);
      }

      await choose('preferences-list-order', 'choice-ListOrder.myOrder');
      expect(cubit.state.listOrder, ListOrder.myOrder);
      await choose('preferences-list-order', 'choice-ListOrder.alphabetical');
      expect(cubit.state.listOrder, ListOrder.alphabetical);
      // Home list order, right under the dial's (Q-108): the same three
      // choices, greyed while Same as dial is on.
      expect(cubit.state.homeListOrder, HomeListOrder.sameAsDial);
      expect(find.text("Following the dial's order."), findsOneWidget);
      await _tapKey(tester, 'choice-HomeListOrder.myOrder');
      expect(cubit.state.homeListOrder, HomeListOrder.sameAsDial);
      // Off, home starts from the dial's choice.
      await _tapKey(tester, 'preferences-home-same-as-dial');
      expect(cubit.state.homeListOrder, HomeListOrder.alphabetical);
      expect(find.text('Home keeps its own order.'), findsOneWidget);
      await choose(
        'preferences-home-list-order',
        'choice-HomeListOrder.myOrder',
      );
      expect(cubit.state.homeListOrder, HomeListOrder.myOrder);
      await _tapKey(tester, 'preferences-home-same-as-dial');
      expect(cubit.state.homeListOrder, HomeListOrder.sameAsDial);
      expect(
        find.text("Pinned cards follow the dial's order."),
        findsOneWidget,
      );
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

    testWidgets('the picked choice is marked, as one of a group, with its line', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);
      await _openPreferences(tester);
      final Finder current = find.byKey(
        const ValueKey('choice-TickedItems.moveToDone'),
      );
      await tester.ensureVisible(current);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: current,
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('choice-line-TickedItems.moveToDone')),
        findsOneWidget,
      );
      final SemanticsHandle handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(current),
        isSemantics(
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      expect(tester.getSemantics(current).label, startsWith('Move to the bottom'));
      handle.dispose();

      await _tapKey(tester, 'choice-TickedItems.hide');
      expect(
        find.byKey(const ValueKey('choice-line-TickedItems.moveToDone')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('choice-line-TickedItems.hide')),
        findsOneWidget,
      );
    });

    testWidgets('rows stay put when Home shows changes: they grey with a line', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);
      await _openPreferences(tester);
      final AccountPreferencesCubit cubit = _account(tester);
      final Finder below = find.byKey(const ValueKey('preferences-list-order'));
      await tester.ensureVisible(below);
      await tester.pumpAndSettle();
      final double before = tester.getTopLeft(below).dy;
      expect(find.text('Only when home shows list cards.'), findsNothing);

      await cubit.setHomeContent(HomeContent.dueToday);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('preferences-home-suggestions')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('preferences-home-list-order')),
        findsOneWidget,
      );
      expect(find.text('Only when home shows list cards.'), findsNWidgets(2));
      // The suggestions row's line is as tall as the one it replaced.
      expect(tester.getTopLeft(below).dy, before);
      // Greyed rows do nothing.
      await tester.tap(
        find.byKey(const ValueKey('preferences-home-suggestions')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(cubit.state.homeSuggestions, isTrue);
    });

    testWidgets('"N lists have their own" counts lists with a tick, live (O4)', (
      WidgetTester tester,
    ) async {
      final FirestoreListStore store = await _pumpApp(tester);
      await _openPreferences(tester);
      Finder line(String text) => find.descendant(
        of: find.byKey(const ValueKey('preferences-lists-own-ticked')),
        matching: find.text(text),
      );
      const String none = 'A list can pick its own in Edit list.';
      expect(line(none), findsOneWidget);

      Future<void> own(String listId) async {
        await tester.runAsync(
          () => store.patchList(listId, [
            ListPatchOp(PatchOpKind.setListInfo, {'tickedItems': 'hide'}),
          ]),
        );
        await settle(tester);
      }

      // Journal has no tick: its choice does not count.
      await own(BuiltinTemplates.journalId);
      expect(line(none), findsOneWidget);
      await own(BuiltinTemplates.groceryId);
      expect(line('1 list has its own choice.'), findsOneWidget);
    });

    testWidgets('lines follow the choice: the AI bar line shows only when off', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);
      await _openPreferences(tester);
      expect(find.text('What opens when you start the app.'), findsOneWidget);
      expect(find.text('The order of lists on the dial.'), findsOneWidget);
      expect(
        find.text('The AI bar is hidden. Your lists stay as they are.'),
        findsNothing,
      );
      await _tapKey(tester, 'preferences-show-ai-bar');
      expect(
        find.text('The AI bar is hidden. Your lists stay as they are.'),
        findsOneWidget,
      );
    });

    testWidgets('each switch flips from the row and from the switch', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);
      await _openPreferences(tester);
      final AccountPreferencesCubit cubit = _account(tester);

      await tester.ensureVisible(find.text('Confirm before deleting'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm before deleting'));
      await tester.pumpAndSettle();
      expect(cubit.state.confirmDelete, isTrue);
      // Its own switch, not the sub-option's under it.
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const ValueKey('preferences-confirm-delete')),
              matching: find.byType(Switch),
            )
            .first,
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

      bool picked(String key) => isSemantics(
        isChecked: true,
      ).matches(tester.getSemantics(find.byKey(ValueKey(key))), {});
      final SemanticsHandle handle = tester.ensureSemantics();
      expect(picked('choice-ListOrder.alphabetical'), isTrue);
      expect(picked('choice-TimeFormat.h12'), isTrue);

      // Another phone changes one while the page is open.
      await cubit.setListOrder(ListOrder.lastUsed);
      await tester.pumpAndSettle();
      expect(picked('choice-ListOrder.lastUsed'), isTrue);
      expect(picked('choice-ListOrder.alphabetical'), isFalse);
      handle.dispose();
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
