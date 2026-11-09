// Interaction law rule 7 (Q-105, T-23 unit 1): a button that appears never
// takes another's place or pushes it aside.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/generic_list_screen.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_rules.dart';
import 'package:hybrid_note/lists/list_store.dart';

final ListDefinition _grocery = BuiltinTemplates.grocery();
final ListDefinition _tasks = BuiltinTemplates.tasks();

ListItem _item(ListDefinition list, String id, Map<String, dynamic> values) {
  final DateTime time = DateTime.utc(2026, 3, 1);
  return ListItem(
    id: id,
    listId: list.id,
    values: values,
    createdAt: time,
    updatedAt: time,
  );
}

ListItem _milk({required bool done}) => _item(_grocery, 'milk', {
      'title': 'Milk',
      'done': done,
      'section': 'nextTime',
    });

ListItem _task({required bool done}) =>
    _item(_tasks, 'call', {'title': 'Call Sam', 'done': done});

class _Store implements ListStore {
  @override
  Future<void> apply(ListChanges changes) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _screen(
  ListDefinition definition,
  List<ListItem> items, {
  bool reduceMotion = false,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: ListEditAction(
          onEdit: (_) {},
          child: GenericListScreen(
            definition: definition,
            items: items,
            store: _Store(),
            texts: const GenericListTexts(
              title: 'List',
              emptyText: 'Nothing here',
              addTooltip: 'Add item',
              addDialogTitle: 'Add',
              editDialogTitle: 'Edit',
            ),
          ),
        ),
      ),
    ),
  );
}

final Finder _move = find.byKey(const ValueKey('move-all-button-nextTime'));
final Finder _clear = find.byKey(const ValueKey('clear-ticked-button-nextTime'));
final Finder _clearSlot = find.byKey(const ValueKey('clear-ticked-nextTime'));

void main() {
  testWidgets('Next time: ticking leaves Move in place; Clear ticked grows in on its right', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(_grocery, [_milk(done: false)]));
    await tester.pumpAndSettle();

    expect(_move, findsOneWidget);
    expect(_clear, findsNothing);
    final Rect moveBefore = tester.getRect(_move);

    await tester.pumpWidget(_screen(_grocery, [_milk(done: true)]));
    await tester.pump(const Duration(milliseconds: 60));

    // Halfway: Clear ticked is growing, and Move has not moved.
    expect(tester.getRect(_move), moveBefore);
    final double growing = tester.getSize(_clearSlot).width;
    expect(growing, greaterThan(0));
    expect(growing, lessThan(tester.getSize(_clear).width));

    await tester.pumpAndSettle();
    expect(tester.getRect(_move), moveBefore);
    expect(tester.getRect(_clear).left, greaterThan(moveBefore.right));
    expect(find.text('Clear Ticked (1 ticked)'), findsOneWidget);

    // It goes the same way, and Move still stays.
    await tester.pumpWidget(_screen(_grocery, [_milk(done: false)]));
    await tester.pumpAndSettle();
    expect(tester.getRect(_move), moveBefore);
    expect(_clear, findsNothing);
  });

  testWidgets('reduced motion: Clear ticked appears at once', (tester) async {
    await tester.pumpWidget(
      _screen(_grocery, [_milk(done: false)], reduceMotion: true),
    );
    await tester.pumpAndSettle();
    final Rect moveBefore = tester.getRect(_move);

    await tester.pumpWidget(
      _screen(_grocery, [_milk(done: true)], reduceMotion: true),
    );
    await tester.pump();

    expect(tester.getSize(_clearSlot).width, tester.getSize(_clear).width);
    expect(tester.getRect(_move), moveBefore);
  });

  testWidgets('top bar: the clear button grows in left of Edit list, which stays', (
    tester,
  ) async {
    final Finder edit = find.byKey(const ValueKey('edit-list'));
    final Finder clear = find.byKey(const ValueKey('list-clear'));

    await tester.pumpWidget(_screen(_tasks, [_task(done: false)]));
    await tester.pumpAndSettle();
    final Rect editBefore = tester.getRect(edit);
    expect(tester.getSize(clear).width, 0);

    await tester.pumpWidget(_screen(_tasks, [_task(done: true)]));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getRect(edit), editBefore);
    expect(tester.getSize(clear).width, greaterThan(0));

    await tester.pumpAndSettle();
    expect(tester.getRect(edit), editBefore);
    expect(tester.getRect(clear).right, lessThanOrEqualTo(editBefore.left));
    expect(find.byTooltip('Clear'), findsOneWidget);
  });
}
