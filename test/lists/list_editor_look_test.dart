import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/app_theme.dart';
import 'package:hybrid_note/app_colors.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_editor_screen.dart';
import 'package:hybrid_note/lists/list_icons.dart';
import 'package:hybrid_note/lists/list_template_picker.dart';

// The look of the list editor and the "New list" picker (T-16 unit 4). The
// editor's patch logic is covered by list_editor_test and list_editor_rules_test.

final ListDefinition _grocery = BuiltinTemplates.grocery();

Widget _app({
  required Widget Function(BuildContext context) home,
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
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
    home: Builder(builder: home),
  );
}

Future<void> _pumpEditor(
  WidgetTester tester,
  ListDefinition definition, {
  bool isNew = false,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(
      brightness: brightness,
      home: (_) => ListEditorScreen(definition: definition, isNew: isNew),
    ),
  );
  await tester.pumpAndSettle();
}

// The swatch's disc: the first circle inside its 48 dp target.
Color _discColor(WidgetTester tester, String hex) {
  final Container disc = tester.widget<Container>(
    find
        .descendant(
          of: find.byKey(ValueKey('color-$hex')),
          matching: find.byType(Container),
        )
        .first,
  );
  return (disc.decoration! as BoxDecoration).color!;
}

void main() {
  testWidgets(
    'the chosen colour carries the eclipse ring, which moves on tap',
    (tester) async {
      await _pumpEditor(tester, _grocery);

      Finder ringOn(String hex) => find.descendant(
        of: find.byKey(ValueKey('color-$hex')),
        matching: find.byKey(const ValueKey('color-selected')),
      );

      expect(find.byKey(const ValueKey('color-selected')), findsOneWidget);
      expect(ringOn(_grocery.color), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('color-#6B3BFF')));
      await tester.pump();
      expect(find.byKey(const ValueKey('color-selected')), findsOneWidget);
      expect(ringOn('#6B3BFF'), findsOneWidget);
      expect(ringOn(_grocery.color), findsNothing);
    },
  );

  testWidgets(
    'a colour or icon takes a tap anywhere in its 48 dp square and has a name',
    (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pumpEditor(tester, _grocery);
      // Just inside the square's left edge, outside the 36 dp disc.
      final Rect violet =
          tester.getRect(find.byKey(const ValueKey('color-#6B3BFF')));
      expect(violet.width, 48);
      await tester.tapAt(violet.centerLeft + const Offset(3, 0));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('color-#6B3BFF')),
          matching: find.byKey(const ValueKey('color-selected')),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Violet'), findsOneWidget);

      final Rect book = tester.getRect(find.byKey(const ValueKey('icon-book')));
      expect(book.width, 48);
      expect(find.bySemanticsLabel('Book'), findsOneWidget);
      handle.dispose();
    },
  );

  testWidgets('swatches show the dark variants in dark mode', (tester) async {
    await _pumpEditor(tester, _grocery, brightness: Brightness.dark);
    for (final ListPaletteColor entry in listPalette) {
      final String hex = listColorChoices[listPalette.indexOf(entry)];
      expect(_discColor(tester, hex), entry.dark);
    }
  });

  testWidgets(
    'the title is the serif screen title; Delete only for a saved list',
    (tester) async {
      await _pumpEditor(tester, _grocery);
      final Text title = tester.widget<Text>(find.text('Edit list'));
      expect(title.style?.fontFamily, AppFonts.serif);
      expect(title.style?.fontStyle, FontStyle.italic);
      expect(find.byKey(const ValueKey('delete-list')), findsOneWidget);
      expect(find.byType(Card), findsNothing);

      await _pumpEditor(tester, blankListDefinitionForTest(), isNew: true);
      expect(find.text('New list'), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-list')), findsNothing);
    },
  );

  testWidgets('Allow AI is a switch row that changes the draft', (
    tester,
  ) async {
    await _pumpEditor(tester, _grocery);
    final Finder allowAi = find.byKey(const ValueKey('allow-ai'));
    final bool before = tester.widget<SwitchListTile>(allowAi).value;
    await tester.ensureVisible(allowAi);
    await tester.pump();
    await tester.tap(allowAi);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(allowAi).value, !before);
  });

  group('the "New list" picker', () {
    Widget picker({
      Brightness brightness = Brightness.light,
      bool reduceMotion = false,
      ValueSetter<ListDefinition?>? onPicked,
    }) {
      return _app(
        brightness: brightness,
        reduceMotion: reduceMotion,
        home: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final ListDefinition? value = await showListTemplatePicker(
                  context,
                );
                onPicked?.call(value);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
    }

    testWidgets('slides up as a sheet without a fade', (tester) async {
      await tester.pumpWidget(picker());
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(AppMotion.slow ~/ 2);
      final double midway = tester.getTopLeft(find.text('Blank')).dy;
      expect(
        find.ancestor(
          of: find.text('Blank'),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Blank')).dy, lessThan(midway));
    });

    testWidgets('is in place at once with reduced motion', (tester) async {
      await tester.pumpWidget(picker(reduceMotion: true));
      await tester.tap(find.text('Open'));
      await tester.pump();
      final double first = tester.getTopLeft(find.text('Blank')).dy;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Blank')).dy, first);
    });

    testWidgets('each template shows its colour disc, dark variant in dark', (
      tester,
    ) async {
      await tester.pumpWidget(picker(brightness: Brightness.dark));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      for (final ListDefinition template in BuiltinTemplates.all()) {
        final Finder row = find.byKey(ValueKey('template-${template.id}'));
        final Iterable<Color?> discs = tester
            .widgetList<Container>(
              find.descendant(of: row, matching: find.byType(Container)),
            )
            .map((box) => (box.decoration as BoxDecoration?)?.color);
        expect(
          discs,
          contains(listColor(template.color, brightness: Brightness.dark)),
        );
      }
    });

    testWidgets('picking a template returns a fresh copy of it', (
      tester,
    ) async {
      ListDefinition? picked;
      await tester.pumpWidget(picker(onPicked: (value) => picked = value));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('template-${_grocery.id}')));
      await tester.pumpAndSettle();

      expect(picked, isNotNull);
      expect(picked!.id, isNot(_grocery.id));
      expect(picked!.templateId, _grocery.templateId);
      expect(find.text('Blank'), findsNothing);
    });
  });
}

// A blank definition without needing localizations at build time.
ListDefinition blankListDefinitionForTest() {
  return ListDefinition.fromJson({
    'id': 'list-new',
    'name': '',
    'icon': 'list',
    'color': listColorChoices.first,
    'fields': [
      {
        'key': 'title',
        'type': 'text',
        'label': 'Title',
        'required': true,
        'primary': true,
      },
    ],
    'view': {'kind': 'checklist'},
    'updatedAt': DateTime.utc(2026).toIso8601String(),
  });
}
