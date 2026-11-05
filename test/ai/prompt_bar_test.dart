import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/ai/ai_bar_controller.dart';
import 'package:hybrid_note/ai/ai_service.dart';
import 'package:hybrid_note/ai/prompt_bar.dart';
import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_rules.dart';

import '../support/fake_auth.dart';
import '../support/firestore_store.dart';

// Answers the bar's requests from a script and keeps them for the checks.
class FakeAiService implements AiService {
  final List<Object> answers = [];
  final List<AiRequest> requests = [];

  @override
  Future<AiAnswer> send(AiRequest request) async {
    requests.add(request);
    final Object next = answers.isEmpty
        ? const AiRefusal('provider')
        : answers.removeAt(0);
    if (next is AiRefusal) {
      throw next;
    }
    return next as AiAnswer;
  }
}

AiAnswer _calls(List<AiToolCall> calls) =>
    AiAnswer(requestId: 'r', toolCalls: calls);

AiToolCall _add(String listId, List<String> titles, {String field = 'title'}) =>
    AiToolCall('upsert_items', {
      'listId': listId,
      'items': [
        for (final String title in titles)
          {
            'values': [
              {'field': field, 'value': title},
            ],
          },
      ],
    });

const String _grocery = BuiltinTemplates.groceryId;
const String _tasks = BuiltinTemplates.tasksId;
const String _journal = BuiltinTemplates.journalId;

final Finder _field = find.byKey(const ValueKey('ai-bar-field'));
final Finder _send = find.byKey(const ValueKey('ai-bar-send'));
final Finder _hub = find.byKey(const ValueKey('launcher-hub'));

AccountPreferencesCubit _account(WidgetTester tester) => tester
    .element(find.byKey(const ValueKey('ai-bar')))
    .read<AccountPreferencesCubit>();

Future<FirestoreListStore> _pump(
  WidgetTester tester,
  FakeAiService ai, {
  bool noticeSeen = true,
  List<ListDefinition>? lists,
  List<ListItem> items = const [],
  Size size = const Size(360, 780),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    if (noticeSeen) AccountPreferencesCubit.legacyNoticeSeenKey: aiNoticeId,
  });
  final FirestoreListStore store = await widgetTestStore(
    tester,
    lists: lists,
    items: items,
  );
  final Widget app = await testApp(
    auth: FakeAuthService(user: testUser),
    openStore: (_) => store,
  );
  await tester.pumpWidget(
    RepositoryProvider<AiService>.value(value: ai, child: app),
  );
  await settle(tester);
  return store;
}

// Taps the bar (which brings a draft back), types and sends.
Future<void> _ask(WidgetTester tester, String text) async {
  await tester.tap(find.byKey(const ValueKey('ai-bar')));
  await tester.pumpAndSettle();
  await tester.enterText(_field, text);
  await tester.pump();
  await tester.tap(_send);
  await settle(tester);
}

Future<void> _openList(WidgetTester tester, String listId) async {
  await tester.tap(_hub);
  await tester.pump();
  await tester.tap(find.byKey(ValueKey('launcher-note-$listId')));
  await settle(tester);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await settle(tester);
}

// The run log of the AI examples (schema/ai_examples.json, T-19 unit 1).
Map<String, Object?> _runLog() {
  final Map<String, Object?> examples =
      jsonDecode(File('schema/ai_examples.json').readAsStringSync())
          as Map<String, Object?>;
  return ((examples['examples']! as List).firstWhere(
            (example) => (example as Map)['id'] == 'runLog',
          )
          as Map)['input']
      as Map<String, Object?>;
}

ListDefinition _aiOff(ListDefinition list) =>
    ListDefinition.fromJson({...list.toJson(), 'aiAllowed': false});

List<String> _titles(FirestoreListStore store, String listId) => [
  for (final ListItem item in store.current.itemsOf(listId)) '${item['title']}',
];

void main() {
  testWidgets('the one-time notice names DeepSeek and China before the first '
      'request, then never again', (tester) async {
    final FakeAiService ai = FakeAiService()
      ..answers.addAll([
        _calls([
          _add(_grocery, ['Milk']),
        ]),
        _calls([
          _add(_grocery, ['Eggs']),
        ]),
      ]);
    await _pump(tester, ai, noticeSeen: false);

    await _ask(tester, 'milk');
    expect(ai.requests, isEmpty);
    final String notice = tester
        .widget<Text>(find.byKey(const ValueKey('ai-notice')))
        .data!;
    expect(notice, contains('DeepSeek'));
    expect(notice, contains('China'));
    expect(notice, contains('7 days'));
    expect(notice, contains('20 recent items'));

    await _tapKey(tester, 'ai-notice-continue');
    expect(ai.requests, hasLength(1));
    expect(_account(tester).state.aiNoticeSeen, aiNoticeId);

    await _ask(tester, 'eggs');
    expect(find.byKey(const ValueKey('ai-notice')), findsNothing);
    expect(ai.requests, hasLength(2));
  });

  testWidgets('on the home an add applies at once: "Added to" with Undo, and '
      'Undo takes it back', (tester) async {
    final FakeAiService ai = FakeAiService()
      ..answers.add(
        _calls([
          _add(_grocery, ['Milk', 'Eggs']),
        ]),
      );
    final FirestoreListStore store = await _pump(tester, ai);

    await _ask(tester, 'milk and eggs');
    expect(_titles(store, _grocery), containsAll(['Milk', 'Eggs']));
    expect(find.textContaining('Added to'), findsOneWidget);
    expect(tester.widget<TextField>(_field).controller!.text, isEmpty);

    await _tapKey(tester, 'ai-undo');
    expect(_titles(store, _grocery), isNot(contains('Milk')));
    expect(find.text('Undone'), findsOneWidget);
  });

  testWidgets('requests carry today, AI-on list summaries only, and the open '
      'list with its items', (tester) async {
    final List<ListDefinition> lists = [
      for (final ListDefinition list in starterLists())
        list.id == _journal ? _aiOff(list) : list,
    ];
    final DateTime now = DateTime.now();
    final FakeAiService ai = FakeAiService()
      ..answers.addAll([
        _calls([
          const AiToolCall('reply', {'text': 'Fine.'}),
        ]),
        _calls([
          const AiToolCall('reply', {'text': 'Fine.'}),
        ]),
      ]);
    await _pump(
      tester,
      ai,
      lists: lists,
      items: [
        for (int i = 0; i < 25; i++)
          ListItem(
            id: 'g$i',
            listId: _grocery,
            values: {'title': 'Item $i'},
            createdAt: now.toUtc(),
            updatedAt: now.toUtc().add(Duration(minutes: i)),
          ),
      ],
    );

    await _ask(tester, 'what is open');
    expect(find.text('Fine.'), findsOneWidget);
    final Map<String, Object?> home = ai.requests.single.toJson();
    expect(home['openList'], isNull);
    expect(
      home['today'],
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}',
    );
    final List<Map<String, Object?>> summaries = [
      for (final Object? list in home['lists']! as List)
        list! as Map<String, Object?>,
    ];
    expect(summaries.map((list) => list['id']), isNot(contains(_journal)));
    expect(summaries.map((list) => list['id']), contains(_grocery));
    expect(summaries.every((list) => list['aiAllowed'] == true), isTrue);
    await _tapKey(tester, 'ai-close');

    await _openList(tester, _grocery);
    await _ask(tester, 'what is open');
    final Map<String, Object?> open =
        ai.requests.last.toJson()['openList']! as Map<String, Object?>;
    expect((open['definition']! as Map)['id'], _grocery);
    final List<Object?> sent = open['items']! as List<Object?>;
    expect(sent, hasLength(20));
    // The most recently changed first.
    expect((sent.first! as Map)['id'], 'g24');
  });

  testWidgets('the bar is absent on a list with AI off and under a sheet', (
    tester,
  ) async {
    final List<ListDefinition> lists = [
      for (final ListDefinition list in starterLists())
        list.id == _journal ? _aiOff(list) : list,
    ];
    await _pump(tester, FakeAiService(), lists: lists);
    expect(_field, findsOneWidget);

    await _openList(tester, _journal);
    expect(_field.hitTestable(), findsNothing);

    await _openList(tester, _grocery);
    expect(_field.hitTestable(), findsOneWidget);
    // The add button's item sheet hides the hub and the bar.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(_field.hitTestable(), findsNothing);
  });

  testWidgets('deletes, edits and structure changes preview; Apply saves '
      'through the store and Undo restores the snapshot', (tester) async {
    final DateTime now = DateTime.now().toUtc();
    final FakeAiService ai = FakeAiService()
      ..answers.addAll([
        _calls([
          const AiToolCall('delete_items', {
            'listId': _grocery,
            'ids': ['g1'],
          }),
        ]),
        _calls([
          const AiToolCall('patch_list', {
            'listId': _grocery,
            'ops': [
              {
                'op': 'addField',
                'field': {'key': 'price', 'type': 'number', 'label': 'Price'},
              },
            ],
          }),
        ]),
      ]);
    final FirestoreListStore store = await _pump(
      tester,
      ai,
      items: [
        ListItem(
          id: 'g1',
          listId: _grocery,
          values: {'title': 'Bread'},
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    await _openList(tester, _grocery);

    await _ask(tester, 'remove bread');
    expect(find.textContaining('delete Bread'), findsOneWidget);
    expect(_titles(store, _grocery), contains('Bread'));
    await _tapKey(tester, 'ai-apply');
    expect(_titles(store, _grocery), isNot(contains('Bread')));
    await _tapKey(tester, 'ai-undo');
    expect(_titles(store, _grocery), contains('Bread'));

    await _ask(tester, 'add a price column');
    expect(find.textContaining('add the field Price'), findsOneWidget);
    await _tapKey(tester, 'ai-apply');
    expect(
      store.current.definition(_grocery)!.fields.map((f) => f.key),
      contains('price'),
    );
    expect(find.textContaining('Changed'), findsOneWidget);
    await _tapKey(tester, 'ai-undo');
    expect(
      store.current.definition(_grocery)!.fields.map((f) => f.key),
      isNot(contains('price')),
    );
  });

  testWidgets('Undo goes away, changing nothing, when what it touched changes '
      '(Q-52)', (tester) async {
    final FakeAiService ai = FakeAiService()
      ..answers.add(
        _calls([
          _add(_grocery, ['Milk']),
        ]),
      );
    final FirestoreListStore store = await _pump(tester, ai);

    await _ask(tester, 'milk');
    final ListItem milk = store.current
        .itemsOf(_grocery)
        .firstWhere((item) => item['title'] == 'Milk');
    await tester.runAsync(
      () => store.apply(
        ListChanges(
          saved: [
            ListItem(
              id: milk.id,
              listId: milk.listId,
              values: {...milk.values, 'title': 'Oat milk'},
              createdAt: milk.createdAt,
              updatedAt: DateTime.now().toUtc(),
            ),
          ],
        ),
      ),
    );
    await settle(tester);

    expect(find.byKey(const ValueKey('ai-undo')), findsNothing);
    expect(_titles(store, _grocery), contains('Oat milk'));
  });

  testWidgets('an add to another list than the open one previews (L12)', (
    tester,
  ) async {
    final FakeAiService ai = FakeAiService()
      ..answers.add(
        _calls([
          _add(_tasks, ['Call the bank']),
        ]),
      );
    final FirestoreListStore store = await _pump(tester, ai);
    await _openList(tester, _grocery);

    await _ask(tester, 'call the bank');
    expect(find.byKey(const ValueKey('ai-apply')), findsOneWidget);
    expect(_titles(store, _tasks), isNot(contains('Call the bank')));
    await _tapKey(tester, 'ai-apply');
    expect(_titles(store, _tasks), contains('Call the bank'));
  });

  testWidgets('"which list?" shows list chips; a chip sends the request again '
      'with that list open', (tester) async {
    final FakeAiService ai = FakeAiService()
      ..answers.addAll([
        _calls([
          const AiToolCall('choose_list', {
            'question': 'Grocery or Tasks?',
            'candidates': [_grocery, _tasks],
          }),
        ]),
        _calls([
          _add(_tasks, ['New running shoes']),
        ]),
      ]);
    final FirestoreListStore store = await _pump(tester, ai);

    await _ask(tester, 'new running shoes');
    expect(find.text('Grocery or Tasks?'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-chip-$_grocery')), findsOneWidget);
    await _tapKey(tester, 'ai-chip-$_tasks');

    expect(ai.requests, hasLength(2));
    expect(ai.requests.last.prompt, 'new running shoes');
    expect(ai.requests.last.openList!.id, _tasks);
    // The pick is final: the AI is told not to ask again (Q-45).
    expect(ai.requests.first.toJson().containsKey('chosenList'), isFalse);
    expect(ai.requests.last.toJson()['chosenList'], isTrue);
    expect(_titles(store, _tasks), contains('New running shoes'));
  });

  testWidgets('device ListErrors go back once for self-correction', (
    tester,
  ) async {
    final FakeAiService ai = FakeAiService()
      ..answers.addAll([
        _calls([
          _add(_grocery, ['Milk'], field: 'name'),
        ]),
        _calls([
          _add(_grocery, ['Milk']),
        ]),
      ]);
    final FirestoreListStore store = await _pump(tester, ai);

    await _ask(tester, 'milk');
    expect(ai.requests, hasLength(2));
    final Map<String, Object?> correction =
        ai.requests.last.toJson()['correction']! as Map<String, Object?>;
    expect(
      (correction['errors']! as List).any((error) => '$error'.contains('name')),
      isTrue,
    );
    expect((correction['toolCalls']! as List).single, isA<Map>());
    expect(_titles(store, _grocery), contains('Milk'));
  });

  testWidgets('still invalid after the correction: the errors show and '
      'nothing is applied', (tester) async {
    final FakeAiService ai = FakeAiService()
      ..answers.addAll([
        _calls([
          _add(_grocery, ['Milk'], field: 'name'),
        ]),
        _calls([
          _add(_grocery, ['Milk'], field: 'name'),
        ]),
      ]);
    final FirestoreListStore store = await _pump(tester, ai);

    await _ask(tester, 'milk');
    expect(ai.requests, hasLength(2));
    expect(find.textContaining('do not fit the list'), findsOneWidget);
    expect(_titles(store, _grocery), isNot(contains('Milk')));
  });

  testWidgets('declines and refusals show translated messages', (tester) async {
    final FakeAiService ai = FakeAiService();
    await _pump(tester, ai);
    final Map<Object, String> expected = {
      const AiAnswer(requestId: 'r', toolCalls: [], declineReason: 'offTopic'):
          'I can only help with your lists.',
      const AiAnswer(
        requestId: 'r',
        toolCalls: [],
        declineReason: 'noValidTool',
      ): 'The answer could not be used. Try other words.',
      const AiRefusal('aiNotAllowed'): 'AI is turned off for this list.',
      const AiRefusal('outputTooLong'):
          'The answer was too long. Try a shorter request.',
      const AiRefusal('dailyCount'):
          'You have reached today’s limit of AI requests.',
      const AiRefusal('globalBudget'): 'The AI is paused until tomorrow.',
      const AiRefusal('appCheck'): 'This account or app may not use the AI.',
      const AiRefusal('provider'):
          'The AI is not available right now. Try again later.',
      AiRefusal.of({'reason': 'provider', 'kind': 'billing'}, 'unavailable'):
          'The AI provider account needs attention: check its key or balance.',
      AiRefusal.of({'reason': 'provider', 'kind': 'network'}, 'unavailable'):
          'The AI is not available right now. Try again later.',
    };
    for (final MapEntry<Object, String> entry in expected.entries) {
      ai.answers.add(entry.key);
      await _ask(tester, 'something');
      expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
      await _tapKey(tester, 'ai-close');
    }
  });

  testWidgets('a tap on the bar after a decline opens it (T-19 unit 8)', (
    tester,
  ) async {
    final FakeAiService ai = FakeAiService()
      ..answers.add(
        const AiAnswer(
          requestId: 'r',
          toolCalls: [],
          declineReason: 'offTopic',
        ),
      );
    await _pump(tester, ai);
    await _ask(tester, 'weather in Paris?');
    expect(find.text('I can only help with your lists.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-bar')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('ai-bar-field'), skipOffstage: false),
          )
          .focusNode!
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('an answer the function left part out of says so (L3)', (
    tester,
  ) async {
    final FakeAiService ai = FakeAiService()
      ..answers.add(
        AiAnswer(
          requestId: 'r',
          toolCalls: [
            _add(_grocery, ['Milk']),
          ],
          droppedTools: 1,
        ),
      )
      ..answers.add(
        _calls([
          _add(_grocery, ['Eggs']),
        ]),
      );
    final FirestoreListStore store = await _pump(tester, ai);

    await _ask(tester, 'milk and a price column');
    expect(find.textContaining('Added to'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-partial')), findsOneWidget);
    expect(_titles(store, _grocery), contains('Milk'));
    await _tapKey(tester, 'ai-undo');
    expect(find.byKey(const ValueKey('ai-partial')), findsNothing);

    await _ask(tester, 'eggs');
    expect(find.byKey(const ValueKey('ai-partial')), findsNothing);
  });

  test('AiAnswer reads droppedTools, 0 when absent or not a count', () {
    expect(AiAnswer.fromJson({'droppedTools': 2}).droppedTools, 2);
    expect(AiAnswer.fromJson({}).droppedTools, 0);
    expect(AiAnswer.fromJson({'droppedTools': 'x'}).droppedTools, 0);
  });

  testWidgets('"Describe a new list" asks for a new list, previews it, '
      'creates and opens it; Undo deletes it', (tester) async {
    final FakeAiService ai = FakeAiService()
      ..answers.add(_calls([AiToolCall('create_list', _runLog())]));
    final FirestoreListStore store = await _pump(tester, ai);

    await tester.tap(_hub);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('launcher-add')));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'template-describe');
    expect(find.text('Describe the list'), findsOneWidget);

    await _ask(tester, 'my runs');
    expect(ai.requests.single.prompt, 'my runs');
    expect(ai.requests.single.newList, isTrue);
    expect(ai.requests.single.openList, isNull);
    expect(
      find.textContaining('New list Runs: Route, Day, Distance (km)'),
      findsOneWidget,
    );
    await _tapKey(tester, 'ai-apply');

    final ListDefinition runs = store.current.definitions.firstWhere(
      (list) => list.name == 'Runs',
    );
    expect(find.text('Created Runs'), findsOneWidget);
    await _tapKey(tester, 'ai-undo');
    expect(store.current.definition(runs.id), isNull);
  });

  testWidgets('Back closes the panel first, then goes back as before', (
    tester,
  ) async {
    final FakeAiService ai = FakeAiService();
    await _pump(tester, ai);

    // On the home Back would leave the app; with the panel open it only
    // closes the panel.
    ai.answers.add(
      _calls([
        const AiToolCall('reply', {'text': 'On the home.'}),
      ]),
    );
    await _ask(tester, 'hello');
    expect(find.text('On the home.'), findsOneWidget);
    final List<MethodCall> platform = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platform.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('On the home.'), findsNothing);
    expect(
      platform.where((call) => call.method == 'SystemNavigator.pop'),
      isEmpty,
    );

    await _openList(tester, _grocery);
    ai.answers.add(
      _calls([
        const AiToolCall('reply', {'text': 'Grocery has 3 items.'}),
      ]),
    );
    await _ask(tester, 'how many');
    expect(find.text('Grocery has 3 items.'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Grocery has 3 items.'), findsNothing);
    // Still on the list: the next Back goes home.
    expect(find.textContaining('Add to Grocery'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Add or change'), findsOneWidget);
  });
  // The bar's rules at rest and focused (owner, 2026-11-03,
  // docs/INTERACTIONS.md "AI bar").
  group('T-19 unit 8', () {
    ListItem item(String id, String title) {
      final DateTime now = DateTime.now().toUtc();
      return ListItem(
        id: id,
        listId: _grocery,
        values: {'title': title},
        createdAt: now,
        updatedAt: now,
      );
    }

    testWidgets('from the home, items named by their words are found on the '
        'phone: one request, a preview, then deleted (Q-39)', (tester) async {
      final FakeAiService ai = FakeAiService()
        ..answers.add(
          _calls([
            const AiToolCall('delete_items', {
              'listId': _grocery,
              'match': ['milk', 'eggs'],
            }),
          ]),
        );
      final FirestoreListStore store = await _pump(
        tester,
        ai,
        items: [item('g1', 'Milk'), item('g2', 'Eggs'), item('g3', 'Bread')],
      );

      await _ask(tester, 'remove milk and eggs');
      expect(ai.requests, hasLength(1));
      expect(find.textContaining('delete'), findsOneWidget);
      await _tapKey(tester, 'ai-apply');
      expect(_titles(store, _grocery), ['Bread']);
    });

    testWidgets('an unclear match sends the request again with that list\'s '
        'items (Q-39 D)', (tester) async {
      final FakeAiService ai = FakeAiService()
        ..answers.addAll([
          _calls([
            const AiToolCall('delete_items', {
              'listId': _grocery,
              'match': ['the dairy stuff'],
            }),
          ]),
          _calls([
            const AiToolCall('delete_items', {
              'listId': _grocery,
              'ids': ['g1', 'g2'],
            }),
          ]),
        ]);
      final FirestoreListStore store = await _pump(
        tester,
        ai,
        items: [item('g1', 'Milk'), item('g2', 'Cheese'), item('g3', 'Bread')],
      );

      await _ask(tester, 'remove the dairy stuff');
      expect(ai.requests, hasLength(2));
      expect(ai.requests.first.openList, isNull);
      expect(ai.requests.last.openList!.id, _grocery);
      expect(ai.requests.last.openItems, hasLength(3));
      await _tapKey(tester, 'ai-apply');
      expect(_titles(store, _grocery), ['Bread']);
    });

    testWidgets('the first Apply offers auto-apply; after a yes changes apply '
        'at once with Undo, and Settings shows it (Q-40)', (tester) async {
      final FakeAiService ai = FakeAiService()
        ..answers.addAll([
          _calls([
            const AiToolCall('delete_items', {
              'listId': _grocery,
              'ids': ['g1'],
            }),
          ]),
          _calls([
            const AiToolCall('delete_items', {
              'listId': _grocery,
              'ids': ['g2'],
            }),
          ]),
        ]);
      final FirestoreListStore store = await _pump(
        tester,
        ai,
        items: [item('g1', 'Milk'), item('g2', 'Eggs')],
      );

      await _ask(tester, 'remove milk');
      await _tapKey(tester, 'ai-apply');
      expect(find.byKey(const ValueKey('ai-auto-apply-offer')), findsOneWidget);
      // The offer waits for an answer.
      await tester.pump(AiBarController.doneFor * 2);
      expect(find.byKey(const ValueKey('ai-auto-apply-offer')), findsOneWidget);
      await _tapKey(tester, 'ai-auto-apply-yes');
      expect(_account(tester).state.aiAutoApply, isTrue);

      await _ask(tester, 'remove eggs');
      expect(find.byKey(const ValueKey('ai-apply')), findsNothing);
      expect(_titles(store, _grocery), isEmpty);
      expect(find.byKey(const ValueKey('ai-undo')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-auto-apply-offer')), findsNothing);
    });

    testWidgets('"Not now" keeps the preview and is not asked again', (
      tester,
    ) async {
      final FakeAiService ai = FakeAiService()
        ..answers.addAll([
          _calls([
            const AiToolCall('delete_items', {
              'listId': _grocery,
              'ids': ['g1'],
            }),
          ]),
          _calls([
            const AiToolCall('delete_items', {
              'listId': _grocery,
              'ids': ['g2'],
            }),
          ]),
        ]);
      await _pump(tester, ai, items: [item('g1', 'Milk'), item('g2', 'Eggs')]);
      await _ask(tester, 'remove milk');
      await _tapKey(tester, 'ai-apply');
      await _tapKey(tester, 'ai-auto-apply-no');
      await _ask(tester, 'remove eggs');
      expect(find.byKey(const ValueKey('ai-apply')), findsOneWidget);
      await _tapKey(tester, 'ai-apply');
      expect(find.byKey(const ValueKey('ai-auto-apply-offer')), findsNothing);
    });

    testWidgets('a request naming a list with AI off says so and sends '
        'nothing; a new list named like it is not made (Q-41)', (tester) async {
      final List<ListDefinition> lists = [
        for (final ListDefinition list in starterLists())
          list.id == _grocery ? _aiOff(list) : list,
      ];
      final FakeAiService ai = FakeAiService()
        ..answers.add(
          _calls([
            AiToolCall('create_list', {
              'list': {..._runLog()['list']! as Map, 'name': 'Grocery'},
            }),
          ]),
        );
      await _pump(tester, ai, lists: lists);

      await _ask(tester, 'add milk to "Grocery"');
      expect(ai.requests, isEmpty);
      expect(find.text('"Grocery" has AI turned off.'), findsOneWidget);
      await _tapKey(tester, 'ai-close');

      await _ask(tester, 'I need a shopping list');
      expect(ai.requests, hasLength(1));
      expect(find.text('"Grocery" has AI turned off.'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-apply')), findsNothing);
    });

    testWidgets('a possible mention of an AI-off list offers the other lists; '
        'Send goes without it and waits for Apply (Q-62)', (tester) async {
      final List<ListDefinition> lists = [
        for (final ListDefinition list in starterLists())
          list.id == _grocery ? _aiOff(list) : list,
      ];
      final FakeAiService ai = FakeAiService()
        ..answers.add(
          _calls([
            _add(_tasks, ['Call about the grocery order']),
          ]),
        );
      await _pump(tester, ai, lists: lists);

      await _ask(tester, 'call about the grocery order');
      expect(ai.requests, isEmpty);
      expect(find.byKey(const ValueKey('ai-offer')), findsOneWidget);

      // Cancel sends nothing and the words stay.
      await _tapKey(tester, 'ai-cancel');
      expect(ai.requests, isEmpty);
      expect(find.byKey(const ValueKey('ai-offer')), findsNothing);

      await tester.tap(_send);
      await settle(tester);
      expect(find.byKey(const ValueKey('ai-offer')), findsOneWidget);
      await _tapKey(tester, 'ai-offer-send');
      await settle(tester);
      expect(ai.requests, hasLength(1));
      expect(
        ai.requests.single.lists.map((list) => list.id),
        isNot(contains(_grocery)),
      );
      expect(find.byKey(const ValueKey('ai-apply')), findsOneWidget);
    });

    testWidgets('"Which items?" shows the items as buttons; the picked ones '
        'are deleted with Undo (Q-42)', (tester) async {
      final FakeAiService ai = FakeAiService()
        ..answers.add(
          _calls([
            const AiToolCall('choose_items', {
              'question': 'Which milk?',
              'listId': _grocery,
              'candidates': ['g1', 'g2'],
            }),
          ]),
        );
      final FirestoreListStore store = await _pump(
        tester,
        ai,
        items: [
          item('g1', 'Milk'),
          item('g2', 'Oat milk'),
          item('g3', 'Bread'),
        ],
      );
      await _openList(tester, _grocery);

      await _ask(tester, 'remove the milk');
      expect(find.text('Which milk?'), findsOneWidget);
      final Finder apply = find.byKey(const ValueKey('ai-apply'));
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);
      await _tapKey(tester, 'ai-item-g2');
      await _tapKey(tester, 'ai-apply');
      expect(ai.requests, hasLength(1));
      expect(_titles(store, _grocery), ['Milk', 'Bread']);
      await _tapKey(tester, 'ai-undo');
      expect(_titles(store, _grocery), containsAll(['Milk', 'Oat milk']));
    });

    testWidgets('typing after a reply answers it: the reply stays up and the '
        'request carries it; Close makes a fresh one (Q-42)', (tester) async {
      final FakeAiService ai = FakeAiService()
        ..answers.addAll([
          _calls([
            const AiToolCall('reply', {'text': 'Milk or eggs?'}),
          ]),
          _calls([
            const AiToolCall('reply', {'text': 'Fine.'}),
          ]),
          _calls([
            const AiToolCall('reply', {'text': 'Fine again.'}),
          ]),
        ]);
      await _pump(tester, ai);

      await _ask(tester, 'remove the dairy');
      expect(find.text('Milk or eggs?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai-bar')));
      await tester.pumpAndSettle();
      expect(find.text('Milk or eggs?'), findsOneWidget);
      expect(find.text('Your answer'), findsOneWidget);
      await tester.enterText(_field, 'milk');
      await tester.pump();
      await tester.tap(_send);
      await settle(tester);
      final Map<String, Object?> answer = ai.requests[1].toJson();
      expect(answer['followUp'], {
        'prompt': 'remove the dairy',
        'reply': 'Milk or eggs?',
      });

      // A new reply; its Close makes the next request a fresh one.
      await tester.tap(find.byKey(const ValueKey('ai-bar')));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'ai-close');
      expect(find.text('Your answer'), findsNothing);
      await tester.enterText(_field, 'something else');
      await tester.pump();
      await tester.tap(_send);
      await settle(tester);
      expect(ai.requests[2].toJson().containsKey('followUp'), isFalse);
    });

    testWidgets('the AI question stays up while the answer is typed, '
        'and the answer goes out with it (owner, 2026-11-04)', (tester) async {
      final FakeAiService ai = FakeAiService()
        ..answers.addAll([
          _calls([
            const AiToolCall('reply', {'text': 'Milk or eggs?'}),
          ]),
          _calls([
            const AiToolCall('choose_list', {
              'question': 'Add to Tasks, or start a new list?',
              'candidates': [_tasks],
              'newList': true,
            }),
          ]),
          _calls([
            const AiToolCall('reply', {'text': 'Fine.'}),
          ]),
        ]);
      await _pump(tester, ai);
      final Finder bar = find.byKey(const ValueKey('ai-bar'));

      // A question as a reply.
      await _ask(tester, 'remove the dairy');
      await tester.tap(bar);
      await tester.pumpAndSettle();
      expect(find.text('Milk or eggs?'), findsOneWidget);
      expect(tester.widget<TextField>(_field).focusNode!.hasFocus, isTrue);
      await tester.enterText(_field, 'milk');
      await tester.pump();
      await tester.tap(_send);
      await settle(tester);
      expect(ai.requests[1].toJson()['followUp'], {
        'prompt': 'remove the dairy',
        'reply': 'Milk or eggs?',
      });

      // A question with buttons: still there while typing, buttons work.
      await tester.tap(bar);
      await tester.pumpAndSettle();
      expect(find.text('Add to Tasks, or start a new list?'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-chip-$_tasks')), findsOneWidget);
      // The raised hub keeps clear of the question and its buttons.
      final Rect panel = tester.getRect(find.byKey(const ValueKey('ai-panel')));
      expect(
        tester.getRect(find.byKey(const ValueKey('launcher-hub'))).bottom,
        lessThanOrEqualTo(panel.top),
      );
      await tester.enterText(_field, 'tasks please');
      await tester.pump();
      await tester.tap(_send);
      await settle(tester);
      expect(ai.requests[2].toJson()['followUp'], {
        'prompt': 'remove the dairy',
        'reply': 'Add to Tasks, or start a new list?',
        'earlier': [
          {'reply': 'Milk or eggs?', 'answer': 'milk'},
        ],
      });
    });

    testWidgets('a tap anywhere on a draft bar opens it', (tester) async {
      await _pump(tester, FakeAiService());
      final Finder bar = find.byKey(const ValueKey('ai-bar'));
      await tester.tap(bar);
      await tester.pumpAndSettle();
      await tester.enterText(_field, 'eggs');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-bar-draft')), findsOneWidget);
      // Right of the short draft text, where the old draft line did not
      // reach.
      final Rect rect = tester.getRect(bar);
      await tester.tapAt(Offset(rect.right - 80, rect.center.dy));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_field).focusNode!.hasFocus, isTrue);
    });

    testWidgets('"New list" next to the lists asks again for a new list; '
        'the request carries the ask-first setting (Q-43)', (tester) async {
      final FakeAiService ai = FakeAiService()
        ..answers.addAll([
          _calls([
            const AiToolCall('choose_list', {
              'question': 'Add to Tasks, or start a new list?',
              'candidates': [_tasks],
              'newList': true,
            }),
          ]),
          _calls([
            const AiToolCall('reply', {'text': 'Fine.'}),
          ]),
        ]);
      await _pump(tester, ai);
      await _account(tester).setAiAskLevel(AiAskLevel.more);

      await _ask(tester, 'dinner tomorrow');
      expect(ai.requests.first.toJson()['askLevel'], 'more');
      expect(find.byKey(const ValueKey('ai-chip-$_tasks')), findsOneWidget);
      // Typing had started; a button answers instead, so the request does
      // not quote the question.
      await tester.tap(find.byKey(const ValueKey('ai-bar')));
      await tester.pumpAndSettle();
      expect(find.text('Your answer'), findsOneWidget);
      await _tapKey(tester, 'ai-chip-new');
      expect(ai.requests.last.followUp, isNull);
      expect(ai.requests, hasLength(2));
      expect(ai.requests.last.prompt, 'dinner tomorrow');
      expect(ai.requests.last.newList, isTrue);
      expect(ai.requests.last.openList, isNull);
      expect(ai.requests.last.askLevel, 'more');
    });

    testWidgets('with auto-apply on, an add the AI moves away from the open '
        'list still waits for Apply, unless the request named that list '
        '(Q-45)', (tester) async {
      final FakeAiService ai = FakeAiService()
        ..answers.addAll([
          _calls([
            _add(_grocery, ['Beef']),
          ]),
          _calls([
            _add(_grocery, ['Broccoli']),
          ]),
          _calls([
            _add(_tasks, ['Defrost beef']),
          ]),
        ]);
      final FirestoreListStore store = await _pump(tester, ai);
      await _account(tester).setAiAutoApply(true);
      await _openList(tester, _tasks);

      // Not named: the preview stays, with auto-apply on.
      await _ask(tester, 'beef and broccoli');
      expect(find.byKey(const ValueKey('ai-apply')), findsOneWidget);
      expect(_titles(store, _grocery), isNot(contains('Beef')));
      await _tapKey(tester, 'ai-cancel');

      // Named: auto-apply applies it.
      await _ask(tester, 'add broccoli to grocery');
      expect(find.byKey(const ValueKey('ai-apply')), findsNothing);
      expect(_titles(store, _grocery), contains('Broccoli'));

      // The open list itself: applied at once as before.
      await _ask(tester, 'defrost beef');
      expect(_titles(store, _tasks), contains('Defrost beef'));
    });

    testWidgets('after Undo the request comes back as a draft, not focused; '
        'one Backspace at its end clears it', (tester) async {
      final FakeAiService ai = FakeAiService()
        ..answers.add(
          _calls([
            _add(_grocery, ['Milk']),
          ]),
        );
      await _pump(tester, ai);
      await _ask(tester, 'add milk');
      await _tapKey(tester, 'ai-undo');

      final TextField field = tester.widget<TextField>(
        find.byKey(const ValueKey('ai-bar-field'), skipOffstage: false),
      );
      expect(field.controller!.text, 'add milk');
      expect(field.focusNode!.hasFocus, isFalse);
      expect(find.byKey(const ValueKey('ai-bar-draft')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ai-bar-draft')));
      await tester.pumpAndSettle();
      expect(field.focusNode!.hasFocus, isTrue);
      // What a soft keyboard's Backspace does at the end of the text.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'add mil',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      await tester.pump();
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('Delete at the end clears the refilled text; an edit makes '
        'Backspace ordinary again', (tester) async {
      final FakeAiService ai = FakeAiService()
        ..answers.addAll([
          _calls([
            _add(_grocery, ['Milk']),
          ]),
          _calls([
            _add(_grocery, ['Milk']),
          ]),
        ]);
      await _pump(tester, ai);
      await _ask(tester, 'add milk');
      await _tapKey(tester, 'ai-undo');
      await tester.tap(find.byKey(const ValueKey('ai-bar-draft')));
      await tester.pumpAndSettle();
      // The cursor at the end, as a tap right of the text puts it.
      final TextField field = tester.widget<TextField>(_field);
      field.controller!.selection = const TextSelection.collapsed(offset: 8);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(field.controller!.text, isEmpty);

      await _ask(tester, 'add milk');
      await _tapKey(tester, 'ai-undo');
      await tester.tap(find.byKey(const ValueKey('ai-bar-draft')));
      await tester.pumpAndSettle();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'add milks',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'add milk',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      await tester.pump();
      expect(field.controller!.text, 'add milk');
    });
  });

  testWidgets('a rename through the bar shows on the open list at once', (
    tester,
  ) async {
    final FakeAiService ai = FakeAiService()
      ..answers.add(
        _calls([
          const AiToolCall('patch_list', {
            'listId': _tasks,
            'ops': [
              {'op': 'setListInfo', 'name': 'Chores'},
            ],
          }),
        ]),
      );
    await _pump(tester, ai);
    await _openList(tester, _tasks);
    expect(find.text('Chores'), findsNothing);
    await _ask(tester, 'rename this list to Chores');
    await _tapKey(tester, 'ai-apply');
    expect(find.text('Chores'), findsWidgets);
  });

  group('focus, the raised hub and the draft', () {
    final Finder bar = find.byKey(const ValueKey('ai-bar'));
    final Finder draft = find.byKey(const ValueKey('ai-bar-draft'));
    const Offset restHub = Offset(360 - 56, 780 - 72);

    Future<void> focusBar(WidgetTester tester) async {
      await tester.tap(bar);
      await tester.pumpAndSettle();
    }

    testWidgets('a tap grows the bar to full width and two lines and raises '
        'the hub just above it; leaving brings both back', (tester) async {
      await _pump(tester, FakeAiService());
      final Rect rest = tester.getRect(bar);
      expect(rest.height, PromptBarGeometry.height);
      expect(rest.right, lessThan(restHub.dx - 48));
      expect(tester.getCenter(_hub), restHub);

      await focusBar(tester);
      final Rect focused = tester.getRect(bar);
      expect(focused.left, PromptBarGeometry.margin);
      expect(focused.right, 360 - PromptBarGeometry.margin);
      expect(focused.height, greaterThan(PromptBarGeometry.height));
      expect(tester.widget<TextField>(_field).minLines, 2);
      expect(tester.widget<TextField>(_field).maxLines, 4);
      final Offset raised = tester.getCenter(_hub);
      expect(raised.dx, restHub.dx);
      expect(raised.dy, lessThan(focused.top));
      expect(raised.dy, greaterThan(focused.top - 80));

      // Back leaves the bar first (the keyboard may already be gone).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.getRect(bar), rest);
      expect(tester.getCenter(_hub), restHub);
      expect(find.text('Add or change'), findsOneWidget);
    });

    testWidgets('typing grows the bar to four lines at most; the 1000 '
        'character cap stays', (tester) async {
      await _pump(tester, FakeAiService());
      await focusBar(tester);
      await tester.enterText(_field, 'one\ntwo');
      await tester.pumpAndSettle();
      final double two = tester.getRect(bar).height;
      await tester.enterText(_field, 'one\ntwo\nthree\nfour');
      await tester.pumpAndSettle();
      final double four = tester.getRect(bar).height;
      expect(four, greaterThan(two));
      // The raised hub keeps clear of the taller bar.
      expect(
        tester.getCenter(_hub).dy + 48,
        lessThanOrEqualTo(tester.getRect(bar).top),
      );
      await tester.enterText(_field, 'a\nb\nc\nd\ne\nf\ng');
      await tester.pumpAndSettle();
      expect(tester.getRect(bar).height, four);
      expect(tester.widget<TextField>(_field).maxLength, 1000);
    });

    testWidgets('leaving keeps the text as a one-line draft ending in "…"; a '
        'tap brings it all back', (tester) async {
      await _pump(tester, FakeAiService());
      await focusBar(tester);
      const String long =
          'milk, eggs, bread, butter, cheese, apples, pears and a lot more';
      await tester.enterText(_field, long);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(tester.getRect(bar).height, PromptBarGeometry.height);
      final Text shown = tester.widget<Text>(draft);
      expect(shown.data, long);
      expect(shown.maxLines, 1);
      expect(shown.overflow, TextOverflow.ellipsis);

      await tester.tap(draft);
      await tester.pumpAndSettle();
      expect(draft, findsNothing);
      expect(tester.widget<TextField>(_field).controller!.text, long);
      expect(tester.widget<TextField>(_field).focusNode!.hasFocus, isTrue);
    });

    testWidgets('closing the keyboard leaves the bar', (tester) async {
      await _pump(tester, FakeAiService());
      await focusBar(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.getRect(bar).height, PromptBarGeometry.height);
      expect(tester.getCenter(_hub), restHub);
    });

    testWidgets('sending leaves the bar', (tester) async {
      final FakeAiService ai = FakeAiService()
        ..answers.add(
          _calls([
            const AiToolCall('reply', {'text': 'Fine.'}),
          ]),
        );
      await _pump(tester, ai);
      await _ask(tester, 'hello');
      expect(find.text('Fine.'), findsOneWidget);
      expect(tester.getRect(bar).height, PromptBarGeometry.height);
      expect(tester.getCenter(_hub), restHub);
    });

    testWidgets('a tap outside leaves the bar and still does its own job', (
      tester,
    ) async {
      final DateTime now = DateTime.now().toUtc();
      await _pump(
        tester,
        FakeAiService(),
        items: [
          ListItem(
            id: 'g1',
            listId: _grocery,
            values: {'title': 'Bread'},
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      await _openList(tester, _grocery);
      await focusBar(tester);
      await tester.enterText(_field, 'a draft');
      await tester.pumpAndSettle();

      // The list's add button, while the keyboard is up.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      // The new-item sheet opened (it hides the bar) and the bar was left.
      expect(_field.hitTestable(), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('ai-bar-field'), skipOffstage: false),
            )
            .focusNode!
            .hasFocus,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('ai-bar-field'), skipOffstage: false),
            )
            .controller!
            .text,
        'a draft',
      );
    });

    testWidgets('pressing the raised hub opens the dial there and keeps the '
        'draft; the hub comes down when the dial closes; another list keeps '
        'the draft', (tester) async {
      await _pump(tester, FakeAiService());
      await focusBar(tester);
      await tester.enterText(_field, 'eggs');
      await tester.pumpAndSettle();
      final Offset raised = tester.getCenter(_hub);
      expect(raised.dy, lessThan(restHub.dy));

      // A quick tap: the dial stays open (tap mode).
      await tester.tap(_hub);
      await tester.pumpAndSettle();
      expect(tester.getCenter(_hub), raised);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('ai-bar-field'), skipOffstage: false),
            )
            .focusNode!
            .hasFocus,
        isFalse,
      );
      expect(draft, findsOneWidget);

      // Picking a list closes the dial; the hub comes down, the draft stays
      // and the bar now targets that list.
      await tester.tap(find.byKey(const ValueKey('launcher-note-$_grocery')));
      await settle(tester);
      expect(tester.getCenter(_hub), restHub);
      expect(tester.widget<Text>(draft).data, 'eggs');
      await tester.tap(draft);
      await tester.pumpAndSettle();
      await tester.enterText(_field, '');
      await tester.pumpAndSettle();
      expect(find.textContaining('Add to Grocery'), findsOneWidget);
    });

    testWidgets('on a wide screen the focused bar fits beside the hub and '
        'nothing moves', (tester) async {
      await _pump(tester, FakeAiService(), size: const Size(1000, 780));
      final Offset hub = tester.getCenter(_hub);
      final Rect rest = tester.getRect(bar);
      expect(rest.width, PromptBarGeometry.maxWidth);
      await focusBar(tester);
      final Rect focused = tester.getRect(bar);
      expect(focused.left, rest.left);
      expect(focused.width, PromptBarGeometry.maxWidth);
      expect(focused.height, greaterThan(rest.height));
      expect(tester.getCenter(_hub), hub);
    });
  });
}
