import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/account_preferences.dart';

const String _uid = 'user-a';

// The account's document as a test scripts it.
class _FakeSync implements AccountPreferencesSync {
  final StreamController<AccountPreferencesSnapshot> snapshots =
      StreamController<AccountPreferencesSnapshot>.broadcast();
  final List<Map<String, Object?>> seeds = [];
  final List<Map<String, Object?>> writes = [];
  int watches = 0;
  Object? seedError;
  Object? writeError;
  // Set: the next write stays open until the test answers it, as offline.
  Completer<void>? heldWrite;

  @override
  Stream<AccountPreferencesSnapshot> watch() {
    watches++;
    return snapshots.stream;
  }

  @override
  Future<void> seed(Map<String, Object?> values) async {
    if (seedError != null) {
      throw seedError!;
    }
    seeds.add(values);
  }

  @override
  Future<void> write(Map<String, Object?> changes) async {
    final Completer<void>? held = heldWrite;
    if (held != null) {
      await held.future;
      return;
    }
    if (writeError != null) {
      throw writeError!;
    }
    writes.add(changes);
  }

  // Lets the cubit's listener and the writes it starts run.
  Future<void> send(
    Map<String, Object?>? data, {
    bool fromCache = false,
  }) async {
    snapshots.add((data: data, fromCache: fromCache));
    await pumpEventQueue();
  }
}

Future<(AccountPreferencesCubit, _FakeSync)> _cubit([
  Map<String, Object> stored = const {},
]) async {
  SharedPreferences.setMockInitialValues(stored);
  final _FakeSync sync = _FakeSync();
  addTearDown(sync.snapshots.close);
  final AccountPreferencesCubit cubit = AccountPreferencesCubit(
    await SharedPreferences.getInstance(),
    _uid,
    sync: sync,
  );
  addTearDown(cubit.close);
  return (cubit, sync);
}

void main() {
  group('AccountPreferences', () {
    test('defaults are today\'s behaviour', () {
      const AccountPreferences preferences = AccountPreferences();
      expect(AccountPreferences.fromJson(const {}), preferences);
      expect(preferences.listOrder, ListOrder.lastUsed);
      expect(preferences.myListOrder, isEmpty);
      expect(preferences.startScreen, StartScreen.home);
      expect(preferences.tickedItems, TickedItems.moveToDone);
      expect(preferences.confirmDelete, isFalse);
      expect(preferences.showAiBar, isTrue);
      expect(preferences.aiAutoApply, isFalse);
      expect(preferences.aiAskLevel, AiAskLevel.balanced);
      expect(preferences.aiAutoApplyOffered, isFalse);
      expect(preferences.aiNoticeSeen, isNull);
      expect(preferences.vibration, isTrue);
      expect(preferences.timeFormat, TimeFormat.followLanguage);
      expect(preferences.weekStart, WeekStart.followLanguage);
    });

    test('every value survives the round trip', () {
      const AccountPreferences preferences = AccountPreferences(
        listOrder: ListOrder.alphabetical,
        myListOrder: ['b', 'a'],
        startScreen: StartScreen.lastOpenList,
        tickedItems: TickedItems.hide,
        confirmDelete: true,
        showAiBar: false,
        aiAutoApply: true,
        aiAskLevel: AiAskLevel.less,
        aiAutoApplyOffered: true,
        aiNoticeSeen: 'notice-1',
        vibration: false,
        timeFormat: TimeFormat.h24,
        weekStart: WeekStart.sunday,
      );
      final Object? stored = jsonDecode(jsonEncode(preferences.toJson()));
      expect(
        AccountPreferences.fromJson(stored! as Map<String, Object?>),
        preferences,
      );
    });

    test('bad and unknown values get the default', () {
      final AccountPreferences preferences = AccountPreferences.fromJson(const {
        'listOrder': 'byColour',
        'myListOrder': ['a', 7, null, 'b'],
        'startScreen': 3,
        'tickedItems': null,
        'confirmDelete': 'yes',
        'showAiBar': 0,
        'aiAskLevel': 'never',
        'aiNoticeSeen': 12,
        'vibration': 'off',
        'timeFormat': true,
        'weekStart': 'tuesday',
        'fromANewerBuild': {'x': 1},
      });
      expect(preferences, const AccountPreferences(myListOrder: ['a', 'b']));
    });

    test('a list that is not a list gives no order', () {
      expect(
        AccountPreferences.fromJson(const {'myListOrder': 'a,b'}).myListOrder,
        isEmpty,
      );
    });
  });

  group('first frame', () {
    test('the copy from last time is there at once', () async {
      final (AccountPreferencesCubit cubit, _) = await _cubit({
        AccountPreferencesCubit.mirrorKey(_uid): jsonEncode({
          'vibration': false,
          'weekStart': 'monday',
        }),
      });
      expect(cubit.state.vibration, isFalse);
      expect(cubit.state.weekStart, WeekStart.monday);
    });

    test('a damaged copy gives the defaults', () async {
      final (AccountPreferencesCubit cubit, _) = await _cubit({
        AccountPreferencesCubit.mirrorKey(_uid): '{not json',
      });
      expect(cubit.state, const AccountPreferences());
    });

    test('another user\'s copy is not used', () async {
      final (AccountPreferencesCubit cubit, _) = await _cubit({
        AccountPreferencesCubit.mirrorKey('user-b'): jsonEncode({
          'vibration': false,
        }),
      });
      expect(cubit.state.vibration, isTrue);
    });

    test('before the first sign-in, the AI settings the phone kept', () async {
      final (AccountPreferencesCubit cubit, _) = await _cubit({
        AccountPreferencesCubit.legacyAutoApplyKey: true,
        AccountPreferencesCubit.legacyAskLevelKey: 'more',
        AccountPreferencesCubit.legacyAutoApplyOfferedKey: true,
        AccountPreferencesCubit.legacyNoticeSeenKey: 'notice-1',
      });
      expect(cubit.state.aiAutoApply, isTrue);
      expect(cubit.state.aiAskLevel, AiAskLevel.more);
      expect(cubit.state.aiAutoApplyOffered, isTrue);
      expect(cubit.state.aiNoticeSeen, 'notice-1');
    });
  });

  group('first sign-in on a phone (Q-48 A)', () {
    test('the account\'s values win over what the phone had', () async {
      final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit({
        AccountPreferencesCubit.legacyAutoApplyKey: true,
        AccountPreferencesCubit.legacyAskLevelKey: 'more',
      });

      await sync.send({'aiAskLevel': 'less', 'vibration': false});

      expect(cubit.state.aiAskLevel, AiAskLevel.less);
      expect(cubit.state.vibration, isFalse);
      // The account has no auto-apply stored, so it is the default, not this
      // phone's.
      expect(cubit.state.aiAutoApply, isFalse);
      expect(sync.seeds, isEmpty);
      expect(sync.writes, isEmpty);
    });

    test('the phone\'s old keys go once the account was seen', () async {
      final (_, _FakeSync sync) = await _cubit({
        AccountPreferencesCubit.legacyAutoApplyKey: true,
        AccountPreferencesCubit.legacyAskLevelKey: 'more',
        AccountPreferencesCubit.legacyAutoApplyOfferedKey: true,
        AccountPreferencesCubit.legacyNoticeSeenKey: 'notice-1',
      });

      await sync.send(const {});

      final SharedPreferences stored = await SharedPreferences.getInstance();
      expect(
        stored.containsKey(AccountPreferencesCubit.legacyAutoApplyKey),
        isFalse,
      );
      expect(
        stored.containsKey(AccountPreferencesCubit.legacyAskLevelKey),
        isFalse,
      );
      expect(
        stored.containsKey(AccountPreferencesCubit.legacyAutoApplyOfferedKey),
        isFalse,
      );
      expect(
        stored.containsKey(AccountPreferencesCubit.legacyNoticeSeenKey),
        isFalse,
      );
    });

    test('an account with none is seeded once from the phone', () async {
      final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit({
        AccountPreferencesCubit.legacyAutoApplyKey: true,
        AccountPreferencesCubit.legacyAskLevelKey: 'less',
      });

      await sync.send(null);

      expect(sync.seeds, hasLength(1));
      final AccountPreferences seeded = AccountPreferences.fromJson(
        sync.seeds.single,
      );
      expect(seeded.aiAutoApply, isTrue);
      expect(seeded.aiAskLevel, AiAskLevel.less);
      expect(seeded, cubit.state);

      // The server's answer arrives; it changes nothing and seeds no more.
      await sync.send(sync.seeds.single);
      await sync.send(sync.seeds.single);
      expect(sync.seeds, hasLength(1));
      expect(cubit.state, seeded);
    });

    test('offline an empty cache does not seed: the server decides', () async {
      final (_, _FakeSync sync) = await _cubit();

      await sync.send(null, fromCache: true);

      expect(sync.seeds, isEmpty);
    });

    test('seeding that fails leaves the phone working', () async {
      final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit();
      sync.seedError = StateError('offline');

      await sync.send(null);
      expect(sync.seeds, isEmpty);
      await cubit.setVibration(false);
      expect(cubit.state.vibration, isFalse);

      // The next word from the server tries again.
      sync.seedError = null;
      await sync.send(null);
      expect(AccountPreferences.fromJson(sync.seeds.single).vibration, isFalse);
    });

    test('a listener error (no rules yet) leaves the phone working', () async {
      final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit();

      sync.snapshots.addError(StateError('permission-denied'));
      await pumpEventQueue();
      await cubit.setTimeFormat(TimeFormat.h12);

      expect(cubit.state.timeFormat, TimeFormat.h12);
    });
  });

  group('changes before the phone has seen the account', () {
    test('wait, and go on top of the account\'s values', () async {
      final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit();

      await sync.send(null, fromCache: true);
      await cubit.setVibration(false);
      expect(cubit.state.vibration, isFalse);
      expect(sync.writes, isEmpty);

      await sync.send({'aiAskLevel': 'less', 'vibration': true});

      expect(cubit.state.aiAskLevel, AiAskLevel.less);
      expect(cubit.state.vibration, isFalse);
      expect(sync.writes, [
        {'vibration': false},
      ]);
      expect(sync.seeds, isEmpty);
    });

    test('are part of the seeding when the account has none', () async {
      final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit();

      await cubit.setWeekStart(WeekStart.sunday);
      await sync.send(null);

      expect(sync.writes, isEmpty);
      expect(
        AccountPreferences.fromJson(sync.seeds.single).weekStart,
        WeekStart.sunday,
      );
      expect(cubit.state.weekStart, WeekStart.sunday);
    });

    test('survive a restart', () async {
      final (AccountPreferencesCubit cubit, _) = await _cubit();
      await cubit.setConfirmDelete(true);

      final _FakeSync sync = _FakeSync();
      addTearDown(sync.snapshots.close);
      final AccountPreferencesCubit restarted = AccountPreferencesCubit(
        await SharedPreferences.getInstance(),
        _uid,
        sync: sync,
      );
      addTearDown(restarted.close);
      expect(restarted.state.confirmDelete, isTrue);

      await sync.send({'confirmDelete': false, 'vibration': false});
      expect(restarted.state.confirmDelete, isTrue);
      expect(restarted.state.vibration, isFalse);
      expect(sync.writes, [
        {'confirmDelete': true},
      ]);
    });
  });

  group('changes on a phone that knows the account', () {
    Future<(AccountPreferencesCubit, _FakeSync)> known() async {
      final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit();
      await sync.send(const {});
      return (cubit, sync);
    }

    test('each setter shows at once and stores only its own key', () async {
      final (AccountPreferencesCubit cubit, _FakeSync sync) = await known();

      await cubit.setListOrder(ListOrder.myOrder);
      await cubit.setMyListOrder(['b', 'a']);
      await cubit.setStartScreen(StartScreen.lastOpenList);
      await cubit.setTickedItems(TickedItems.stayInPlace);
      await cubit.setConfirmDelete(true);
      await cubit.setShowAiBar(false);
      await cubit.setAiAutoApply(true);
      await cubit.setAiAskLevel(AiAskLevel.more);
      await cubit.setAiAutoApplyOffered();
      await cubit.setAiNoticeSeen('notice-2');
      await cubit.setVibration(false);
      await cubit.setTimeFormat(TimeFormat.h24);
      await cubit.setWeekStart(WeekStart.monday);
      await pumpEventQueue();

      expect(
        cubit.state,
        const AccountPreferences(
          listOrder: ListOrder.myOrder,
          myListOrder: ['b', 'a'],
          startScreen: StartScreen.lastOpenList,
          tickedItems: TickedItems.stayInPlace,
          confirmDelete: true,
          showAiBar: false,
          aiAutoApply: true,
          aiAskLevel: AiAskLevel.more,
          aiAutoApplyOffered: true,
          aiNoticeSeen: 'notice-2',
          vibration: false,
          timeFormat: TimeFormat.h24,
          weekStart: WeekStart.monday,
        ),
      );
      expect(sync.writes, [
        {'listOrder': 'myOrder'},
        {
          'myListOrder': ['b', 'a'],
        },
        {'startScreen': 'lastOpenList'},
        {'tickedItems': 'stayInPlace'},
        {'confirmDelete': true},
        {'showAiBar': false},
        {'aiAutoApply': true},
        {'aiAskLevel': 'more'},
        {'aiAutoApplyOffered': true},
        {'aiNoticeSeen': 'notice-2'},
        {'vibration': false},
        {'timeFormat': 'h24'},
        {'weekStart': 'monday'},
      ]);
    });

    test(
      'a change from another phone arrives and is kept for next time',
      () async {
        final (AccountPreferencesCubit cubit, _FakeSync sync) = await known();

        await sync.send({'showAiBar': false});
        expect(cubit.state.showAiBar, isFalse);

        final AccountPreferencesCubit restarted = AccountPreferencesCubit(
          await SharedPreferences.getInstance(),
          _uid,
        );
        addTearDown(restarted.close);
        expect(restarted.state.showAiBar, isFalse);
      },
    );

    test('a change is in the copy without waiting for the server', () async {
      final (AccountPreferencesCubit cubit, _FakeSync sync) = await known();

      // Offline a write stays open; the setter does not wait for it.
      await cubit.setVibration(false);
      expect(sync.writes, hasLength(1));

      final AccountPreferencesCubit restarted = AccountPreferencesCubit(
        await SharedPreferences.getInstance(),
        _uid,
      );
      addTearDown(restarted.close);
      expect(restarted.state.vibration, isFalse);
    });

    group('a write the server refuses (Codex H1)', () {
      Future<(AccountPreferencesCubit, _FakeSync, List<void>)> refused() async {
        final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit();
        await sync.send({'aiAutoApply': true, 'vibration': true});
        final List<void> failures = [];
        final StreamSubscription<void> watching = cubit.saveFailures.listen(
          failures.add,
        );
        addTearDown(watching.cancel);
        sync.writeError = StateError('permission-denied');
        await cubit.setAiAutoApply(false);
        await pumpEventQueue();
        return (cubit, sync, failures);
      }

      test('auto-apply stays off when the server takes it back', () async {
        final (AccountPreferencesCubit cubit, _FakeSync sync, _) =
            await refused();

        // Firestore takes a refused change back through the listener.
        await sync.send({'aiAutoApply': true, 'vibration': true});

        expect(cubit.state.aiAutoApply, isFalse);
      });

      test('it also holds when the taking back comes first', () async {
        final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit();
        await sync.send({'aiAutoApply': true});
        final Completer<void> answer = Completer<void>();
        sync.heldWrite = answer;

        await cubit.setAiAutoApply(false);
        await sync.send({'aiAutoApply': true});
        expect(cubit.state.aiAutoApply, isFalse);

        answer.completeError(StateError('permission-denied'));
        await pumpEventQueue();
        expect(cubit.state.aiAutoApply, isFalse);
      });

      test('it says so, once for each refusal', () async {
        final (_, _, List<void> failures) = await refused();
        expect(failures, hasLength(1));
      });

      test('it survives a restart and is tried again, its key only', () async {
        final (_, _FakeSync sync, _) = await refused();
        await sync.send({'aiAutoApply': true, 'vibration': true});
        expect(sync.writes, isEmpty);

        final _FakeSync next = _FakeSync();
        addTearDown(next.snapshots.close);
        final AccountPreferencesCubit restarted = AccountPreferencesCubit(
          await SharedPreferences.getInstance(),
          _uid,
          sync: next,
        );
        addTearDown(restarted.close);
        expect(restarted.state.aiAutoApply, isFalse);
        await pumpEventQueue();
        expect(next.writes, [
          {'aiAutoApply': false},
        ]);

        // The server has it now: nothing is left to send.
        await next.send({'aiAutoApply': false});
        final _FakeSync third = _FakeSync();
        addTearDown(third.snapshots.close);
        final AccountPreferencesCubit again = AccountPreferencesCubit(
          await SharedPreferences.getInstance(),
          _uid,
          sync: third,
        );
        addTearDown(again.close);
        await pumpEventQueue();
        expect(third.writes, isEmpty);
      });

      test('other values from the account still arrive', () async {
        final (AccountPreferencesCubit cubit, _FakeSync sync, _) =
            await refused();

        await sync.send({'aiAutoApply': true, 'vibration': false});

        expect(cubit.state.aiAutoApply, isFalse);
        expect(cubit.state.vibration, isFalse);
      });

      test('a newer choice replaces it, and an old refusal is quiet', () async {
        final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit();
        await sync.send(const {});
        final List<void> failures = [];
        final StreamSubscription<void> watching = cubit.saveFailures.listen(
          failures.add,
        );
        addTearDown(watching.cancel);
        final Completer<void> first = Completer<void>();
        sync.heldWrite = first;
        await cubit.setVibration(false);
        sync.heldWrite = null;
        await cubit.setVibration(true);

        first.completeError(StateError('permission-denied'));
        await pumpEventQueue();

        expect(failures, isEmpty);
        expect(cubit.state.vibration, isTrue);
      });

      test('offline: no message, and the change just waits', () async {
        final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit();
        await sync.send(const {});
        final List<void> failures = [];
        final StreamSubscription<void> watching = cubit.saveFailures.listen(
          failures.add,
        );
        addTearDown(watching.cancel);
        // Offline a write stays open until the server can answer.
        final Completer<void> answer = Completer<void>();
        sync.heldWrite = answer;

        await cubit.setVibration(false);
        await sync.send(const {'vibration': false}, fromCache: true);
        await pumpEventQueue();
        expect(failures, isEmpty);
        expect(cubit.state.vibration, isFalse);

        answer.complete();
        await pumpEventQueue();
        expect(failures, isEmpty);
        final SharedPreferences stored = await SharedPreferences.getInstance();
        expect(
          stored.containsKey(AccountPreferencesCubit.pendingKey(_uid)),
          isFalse,
        );
      });

      test('an answer after sign-out leaves nothing behind', () async {
        final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit();
        await sync.send(const {});
        final Completer<void> answer = Completer<void>();
        sync.heldWrite = answer;
        await cubit.setVibration(false);

        await cubit.close();
        final SharedPreferences stored = await SharedPreferences.getInstance();
        await AccountPreferencesCubit.forget(stored, _uid);
        answer.completeError(StateError('permission-denied'));
        await pumpEventQueue();

        expect(
          stored.containsKey(AccountPreferencesCubit.pendingKey(_uid)),
          isFalse,
        );
      });
    });
  });

  group('a listener that ends with an error (Codex M4)', () {
    // Each retry comes after a turn of the event loop, so tests need no clock.
    Future<(AccountPreferencesCubit, _FakeSync)> listening({
      List<Duration> delays = const [
        Duration.zero,
        Duration.zero,
        Duration.zero,
      ],
    }) async {
      SharedPreferences.setMockInitialValues(const {});
      final _FakeSync sync = _FakeSync();
      addTearDown(sync.snapshots.close);
      final AccountPreferencesCubit cubit = AccountPreferencesCubit(
        await SharedPreferences.getInstance(),
        _uid,
        sync: sync,
        relistenDelays: delays,
      );
      addTearDown(cubit.close);
      await sync.send(const {});
      return (cubit, sync);
    }

    Future<void> fail(_FakeSync sync) async {
      sync.snapshots.addError(StateError('permission-denied'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await pumpEventQueue();
    }

    test('it listens again, and changes from another phone arrive', () async {
      final (AccountPreferencesCubit cubit, _FakeSync sync) = await listening();

      await fail(sync);
      expect(sync.watches, 2);

      await sync.send({'vibration': false});
      expect(cubit.state.vibration, isFalse);
    });

    test('it stops after the last retry', () async {
      final (_, _FakeSync sync) = await listening();

      for (int i = 0; i < 6; i++) {
        await fail(sync);
      }

      expect(sync.watches, 4);
    });

    test('a copy from the cache does not start the retries over', () async {
      final (_, _FakeSync sync) = await listening();

      for (int i = 0; i < 6; i++) {
        await sync.send(const {}, fromCache: true);
        await fail(sync);
      }

      expect(sync.watches, 4);
    });

    test('a word from the server starts them over', () async {
      final (_, _FakeSync sync) = await listening();

      for (int i = 0; i < 6; i++) {
        await sync.send(const {});
        await fail(sync);
      }

      expect(sync.watches, 7);
    });

    test('closing, as at sign-out, cancels a retry on its way', () async {
      final (AccountPreferencesCubit cubit, _FakeSync sync) = await listening(
        delays: const [Duration(milliseconds: 5)],
      );

      sync.snapshots.addError(StateError('permission-denied'));
      await pumpEventQueue();
      await cubit.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(sync.watches, 1);
    });

    test('a refused change is kept, and sent again once it listens', () async {
      final (AccountPreferencesCubit cubit, _FakeSync sync) = await listening();
      final List<void> failures = [];
      final StreamSubscription<void> watching = cubit.saveFailures.listen(
        failures.add,
      );
      addTearDown(watching.cancel);
      sync.writeError = StateError('permission-denied');
      await cubit.setVibration(false);
      await pumpEventQueue();
      expect(failures, hasLength(1));

      await fail(sync);
      // The rules are right again.
      sync.writeError = null;
      await sync.send({'vibration': true});

      expect(cubit.state.vibration, isFalse);
      expect(sync.writes, [
        {'vibration': false},
      ]);

      // Only once: the server's next words send nothing more.
      await sync.send({'vibration': false});
      expect(sync.writes, hasLength(1));
    });

    test('nothing is shown for it', () async {
      final (AccountPreferencesCubit cubit, _FakeSync sync) = await listening();
      final List<void> failures = [];
      final StreamSubscription<void> watching = cubit.saveFailures.listen(
        failures.add,
      );
      addTearDown(watching.cancel);

      await fail(sync);

      expect(failures, isEmpty);
    });
  });

  test('without a sync, changes stay on the phone', () async {
    SharedPreferences.setMockInitialValues(const {});
    final AccountPreferencesCubit cubit = AccountPreferencesCubit(
      await SharedPreferences.getInstance(),
      _uid,
    );
    addTearDown(cubit.close);

    await cubit.setShowAiBar(false);

    final AccountPreferencesCubit restarted = AccountPreferencesCubit(
      await SharedPreferences.getInstance(),
      _uid,
    );
    addTearDown(restarted.close);
    expect(restarted.state.showAiBar, isFalse);
  });

  test('forget removes this user\'s copy and waiting changes only', () async {
    final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit({
      AccountPreferencesCubit.mirrorKey('user-b'): '{}',
    });
    await sync.send(const {});
    await cubit.setVibration(false);
    final SharedPreferences stored = await SharedPreferences.getInstance();
    expect(stored.containsKey(AccountPreferencesCubit.mirrorKey(_uid)), isTrue);

    await AccountPreferencesCubit.forget(stored, _uid);

    expect(
      stored.containsKey(AccountPreferencesCubit.mirrorKey(_uid)),
      isFalse,
    );
    expect(
      stored.containsKey(AccountPreferencesCubit.pendingKey(_uid)),
      isFalse,
    );
    expect(
      stored.containsKey(AccountPreferencesCubit.mirrorKey('user-b')),
      isTrue,
    );
  });

  test('a change after close is ignored', () async {
    final (AccountPreferencesCubit cubit, _FakeSync sync) = await _cubit();
    await sync.send(const {});
    await cubit.close();

    await cubit.setVibration(false);

    expect(sync.writes, isEmpty);
  });
}
