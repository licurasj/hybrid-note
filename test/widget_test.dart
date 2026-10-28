import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/app_settings.dart';
import 'package:hybrid_note/backend/auth_service.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/backend/firestore_setup.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/generic_list_screen.dart';
import 'package:hybrid_note/lists/list_definition.dart';

import 'support/fake_auth.dart';
import 'support/firestore_store.dart';

// The app on [auth]; whoever signs in gets [store] (the starter lists).
Future<FirestoreListStore> _pumpApp(
  WidgetTester tester,
  FakeAuthService auth, {
  Map<String, Object> preferences = const {},
  VoidCallback? afterSignOut,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(preferences);

  final FirestoreListStore store = await widgetTestStore(tester);
  await tester.pumpWidget(
    await testApp(
      auth: auth,
      openStore: (_) => store,
      afterSignOut: afterSignOut,
    ),
  );
  await settle(tester);
  return store;
}

final Finder _hub = find.byKey(const ValueKey('launcher-hub'));

void main() {
  testWidgets('signed in, the app starts on the home screen with the lists', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, FakeAuthService(user: testUser));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-in')), findsNothing);
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(_hub, findsOneWidget);

    // Tap mode: open the hub and pick Grocery; the list opens as a page.
    await tester.tap(_hub);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('launcher-note-${BuiltinTemplates.groceryId}')),
    );
    await settle(tester);
    expect(find.text('Grocery List'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed out shows only the sign-in screen; sign in and out', (
    WidgetTester tester,
  ) async {
    final FakeAuthService auth = FakeAuthService();
    await _pumpApp(tester, auth);

    expect(find.text('Hybrid Note App'), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
    expect(_hub, findsNothing);
    expect(find.text('Grocery'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sign-in')));
    await settle(tester);
    expect(find.byKey(const ValueKey('sign-in')), findsNothing);
    expect(_hub, findsOneWidget);
    expect(find.text('Grocery'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sign-out')));
    await settle(tester);
    expect(auth.calls, ['signIn', 'signOut', 'clearCache']);
    expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
    expect(_hub, findsNothing);
    expect(find.text('Grocery List'), findsNothing);
    expect(find.text('owner@example.com'), findsNothing);
  });

  testWidgets('a failed cache clear keeps a retry state until it works', (
    WidgetTester tester,
  ) async {
    final FakeAuthService auth = FakeAuthService(user: testUser)
      ..cleanupResults.add(false);
    int reloads = 0;
    await _pumpApp(tester, auth, afterSignOut: () => reloads++);
    final Finder signIn = find.byKey(const ValueKey('sign-in'));
    bool signInEnabled() =>
        tester.widget<ButtonStyleButton>(signIn).onPressed != null;

    await tester.tap(find.byKey(const ValueKey('sign-out')));
    await settle(tester);
    // Signed out, but the lists are still on the device: no reload (on web)
    // and no sign-in until they are deleted (T-17 R1).
    expect(_hub, findsNothing);
    expect(find.byKey(const ValueKey('cleanup-failed')), findsOneWidget);
    expect(signInEnabled(), isFalse);
    expect(reloads, 0);

    await tester.tap(find.byKey(const ValueKey('retry-cleanup')));
    await settle(tester);
    expect(auth.calls, ['signOut', 'clearCache', 'clearCache']);
    expect(find.byKey(const ValueKey('cleanup-failed')), findsNothing);
    expect(signInEnabled(), isTrue);
    expect(reloads, 1);
  });

  testWidgets('a new user waits until the sign-out and its cleanup end', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(const {});
    final FakeAuthService auth = FakeAuthService(user: testUser)
      ..cleanupGate = Completer<void>();
    final List<FirestoreListStore> stores = [
      await widgetTestStore(tester),
      await widgetTestStore(tester),
    ];
    const AuthUser other = AuthUser(uid: 'user-2', email: 'other@example.com');
    await tester.pumpWidget(
      await testApp(
        auth: auth,
        openStore: (user) {
          auth.calls.add('open ${user.uid}');
          return stores.removeAt(0);
        },
      ),
    );
    await settle(tester);
    final Finder signIn = find.byKey(const ValueKey('sign-in'));
    bool signInEnabled() =>
        tester.widget<ButtonStyleButton>(signIn).onPressed != null;

    await tester.tap(find.byKey(const ValueKey('sign-out')));
    await settle(tester);
    // The cache is still being cleared: sign-in waits (T-17 R2).
    expect(auth.calls, ['open $testUid', 'signOut', 'clearCache']);
    expect(signInEnabled(), isFalse);

    // Another user signs in meanwhile (another tab, say): no store opens on
    // the cache that is about to go.
    auth.emit(other);
    await settle(tester);
    expect(auth.calls, ['open $testUid', 'signOut', 'clearCache']);
    expect(signIn, findsOneWidget);

    auth.cleanupGate!.complete();
    await settle(tester);
    expect(auth.calls, [
      'open $testUid',
      'signOut',
      'clearCache',
      'open user-2',
    ]);
    expect(find.text('other@example.com'), findsOneWidget);
    expect(_hub, findsOneWidget);
  });

  testWidgets('a sign-in failure shows a message and stays signed out', (
    WidgetTester tester,
  ) async {
    final FakeAuthService auth = FakeAuthService()
      ..signInError = const AuthException(AuthFailure.network);
    await _pumpApp(tester, auth);

    await tester.tap(find.byKey(const ValueKey('sign-in')));
    await settle(tester);
    expect(
      find.text('No connection. Connect to the internet to sign in.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
    expect(_hub, findsNothing);
  });

  testWidgets('an anonymous user reaches the lists the same way (D-13)', (
    WidgetTester tester,
  ) async {
    await _pumpApp(
      tester,
      FakeAuthService(user: const AuthUser(uid: testUid, isAnonymous: true)),
    );

    expect(find.byKey(const ValueKey('sign-in')), findsNothing);
    expect(_hub, findsOneWidget);
    expect(find.text('Grocery'), findsOneWidget);
  });

  testWidgets('settings come from this device: dark mode and language', (
    WidgetTester tester,
  ) async {
    await _pumpApp(
      tester,
      FakeAuthService(user: testUser),
      preferences: {
        AppSettingsCubit.darkModeKey: true,
        AppSettingsCubit.localeKey: 'de',
      },
    );

    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.locale, const Locale('de'));
  });

  testWidgets('"New list" offers Blank and the four templates', (
    WidgetTester tester,
  ) async {
    final FirestoreListStore store = await _pumpApp(
      tester,
      FakeAuthService(user: testUser),
    );

    Future<void> openPicker() async {
      await tester.tap(_hub);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('launcher-add')));
      await tester.pumpAndSettle();
    }

    await openPicker();
    expect(find.byKey(const ValueKey('template-blank')), findsOneWidget);
    for (final ListDefinition template in BuiltinTemplates.all()) {
      expect(find.byKey(ValueKey('template-${template.id}')), findsOneWidget);
    }

    // Each template opens the editor on a fresh copy, saved as a new list.
    for (final ListDefinition template in BuiltinTemplates.all()) {
      final int before = store.current.definitions.length;
      if (find.byKey(const ValueKey('template-blank')).evaluate().isEmpty) {
        await openPicker();
      }
      await tester.tap(find.byKey(ValueKey('template-${template.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-list')));
      await settle(tester);

      expect(store.current.definitions, hasLength(before + 1));
      final ListDefinition created = store.current.definitions.last;
      expect(created.id, isNot(template.id));
      expect(created.templateId, template.id);
      expect(created.fields.map((f) => f.key), template.fields.map((f) => f.key));
      // The new list opens; go back to the shell.
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    // Blank needs a name before it can be saved.
    await openPicker();
    await tester.tap(find.byKey(const ValueKey('template-blank')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('list-name')), 'Plants');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-list')));
    await settle(tester);
    expect(store.current.definitions.last.name, 'Plants');
    expect(store.current.definitions.last.templateId, isNull);
  });

  testWidgets('offline, a new list opens and a deleted one offers Undo at once', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(const {});
    final DelayedAckFirestore firestore = DelayedAckFirestore();
    final FirestoreListStore store = await widgetTestStore(
      tester,
      firestore: firestore,
    );
    await tester.pumpWidget(
      await testApp(
        auth: FakeAuthService(user: testUser),
        openStore: (_) => store,
      ),
    );
    await settle(tester);
    // From here the server never answers (T-17 R3).
    firestore.holdAcks = true;

    await tester.tap(_hub);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('launcher-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('template-blank')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('list-name')), 'Plants');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-list')));
    await settle(tester);
    expect(find.byType(GenericListScreen), findsOneWidget);
    final String created = store.current.definitions.last.id;
    expect(store.current.definitions.last.name, 'Plants');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(_hub);
    await tester.pump();
    await tester.longPress(find.byKey(ValueKey('launcher-note-$created')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-list')));
    await settle(tester);
    expect(store.current.definition(created), isNull);
    expect(find.text('List deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(store.current.definition(created)!.name, 'Plants');
    expect(firestore.acks, hasLength(3));
    expect(firestore.acks.where((ack) => ack.isCompleted), isEmpty);
  });

  testWidgets('a list change the server rejects later shows a message', (
    WidgetTester tester,
  ) async {
    final DelayedAckFirestore firestore = DelayedAckFirestore();
    SharedPreferences.setMockInitialValues(const {});
    final FirestoreListStore store = await widgetTestStore(
      tester,
      firestore: firestore,
    );
    await tester.pumpWidget(
      await testApp(
        auth: FakeAuthService(user: testUser),
        openStore: (_) => store,
      ),
    );
    await settle(tester);
    firestore.holdAcks = true;

    await tester.runAsync(
      () => store.deleteList(BuiltinTemplates.groceryId),
    );
    firestore.acks.single.completeError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await settle(tester);
    expect(find.text('A list change could not be saved and was undone.'),
        findsOneWidget);
  });

  // T-17 F1: the editor has closed when the patch fails, so the failure is
  // reported rather than lost.
  testWidgets('a list edit that cannot be saved shows a message', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(const {});
    final _RefusingTransactions firestore = _RefusingTransactions();
    final FirestoreListStore store = await widgetTestStore(
      tester,
      firestore: firestore,
    );
    await tester.pumpWidget(
      await testApp(
        auth: FakeAuthService(user: testUser),
        openStore: (_) => store,
      ),
    );
    await settle(tester);

    await tester.tap(_hub);
    await tester.pump();
    await tester.longPress(
      find.byKey(const ValueKey('launcher-note-${BuiltinTemplates.groceryId}')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('list-name')), 'Shops');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-list')));
    await settle(tester);

    expect(
      find.text('A list change could not be saved and was undone.'),
      findsOneWidget,
    );
    expect(
      store.current.definition(BuiltinTemplates.groceryId)!.name,
      isNot('Shops'),
    );
  });

  group('starter lists could not be written (Q-27)', () {
    // An empty account whose seeding failed once; [seeds] records each
    // later attempt (empty = "Start empty").
    Future<List<bool>> pumpFailed(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(const {});
      final List<bool> seeds = [];
      bool fail = true;
      final StarterSeeding starter = StarterSeeding(({required empty}) async {
        if (fail) {
          fail = false;
          throw StateError('unavailable');
        }
        seeds.add(empty);
        return true;
      }, onError: (_) {});
      await starter.start();
      expect(starter.status, StarterStatus.failed);
      final FirestoreListStore store = await widgetTestStore(
        tester,
        lists: const [],
      );
      await tester.pumpWidget(
        await testApp(
          auth: FakeAuthService(user: testUser),
          openStore: (_) => store,
          starter: starter,
        ),
      );
      await settle(tester);
      return seeds;
    }

    testWidgets('the empty home says so; Try again seeds now', (
      WidgetTester tester,
    ) async {
      final List<bool> seeds = await pumpFailed(tester);
      expect(
        find.text('The starter lists could not be set up.'),
        findsOneWidget,
      );
      expect(seeds, isEmpty);

      await tester.tap(find.byKey(const ValueKey('starter-retry')));
      await settle(tester);
      expect(seeds, [false]);
      expect(find.byKey(const ValueKey('starter-failed')), findsNothing);
    });

    testWidgets('Start empty writes the marker without lists', (
      WidgetTester tester,
    ) async {
      final List<bool> seeds = await pumpFailed(tester);

      await tester.tap(find.byKey(const ValueKey('starter-empty')));
      await settle(tester);
      expect(seeds, [true]);
      expect(find.byKey(const ValueKey('starter-failed')), findsNothing);
    });
  });

  testWidgets('the hub can be moved and its position is saved', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, FakeAuthService(user: testUser));

    final Offset start = tester.getCenter(_hub);
    TestGesture gesture = await tester.startGesture(start);
    for (int i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final Offset prompt = tester.getCenter(find.byKey(const ValueKey('launcher-move-prompt')));
    for (int i = 1; i <= 6; i++) {
      await gesture.moveTo(Offset.lerp(start, prompt, i / 6)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();

    gesture = await tester.startGesture(start);
    await gesture.moveTo(const Offset(120, 200));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getCenter(_hub).dx, closeTo(120, 1));
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    expect(preferences.getDouble(AppSettingsCubit.hubXKey), isNotNull);
  });
}

// A server that refuses every transaction, as the rules would.
class _RefusingTransactions extends FakeFirebaseFirestore {
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
  }
}
