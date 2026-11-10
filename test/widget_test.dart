import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/app/app_settings.dart';
import 'package:hybrid_note/backend/auth_service.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/backend/firestore_preferences.dart';
import 'package:hybrid_note/backend/firestore_setup.dart';
import 'package:hybrid_note/home_screen.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/generic_list_host.dart';
import 'package:hybrid_note/lists/generic_list_screen.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_editor_screen.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_patch.dart';
import 'package:hybrid_note/lists/list_rules.dart';

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

// The account row (email, Log out) is in the settings sheet behind the home's
// settings button (T-16 unit 5).
Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('settings')));
  await tester.pumpAndSettle();
}

Future<void> _closeSettings(WidgetTester tester) async {
  Navigator.of(tester.element(find.byKey(const ValueKey('settings-account')))).pop();
  await tester.pumpAndSettle();
}

// The home no longer lists every list; the launcher (tap mode) does.
Future<void> _expectLauncherShows(WidgetTester tester, String label) async {
  await tester.tap(_hub);
  await tester.pump();
  expect(find.text(label), findsOneWidget);
  await tester.tap(_hub);
  await tester.pump();
}

void main() {
  testWidgets('signed in, the app starts on the home screen with the lists', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, FakeAuthService(user: testUser));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-in')), findsNothing);
    await _openSettings(tester);
    expect(find.text('owner@example.com'), findsOneWidget);
    await _closeSettings(tester);
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
    await _expectLauncherShows(tester, 'Grocery');

    await _openSettings(tester);
    await tester.tap(find.byKey(const ValueKey('sign-out')));
    await settle(tester);
    expect(auth.calls, ['signIn', 'signOut', 'clearCache']);
    expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
    expect(_hub, findsNothing);
    expect(find.text('Grocery List'), findsNothing);
    expect(find.text('owner@example.com'), findsNothing);
  });

  group('account preferences at the gate', () {
    AccountPreferencesCubit account(WidgetTester tester) => tester
        .element(find.byType(HomeScreen))
        .read<AccountPreferencesCubit>();

    testWidgets('a signed-in user gets theirs; sign-out forgets the copy', (
      WidgetTester tester,
    ) async {
      final FakeAuthService auth = FakeAuthService(user: testUser);
      await _pumpApp(tester, auth);
      await account(tester).setVibration(false);
      expect(account(tester).state.vibration, isFalse);
      final SharedPreferences stored = await SharedPreferences.getInstance();
      expect(
        stored.containsKey(AccountPreferencesCubit.pendingKey(testUser.uid)),
        isTrue,
      );

      await _openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('sign-out')));
      await settle(tester);

      expect(
        stored.containsKey(AccountPreferencesCubit.pendingKey(testUser.uid)),
        isFalse,
      );
      expect(
        stored.containsKey(AccountPreferencesCubit.mirrorKey(testUser.uid)),
        isFalse,
      );

      await tester.tap(find.byKey(const ValueKey('sign-in')));
      await settle(tester);
      expect(account(tester).state.vibration, isTrue);
    });

    testWidgets('a failed sign-out keeps the copy', (
      WidgetTester tester,
    ) async {
      final FakeAuthService auth = FakeAuthService(user: testUser)
        ..signOutError = StateError('no network');
      await _pumpApp(tester, auth);
      await account(tester).setVibration(false);

      await _openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('sign-out')));
      await settle(tester);

      expect(account(tester).state.vibration, isFalse);
    });

    testWidgets('they sync where the app says, for that user', (
      WidgetTester tester,
    ) async {
      final FakeFirebaseFirestore firestore = FakeFirebaseFirestore();
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        AccountPreferencesCubit.legacyAskLevelKey: 'less',
      });
      final FirestoreListStore store = await widgetTestStore(tester);
      await tester.pumpWidget(
        await testApp(
          auth: FakeAuthService(user: testUser),
          openStore: (_) => store,
          openPreferences: (user) =>
              FirestorePreferencesSync(firestore, user.uid),
        ),
      );
      await settle(tester);
      final document = firestore.doc(
        'users/${testUser.uid}/settings/preferences',
      );

      // The account had none: the phone's AI setting seeded it.
      expect((await document.get()).data()!['aiAskLevel'], 'less');

      await account(tester).setWeekStart(WeekStart.monday);
      await settle(tester);
      expect((await document.get()).data()!['weekStart'], 'monday');

      await document.set({'vibration': false}, SetOptions(merge: true));
      await settle(tester);
      expect(account(tester).state.vibration, isFalse);
    });

    testWidgets('hub, theme and language stay out of the account', (
      WidgetTester tester,
    ) async {
      await _pumpApp(
        tester,
        FakeAuthService(user: testUser),
        preferences: {
          AppSettingsCubit.themeModeKey: 'dark',
          AppSettingsCubit.localeKey: 'de',
          AppSettingsCubit.hubXKey: 0.5,
          AppSettingsCubit.hubYKey: 0.5,
        },
      );
      for (final String key in account(tester).state.toJson().keys) {
        expect(key, isNot(anyOf('theme', 'themeMode', 'locale', 'hubX', 'hubY')));
      }
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
    });
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

    await _openSettings(tester);
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

    await _openSettings(tester);
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
    await _openSettings(tester);
    expect(find.text('other@example.com'), findsOneWidget);
    await _closeSettings(tester);
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
    await _expectLauncherShows(tester, 'Grocery');
  });

  testWidgets('settings come from this device: dark mode and language', (
    WidgetTester tester,
  ) async {
    await _pumpApp(
      tester,
      FakeAuthService(user: testUser),
      preferences: {
        AppSettingsCubit.legacyDarkModeKey: true,
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

  testWidgets('items of a big change that stay stuck get a short message (Q-64)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(const {});
    const String plants = 'list-plants';
    final DateTime at = DateTime.utc(2026, 11, 4);
    final _FailingAfterOne firestore = _FailingAfterOne();
    final FirestoreListStore store = await widgetTestStore(
      tester,
      firestore: firestore,
      lists: [
        ListDefinition.fromJson({
          'id': plants,
          'name': 'Plants',
          'icon': 'local_florist',
          'color': '#43A047',
          'fields': [
            {'key': 'title', 'type': 'text', 'label': 'Plant', 'primary': true},
            {'key': 'kind', 'type': 'text', 'label': 'Kind'},
          ],
          'view': {'kind': 'cards'},
          'updatedAt': at.toIso8601String(),
        }),
      ],
      items: [
        for (int n = 0; n < 4; n++)
          ListItem(
            id: 'i$n',
            listId: plants,
            values: {'title': 'Plant $n', 'kind': '$n'},
            createdAt: at,
            updatedAt: at,
          ),
      ],
      batchLimit: 2,
    );
    await tester.pumpWidget(
      await testApp(
        auth: FakeAuthService(user: testUser),
        openStore: (_) => store,
      ),
    );
    await settle(tester);

    firestore.arm();
    final ListPatchResult? result = await tester.runAsync<ListPatchResult?>(
      () => store.patchList(plants, const [
        ListPatchOp(PatchOpKind.changeFieldType, {
          'key': 'kind',
          'type': 'counter',
        }),
      ]),
    );
    expect(result!.itemsPending, isTrue);
    await settle(tester);
    await tester.pump();

    expect(
      find.text(
        'Some items in this list could not be updated yet. '
        'The app will try again next time it opens.',
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
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
    // The editor's Items rows (T-13's how early too) push it down.
    await tester.ensureVisible(find.byKey(const ValueKey('delete-list')));
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

  testWidgets('renaming the open list in the edit screen shows on its page '
      'at once', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(const {});
    final FirestoreListStore store = await widgetTestStore(tester);
    await tester.pumpWidget(
      await testApp(
        auth: FakeAuthService(user: testUser),
        openStore: (_) => store,
      ),
    );
    await settle(tester);
    const String grocery = BuiltinTemplates.groceryId;

    await tester.tap(_hub);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('launcher-note-$grocery')));
    await settle(tester);
    await tester.tap(_hub);
    await tester.pump();
    await tester.longPress(find.byKey(const ValueKey('launcher-note-$grocery')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('list-name')), 'Shops');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-list')));
    await settle(tester);

    expect(store.current.definition(grocery)!.name, 'Shops');
    expect(find.text('Shops'), findsWidgets);
  });

  testWidgets('Settings sets how often the AI asks first (Q-43)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(const {});
    final FirestoreListStore store = await widgetTestStore(tester);
    await tester.pumpWidget(
      await testApp(
        auth: FakeAuthService(user: testUser),
        openStore: (_) => store,
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('settings')));
    await tester.pumpAndSettle();
    final Finder hint = find.byKey(const ValueKey('settings-ai-ask-hint'));
    await tester.ensureVisible(find.text('How often the AI checks with you'));
    await tester.pumpAndSettle();
    expect(find.text('How often the AI checks with you'), findsOneWidget);
    expect(
      tester.widget<Text>(hint).data,
      startsWith('Does clear requests right away'),
    );
    // The right end of the slider: Just do it.
    final Finder slider = find.byKey(const ValueKey('settings-ai-ask-slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final Rect rect = tester.getRect(slider);
    await tester.tapAt(Offset(rect.right - 12, rect.center.dy));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(hint).data, startsWith('Goes with its best guess'));
    expect(
      tester
          .element(find.byKey(const ValueKey('settings-ai-ask')))
          .read<AccountPreferencesCubit>()
          .state
          .aiAskLevel,
      AiAskLevel.less,
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

  testWidgets('the hub floats over a list; a list opened from a list replaces it, and back goes home', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, FakeAuthService(user: testUser));
    Finder host(String id) => find.byWidgetPredicate(
      (widget) => widget is GenericListHost && widget.listId == id,
    );
    Future<void> pick(String id) async {
      await tester.tap(_hub);
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('launcher-note-$id')));
      await settle(tester);
    }

    await pick(BuiltinTemplates.groceryId);
    expect(host(BuiltinTemplates.groceryId), findsOneWidget);
    expect(_hub, findsOneWidget);
    // The list's add button sits just above the hub, clear of it.
    final Rect add = tester.getRect(find.byType(FloatingActionButton));
    final Rect hub = tester.getRect(_hub);
    expect(add.bottom, lessThan(hub.top - 8));
    expect(add.center.dx, closeTo(hub.center.dx, 12));

    await pick(BuiltinTemplates.journalId);
    expect(host(BuiltinTemplates.journalId), findsOneWidget);
    expect(host(BuiltinTemplates.groceryId), findsNothing);

    // Inside a list the fan starts with Home; it goes back to the home.
    await tester.tap(_hub);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('launcher-home')));
    await settle(tester);
    expect(host(BuiltinTemplates.journalId), findsNothing);
    expect(find.byKey(const ValueKey('settings')), findsOneWidget);
    await tester.tap(_hub);
    await tester.pump();
    expect(find.byKey(const ValueKey('launcher-home')), findsNothing);
    await tester.tap(_hub);
    await tester.pump();
    await pick(BuiltinTemplates.journalId);

    // Android back: from list B to the home, not to list A.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(host(BuiltinTemplates.journalId), findsNothing);
    expect(host(BuiltinTemplates.groceryId), findsNothing);
    expect(find.byKey(const ValueKey('settings')), findsOneWidget);
    expect(_hub, findsOneWidget);
  });

  testWidgets('a list page has Edit list at the top right', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, FakeAuthService(user: testUser));
    await tester.tap(_hub);
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey('launcher-note-${BuiltinTemplates.groceryId}')),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('edit-list')));
    await settle(tester);
    expect(find.byType(ListEditorScreen), findsOneWidget);
  });

  group('Suggest on home with other list changes (Codex review M3)', () {
    Future<void> editGrocery(WidgetTester tester) async {
      await tester.tap(_hub);
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('launcher-note-${BuiltinTemplates.groceryId}')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('edit-list')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('list-name')),
        'Shopping',
      );
      final Finder suggest = find.byKey(const ValueKey('suggest-on-home'));
      await tester.ensureVisible(suggest);
      await settle(tester);
      await tester.tap(suggest);
      await settle(tester);
    }

    List<String> removed(WidgetTester tester) => tester
        .element(find.byType(Scaffold).first)
        .read<AccountPreferencesCubit>()
        .state
        .homeRemoved;

    testWidgets('is saved once the list change is saved', (tester) async {
      final FirestoreListStore store =
          await _pumpApp(tester, FakeAuthService(user: testUser));
      await editGrocery(tester);
      // Not before the save.
      expect(removed(tester), isNot(contains(BuiltinTemplates.groceryId)));
      await tester.tap(find.byKey(const ValueKey('save-list')));
      await settle(tester);
      expect(
        store.current.definition(BuiltinTemplates.groceryId)!.name,
        'Shopping',
      );
      expect(removed(tester), contains(BuiltinTemplates.groceryId));
    });

    testWidgets('is not saved when the list change fails', (tester) async {
      final FirestoreListStore store =
          await _pumpApp(tester, FakeAuthService(user: testUser));
      await editGrocery(tester);
      // The list goes on another phone while the editor is open.
      await tester.runAsync(() => store.deleteList(BuiltinTemplates.groceryId));
      await tester.tap(find.byKey(const ValueKey('save-list')));
      await settle(tester);
      expect(removed(tester), isNot(contains(BuiltinTemplates.groceryId)));
      expect(
        find.text('A list change could not be saved and was undone.'),
        findsOneWidget,
      );
    });
  });

  for (final Size screen in const [Size(360, 780), Size(412, 915)]) {
    testWidgets('scrolled to the end, a list\'s last row clears the add button '
        '(${screen.width.toInt()} dp, T-24 unit 7 D1)', (
      WidgetTester tester,
    ) async {
      final FirestoreListStore store =
          await _pumpApp(tester, FakeAuthService(user: testUser));
      tester.view.physicalSize = screen * 3;
      tester.view.devicePixelRatio = 3;
      final DateTime at = DateTime.utc(2026, 3, 1);
      await tester.runAsync(
        () => store.apply(
          ListChanges(
            saved: [
              for (int n = 0; n < 30; n++)
                ListItem(
                  id: 'row$n',
                  listId: BuiltinTemplates.groceryId,
                  values: {'title': 'Row $n', 'section': 'nextTime'},
                  createdAt: at,
                  updatedAt: at,
                ),
            ],
          ),
        ),
      );
      await settle(tester);
      await tester.tap(_hub);
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('launcher-note-${BuiltinTemplates.groceryId}')),
      );
      await settle(tester);

      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await settle(tester);
      final double lowest = [
        for (final Element row in find.textContaining('Row ', findRichText: true).evaluate())
          tester.getRect(find.byElementPredicate((e) => e == row)).bottom,
      ].reduce((a, b) => a > b ? a : b);
      final Rect add = tester.getRect(find.byType(FloatingActionButton));
      // The row's own height below its text, × included, fits too.
      expect(lowest + 24, lessThanOrEqualTo(add.top));
    });
  }

  // The add button's own size animation (under the hub) and whether any
  // turn is applied around it.
  Animation<double> addScale(WidgetTester tester) => tester
      .widget<ScaleTransition>(find.byKey(const ValueKey('add-button-scale')))
      .scale;
  bool addTurns(WidgetTester tester) => tester
      .widgetList<RotationTransition>(
        find.ancestor(
          of: find.byType(FloatingActionButton),
          matching: find.byType(RotationTransition),
        ),
      )
      .any((transition) => transition.turns.value % 1 != 0);

  testWidgets('the add button of a list grows in once the page has arrived and shrinks as it leaves', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, FakeAuthService(user: testUser));
    await tester.tap(_hub);
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey('launcher-note-${BuiltinTemplates.groceryId}')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Mid-transition: the page is coming in, the button is not there yet.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is GenericListHost &&
            widget.listId == BuiltinTemplates.groceryId,
      ),
      findsOneWidget,
    );
    expect(addScale(tester).value, 0);
    await settle(tester);
    expect(addScale(tester).value, 1);
    expect(addTurns(tester), isFalse);

    // Leaving for the home: the button shrinks away (size only) while the
    // page goes.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 50));
    expect(addScale(tester).status, AnimationStatus.reverse);
    expect(addScale(tester).value, lessThan(1));
    expect(addTurns(tester), isFalse);
    await settle(tester);
  });

  testWidgets('with reduced motion the add button is there at once', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpApp(tester, FakeAuthService(user: testUser));
    await tester.tap(_hub);
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey('launcher-note-${BuiltinTemplates.groceryId}')),
    );
    await tester.pump();
    await tester.pump();
    expect(addScale(tester).value, 1);
    await settle(tester);
  });

  testWidgets('a sheet on the home or a list hides the hub until it closes', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, FakeAuthService(user: testUser));

    await _openSettings(tester);
    expect(_hub, findsNothing);
    // Halfway through the sheet sliding away the hub is still hidden; it
    // comes back once the sheet has gone.
    Navigator.of(
      tester.element(find.byKey(const ValueKey('settings-account'))),
    ).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('settings-account')), findsOneWidget);
    expect(_hub, findsNothing);
    await tester.pumpAndSettle();
    expect(_hub, findsOneWidget);
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
    // Reaching Move picked the hub up; it follows the same drag.
    final Offset grab = tester.getCenter(_hub) - prompt;
    await gesture.moveTo(const Offset(120, 200) - grab);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getCenter(_hub).dx, closeTo(120, 1));
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    expect(preferences.getDouble(AppSettingsCubit.hubXKey), isNotNull);
  });
}

// A server that refuses every transaction, as the rules would.
// Lets the first transaction after [arm] through, and fails the rest.
class _FailingAfterOne extends FakeFirebaseFirestore {
  int? left;

  void arm() => left = 1;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    final int? remaining = left;
    if (remaining != null) {
      if (remaining == 0) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'aborted');
      }
      left = remaining - 1;
    }
    return super.runTransaction(
      transactionHandler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

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
