import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_note/ai/ai_bar_controller.dart';
import 'package:hybrid_note/ai/ai_match.dart';
import 'package:hybrid_note/ai/ai_service.dart';
import 'package:hybrid_note/app/app_settings.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/l10n/generated/app_localizations_en.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_error.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_labels.dart';
import 'package:hybrid_note/lists/list_patch.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/firestore_store.dart';

// What can happen between an AI answer, its Apply and its Undo (the Codex
// review of the T-19 branch, H1-H6, M1-M6 and L2), on the real controller over
// FirestoreListStore with a scripted AI.

const String _g = BuiltinTemplates.groceryId;
const String _t = BuiltinTemplates.tasksId;
final DateTime _now = DateTime.utc(2026, 11, 4);

ListItem _item(String id, String title, {String list = _g, bool done = false}) {
  return ListItem(
    id: id,
    listId: list,
    values: {'title': title, 'done': done},
    createdAt: _now,
    updatedAt: _now,
  );
}

AiToolCall _edit(String id, String field, Object value, {String list = _g}) {
  return AiToolCall('upsert_items', {
    'listId': list,
    'items': [
      {
        'id': id,
        'values': [
          {'field': field, 'value': value},
        ],
      },
    ],
  });
}

AiToolCall _patch(Map<String, Object> op, {String list = _g}) {
  return AiToolCall('patch_list', {
    'listId': list,
    'ops': [op],
  });
}

const AiToolCall _createBooks = AiToolCall('create_list', {
  'list': {
    'name': 'Books',
    'icon': 'book',
    'color': '#123456',
    'fields': [
      {'key': 'title', 'type': 'text', 'label': 'Title', 'primary': true},
    ],
    'view': {'kind': 'cards'},
  },
});

AiAnswer _answer(List<AiToolCall> calls) {
  return AiAnswer(requestId: 'r', toolCalls: calls);
}

class _Script implements AiService {
  _Script(this.callback);

  final Future<AiAnswer> Function(AiRequest request, int round) callback;
  final List<AiRequest> requests = [];

  @override
  Future<AiAnswer> send(AiRequest request) {
    requests.add(request);
    return callback(request, requests.length);
  }
}

// Runs "another device's" write just before the next transaction, or fails
// transactions like a device without a connection.
class _Racing extends FakeFirebaseFirestore {
  Future<void> Function()? beforeTransaction;
  bool offline = false;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    if (offline) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    final Future<void> Function()? hook = beforeTransaction;
    beforeTransaction = null;
    await hook?.call();
    return super.runTransaction(
      handler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 25));

Future<AiBarController> _bar(
  FirestoreListStore store,
  AiService service, {
  bool autoApply = false,
  void Function(String listId)? onOpen,
  int? maxListFetches,
}) async {
  SharedPreferences.setMockInitialValues({
    AiBarController.noticeKey: aiNoticeId,
    AiBarController.autoApplyAskedKey: true,
    AppSettingsCubit.aiAutoApplyKey: autoApply,
  });
  final AiBarController controller = AiBarController(
    service: service,
    store: store,
    preferences: await SharedPreferences.getInstance(),
    onOpenList: onOpen ?? (_) {},
    maxListFetches: maxListFetches,
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _send(AiBarController bar, String text, {String? open = _g}) async {
  bar.text.text = text;
  await bar.submit(
    locale: 'en',
    labels: ListLabels(AppLocalizationsEn()),
    openListId: open,
  );
  await _tick();
}

Future<void> _aiOff(FirestoreListStore store, String listId) async {
  await store.patchList(listId, const [
    ListPatchOp(PatchOpKind.setListInfo, {'aiAllowed': false}),
  ]);
  await _tick();
}

ListItem _only(FirestoreListStore store) => store.current.itemsOf(_g).single;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AI turned off while a request is under way (H1)', () {
    test('no second round goes out for that list', () async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [_item('a', 'PRIVATE MILK')],
      );
      final _Script ai = _Script((_, _) async {
        await _aiOff(store, _g);
        return _answer([_edit('a', 'title', 'Oat milk')]);
      });
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'rename this item');
      expect(ai.requests, hasLength(1));
      expect(bar.phase, AiBarPhase.problem);
      expect(bar.problem!.listOff, isNotNull);
      expect(_only(store)['title'], 'PRIVATE MILK');
    });

    test('a later round leaves out a list turned off since the first', () async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [_item('b', 'Brown bread'), _item('w', 'White bread')],
      );
      final _Script ai = _Script((_, round) async {
        if (round == 1) {
          await _aiOff(store, _t);
          return _answer([
            const AiToolCall('delete_items', {
              'listId': _g,
              'match': ['bread'],
            }),
          ]);
        }
        return _answer([
          const AiToolCall('reply', {'text': 'Which one?'}),
        ]);
      });
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'remove bread', open: null);
      expect(ai.requests.first.lists.map((list) => list.id), contains(_t));
      expect(ai.requests.last.lists.map((list) => list.id), isNot(contains(_t)));
    });

    test('a choice after the list turned off sends nothing', () async {
      final FirestoreListStore store = await fakeFirestoreStore();
      final _Script ai = _Script((_, _) async {
        return _answer([
          const AiToolCall('choose_list', {
            'question': 'Which?',
            'candidates': [_g, _t],
          }),
        ]);
      });
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'bread', open: null);
      expect(bar.phase, AiBarPhase.question);
      await _aiOff(store, _g);
      await bar.choose(_g);
      expect(ai.requests, hasLength(1));
    });
  });

  group('Apply (H2, H3; Q-51)', () {
    Future<(FirestoreListStore, AiBarController)> previewed(
      List<AiToolCall> calls, {
      FakeFirebaseFirestore? firestore,
      List<ListItem>? items,
    }) async {
      final FirestoreListStore store = await fakeFirestoreStore(
        firestore: firestore,
        items: items ?? [_item('a', 'Milk')],
      );
      final AiBarController bar = await _bar(
        store,
        _Script((_, _) async => _answer(calls)),
      );
      await _send(bar, 'rename milk');
      expect(bar.phase, AiBarPhase.preview);
      return (store, bar);
    }

    test('a preview is not applied once its list has AI off', () async {
      final (store, bar) = await previewed([_edit('a', 'title', 'Oat milk')]);
      await _aiOff(store, _g);
      await bar.apply();
      expect(bar.phase, AiBarPhase.problem);
      expect(bar.problem!.listOff, isNotNull);
      expect(_only(store)['title'], 'Milk');
    });

    test('a patch is not applied once its list has AI off', () async {
      final (store, bar) = await previewed([
        _patch({'op': 'setListInfo', 'color': '#123456'}),
      ]);
      await _aiOff(store, _g);
      await bar.apply();
      expect(bar.problem!.listOff, isNotNull);
      expect(store.current.definition(_g)!.color, isNot('#123456'));
    });

    test('AI turned off by another device just before the write', () async {
      final _Racing firestore = _Racing();
      final (store, bar) = await previewed([
        _edit('a', 'title', 'Oat milk'),
      ], firestore: firestore);
      firestore.beforeTransaction = () => firestore
          .doc('users/$testUid/lists/$_g')
          .update({'aiAllowed': false});
      await bar.apply();
      await _tick();
      expect(bar.problem!.listOff, isNotNull);
      expect(_only(store)['title'], 'Milk');
    });

    test('with auto-apply too, and the plan stops at the refusal', () async {
      final _Racing firestore = _Racing();
      final FirestoreListStore store = await fakeFirestoreStore(
        firestore: firestore,
        items: [_item('a', 'Milk'), _item('t', 'Call', list: _t)],
      );
      final AiBarController bar = await _bar(
        store,
        _Script(
          (_, _) async => _answer([
            _edit('a', 'title', 'Oat milk'),
            _edit('t', 'title', 'Call Sam', list: _t),
          ]),
        ),
        autoApply: true,
      );
      firestore.beforeTransaction = () => firestore
          .doc('users/$testUid/lists/$_g')
          .update({'aiAllowed': false});
      await _send(bar, 'rename', open: null);
      expect(bar.phase, AiBarPhase.problem);
      expect(_only(store)['title'], 'Milk');
      expect(store.current.itemsOf(_t).single['title'], 'Call');
    });

    test('another field changed since the preview is kept', () async {
      final (store, bar) = await previewed([_edit('a', 'title', 'Oat milk')]);
      await store.apply(ListChanges(saved: [_item('a', 'Milk', done: true)]));
      await _tick();
      await bar.apply();
      await _tick();
      expect(bar.phase, AiBarPhase.done);
      expect(_only(store)['title'], 'Oat milk');
      expect(_only(store)['done'], true);
    });

    test('the same field changed since: refused, the words come back', () async {
      final (store, bar) = await previewed([_edit('a', 'title', 'Oat milk')]);
      await store.apply(ListChanges(saved: [_item('a', 'Soy milk')]));
      await _tick();
      await bar.apply();
      await _tick();
      expect(bar.phase, AiBarPhase.problem);
      expect(bar.problem!.errors.single.code, ListErrorCode.previewChanged);
      expect(_only(store)['title'], 'Soy milk');
      expect(bar.text.text, 'rename milk');
    });

    test('the same change made elsewhere is no conflict', () async {
      final (store, bar) = await previewed([_edit('a', 'title', 'Oat milk')]);
      await store.apply(ListChanges(saved: [_item('a', 'Oat milk')]));
      await _tick();
      await bar.apply();
      await _tick();
      expect(bar.phase, AiBarPhase.done);
    });

    test('a deleted item is not brought back', () async {
      final (store, bar) = await previewed([_edit('a', 'title', 'Oat milk')]);
      await store.apply(const ListChanges(deletedIds: ['a']));
      await _tick();
      await bar.apply();
      await _tick();
      expect(bar.problem!.errors.single.code, ListErrorCode.previewChanged);
      expect(store.current.itemsOf(_g), isEmpty);
    });

    test('changed fields refuse an item change and a patch', () async {
      for (final AiToolCall call in [
        _edit('a', 'title', 'Oat milk'),
        _patch({'op': 'setListInfo', 'color': '#123456'}),
      ]) {
        final (store, bar) = await previewed([call]);
        await store.patchList(_g, const [
          ListPatchOp(PatchOpKind.addField, {
            'field': {'key': 'note', 'type': 'text', 'label': 'Note'},
          }),
        ]);
        await _tick();
        await bar.apply();
        await _tick();
        expect(bar.problem!.errors.single.code, ListErrorCode.previewChanged);
        expect(_only(store)['title'], 'Milk');
        expect(store.current.definition(_g)!.color, isNot('#123456'));
      }
    });

    test('the list renamed elsewhere does not stop an item change', () async {
      final (store, bar) = await previewed([_edit('a', 'title', 'Oat milk')]);
      await store.patchList(_g, const [
        ListPatchOp(PatchOpKind.setListInfo, {'name': 'Food'}),
      ]);
      await _tick();
      await bar.apply();
      await _tick();
      expect(_only(store)['title'], 'Oat milk');
    });

    test('a delete of an item changed since the preview is refused', () async {
      final (store, bar) = await previewed([
        const AiToolCall('delete_items', {
          'listId': _g,
          'ids': ['a'],
        }),
      ]);
      await store.apply(ListChanges(saved: [_item('a', 'Milk', done: true)]));
      await _tick();
      await bar.apply();
      await _tick();
      expect(bar.problem!.errors.single.code, ListErrorCode.previewChanged);
      expect(store.current.itemsOf(_g), hasLength(1));
    });

    test('offline: a change needs a connection, an add may queue', () async {
      final _Racing firestore = _Racing();
      final (store, bar) = await previewed([
        _edit('a', 'title', 'Oat milk'),
      ], firestore: firestore);
      firestore.offline = true;
      await bar.apply();
      expect(bar.problem!.errors.single.code, ListErrorCode.needsConnection);
      expect(_only(store)['title'], 'Milk');

      final AiBarController adder = await _bar(
        store,
        _Script(
          (_, _) async => _answer([
            const AiToolCall('upsert_items', {
              'listId': _g,
              'items': [
                {
                  'values': [
                    {'field': 'title', 'value': 'Eggs'},
                  ],
                },
              ],
            }),
          ]),
        ),
      );
      await _send(adder, 'eggs');
      expect(adder.phase, AiBarPhase.done);
      expect(store.current.itemsOf(_g), hasLength(2));
    });
  });

  group('Undo', () {
    test('goes away once a created list changes; a race is refused (Q-52, H4)', () async {
      final _Racing firestore = _Racing();
      final FirestoreListStore store = await fakeFirestoreStore(
        firestore: firestore,
      );
      final AiBarController bar = await _bar(
        store,
        _Script((_, _) async => _answer([_createBooks])),
      );
      await _send(bar, 'make a books list', open: null);
      await bar.apply();
      await _tick();
      final String id = bar.plan!.steps.single.listId;
      expect(bar.canUndo, isTrue);

      // A change that reaches the store only during the tap.
      firestore.beforeTransaction = () => firestore
          .doc('users/$testUid/lists/$id')
          .update({'name': 'Mine'});
      await bar.undo();
      await _tick();
      expect(bar.phase, AiBarPhase.problem);
      expect(store.current.definition(id), isNotNull);

      final AiBarController second = await _bar(
        store,
        _Script((_, _) async => _answer([_createBooks])),
      );
      await _send(second, 'make another', open: null);
      await second.apply();
      await _tick();
      final String other = second.plan!.steps.single.listId;
      expect(second.canUndo, isTrue);
      await store.apply(
        ListChanges(saved: [_item('mine', 'Mine', list: other)]),
      );
      await _tick();
      expect(second.canUndo, isFalse);
      await second.undo();
      expect(store.current.definition(other), isNotNull);
      expect(store.current.itemsOf(other), hasLength(1));
    });

    test('an untouched created list is deleted', () async {
      final FirestoreListStore store = await fakeFirestoreStore();
      final AiBarController bar = await _bar(
        store,
        _Script((_, _) async => _answer([_createBooks])),
      );
      await _send(bar, 'make a books list', open: null);
      await bar.apply();
      await _tick();
      final String id = bar.plan!.steps.single.listId;
      await bar.undo();
      await _tick();
      expect(bar.phase, AiBarPhase.done);
      expect(store.current.definition(id), isNull);
    });

    test('goes away when a touched item changes elsewhere, stays for others (Q-52)', () async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [_item('a', 'Milk'), _item('b', 'Bread')],
      );
      final AiBarController bar = await _bar(
        store,
        _Script((_, _) async => _answer([_edit('a', 'title', 'Oat milk')])),
      );
      await _send(bar, 'rename milk');
      await bar.apply();
      await _tick();
      await store.apply(ListChanges(saved: [_item('b', 'Rye bread')]));
      await _tick();
      expect(bar.canUndo, isTrue);
      await store.apply(ListChanges(saved: [_item('a', 'Soy milk')]));
      await _tick();
      expect(bar.canUndo, isFalse);
      expect(bar.phase, AiBarPhase.done);
    });

    test('offline: nothing changes and Undo stays to try again (Q-53, H5)', () async {
      final _Racing firestore = _Racing();
      final FirestoreListStore store = await fakeFirestoreStore(
        firestore: firestore,
        items: [_item('a', 'Milk')],
      );
      final AiBarController bar = await _bar(
        store,
        _Script((_, _) async => _answer([_edit('a', 'title', 'Oat milk')])),
      );
      await _send(bar, 'rename milk');
      await bar.apply();
      await _tick();

      firestore.offline = true;
      await bar.undo();
      await _tick();
      expect(bar.phase, AiBarPhase.problem);
      expect(bar.problem!.errors.single.code, ListErrorCode.needsConnection);
      expect(bar.canUndo, isTrue);
      expect(_only(store)['title'], 'Oat milk');

      firestore.offline = false;
      await bar.undo();
      await _tick();
      expect(bar.phase, AiBarPhase.done);
      expect(_only(store)['title'], 'Milk');
    });

    test('a patch undoes to what its transaction read (H6)', () async {
      final _Racing firestore = _Racing();
      final FirestoreListStore store = await fakeFirestoreStore(
        firestore: firestore,
      );
      final AiBarController bar = await _bar(
        store,
        _Script(
          (_, _) async => _answer([
            _patch({'op': 'setListInfo', 'color': '#123456'}),
          ]),
        ),
      );
      final String color = store.current.definition(_g)!.color;
      await _send(bar, 'change the color');
      firestore.beforeTransaction = () => firestore
          .doc('users/$testUid/lists/$_g')
          .update({'name': 'Other device rename', 'nameKey': null});
      await bar.apply();
      await _tick();
      expect(store.current.definition(_g)!.name, 'Other device rename');

      await bar.undo();
      await _tick();
      expect(bar.phase, AiBarPhase.done);
      expect(store.current.definition(_g)!.color, color);
      expect(store.current.definition(_g)!.name, 'Other device rename');
    });

    test('an item change and a patch undo together (M3)', () async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [_item('a', 'Milk')],
      );
      final String color = store.current.definition(_g)!.color;
      final AiBarController bar = await _bar(
        store,
        _Script(
          (_, _) async => _answer([
            _edit('a', 'title', 'Oat milk'),
            _patch({'op': 'setListInfo', 'color': '#123456'}),
            _patch({'op': 'setListInfo', 'name': 'Food'}),
          ]),
        ),
      );
      await _send(bar, 'rename and recolor');
      await bar.apply();
      await _tick();
      expect(store.current.definition(_g)!.name, 'Food');

      await bar.undo();
      await _tick();
      expect(bar.phase, AiBarPhase.done);
      expect(_only(store)['title'], 'Milk');
      expect(store.current.definition(_g)!.color, color);
      expect(store.current.definition(_g)!.name, isNot('Food'));
    });

    test('a change elsewhere is still refused after joining (M3)', () async {
      final _Racing firestore = _Racing();
      final FirestoreListStore store = await fakeFirestoreStore(
        firestore: firestore,
        items: [_item('a', 'Milk')],
      );
      final AiBarController bar = await _bar(
        store,
        _Script(
          (_, _) async => _answer([
            _edit('a', 'title', 'Oat milk'),
            _patch({'op': 'setListInfo', 'color': '#123456'}),
          ]),
        ),
      );
      await _send(bar, 'rename and recolor');
      await bar.apply();
      await _tick();
      firestore.beforeTransaction = () => firestore
          .doc('users/$testUid/lists/$_g')
          .update({'name': 'Elsewhere', 'nameKey': null});
      await bar.undo();
      await _tick();
      expect(bar.phase, AiBarPhase.problem);
      expect(store.current.definition(_g)!.name, 'Elsewhere');
      expect(_only(store)['title'], 'Oat milk');
    });
  });

  group('A back-and-forth when a list goes AI-off (R1, Q-57)', () {
    Future<(_Script, AiBarController, FirestoreListStore)> chat(
      List<String> replies,
    ) async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [_item('a', 'PRIVATE MEDICATION')],
      );
      final _Script ai = _Script(
        (_, round) async => _answer([
          AiToolCall('reply', {'text': replies[round - 1]}),
        ]),
      );
      return (ai, await _bar(store, ai), store);
    }

    test('the latest reply does not go out, from the list or from Home', () async {
      for (final String? open in [_g, null]) {
        final (ai, bar, store) = await chat(['Do you mean PRIVATE MEDICATION?']);
        await _send(bar, 'rename this');
        await _aiOff(store, _g);
        await _send(bar, 'yes', open: open);
        expect(ai.requests, hasLength(1));
        expect(bar.phase, AiBarPhase.problem);
        expect(bar.problem!.listOff, isNotNull);
        expect(bar.text.text, 'yes');
      }
    });

    test('an earlier reply does not go out either', () async {
      final (ai, bar, store) = await chat(['Do you mean Grocery?', 'Which one?']);
      await _send(bar, 'rename this', open: null);
      await _send(bar, 'yes', open: null);
      expect(ai.requests, hasLength(2));
      await _aiOff(store, _g);
      await _send(bar, 'the first', open: null);
      expect(ai.requests, hasLength(2));
      expect(bar.problem!.listOff, isNotNull);
    });

    test('a reply that never mentions the list ends too; the next send is fresh', () async {
      final (ai, bar, store) = await chat(['Which one?', 'Fine.']);
      await _send(bar, 'rename this');
      await _aiOff(store, _g);
      await _send(bar, 'the first', open: null);
      expect(ai.requests, hasLength(1));
      await _send(bar, 'the first', open: null);
      expect(ai.requests, hasLength(2));
      expect(ai.requests.last.followUp, isNull);
      expect(ai.requests.last.toJson().toString(), isNot(contains('Which one?')));
    });

    test('a correction does not go out once any list of the chain is off', () async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [_item('a', 'Milk')],
      );
      final _Script ai = _Script((_, _) async {
        await _aiOff(store, _t);
        return _answer([
          const AiToolCall('upsert_items', {
            'listId': _g,
            'items': [
              {
                'values': [
                  {'field': 'nope', 'value': 'x'},
                ],
              },
            ],
          }),
        ]);
      });
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'add it');
      expect(ai.requests, hasLength(1));
      expect(bar.problem!.listOff, isNotNull);
    });
  });

  group('Requests over several lists (R4, Q-61)', () {
    // Answers as a model would: by id where a list's items are in the request,
    // by words where they are not.
    AiAnswer breadInAll(AiRequest request, List<String> lists) {
      return _answer([
        for (final String list in lists)
          if (request.openList?.id == list)
            AiToolCall('delete_items', {
              'listId': list,
              'ids': [
                for (final ListItem item in request.openItems)
                  if (item['done'] == true) item.id,
              ],
            })
          else
            AiToolCall('delete_items', {
              'listId': list,
              'match': ['bread'],
            }),
      ]);
    }

    List<ListItem> breads(String list) => [
      _item('$list-1', 'Brown bread', list: list, done: true),
      _item('$list-2', 'White bread', list: list),
    ];

    test('two lists that each need their items succeed', () async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [...breads(_g), ...breads(_t)],
      );
      final _Script ai = _Script(
        (request, _) async => breadInAll(request, [_g, _t]),
      );
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'delete the completed bread in Grocery and Tasks', open: null);
      expect(bar.phase, AiBarPhase.preview);
      expect(ai.requests, hasLength(3));
      await bar.apply();
      await _tick();
      expect(bar.phase, AiBarPhase.done);
      expect(store.current.itemsOf(_g).single.id, '$_g-2');
      expect(store.current.itemsOf(_t).single.id, '$_t-2');
      // Undo brings both back.
      await bar.undo();
      await _tick();
      expect(store.current.itemsOf(_g), hasLength(2));
      expect(store.current.itemsOf(_t), hasLength(2));
    });

    test('every list works, each fetched once (Q-61)', () async {
      final List<String> ids = [
        for (final ListDefinition definition in BuiltinTemplates.all())
          definition.id,
      ];
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [for (final String id in ids) ...breads(id)],
      );
      final _Script ai = _Script(
        (request, _) async => breadInAll(request, ids),
      );
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'remove the done bread from all my lists', open: null);
      expect(bar.phase, AiBarPhase.preview);
      expect(ai.requests.length, ids.length + 1);
      final List<String?> fetched = [
        for (final AiRequest request in ai.requests) request.openList?.id,
      ];
      expect(fetched.whereType<String>().toSet(), ids.toSet());
      expect(fetched.whereType<String>().length, ids.length);
    });

    // A list settled in one round, then changed before the answer is complete
    // (F1 of the last Codex pass).
    Future<(FirestoreListStore, AiBarController)> changedMidRequest(
      Future<void> Function(FirestoreListStore store) change, {
      bool autoApply = false,
    }) async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [...breads(_g), ...breads(_t)],
      );
      final _Script ai = _Script((request, round) async {
        if (round == 3) {
          await change(store);
          await _tick();
        }
        return breadInAll(request, [_g, _t]);
      });
      final AiBarController bar = await _bar(store, ai, autoApply: autoApply);
      await _send(bar, 'delete the completed bread', open: null);
      if (!autoApply) {
        expect(bar.phase, AiBarPhase.preview);
        await bar.apply();
        await _tick();
      }
      return (store, bar);
    }

    ListItem unticked(ListItem item) => ListItem(
      id: item.id,
      listId: item.listId,
      values: {...item.values, 'done': false},
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
    );

    for (final bool autoApply in [false, true]) {
      test('an item unticked mid-request is not deleted, auto-apply $autoApply', () async {
        final (store, bar) = await changedMidRequest(
          (store) => store.apply(
            ListChanges(saved: [unticked(store.current.itemsOf(_g).first)]),
          ),
          autoApply: autoApply,
        );
        expect(store.current.itemsOf(_g), hasLength(2));
        expect(bar.phase, AiBarPhase.problem);
        expect(bar.problem!.errors.single.code, ListErrorCode.previewChanged);
      });
    }

    test('fields changed mid-request stop the kept step', () async {
      final (store, bar) = await changedMidRequest(
        (store) => store.patchList(_g, const [
          ListPatchOp(PatchOpKind.addField, {
            'field': {'key': 'note', 'type': 'text', 'label': 'Note'},
          }),
        ]),
      );
      expect(store.current.itemsOf(_g), hasLength(2));
      expect(bar.problem!.errors.single.code, ListErrorCode.previewChanged);
    });

    test('an item deleted mid-request stays deleted; the rest goes on', () async {
      final (store, bar) = await changedMidRequest(
        (store) => store.apply(ListChanges(deletedIds: ['$_g-1'])),
      );
      expect(bar.phase, AiBarPhase.done);
      expect(store.current.itemsOf(_g).single.id, '$_g-2');
      expect(store.current.itemsOf(_t).single.id, '$_t-2');
    });

    test('a kept change still merges with another field changed mid-request', () async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [...breads(_g), ...breads(_t)],
      );
      final _Script ai = _Script((request, round) async {
        if (round == 3) {
          final ListItem item = store.current.itemsOf(_g).firstWhere((i) => i.id == '$_g-2');
          await store.apply(
            ListChanges(
              saved: [
                ListItem(
                  id: item.id,
                  listId: item.listId,
                  values: {...item.values, 'done': true},
                  createdAt: item.createdAt,
                  updatedAt: item.updatedAt,
                ),
              ],
            ),
          );
          await _tick();
        }
        return _answer([
          for (final String list in [_g, _t])
            if (request.openList?.id == list)
              _edit('$list-2', 'title', 'Rye bread', list: list)
            else
              AiToolCall('delete_items', {
                'listId': list,
                'match': ['bread'],
              }),
        ]);
      });
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'rename the white bread', open: null);
      await bar.apply();
      await _tick();
      expect(bar.phase, AiBarPhase.done);
      final ListItem merged = store.current.itemsOf(_g).firstWhere((i) => i.id == '$_g-2');
      expect(merged['title'], 'Rye bread');
      expect(merged['done'], true);
    });

    test('a limit, for account tiers later, ends with nothing changed', () async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [...breads(_g), ...breads(_t)],
      );
      final _Script ai = _Script(
        (request, _) async => breadInAll(request, [_g, _t]),
      );
      final AiBarController bar = await _bar(store, ai, maxListFetches: 1);
      await _send(bar, 'delete the completed bread', open: null);
      expect(bar.phase, AiBarPhase.problem);
      expect(ai.requests.length, lessThanOrEqualTo(3));
      expect(store.current.itemsOf(_g), hasLength(2));
    });

    test('a settled list turned AI-off stops the whole answer', () async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [...breads(_g), ...breads(_t)],
      );
      final _Script ai = _Script((request, round) async {
        if (round == 3) {
          await _aiOff(store, _g);
        }
        return breadInAll(request, [_g, _t]);
      });
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'delete the completed bread in both', open: null);
      expect(bar.phase, AiBarPhase.problem);
      expect(bar.problem!.listOff, isNotNull);
      expect(store.current.itemsOf(_t), hasLength(2));
    });
  });

  group('Too many changes (R3, Q-60)', () {
    AiToolCall fifty(int start, {int count = 50}) => AiToolCall('upsert_items', {
      'listId': _g,
      'items': [
        for (int n = start; n < start + count; n++)
          {
            'values': [
              {'field': 'title', 'value': 'Row $n'},
            ],
          },
      ],
    });

    test('501 across valid calls is refused before any preview', () async {
      final FirestoreListStore store = await fakeFirestoreStore();
      final _Script ai = _Script(
        (_, _) async => _answer([
          for (int call = 0; call < 10; call++) fifty(call * 50),
          fifty(500, count: 1),
        ]),
      );
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'add a lot');
      expect(ai.requests, hasLength(1));
      expect(bar.phase, AiBarPhase.problem);
      expect(bar.problem!.errors.single.code, ListErrorCode.answerTooLarge);
      expect(bar.text.text, 'add a lot');
      expect(store.current.itemsOf(_g), isEmpty);
    });

    AiToolCall newList(String name, int items) => AiToolCall('create_list', {
      'list': {
        'name': name,
        'icon': 'book',
        'color': '#123456',
        'fields': [
          {'key': 'title', 'type': 'text', 'label': 'Title', 'primary': true},
        ],
        'view': {'kind': 'cards'},
      },
      'items': [
        for (int n = 0; n < items; n++)
          {
            'values': [
              {'field': 'title', 'value': 'Row $n'},
            ],
          },
      ],
    });

    Future<AiBarController> answered(List<AiToolCall> calls) async {
      final FirestoreListStore store = await fakeFirestoreStore();
      final _Script ai = _Script((_, _) async => _answer(calls));
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'make lists');
      return bar;
    }

    test('items of new lists count: 550 is refused (F4)', () async {
      final AiBarController bar = await answered([
        for (int n = 0; n < 11; n++) newList('List $n', 50),
      ]);
      expect(bar.phase, AiBarPhase.problem);
      expect(bar.problem!.errors.single.code, ListErrorCode.answerTooLarge);
    });

    test('new lists and item changes count together: 501 refused, 500 fits (F4)', () async {
      final AiBarController over = await answered([
        for (int call = 0; call < 9; call++) fifty(call * 50),
        newList('Books', 50),
        fifty(450, count: 1),
      ]);
      expect(over.problem?.errors.single.code, ListErrorCode.answerTooLarge);
      final AiBarController fits = await answered([
        for (int call = 0; call < 9; call++) fifty(call * 50),
        newList('Books', 50),
      ]);
      expect(fits.phase, AiBarPhase.preview);
    });

    test('kept rounds count too (F4)', () async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [_item('a', 'Brown bread'), _item('b', 'White bread')],
      );
      final _Script ai = _Script(
        (request, _) async => request.openList?.id == _t
            ? _answer([
                for (int call = 0; call < 10; call++) AiToolCall('upsert_items', {
                  'listId': _t,
                  'items': [
                    for (int n = 0; n < 50; n++)
                      {
                        'values': [
                          {'field': 'title', 'value': 'Row $n'},
                        ],
                      },
                  ],
                }),
              ])
            : request.openList?.id == _g
            ? _answer([
                const AiToolCall('delete_items', {
                  'listId': _g,
                  'ids': ['a'],
                }),
                const AiToolCall('delete_items', {
                  'listId': _t,
                  'match': ['anything'],
                }),
              ])
            : _answer([
                const AiToolCall('delete_items', {
                  'listId': _g,
                  'match': ['bread'],
                }),
              ]),
      );
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'do it all', open: null);
      expect(bar.problem?.errors.single.code, ListErrorCode.answerTooLarge);
    });

    test('500 across valid calls applies, and Undo takes them back', () async {
      final FirestoreListStore store = await fakeFirestoreStore();
      final _Script ai = _Script(
        (_, _) async => _answer([
          for (int call = 0; call < 10; call++) fifty(call * 50),
        ]),
      );
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'add a lot');
      await bar.apply();
      await _tick();
      expect(bar.phase, AiBarPhase.done);
      expect(store.current.itemsOf(_g), hasLength(500));
      await bar.undo();
      await _tick();
      await _tick();
      expect(store.current.itemsOf(_g), isEmpty);
    });
  });

  group('A big structure change (Q-59)', () {
    test('it reports done with items still updating, and no Undo', () async {
      const String plants = 'list-plants';
      final ListDefinition list = ListDefinition.fromJson({
        'id': plants,
        'name': 'Plants',
        'icon': 'local_florist',
        'color': '#43A047',
        'fields': [
          {'key': 'title', 'type': 'text', 'label': 'Plant', 'primary': true},
          {'key': 'kind', 'type': 'text', 'label': 'Kind'},
        ],
        'view': {'kind': 'cards'},
        'updatedAt': _now.toIso8601String(),
      });
      final FirestoreListStore store = await fakeFirestoreStore(
        lists: [list],
        batchLimit: 5,
      );
      await store.apply(
        ListChanges(
          saved: [
            for (int n = 0; n < 6; n++)
              ListItem(
                id: 'i$n',
                listId: plants,
                values: {'title': 'Plant $n', 'kind': '$n'},
                createdAt: _now,
                updatedAt: _now,
              ),
          ],
        ),
      );
      await _tick();
      final AiBarController bar = await _bar(
        store,
        _Script(
          (_, _) async => _answer([
            _patch({
              'op': 'changeFieldType',
              'key': 'kind',
              'type': 'counter',
            }, list: plants),
          ]),
        ),
      );
      await _send(bar, 'make kind a counter', open: plants);
      expect(bar.phase, AiBarPhase.preview);
      await bar.apply();
      expect(bar.phase, AiBarPhase.done);
      expect(bar.itemsPending, isTrue);
      expect(bar.canUndo, isFalse);
      await _tick();
      expect(store.current.itemsOf(plants).every((i) => i['kind'] is int), isTrue);
    });
  });

  group('Rounds (M1)', () {
    test('alternating unclear lists stop instead of refetching', () async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [
          _item('a', 'Brown bread'),
          _item('b', 'White bread'),
          _item('c', 'Brown bread', list: _t),
          _item('d', 'White bread', list: _t),
        ],
      );
      final _Script ai = _Script(
        (request, _) async => _answer([
          AiToolCall('delete_items', {
            'listId': request.openList?.id == _g ? _t : _g,
            'match': ['bread'],
          }),
        ]),
      );
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'remove bread', open: null);
      expect(ai.requests.length, lessThanOrEqualTo(4));
      expect(bar.phase, AiBarPhase.problem);
      expect(bar.problem!.errors, isNotEmpty);
      final List<String?> fetched = [
        for (final AiRequest request in ai.requests)
          if (request.correction == null) request.openList?.id,
      ];
      expect(fetched.whereType<String>().toSet().length, fetched.whereType<String>().length);
    });

    test('several unclear lists in one answer stay bounded', () async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [
          _item('a', 'Brown bread'),
          _item('b', 'White bread'),
          _item('c', 'Brown bread', list: _t),
          _item('d', 'White bread', list: _t),
        ],
      );
      final _Script ai = _Script(
        (_, _) async => _answer([
          const AiToolCall('delete_items', {
            'listId': _g,
            'match': ['bread'],
          }),
          const AiToolCall('delete_items', {
            'listId': _t,
            'match': ['bread'],
          }),
        ]),
      );
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'remove bread', open: null);
      expect(ai.requests.length, lessThanOrEqualTo(4));
      expect(bar.phase, AiBarPhase.problem);
    });
  });

  group('Calls that overlap (M2)', () {
    Future<(FirestoreListStore, AiBarController)> applied(
      List<AiToolCall> calls,
    ) async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [_item('a', 'Milk')],
      );
      final AiBarController bar = await _bar(
        store,
        _Script((_, _) async => _answer(calls)),
      );
      await _send(bar, 'do it');
      await bar.apply();
      await _tick();
      return (store, bar);
    }

    test('a rename and a tick of one item both land', () async {
      final (store, bar) = await applied([
        _edit('a', 'title', 'Oat milk'),
        _edit('a', 'done', true),
      ]);
      expect(_only(store)['title'], 'Oat milk');
      expect(_only(store)['done'], true);
      await bar.undo();
      await _tick();
      expect(_only(store)['title'], 'Milk');
      expect(_only(store)['done'], false);
    });

    test('an edit then a delete deletes', () async {
      final (store, _) = await applied([
        _edit('a', 'title', 'Oat milk'),
        const AiToolCall('delete_items', {
          'listId': _g,
          'ids': ['a'],
        }),
      ]);
      expect(store.current.itemsOf(_g), isEmpty);
    });

    test('a delete then an edit is an error, and nothing is written', () async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [_item('a', 'Milk')],
      );
      final AiBarController bar = await _bar(
        store,
        _Script(
          (_, _) async => _answer([
            const AiToolCall('delete_items', {
              'listId': _g,
              'ids': ['a'],
            }),
            _edit('a', 'title', 'Oat milk'),
          ]),
        ),
      );
      await _send(bar, 'do it');
      expect(bar.phase, AiBarPhase.problem);
      expect(_only(store)['title'], 'Milk');
    });

    test('a new field can be filled in the same answer', () async {
      final (store, _) = await applied([
        _patch({
          'op': 'addField',
          'field': {'key': 'note', 'type': 'text', 'label': 'Note'},
        }),
        _edit('a', 'note', 'organic'),
      ]);
      expect(store.current.definition(_g)!.field('note'), isNotNull);
      expect(_only(store)['note'], 'organic');
    });
  });

  group('AI-off names (M4, Q-54)', () {
    test('namedIn: scripts without spaces, quotes and near names', () {
      expect(AiMatch.namedIn('往购物清单加牛奶', '购物清单'), isTrue);
      expect(AiMatch.namedIn('购物加牛奶', '购物清单'), isTrue);
      expect(AiMatch.namedIn('買い物リストに牛乳を追加', '買い物リスト'), isTrue);
      expect(AiMatch.namedIn('買い物に牛乳', '買い物リスト'), isTrue);
      expect(AiMatch.namedIn('add milk to "Grocery"', 'Grocery'), isTrue);
      expect(AiMatch.namedIn('add milk to “Grocery”', 'Grocery'), isTrue);
      expect(AiMatch.namedIn("add milk to 'Grocery'", 'Grocery'), isTrue);
      expect(AiMatch.namedIn('add milk to groceries', 'Grocery'), isTrue);
      expect(AiMatch.namedIn('add milk to grocery', 'Grocery list'), isTrue);
      expect(AiMatch.namedIn('add milk to grocery lists', 'Grocery list'), isTrue);
    });

    test('namedIn: what stays out', () {
      expect(AiMatch.namedIn('add milk to pantry', 'Grocery'), isFalse);
      expect(AiMatch.namedIn('add a greengrocer visit', 'Grocer'), isFalse);
      expect(AiMatch.namedIn('add milk to the list', 'Grocery list'), isFalse);
      // One character in such a script must stand alone.
      expect(AiMatch.namedIn('买书包', '书'), isFalse);
      expect(AiMatch.namedIn('添加到 书', '书'), isTrue);
      expect(AiMatch.namedIn('添加到「书」', '书'), isTrue);
      // A list word alone is not the name.
      expect(AiMatch.namedIn('添加到清单', '购物清单'), isFalse);
      expect(AiMatch.namedIn('', 'Grocery'), isFalse);
    });

    test('punctuation is a boundary, no global ie rule (R5)', () {
      // \u4E70\u7C73\u3001\u7C89\u7B14: buy rice, chalk; list: rice noodles.
      expect(AiMatch.namedIn('\u4E70\u7C73\u3001\u7C89\u7B14', '\u7C73\u7C89'), isFalse);
      expect(AiMatch.namedIn('\u4E70\u7C73\u7C89', '\u7C73\u7C89'), isTrue);
      expect(AiMatch.namedIn('call family', 'Familie'), isFalse);
      expect(AiMatch.namedIn('call familie', 'Familie'), isTrue);
      expect(AiMatch.namedIn('add to cookies', 'Cookie'), isTrue);
      expect(AiMatch.namedIn('add to the movies', 'Movie'), isTrue);
    });

    test('clear and possible mentions (Q-62)', () {
      AiMention mention(String text, String name, [List<String> others = const []]) =>
          AiMatch.mention(text, name, otherNames: others);
      expect(mention('add this book to my books', 'Books'), AiMention.possible);
      expect(mention('add to grocery', 'Grocery list'), AiMention.possible);
      expect(mention('add to "Books"', 'Books'), AiMention.clear);
      expect(mention("add to 'Books'", 'Books'), AiMention.clear);
      expect(mention('add to my books list', 'Books'), AiMention.clear);
      expect(mention('add to my grocery list', 'Grocery list'), AiMention.clear);
      // The Chinese and Japanese list words.
      expect(mention('\u5F80\u8D2D\u7269\u6E05\u5355\u52A0\u725B\u5976', '\u8D2D\u7269\u6E05\u5355'), AiMention.clear);
      expect(mention('\u5F80\u8D2D\u7269\u52A0\u725B\u5976', '\u8D2D\u7269\u6E05\u5355'), AiMention.possible);
      expect(mention('\u7C73\u7C89\u6E05\u5355\u52A0\u725B\u5976', '\u7C73\u7C89'), AiMention.clear);
      expect(mention('\u65E5\u672C\u8A9E\u3092\u52C9\u5F37\u3059\u308B', '\u65E5\u672C'), AiMention.possible);
      expect(mention('\u300C\u65E5\u672C\u300D\u306B\u8FFD\u52A0', '\u65E5\u672C'), AiMention.clear);
      // A longer list's name wins.
      expect(mention('add to buy books', 'Books', ['Buy books']), AiMention.none);
      expect(mention('add to buy books', 'Books'), AiMention.possible);
      expect(mention('add this book to my books', 'Books', ['Buy books']), AiMention.possible);
      expect(mention('\u8D2D\u7269\u6E05\u5355\u52A0\u725B\u5976', '\u8D2D\u7269', ['\u8D2D\u7269\u6E05\u5355']), AiMention.none);
      // A shorter one does not take the mention away.
      expect(mention('add to buy books', 'Buy books', ['Books']), AiMention.possible);
    });

    test('a clear occurrence wins over an earlier possible one (F2)', () {
      AiMention mention(String text, String name) => AiMatch.mention(text, name);
      expect(mention('books are useful; add this to my books list', 'Books'), AiMention.clear);
      expect(mention('books and more; put it in "Books"', 'Books'), AiMention.clear);
      // The same in a script without spaces: Japanese words, then the list.
      expect(
        mention('\u65E5\u672C\u8A9E\u3092\u52C9\u5F37\u3001\u65E5\u672C\u30EA\u30B9\u30C8\u306B\u8FFD\u52A0', '\u65E5\u672C'),
        AiMention.clear,
      );
      expect(
        mention('\u65E5\u672C\u8A9E\u3068\u65E5\u672C\u30EA\u30B9\u30C8', '\u65E5\u672C'),
        AiMention.clear,
      );
      expect(mention('books and more books', 'Books'), AiMention.possible);
    });

    test('that request gets the block, not the offer, and sends nothing (F2)', () async {
      final List<ListDefinition> lists = [
        for (final ListDefinition definition in BuiltinTemplates.all())
          definition.id == _g
              ? ListDefinition.fromJson({
                  ...definition.toJson(),
                  'name': 'Books',
                  'nameKey': null,
                  'aiAllowed': false,
                })
              : definition,
      ];
      final FirestoreListStore store = await fakeFirestoreStore(lists: lists);
      final _Script ai = _Script((_, _) async => _answer(const []));
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'books are useful; add this to my books list', open: null);
      expect(bar.phase, AiBarPhase.problem);
      expect(bar.problem!.listOff, 'Books');
      expect(ai.requests, isEmpty);
    });

    test('a request to a longer AI-on name goes out; AI-off stays out of it (Q-62)', () async {
      final List<ListDefinition> lists = [
        for (final ListDefinition definition in BuiltinTemplates.all())
          if (definition.id == _g)
            ListDefinition.fromJson({
              ...definition.toJson(),
              'name': 'Books',
              'nameKey': null,
              'aiAllowed': false,
            })
          else if (definition.id == _t)
            ListDefinition.fromJson({
              ...definition.toJson(),
              'name': 'Buy books',
              'nameKey': null,
            })
          else
            definition,
      ];
      final FirestoreListStore store = await fakeFirestoreStore(lists: lists);
      final _Script ai = _Script(
        (_, _) async => _answer([
          const AiToolCall('reply', {'text': 'Done?'}),
        ]),
      );
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'add to buy books', open: null);
      expect(ai.requests, hasLength(1));
      expect(ai.requests.single.lists.map((l) => l.id), isNot(contains(_g)));
    });

    test('a word keeps its apostrophe when items are matched', () {
      expect(AiMatch.words("Bob's 'coffee'"), ["bob'", 'coffee']);
      expect(AiMatch.words('cookies cookie'), ['cookie', 'cookie']);
    });

    test('the bar sends nothing for such a request', () async {
      final List<ListDefinition> lists = [
        for (final ListDefinition definition in BuiltinTemplates.all())
          definition.id == _g
              ? ListDefinition.fromJson({
                  ...definition.toJson(),
                  'name': '购物清单',
                  'nameKey': null,
                  'aiAllowed': false,
                })
              : definition,
      ];
      final FirestoreListStore store = await fakeFirestoreStore(lists: lists);
      final _Script ai = _Script((_, _) async => _answer(const []));
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, '往购物清单加牛奶', open: null);
      expect(ai.requests, isEmpty);
      expect(bar.problem!.listOff, '购物清单');
    });
  });

  group('A list not on screen (M5)', () {
    Future<(FirestoreListStore, _Script, AiBarController)> matching({
      required bool autoApply,
    }) async {
      final FirestoreListStore store = await fakeFirestoreStore(
        items: [_item('a', 'Brown bread'), _item('b', 'White bread')],
      );
      final _Script ai = _Script(
        (_, round) async => round == 1
            ? _answer([
                const AiToolCall('delete_items', {
                  'listId': _g,
                  'match': ['bread'],
                }),
              ])
            : _answer([
                _patch({'op': 'setListInfo', 'name': 'Unrequested rename'}),
              ]),
      );
      final AiBarController bar = await _bar(store, ai, autoApply: autoApply);
      await _send(bar, 'remove bread', open: null);
      return (store, ai, bar);
    }

    for (final bool autoApply in [false, true]) {
      test('fetching its items gives no structure change, auto-apply $autoApply', () async {
        final (store, ai, bar) = await matching(autoApply: autoApply);
        expect(ai.requests[1].itemsOnly, isTrue);
        expect(ai.requests[1].toJson()['itemsOnly'], isTrue);
        expect(bar.phase, AiBarPhase.problem);
        expect(store.current.definition(_g)!.name, isNot('Unrequested rename'));
      });
    }

    test('the list on screen and a picked list keep their authority', () async {
      final FirestoreListStore store = await fakeFirestoreStore();
      final _Script ai = _Script(
        (_, round) async => round == 1
            ? _answer([
                const AiToolCall('choose_list', {
                  'question': 'Which?',
                  'candidates': [_g, _t],
                }),
              ])
            : _answer([
                _patch({'op': 'setListInfo', 'name': 'Food'}),
              ]),
      );
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'rename it', open: null);
      await bar.choose(_g);
      await _tick();
      expect(ai.requests.last.itemsOnly, isFalse);
      expect(bar.phase, AiBarPhase.preview);
    });
  });

  group('Clarifications (M6, Q-55)', () {
    test('the original request stays through several answers', () async {
      final FirestoreListStore store = await fakeFirestoreStore();
      final _Script ai = _Script(
        (_, round) async => _answer([
          AiToolCall('reply', {'text': 'Question $round'}),
        ]),
      );
      final AiBarController bar = await _bar(store, ai);
      const String first = 'change milk quantity in Grocery';
      await _send(bar, first, open: null);
      for (final String answer in ['one', 'two', 'three', 'four']) {
        await _send(bar, answer, open: null);
      }
      final Map<String, Object?> last = ai.requests.last.followUp!.toJson();
      expect(last['prompt'], first);
      expect(last['reply'], 'Question 4');
      expect(last['earlier'], [
        {'reply': 'Question 2', 'answer': 'two'},
        {'reply': 'Question 3', 'answer': 'three'},
      ]);
      expect(ai.requests.last.prompt, 'four');
    });

    test('New list after a typed answer keeps the context', () async {
      final FirestoreListStore store = await fakeFirestoreStore();
      final _Script ai = _Script(
        (_, round) async => round == 1
            ? _answer([
                const AiToolCall('reply', {'text': 'For what?'}),
              ])
            : _answer([
                const AiToolCall('choose_list', {
                  'question': 'Tasks or a new list?',
                  'candidates': [_t],
                  'newList': true,
                }),
              ]),
      );
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'plan a trip', open: null);
      await _send(bar, 'to Japan', open: null);
      await bar.chooseNewList();
      await _tick();
      final AiRequest last = ai.requests.last;
      expect(last.newList, isTrue);
      expect(last.prompt, 'to Japan');
      expect(last.followUp!.prompt, 'plan a trip');
      expect(last.openList, isNull);
    });

    test('Close starts afresh', () async {
      final FirestoreListStore store = await fakeFirestoreStore();
      final _Script ai = _Script(
        (_, _) async => _answer([
          const AiToolCall('reply', {'text': 'Which?'}),
        ]),
      );
      final AiBarController bar = await _bar(store, ai);
      await _send(bar, 'first', open: null);
      bar.dismiss();
      await _send(bar, 'second', open: null);
      expect(ai.requests.last.followUp, isNull);
    });
  });

  group('New list (L2)', () {
    test('the whole allowance stays the user words, from both entries', () async {
      final FirestoreListStore store = await fakeFirestoreStore();
      final String full = 'x' * 1000;
      final _Script ai = _Script(
        (_, round) async => round == 2
            ? _answer([
                const AiToolCall('choose_list', {
                  'question': 'Tasks or a new list?',
                  'candidates': [_t],
                  'newList': true,
                }),
              ])
            : _answer([_createBooks]),
      );
      final AiBarController bar = await _bar(store, ai);
      bar.startNewList();
      await _send(bar, full, open: null);
      expect(ai.requests.first.prompt, full);
      expect(ai.requests.first.toJson()['newList'], isTrue);
      bar.dismiss();

      await _send(bar, full, open: null);
      expect(bar.phase, AiBarPhase.question);
      expect(ai.requests[1].toJson().containsKey('newList'), isFalse);
      await bar.chooseNewList();
      await _tick();
      expect(ai.requests.last.prompt, full);
      expect(ai.requests.last.newList, isTrue);
    });
  });
}
