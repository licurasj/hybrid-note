import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:hybrid_note/ai/ai_service.dart';
import 'package:hybrid_note/app/app_settings.dart';
import 'package:hybrid_note/demo/demo_app.dart';
import 'package:hybrid_note/demo/demo_build.dart';
import 'package:hybrid_note/demo/memory_list_store.dart';
import 'package:hybrid_note/demo/page_probe.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';

// The demo's root (T-18 unit 2a): the home screen on the starter lists and
// sample items, no account rows and no Reminders section, and the phone
// layout centred in a wide frame (Q-133, Q-136, Q-137).
final Finder _hub = find.byKey(const ValueKey('launcher-hub'));

Future<MemoryListStore> _pumpDemo(
  WidgetTester tester,
  Size size, {
  double topInset = 0,
  AiService? aiService,
  ValueListenable<double>? keyboardInset,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final MemoryListStore store = demoStore(DateTime.now());
  await tester.pumpWidget(
    BlocProvider(
      create: (_) => AppSettingsCubit(preferences),
      child: DemoApp(
        store: store,
        topInset: topInset,
        aiService: aiService,
        keyboardInset: keyboardInset,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

// Never asked here: the keyboard tests only focus the bar.
class _NoAi implements AiService {
  @override
  Future<AiAnswer> send(AiRequest request) => throw UnimplementedError();
}

final Finder _bar = find.byKey(const ValueKey('ai-bar'));

void main() {
  // `flutter test` runs the real build; the demo tests also run with
  // --dart-define=DEMO_BUILD=true (T-18 unit 2b).
  test('the flag follows DEMO_BUILD', () {
    expect(demoBuild, const bool.fromEnvironment('DEMO_BUILD'));
  });

  group('demoStore', () {
    test('holds one starter copy of each template with the sample items', () {
      final ListCatalog catalog = demoStore(DateTime(2026, 11, 17, 9)).current;
      expect(catalog.definitions.map((d) => d.templateId), [
        BuiltinTemplates.tasksId,
        BuiltinTemplates.groceryId,
        BuiltinTemplates.journalId,
        BuiltinTemplates.watchReadId,
      ]);
      for (final ListDefinition list in catalog.definitions) {
        expect(list.id, startsWith('list-'));
        expect(catalog.itemsOf(list.id), isNotEmpty, reason: list.name);
        for (final item in catalog.itemsOf(list.id)) {
          expect(item.validateAgainst(list), isEmpty, reason: '${item.values}');
        }
      }
      final ListDefinition tasks = catalog.definitions.first;
      expect(
        catalog.itemsOf(tasks.id).map((item) => item['reminderAt']),
        everyElement(isNull),
      );
      expect(
        catalog.itemsOf(tasks.id).map((item) => item['title']),
        contains('Call the dentist'),
      );
    });

    test('is fresh on every start', () {
      final DateTime now = DateTime(2026, 11, 17, 9);
      final ListCatalog first = demoStore(now).current;
      final ListCatalog second = demoStore(now).current;
      expect(
        first.definitions
            .map((d) => d.id)
            .toSet()
            .intersection(second.definitions.map((d) => d.id).toSet()),
        isEmpty,
      );
      expect(
        first.items
            .map((i) => i.id)
            .toSet()
            .intersection(second.items.map((i) => i.id).toSet()),
        isEmpty,
      );
    });

    test('keeps a write in memory only for that store', () async {
      final MemoryListStore store = demoStore(DateTime.now());
      addTearDown(store.close);
      final ListDefinition grocery = store.current.definitions[1];
      await store.deleteList(grocery.id);
      expect(store.current.definition(grocery.id), isNull);
      expect(demoStore(DateTime.now()).current.definitions, hasLength(4));
    });
  });

  testWidgets('opens on the home screen with the samples and no sign-in', (
    tester,
  ) async {
    final MemoryListStore store = await _pumpDemo(tester, const Size(390, 844));
    expect(_hub, findsOneWidget);
    expect(find.byKey(const ValueKey('sign-in')), findsNothing);
    expect(find.byKey(const ValueKey('demo-phone-column')), findsNothing);

    // The launcher shows the starter lists; Tasks opens with its samples.
    await tester.tap(_hub);
    await tester.pump();
    for (final ListDefinition list in store.current.definitions) {
      expect(find.byKey(ValueKey('launcher-note-${list.id}')), findsOneWidget);
    }
    await tester.tap(
      find.byKey(
        ValueKey('launcher-note-${store.current.definitions.first.id}'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Call the dentist'), findsOneWidget);
  });

  testWidgets('settings has no account rows; preferences no Reminders', (
    tester,
  ) async {
    await _pumpDemo(tester, const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-preferences')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-account')), findsNothing);
    expect(find.byKey(const ValueKey('sign-out')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-preferences')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('preferences-section-home')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('preferences-section-reminders')),
      findsNothing,
    );
    // No account, nothing syncs: the line saying so is not shown (T-18 M7).
    expect(
      find.text('These follow your account to every phone.'),
      findsNothing,
    );
  });

  testWidgets('a wide frame shows the phone layout centred', (tester) async {
    await _pumpDemo(tester, const Size(1280, 800));
    final Finder column = find.byKey(const ValueKey('demo-phone-column'));
    expect(column, findsOneWidget);
    final Rect rect = tester.getRect(column);
    expect(rect.width, demoPhoneWidth);
    expect(rect.height, 800);
    expect(rect.center.dx, 640);
    // The screens lay out at the column's width, and stay inside it.
    expect(MediaQuery.sizeOf(tester.element(_hub)).width, demoPhoneWidth);
    final Rect hub = tester.getRect(_hub);
    expect(hub.left, greaterThanOrEqualTo(rect.left));
    expect(hub.right, lessThanOrEqualTo(rect.right));

    // A sheet opens inside the column too.
    await tester.tap(find.byKey(const ValueKey('settings')));
    await tester.pumpAndSettle();
    final Rect row = tester.getRect(
      find.byKey(const ValueKey('settings-preferences')),
    );
    expect(row.left, greaterThanOrEqualTo(rect.left));
    expect(row.right, lessThanOrEqualTo(rect.right));
  });

  group('top inset for the portfolio close button (Q-145)', () {
    test('only with embed=1 and a coarse pointer', () {
      expect(
        demoTopInset(query: '?embed=1', coarsePointer: true),
        embedTouchInset,
      );
      expect(demoTopInset(query: 'embed=1', coarsePointer: true), 56);
      expect(demoTopInset(query: '?a=b&embed=1', coarsePointer: true), 56);
      expect(demoTopInset(query: '?embed=1', coarsePointer: false), 0);
      expect(demoTopInset(query: '', coarsePointer: true), 0);
      expect(demoTopInset(query: '?embed=0', coarsePointer: true), 0);
      expect(demoTopInset(query: '?embedded=1', coarsePointer: true), 0);
      expect(demoTopInset(query: '?embed=%', coarsePointer: true), 0);
    });

    test('off the web the page probe reports no URL and a fine pointer', () {
      expect(pageQuery(), '');
      expect(coarsePointer(), isFalse);
    });

    // The portfolio's close button on a 390 wide touch frame: 12 from the
    // top and right edges, about 60 by 36.
    final Rect closeButton = Rect.fromLTWH(390 - 12 - 60, 12, 60, 36);

    void expectBelowInset(WidgetTester tester, Finder finder) {
      for (final Element element in finder.evaluate()) {
        final Rect rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.top, greaterThanOrEqualTo(56), reason: '$rect');
        expect(rect.overlaps(closeButton), isFalse, reason: '$rect');
      }
    }

    testWidgets('with the inset every screen, sheet and dialog sits below '
        'a dark band', (tester) async {
      await _pumpDemo(tester, const Size(390, 844), topInset: 56);
      final Finder band = find.byKey(const ValueKey('demo-top-inset'));
      expect(band, findsOneWidget);
      expect(tester.widget<ColoredBox>(band).color, demoInsetBand);
      expect(tester.getRect(band), const Rect.fromLTWH(0, 0, 390, 844));
      // The screens see the room below the band as the screen.
      expect(MediaQuery.sizeOf(tester.element(_hub)), const Size(390, 788));
      expect(tester.getRect(find.byType(Scaffold).first).top, 56);
      expectBelowInset(tester, find.byKey(const ValueKey('settings')));
      expectBelowInset(tester, find.byType(IconButton));

      // The settings sheet.
      await tester.tap(find.byKey(const ValueKey('settings')));
      await tester.pumpAndSettle();
      expectBelowInset(
        tester,
        find.byKey(const ValueKey('settings-preferences')),
      );
      expect(
        tester.getRect(find.byType(BottomSheet)).top,
        greaterThanOrEqualTo(56),
      );

      // Preferences, a full page.
      await tester.tap(find.byKey(const ValueKey('settings-preferences')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(AppBar).last).top, 56);
      expectBelowInset(tester, find.byType(IconButton));
      // Back twice: to the sheet, then home.
      for (var i = 0; i < 2; i++) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      expect(_hub, findsOneWidget);

      // A full-height sheet and a dialog stay below the band too.
      final BuildContext context = tester.element(_hub);
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const SizedBox.expand(key: ValueKey('tall-sheet')),
        ),
      );
      await tester.pumpAndSettle();
      // Material keeps a full-height sheet a little below the top too.
      expect(
        tester.getRect(find.byKey(const ValueKey('tall-sheet'))).top,
        greaterThanOrEqualTo(56),
      );
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(
            title: Text('Dialog'),
            actions: [TextButton(onPressed: null, child: Text('OK'))],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expectBelowInset(tester, find.byType(AlertDialog));
      expect(
        tester.getRect(find.byType(ModalBarrier).last).top,
        56,
        reason: 'the barrier covers only the room below the band',
      );
    });

    testWidgets('without the inset nothing changes', (tester) async {
      await _pumpDemo(tester, const Size(390, 844));
      expect(find.byKey(const ValueKey('demo-top-inset')), findsNothing);
      expect(MediaQuery.sizeOf(tester.element(_hub)), const Size(390, 844));
      expect(tester.getRect(find.byType(Scaffold).first).top, 0);
    });

    testWidgets('a wide touch frame keeps the centred column below the band', (
      tester,
    ) async {
      await _pumpDemo(tester, const Size(1280, 800), topInset: 56);
      final Rect column = tester.getRect(
        find.byKey(const ValueKey('demo-phone-column')),
      );
      expect(column, const Rect.fromLTWH(425, 56, demoPhoneWidth, 744));
      expect(
        MediaQuery.sizeOf(tester.element(_hub)),
        const Size(demoPhoneWidth, 744),
      );
    });
  });

  // T-18 unit 5 (Q-146): the demo starts light even on a dark system.
  group('light by default', () {
    late SharedPreferencesStorePlatform original;

    setUp(() => original = SharedPreferencesStorePlatform.instance);
    tearDown(() {
      SharedPreferencesStorePlatform.instance = original;
      SharedPreferences.resetStatic();
    });

    testWidgets('the demo start is light on a dark system; without its '
        'preferences the root follows the system', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      // Without the demo's preferences: follows the system, so dark.
      await _pumpDemo(tester, const Size(390, 844));
      expect(Theme.of(tester.element(_hub)).brightness, Brightness.dark);

      SharedPreferences.resetStatic();
      final SharedPreferences preferences =
          await tester.runAsync(demoPreferences) as SharedPreferences;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        BlocProvider(
          create: (_) => AppSettingsCubit(preferences),
          child: DemoApp(store: demoStore(DateTime.now())),
        ),
      );
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(_hub)).brightness, Brightness.light);
    });
  });

  // T-18 unit 5 (Q-147): the portfolio page's keyboard over the frame.
  group('keyboard from the parent page', () {
    testWidgets('the AI bar rises above the covered part and comes back', (
      tester,
    ) async {
      final ValueNotifier<double> keyboard = ValueNotifier<double>(0);
      await _pumpDemo(
        tester,
        const Size(390, 844),
        aiService: _NoAi(),
        keyboardInset: keyboard,
      );
      final double restBottom = tester.getRect(_bar).bottom;
      expect(restBottom, lessThanOrEqualTo(844));

      await tester.tap(_bar);
      await tester.pumpAndSettle();
      final Finder field = find.byKey(const ValueKey('ai-bar-field'));
      final FocusNode focus = tester
          .widget<TextField>(
            find.descendant(
              of: field,
              matching: find.byType(TextField),
              matchRoot: true,
            ),
          )
          .focusNode!;
      expect(focus.hasFocus, isTrue);
      keyboard.value = 320;
      await tester.pumpAndSettle();
      // The field keeps its focus (and the keyboard stays up).
      expect(focus.hasFocus, isTrue);
      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(Scaffold).first),
        ).bottom,
        320,
      );
      expect(tester.getRect(_bar).bottom, lessThanOrEqualTo(844 - 320));
      expect(tester.getRect(_hub).bottom, lessThanOrEqualTo(844 - 320));

      keyboard.value = 0;
      await tester.pumpAndSettle();
      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(Scaffold).first),
        ).bottom,
        0,
      );
      expect(tester.getRect(_bar).bottom, greaterThan(844 - 320));
    });

    testWidgets('with the top inset too, and never below the own keyboard', (
      tester,
    ) async {
      final ValueNotifier<double> keyboard = ValueNotifier<double>(300);
      await _pumpDemo(
        tester,
        const Size(390, 844),
        topInset: 56,
        aiService: _NoAi(),
        keyboardInset: keyboard,
      );
      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(Scaffold).first),
        ).bottom,
        300,
      );
      expect(tester.getRect(_bar).bottom, lessThanOrEqualTo(844 - 300));
      expect(tester.getRect(_bar).top, greaterThanOrEqualTo(56));

      // The demo's own keyboard (outside a frame) wins when it is larger.
      tester.view.viewInsets = const FakeViewPadding(bottom: 400);
      await tester.pumpAndSettle();
      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(Scaffold).first),
        ).bottom,
        400,
      );
    });

    testWidgets('without a parent nothing changes', (tester) async {
      await _pumpDemo(tester, const Size(390, 844), aiService: _NoAi());
      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(Scaffold).first),
        ).bottom,
        0,
      );
    });
  });
}
