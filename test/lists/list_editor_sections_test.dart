// The list editor's sections (T-24 unit 4, Q-115 C, Q-117).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_editor_screen.dart';
import 'package:hybrid_note/lists/list_patch.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';

Future<Future<ListEditorOutcome?> Function()> _open(
  WidgetTester tester,
  ListDefinition definition, {
  bool isNew = false,
}) async {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late Future<ListEditorOutcome?> outcome;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () {
            outcome = Navigator.of(context).push<ListEditorOutcome>(
              MaterialPageRoute(
                builder: (_) => ListEditorScreen(definition: definition, isNew: isNew),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => outcome;
}

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  testWidgets('sections in order; Fields, Layout and Rules folded with what they hold', (tester) async {
    await _open(tester, BuiltinTemplates.tasks());

    final List<String> order = [
      'LIST NAME',
      'Icon and colour',
      'Home and AI',
      'Items',
      'Fields · 7',
      'Layout · Checklist',
      'Rules · 2',
    ];
    double last = -1;
    for (final String text in order) {
      expect(find.text(text), findsOneWidget, reason: text);
      expect(_top(tester, find.text(text)), greaterThan(last), reason: text);
      last = _top(tester, find.text(text));
    }
    // Home and AI holds Suggest on home and AI may read this list.
    expect(_top(tester, find.byKey(const ValueKey('allow-ai'))), lessThan(_top(tester, find.text('Items'))));
    expect(_top(tester, find.byKey(const ValueKey('suggest-on-home'))), greaterThan(_top(tester, find.text('Home and AI'))));
    // Folded.
    expect(find.byKey(const ValueKey('add-field')), findsNothing);
    expect(find.byKey(const ValueKey('view-kind')), findsNothing);
    expect(find.byKey(const ValueKey('rule-clearCompleted')), findsNothing);
    // No drop-downs anywhere.
    expect(find.byType(DropdownButton<Object?>), findsNothing);

    await tester.tap(find.text('Fields · 7'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('tick-mark-done')), findsOneWidget);
  });

  testWidgets('a new list starts with every section open', (tester) async {
    await _open(tester, BuiltinTemplates.tasks(), isNew: true);
    expect(find.byKey(const ValueKey('add-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('view-kind')), findsOneWidget);
    expect(find.byKey(const ValueKey('rule-clearCompleted')), findsOneWidget);
  });

  testWidgets('a section with a problem opens itself', (tester) async {
    await _open(tester, BuiltinTemplates.tasks());
    await tester.tap(find.text('Fields · 7'));
    await tester.pumpAndSettle();
    // Removing the date field the checklist splits by is an error.
    await tester.tap(find.byKey(const ValueKey('remove-field-reminderAt')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-errors')), findsOneWidget);
    expect(find.byKey(const ValueKey('view-kind')), findsOneWidget);
    expect(find.byKey(const ValueKey('rule-clearCompleted')), findsOneWidget);
  });

  testWidgets('the layout is picked on the page, with a line for the picked one', (tester) async {
    final Future<ListEditorOutcome?> Function() outcome = await _open(tester, BuiltinTemplates.watchRead());
    await tester.tap(find.textContaining('Layout ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choice-ViewKind.cards')));
    await tester.pumpAndSettle();
    expect(find.text('Items one per row with their details, newest first.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-list')));
    await tester.pumpAndSettle();
    expect((await outcome())!.result!.definition.view.kind, ViewKind.cards);
  });

  group('Items (Q-117)', () {
    testWidgets('a list follows Preferences until it picks its own', (tester) async {
      final Future<ListEditorOutcome?> Function() outcome = await _open(tester, BuiltinTemplates.grocery());
      Switch follow(String key) => tester.widget<Switch>(
        find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Switch)),
      );
      expect(follow('ticked-follow').value, isTrue);
      expect(follow('confirm-follow').value, isTrue);

      // Following: the choice shows Preferences' value and cannot change.
      await tester.tap(find.byKey(const ValueKey('choice-TickedItems.hide')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('choice-line-TickedItems.moveToDone')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ticked-follow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('choice-TickedItems.hide')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-follow')));
      await tester.pumpAndSettle();
      // The setting's own switch, not Follow Preferences under it.
      await tester.tap(find.text('Confirm before deleting'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save-list')));
      await tester.pumpAndSettle();
      final ListEditorOutcome saved = (await outcome())!;
      expect(saved.result!.definition.ownTickedItems, 'hide');
      expect(saved.result!.definition.ownConfirmDelete, isTrue);
      expect(saved.ops.every((op) => op.kind == PatchOpKind.setListInfo), isTrue);
    });

    testWidgets('Follow Preferences again puts the list back', (tester) async {
      final Map<String, dynamic> json = BuiltinTemplates.grocery().toJson()..['tickedItems'] = 'hide';
      final Future<ListEditorOutcome?> Function() outcome = await _open(tester, ListDefinition.fromJson(json));
      await tester.tap(find.byKey(const ValueKey('ticked-follow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-list')));
      await tester.pumpAndSettle();
      expect((await outcome())!.result!.definition.ownTickedItems, isNull);
    });

    testWidgets('a list without a tick has Ticked items greyed with a line', (tester) async {
      final Map<String, dynamic> json = BuiltinTemplates.watchRead().toJson();
      await _open(tester, ListDefinition.fromJson(json));
      expect(find.text('This list has no tick.'), findsOneWidget);
      final Switch follow = tester.widget<Switch>(
        find.descendant(of: find.byKey(const ValueKey('ticked-follow')), matching: find.byType(Switch)),
      );
      expect(follow.onChanged, isNull);
    });
  });
}
