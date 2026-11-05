import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/home_screen.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
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
  _task('t-tomorrow', 'Tomorrow thing', _today.add(const Duration(days: 1, hours: 9))),
  _task('t-today', 'Submit milestone', _today.add(const Duration(hours: 17))),
  _task('t-late', 'Return books', _today.subtract(const Duration(days: 2))),
  _task('t-done', 'Done already', _today.add(const Duration(hours: 8)), done: true),
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
    final List<HomeDueItem> due = homeDueItems(catalog, _today.add(const Duration(hours: 12)));
    expect(due.map((d) => d.item.id), ['t-late', 't-today']);
    expect(due.every((d) => d.hasTime), isTrue);
  });

  testWidgets('weekday, date with the count, and the due rows with their dots', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(find.text(DateFormat.EEEE('en').format(_now)), findsOneWidget);
    expect(
      find.text('${DateFormat.MMMMd('en').format(_now)} · 2 things today'),
      findsOneWidget,
    );
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Submit milestone'), findsOneWidget);
    expect(find.text('Return books'), findsOneWidget);
    expect(find.text('Tomorrow thing'), findsNothing);
    expect(find.text('Done already'), findsNothing);
    // Overdue first, with its date; today's with its time.
    expect(
      tester.getTopLeft(find.text('Return books')).dy,
      lessThan(tester.getTopLeft(find.text('Submit milestone')).dy),
    );
    expect(
      find.text(DateFormat.MMMd('en').format(_today.subtract(const Duration(days: 2)))),
      findsOneWidget,
    );
    expect(
      find.text(DateFormat.jm('en').format(_today.add(const Duration(hours: 17)))),
      findsOneWidget,
    );
    expect(find.byType(Card), findsNothing);

    // A row opens its list.
    await tester.tap(find.byKey(const ValueKey('home-due-t-today')));
    await settle(tester);
    expect(find.byKey(const ValueKey('item-t-today')), findsOneWidget);
  });

  testWidgets('the blue settings button opens a sheet: language, dark mode, account', (
    tester,
  ) async {
    await _pumpApp(tester);
    final IconButton button = tester.widget(find.byKey(const ValueKey('settings')));
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
    await tester.tap(find.byKey(const ValueKey('settings-dark-mode')));
    await settle(tester);
    expect(app().themeMode, ThemeMode.dark);
  });
}
