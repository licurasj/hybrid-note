import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/app_settings.dart';
import 'package:hybrid_note/demo/demo_app.dart';
import 'package:hybrid_note/demo/demo_build.dart';
import 'package:hybrid_note/demo/memory_list_store.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';

// The demo's root (T-18 unit 2a): the home screen on the starter lists and
// sample items, no account rows and no Reminders section, and the phone
// layout centred in a wide frame (Q-133, Q-136, Q-137).
final Finder _hub = find.byKey(const ValueKey('launcher-hub'));

Future<MemoryListStore> _pumpDemo(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final MemoryListStore store = demoStore(DateTime.now());
  await tester.pumpWidget(
    BlocProvider(
      create: (_) => AppSettingsCubit(preferences),
      child: DemoApp(store: store),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

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
}
