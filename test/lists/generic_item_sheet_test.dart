import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/app_theme.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/generic_item_dialog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_icons.dart';
import 'package:hybrid_note/lists/list_item.dart';

final ListDefinition _tasks = BuiltinTemplates.tasks();

// A screen with one button that opens the item sheet for Tasks.
Widget _app({
  bool reduceMotion = false,
  Brightness brightness = Brightness.light,
  ValueSetter<ListItem?>? onResult,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              final ListItem? result = await showItemSheet(
                context: context,
                definition: _tasks,
                title: 'Add Task',
              );
              onResult?.call(result);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the sheet slides up from the bottom edge without a fade', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(AppMotion.slow ~/ 2);

    final double midway = tester.getTopLeft(find.text('Save')).dy;
    expect(
      find.ancestor(
        of: find.text('Save'),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );

    await tester.pumpAndSettle();
    final double settled = tester.getTopLeft(find.text('Save')).dy;
    expect(midway, greaterThan(settled));
    // Save sits at the bottom of the screen, within thumb reach.
    expect(tester.getBottomLeft(find.text('Save')).dy, greaterThan(500));

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('with reduced motion the sheet is in place at once', (
    tester,
  ) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();

    final double first = tester.getTopLeft(find.text('Save')).dy;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Save')).dy, first);
  });

  for (final Brightness brightness in Brightness.values) {
    testWidgets('Save is in the list colour; the context line names the list '
        '(${brightness.name})', (tester) async {
      await tester.pumpWidget(_app(brightness: brightness));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Tasks · New item'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-title')), 'Plan');
      await tester.pump();

      final FilledButton save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(
        save.style!.backgroundColor!.resolve(const {}),
        listColor(_tasks.color, brightness: brightness),
      );
    });
  }

  testWidgets('subtasks: add, tick and save', (tester) async {
    ListItem? saved;
    await tester.pumpWidget(_app(onResult: (item) => saved = item));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('field-title')), 'Plan');
    await tester.tap(find.byKey(const ValueKey('field-subtasks-add')));
    await tester.pumpAndSettle();
    expect(find.text('SUBTASKS'), findsOneWidget);
    final Finder subtask = find.descendant(
      of: find.byKey(const ValueKey('field-subtasks')),
      matching: find.byType(TextField),
    );
    await tester.enterText(subtask, 'Buy pots');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('field-subtasks')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsNothing);
    expect(saved!['title'], 'Plan');
    final List<Object?> subtasks = saved!['subtasks'] as List<Object?>;
    expect(subtasks, hasLength(1));
    expect(subtasks.single, containsPair('title', 'Buy pots'));
    expect(subtasks.single, containsPair('done', true));
  });

  testWidgets('a new subtask gets the cursor while another field has it', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('field-title')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('field-subtasks-add')));
    await tester.pumpAndSettle();

    final Finder subtask = find.descendant(
      of: find.byKey(const ValueKey('field-subtasks')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(subtask).focusNode.hasFocus, isTrue);
  });
}
