import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_note/app/app_theme.dart';
import 'package:hybrid_note/app_colors.dart';
import 'package:hybrid_note/lists/list_icons.dart';

void main() {
  group('listColor (Q-19 A)', () {
    test('palette colours keep the light value and map to their dark variant', () {
      for (final ListPaletteColor entry in listPalette) {
        final String hex =
            '#${(entry.light.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
        expect(listColor(hex), entry.light);
        expect(listColor(hex, brightness: Brightness.dark), entry.dark);
      }
    });

    test('unknown colours are used as they are in both themes', () {
      expect(listColor('#1E88E5'), const Color(0xFF1E88E5));
      expect(
        listColor('#1E88E5', brightness: Brightness.dark),
        const Color(0xFF1E88E5),
      );
    });

    test('a value that is not a colour falls back to the muted grey', () {
      expect(listColor('blue'), AppNeutrals.light.muted);
      expect(listColor('#12345'), AppNeutrals.light.muted);
      expect(
        listColor('', brightness: Brightness.dark),
        AppNeutrals.dark.muted,
      );
    });

    test('the editor offers the palette, light values first to last', () {
      expect(listColorChoices, [
        '#FF4D12',
        '#00A63E',
        '#E5007E',
        '#6B3BFF',
        '#F5B800',
        '#FF2D55',
        '#00A99D',
        '#2F5BFF',
      ]);
    });
  });

  test('onColor picks white or #111111, whichever contrasts more', () {
    expect(AppColors.onColor(const Color(0xFF2F5BFF)), AppColors.onColorLight);
    expect(AppColors.onColor(const Color(0xFFF5B800)), AppColors.onColorDark);
    expect(AppColors.onColor(Colors.black), AppColors.onColorLight);
    expect(AppColors.onColor(Colors.white), AppColors.onColorDark);
  });

  group('AppTheme', () {
    test('titles use the serif italic and body text the sans', () {
      for (final ThemeData theme in [
        AppTheme.light(languageCode: 'en'),
        AppTheme.dark(languageCode: 'en'),
      ]) {
        expect(theme.textTheme.titleLarge!.fontFamily, AppFonts.serif);
        expect(theme.textTheme.titleLarge!.fontStyle, FontStyle.italic);
        expect(theme.textTheme.bodyLarge!.fontFamily, AppFonts.sans);
        expect(theme.appBarTheme.titleTextStyle!.fontFamily, AppFonts.serif);
        expect(
          theme.extension<AppTypography>()!.listTitle.fontStyle,
          FontStyle.italic,
        );
      }
    });

    test('Japanese and Chinese titles are upright, not in the serif', () {
      for (final String code in ['ja', 'zh']) {
        final ThemeData theme = AppTheme.light(languageCode: code);
        expect(theme.textTheme.titleLarge!.fontFamily, AppFonts.sans);
        expect(theme.textTheme.titleLarge!.fontStyle, FontStyle.normal);
        expect(
          theme.extension<AppTypography>()!.listTitle.fontStyle,
          FontStyle.normal,
        );
      }
    });

    test('grounds are white and true black', () {
      expect(AppTheme.light().scaffoldBackgroundColor, const Color(0xFFFFFFFF));
      expect(AppTheme.dark().scaffoldBackgroundColor, const Color(0xFF000000));
    });

    testWidgets('screens slide in, and do not animate with reduced motion',
        (tester) async {
      Future<void> pumpPush({required bool reduced}) async {
        final GlobalKey<NavigatorState> navigator = GlobalKey();
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: MaterialApp(
              theme: AppTheme.light(languageCode: 'en'),
              navigatorKey: navigator,
              home: const Text('home'),
            ),
          ),
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const Text('next')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }

      await pumpPush(reduced: false);
      expect(
        find.ancestor(of: find.text('next'), matching: find.byType(SlideTransition)),
        findsWidgets,
      );
      expect(
        find.ancestor(of: find.text('next'), matching: find.byType(FadeTransition)),
        findsNothing,
      );
      await tester.pumpAndSettle();

      await pumpPush(reduced: true);
      expect(
        find.ancestor(
          of: find.text('next'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SlideTransition &&
                widget.position.value != Offset.zero,
          ),
        ),
        findsNothing,
      );
    });
  });
}
