import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/ai/ai_service.dart';
import 'package:hybrid_note/app/app_settings.dart';
import 'package:hybrid_note/demo/demo_ai.dart';
import 'package:hybrid_note/demo/demo_app.dart';
import 'package:hybrid_note/demo/memory_list_store.dart';
import 'package:hybrid_note/lists/list_definition.dart';

import '../support/firestore_store.dart' show settle;

// The demo's lazy AI (T-18 unit 2b): Firebase, the anonymous sign-in and
// App Check only at the first send, after the notice; a new sign-in when
// the clean-up job deleted the account; the AI stops said plainly while the
// rest of the demo keeps working.

class _FakeBackend implements DemoAiBackend {
  final List<String> log = [];
  final List<Object> answers = [];
  final List<AiRequest> requests = [];
  int failStarts = 0;
  bool failSignIn = false;
  bool _signedIn = false;

  bool get started => log.contains('start');

  // The account is deleted on the server: the next call has no valid token.
  void deleteAccount() => answers.insert(0, const AiRefusal('signIn'));

  @override
  Future<void> start() async {
    log.add('start');
    if (failStarts > 0) {
      failStarts--;
      throw StateError('no network');
    }
  }

  @override
  bool get signedIn => _signedIn;

  @override
  Future<void> signIn() async {
    log.add('signIn');
    if (failSignIn) {
      throw StateError('anonymous sign-in disabled');
    }
    _signedIn = true;
  }

  @override
  Future<void> signOut() async {
    log.add('signOut');
    _signedIn = false;
  }

  @override
  AiService get service => _FakeService(this);
}

class _FakeService implements AiService {
  _FakeService(this.backend);

  final _FakeBackend backend;

  @override
  Future<AiAnswer> send(AiRequest request) async {
    backend.log.add('send');
    backend.requests.add(request);
    final Object next = backend.answers.isEmpty
        ? const AiAnswer(requestId: 'r', toolCalls: [])
        : backend.answers.removeAt(0);
    if (next is AiRefusal) {
      throw next;
    }
    return next as AiAnswer;
  }
}

AiRequest _request() => AiRequest(
  prompt: 'milk',
  locale: 'en',
  today: DateTime(2026, 11, 17),
  lists: const [],
);

const AiAnswer _ok = AiAnswer(requestId: 'ok', toolCalls: []);

final Finder _hub = find.byKey(const ValueKey('launcher-hub'));

Future<MemoryListStore> _pumpDemo(
  WidgetTester tester,
  _FakeBackend backend,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final MemoryListStore store = demoStore(DateTime.now());
  await tester.pumpWidget(
    BlocProvider(
      create: (_) => AppSettingsCubit(preferences),
      child: DemoApp(store: store, aiService: LazyAiService(backend)),
    ),
  );
  await settle(tester);
  return store;
}

Future<void> _ask(WidgetTester tester, String text) async {
  await tester.tap(find.byKey(const ValueKey('ai-bar')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('ai-bar-field')), text);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('ai-bar-send')));
  await settle(tester);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await settle(tester);
}

void main() {
  group('LazyAiService', () {
    test('does nothing until the first send', () {
      final _FakeBackend backend = _FakeBackend();
      LazyAiService(backend);
      expect(backend.log, isEmpty);
    });

    test('the first send starts Firebase and signs in; later sends only '
        'send', () async {
      final _FakeBackend backend = _FakeBackend();
      final LazyAiService ai = LazyAiService(backend);
      expect((await ai.send(_request())).requestId, 'r');
      await ai.send(_request());
      expect(backend.log, ['start', 'signIn', 'send', 'send']);
    });

    test('a deleted anonymous account signs in again and the request '
        'goes through', () async {
      final _FakeBackend backend = _FakeBackend()..answers.add(_ok);
      final LazyAiService ai = LazyAiService(backend);
      await ai.send(_request());

      backend
        ..deleteAccount()
        ..answers.add(_ok);
      final AiAnswer answer = await ai.send(_request());
      expect(answer.requestId, 'ok');
      expect(backend.log, [
        'start',
        'signIn',
        'send',
        'send',
        'signOut',
        'signIn',
        'send',
      ]);
      expect(backend.requests, hasLength(3));
    });

    test('signs in again only once per request', () async {
      final _FakeBackend backend = _FakeBackend()
        ..answers.addAll(const [AiRefusal('signIn'), AiRefusal('signIn')]);
      final LazyAiService ai = LazyAiService(backend);
      await expectLater(
        ai.send(_request()),
        throwsA(isA<AiRefusal>().having((r) => r.reason, 'reason', 'signIn')),
      );
      expect(backend.log.where((e) => e == 'send'), hasLength(2));
    });

    test('the AI stops pass through without a new sign-in', () async {
      for (final String stop in ['dailyCount', 'globalBudget']) {
        final _FakeBackend backend = _FakeBackend()
          ..answers.add(AiRefusal(stop));
        final LazyAiService ai = LazyAiService(backend);
        await expectLater(
          ai.send(_request()),
          throwsA(isA<AiRefusal>().having((r) => r.reason, 'reason', stop)),
        );
        expect(backend.log, ['start', 'signIn', 'send']);
      }
    });

    test('a failed start is "unavailable" and the next send tries '
        'again', () async {
      final _FakeBackend backend = _FakeBackend()..failStarts = 1;
      final LazyAiService ai = LazyAiService(backend);
      await expectLater(
        ai.send(_request()),
        throwsA(
          isA<AiRefusal>().having((r) => r.reason, 'reason', 'unavailable'),
        ),
      );
      await ai.send(_request());
      expect(backend.log, ['start', 'start', 'signIn', 'send']);
    });

    test('a failed anonymous sign-in is "unavailable"', () async {
      final _FakeBackend backend = _FakeBackend()..failSignIn = true;
      await expectLater(
        LazyAiService(backend).send(_request()),
        throwsA(
          isA<AiRefusal>().having((r) => r.reason, 'reason', 'unavailable'),
        ),
      );
      expect(backend.log, ['start', 'signIn']);
    });
  });

  group('the demo AI bar', () {
    testWidgets('the notice shows before anything of Firebase starts', (
      tester,
    ) async {
      final _FakeBackend backend = _FakeBackend();
      await _pumpDemo(tester, backend);
      expect(find.byKey(const ValueKey('ai-bar')), findsOneWidget);

      await _ask(tester, 'add milk to grocery');
      expect(find.byKey(const ValueKey('ai-notice')), findsOneWidget);
      expect(backend.log, isEmpty);

      await _tapKey(tester, 'ai-notice-continue');
      expect(backend.log, ['start', 'signIn', 'send']);
      expect(backend.requests.single.prompt, 'add milk to grocery');
    });

    for (final (String stop, String text) in const [
      ('dailyCount', 'You have reached today’s limit of AI requests.'),
      ('globalBudget', 'The AI is paused until tomorrow.'),
    ]) {
      testWidgets('at the $stop stop the bar says so and the demo keeps '
          'working', (tester) async {
        final _FakeBackend backend = _FakeBackend()
          ..answers.add(AiRefusal(stop));
        final MemoryListStore store = await _pumpDemo(tester, backend);
        await _ask(tester, 'add milk to grocery');
        await _tapKey(tester, 'ai-notice-continue');
        expect(find.text(text), findsOneWidget);
        await _tapKey(tester, 'ai-close');
        expect(find.text(text), findsNothing);

        // Lists still open and change without the AI.
        final ListDefinition tasks = store.current.definitions.first;
        await tester.tap(_hub);
        await tester.pump();
        await tester.tap(find.byKey(ValueKey('launcher-note-${tasks.id}')));
        await tester.pumpAndSettle();
        expect(find.text('Call the dentist'), findsOneWidget);
        final ListDefinition grocery = store.current.definitions[1];
        await store.deleteList(grocery.id);
        expect(store.current.definition(grocery.id), isNull);

        // And the bar takes the next request (no new notice).
        await _ask(tester, 'something');
        expect(find.byKey(const ValueKey('ai-notice')), findsNothing);
        expect(backend.requests, hasLength(2));
      });
    }
  });
}
