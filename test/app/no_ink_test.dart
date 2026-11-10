import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/app_theme.dart';
import 'package:hybrid_note/app/settings_controls.dart';

// No grey box behind what is pressed or held (owner, 2026-11-10), and
// folding slides (owner, 2026-11-10).
void main() {
  const Set<WidgetState> pressed = {WidgetState.pressed};
  const Set<WidgetState> focused = {WidgetState.focused};

  for (final ThemeData theme in [AppTheme.light(), AppTheme.dark()]) {
    test('${theme.brightness.name}: no splash and no pressed highlight', () {
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(theme.splashColor, Colors.transparent);
      expect(theme.highlightColor, Colors.transparent);
      // Keyboard focus stays visible.
      expect(theme.focusColor.a, greaterThan(0));
      for (final ButtonStyle? style in [
        theme.filledButtonTheme.style,
        theme.elevatedButtonTheme.style,
        theme.outlinedButtonTheme.style,
        theme.textButtonTheme.style,
        theme.iconButtonTheme.style,
      ]) {
        expect(style!.splashFactory, NoSplash.splashFactory);
        expect(style.overlayColor!.resolve(pressed), Colors.transparent);
        expect(style.overlayColor!.resolve(focused)!.a, greaterThan(0));
      }
      for (final WidgetStateProperty<Color?>? overlay in [
        theme.checkboxTheme.overlayColor,
        theme.radioTheme.overlayColor,
        theme.switchTheme.overlayColor,
        theme.datePickerTheme.dayOverlayColor,
      ]) {
        expect(overlay!.resolve(pressed), Colors.transparent);
      }
    });
  }

  test('a button with its own style keeps focus, not the pressed tint', () {
    final ButtonStyle style = AppInk.pressless(
      TextButton.styleFrom(foregroundColor: Colors.red),
    );
    expect(style.overlayColor!.resolve(pressed), Colors.transparent);
    expect(style.overlayColor!.resolve(focused)!.a, greaterThan(0));
    expect(style.splashFactory, NoSplash.splashFactory);
  });

  Future<void> pumpFold(WidgetTester tester, {bool reduceMotion = false}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: const Scaffold(
            body: Column(
              children: [
                FoldSection(
                  title: 'Items',
                  children: [SizedBox(key: ValueKey('row'), height: 200)],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double turns(WidgetTester tester) =>
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns;
  double shown(WidgetTester tester) =>
      tester.getSize(find.byType(ClipRect).last).height;

  testWidgets('a fold slides open and shut, its arrow turning', (tester) async {
    await pumpFold(tester);
    expect(find.byKey(const ValueKey('row')), findsNothing);
    expect(turns(tester), 0);

    await tester.tap(find.text('Items'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final double partway = shown(tester);
    expect(partway, greaterThan(0));
    expect(partway, lessThan(200));
    expect(turns(tester), 0.5);
    await tester.pumpAndSettle();
    expect(shown(tester), 200);

    await tester.tap(find.text('Items'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(shown(tester), lessThan(200));
    expect(find.byKey(const ValueKey('row')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('row')), findsNothing);
    expect(turns(tester), 0);
  });

  testWidgets('with reduced motion a fold opens at once', (tester) async {
    await pumpFold(tester, reduceMotion: true);
    await tester.tap(find.text('Items'));
    await tester.pump();
    expect(shown(tester), 200);
  });
}
