import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/home_cards_view.dart';
import 'package:hybrid_note/home_screen.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';

import 'support/fake_auth.dart';
import 'support/firestore_store.dart';

// The home behind the hub (T-16 unit 5, Q-20 A): weekday, date with
// "N things today", what is due today or overdue, and the settings sheet.

final DateTime _now = DateTime.now();
final DateTime _today = DateTime(_now.year, _now.month, _now.day);

ListItem _task(String id, String title, DateTime? at, {bool done = false}) {
  return ListItem(
    id: id,
    listId: BuiltinTemplates.tasksId,
    values: {
      'title': title,
      'done': done,
      if (at != null) 'reminderAt': at.toIso8601String(),
    },
    createdAt: _today,
    updatedAt: _today,
  );
}

final List<ListItem> _items = [
  _task(
    't-tomorrow',
    'Tomorrow thing',
    _today.add(const Duration(days: 1, hours: 9)),
  ),
  _task('t-today', 'Submit milestone', _today.add(const Duration(hours: 17))),
  _task('t-late', 'Return books', _today.subtract(const Duration(days: 2))),
  _task(
    't-done',
    'Done already',
    _today.add(const Duration(hours: 8)),
    done: true,
  ),
  _task('t-none', 'No date', null),
];

Future<FirestoreListStore> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(const {});
  final FirestoreListStore store = await widgetTestStore(tester, items: _items);
  await tester.pumpWidget(
    await testApp(
      auth: FakeAuthService(user: testUser),
      openStore: (_) => store,
    ),
  );
  await settle(tester);
  return store;
}

void main() {
  test('due today or overdue, open items only, earliest first', () {
    final ListCatalog catalog = ListCatalog(
      definitions: BuiltinTemplates.all(),
      items: _items,
    );
    final List<HomeDueItem> due = homeDueItems(
      catalog,
      _today.add(const Duration(hours: 12)),
    );
    // Ticked ones stay until cleared (t-done, ticked today).
    expect(due.map((d) => d.item.id), ['t-late', 't-done', 't-today']);
    expect(due.map((d) => d.done), [false, true, false]);
    expect(due.every((d) => d.hasTime), isTrue);
  });

  test('in a list that cannot clear, a ticked item stays only while due '
      'today', () {
    final ListDefinition tasks = BuiltinTemplates.all().firstWhere(
      (definition) => definition.id == BuiltinTemplates.tasksId,
    );
    final Map<String, dynamic> json = tasks.toJson()..['behaviors'] = [];
    final ListDefinition noClear = ListDefinition.fromJson(json);
    final List<ListItem> items = [
      _task(
        't-done-today',
        'Ticked today',
        _today.add(const Duration(hours: 8)),
        done: true,
      ),
      _task(
        't-done-late',
        'Ticked late',
        _today.subtract(const Duration(days: 1)),
        done: true,
      ),
    ];
    List<String> due(ListDefinition definition) => [
      for (final HomeDueItem item in homeDueItems(
        ListCatalog(definitions: [definition], items: items),
        _today.add(const Duration(hours: 12)),
      ))
        item.item.id,
    ];
    expect(due(noClear), ['t-done-today']);
    expect(due(tasks), ['t-done-late', 't-done-today']);
  });

  testWidgets(
    'weekday, date with the count, and the due rows with their dots',
    (tester) async {
      await _pumpApp(tester);

      expect(find.text(DateFormat.EEEE('en').format(_now)), findsOneWidget);
      expect(
        find.text('${DateFormat.MMMMd('en').format(_now)} · 2 things today'),
        findsOneWidget,
      );
      // The header's count says it, so no label above the rows.
      expect(find.text('TODAY'), findsNothing);
      // In the Today rows; the Tasks card below may show them too (Q-65).
      Finder inRow(String id, String text) => find.descendant(
        of: find.byKey(ValueKey('home-due-$id')),
        matching: find.text(text),
      );
      // One line, starting at the left edge of the cards' blobs: a small card
      // mark (the blob, the tick circle over its lower right as a card's
      // circle over its blob), then the title on its line.
      final double cardLeft = tester
          .getTopLeft(find.byType(HomeListCard).first)
          .dx;
      final Finder blob = find.descendant(
        of: find.byKey(const ValueKey('home-due-t-today')),
        matching: find.byType(HomeSmallBlob),
      );
      final Rect blobRect = tester.getRect(blob);
      expect(blobRect.left - cardLeft, homeDueLeft);
      expect(blobRect.width, homeDueBlobSize);
      final Finder tick = find.byKey(const ValueKey('home-tick-t-today'));
      expect(tester.getSize(tick), const Size.square(homeTickTarget));
      final Offset circle = tester.getCenter(tick);
      expect(
        circle.dx - blobRect.left,
        moreOrLessEquals(homeDueBlobSize * 25 / 84 + homeTickSize / 2),
      );
      expect(
        circle.dy - blobRect.top,
        moreOrLessEquals(homeDueBlobSize * 25 / 84 + homeTickSize / 2),
      );
      final Rect title = tester.getRect(inRow('t-today', 'Submit milestone'));
      expect(title.left, greaterThanOrEqualTo(tester.getRect(tick).right));
      expect(circle.dy, moreOrLessEquals(title.center.dy, epsilon: 2));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-due-t-today')),
          matching: find.byType(Icon),
        ),
        findsNothing,
      );
      // Still in tests, as with reduced motion: no clock.
      expect(tester.widget<HomeSmallBlob>(blob).clock, isNull);
      expect(inRow('t-today', 'Submit milestone'), findsOneWidget);
      expect(inRow('t-late', 'Return books'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-due-t-tomorrow')), findsNothing);
      // Ticked today and not cleared: it stays, ticked, with its ×; the count
      // is of open items only.
      expect(find.byKey(const ValueKey('home-due-t-done')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-clear-t-done')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-clear-t-today')), findsNothing);
      // Overdue first, with its date; today's with its time.
      expect(
        tester.getTopLeft(inRow('t-late', 'Return books')).dy,
        lessThan(tester.getTopLeft(inRow('t-today', 'Submit milestone')).dy),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-due-t-late')),
          matching: find.textContaining(
            DateFormat.MMMd(
              'en',
            ).format(_today.subtract(const Duration(days: 2))),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-due-t-today')),
          matching: find.textContaining(
            DateFormat.jm('en').format(_today.add(const Duration(hours: 17))),
          ),
        ),
        findsOneWidget,
      );
      expect(find.byType(Card), findsNothing);

      // A row opens its list.
      await tester.tap(find.byKey(const ValueKey('home-due-t-today')));
      await settle(tester);
      expect(find.byKey(const ValueKey('item-t-today')), findsOneWidget);
    },
  );

  group('ticking a Today row', () {
    // What the store holds now, read outside the test's fake clock.
    Future<bool?> done(
      WidgetTester tester,
      FirestoreListStore store,
      String id,
    ) async {
      final ListCatalog catalog = (await tester.runAsync(
        () => store.watch().first,
      ))!;
      for (final ListItem item in catalog.itemsOf(BuiltinTemplates.tasksId)) {
        if (item.id == id) {
          return item['done'] == true;
        }
      }
      return null;
    }

    testWidgets('a tick stays on home, crossed out, and a tap unticks it', (
      tester,
    ) async {
      final FirestoreListStore store = await _pumpApp(tester);
      final Finder row = find.byKey(const ValueKey('home-due-t-today'));
      await tester.tap(find.byKey(const ValueKey('home-tick-t-today')));
      await settle(tester);
      expect(await done(tester, store, 't-today'), isTrue);
      await settle(tester);
      expect(row, findsOneWidget);
      final Text title = tester.widget<Text>(
        find.descendant(of: row, matching: find.text('Submit milestone')),
      );
      expect(title.style?.decoration, TextDecoration.lineThrough);
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-clear-t-today')), findsOneWidget);
      // No banner: the circle itself takes it back.
      expect(find.text('Ticked off'), findsNothing);
      // The list page was not opened.
      expect(find.byKey(const ValueKey('item-t-today')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-tick-t-today')));
      await settle(tester);
      expect(await done(tester, store, 't-today'), isFalse);
      await settle(tester);
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.check)),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('home-clear-t-today')), findsNothing);
    });

    testWidgets('× clears it as the list page does, and the row goes', (
      tester,
    ) async {
      final FirestoreListStore store = await _pumpApp(tester);
      await tester.tap(find.byKey(const ValueKey('home-clear-t-done')));
      await settle(tester);
      expect(await done(tester, store, 't-done'), isNull);
      await settle(tester);
      expect(find.byKey(const ValueKey('home-due-t-done')), findsNothing);
      expect(find.byKey(const ValueKey('home-due-t-today')), findsOneWidget);
    });
  });

  testWidgets('the rows\' blobs move on one clock, repainting only', (
    tester,
  ) async {
    await _pumpApp(tester);
    // Movement on, by hand, as the blobs never settle, and home built again.
    HomeBlob.stillForTests = false;
    addTearDown(() => HomeBlob.stillForTests = true);
    tester.element(find.byType(HomeScreen)).markNeedsBuild();
    await tester.pump();
    final List<HomeSmallBlob> blobs = tester
        .widgetList<HomeSmallBlob>(find.byType(HomeSmallBlob))
        .toList();
    // Two open rows and one ticked.
    expect(blobs, hasLength(3));
    final Listenable? clock = blobs.first.clock;
    expect(clock, isNotNull);
    expect(blobs.every((blob) => identical(blob.clock, clock)), isTrue);
    // Ticks repaint the blobs without rebuilding the row.
    final Element row = tester.element(
      find.byKey(const ValueKey('home-due-t-today')),
    );
    final Widget before = row.widget;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(identical(row.widget, before), isTrue);
    await tester.pumpWidget(Container());
    HomeBlob.stillForTests = true;
  });

  testWidgets(
    'the blue settings button opens a sheet: language, dark mode, account',
    (tester) async {
      await _pumpApp(tester);
      final IconButton button = tester.widget(
        find.byKey(const ValueKey('settings')),
      );
      expect(
        button.style!.backgroundColor!.resolve(const {}),
        const Color(0xFF70D9FF),
      );

      await tester.tap(find.byKey(const ValueKey('settings')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(FadeTransition), findsNothing);
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsWidgets);
      expect(find.byKey(const ValueKey('settings-language')), findsOneWidget);
      expect(find.text('owner@example.com'), findsOneWidget);
      expect(find.byKey(const ValueKey('sign-out')), findsOneWidget);

      MaterialApp app() => tester.widget(find.byType(MaterialApp));
      expect(app().themeMode, ThemeMode.system);
      await tester.tap(find.byKey(const ValueKey('settings-theme')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('choice-ThemeMode.dark')));
      await settle(tester);
      expect(app().themeMode, ThemeMode.dark);
    },
  );

  group('the language list', () {
    Future<void> openLanguages(WidgetTester tester, Size size) async {
      await _pumpApp(tester);
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-language')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-language')));
      await tester.pumpAndSettle();
    }

    ScrollPosition position(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    testWidgets('shows every language without scrolling where they fit', (
      tester,
    ) async {
      await openLanguages(tester, const Size(412, 914));

      expect(position(tester).maxScrollExtent, 0);
      expect(find.text('Deutsch'), findsOneWidget);
      expect(find.text('Use device language'), findsOneWidget);
    });

    testWidgets(
      'on a small screen has a bar, and the last language can be reached',
      (tester) async {
        await openLanguages(tester, const Size(320, 640));

        expect(position(tester).maxScrollExtent, greaterThan(0));
        final Scrollbar bar = tester.widget(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollbar),
          ),
        );
        expect(bar.thumbVisibility, isTrue);

        await tester.scrollUntilVisible(
          find.text('Deutsch'),
          100,
          scrollable: find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Deutsch'));
        await settle(tester);

        expect(find.byType(AlertDialog), findsNothing);
        MaterialApp app() => tester.widget(find.byType(MaterialApp));
        expect(app().locale, const Locale('de'));
      },
    );
  });
}
