import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/ai/ai_bar_controller.dart';
import 'package:hybrid_note/ai/ai_service.dart';
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

Future<FirestoreListStore> _pump(
  WidgetTester tester,
  FakeAiService ai, {
  bool noticeSeen = true,
  List<ListDefinition>? lists,
  List<ListItem> items = const [],
}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    if (noticeSeen) AiBarController.noticeKey: aiNoticeId,
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

Future<void> _ask(WidgetTester tester, String text) async {
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
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(AiBarController.noticeKey), aiNoticeId);

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

  testWidgets('an undo is refused, changing nothing, when the list changed '
      'since', (tester) async {
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

    await _tapKey(tester, 'ai-undo');
    expect(find.textContaining('changed since'), findsOneWidget);
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
    };
    for (final MapEntry<Object, String> entry in expected.entries) {
      ai.answers.add(entry.key);
      await _ask(tester, 'something');
      expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
      await _tapKey(tester, 'ai-close');
    }
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
    expect(ai.requests.single.prompt, 'Create a new list: my runs');
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
}
