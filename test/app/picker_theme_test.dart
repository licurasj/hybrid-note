// Material's time and date pickers in the app's look (Q-122 A): the hour and
// the minute as two tiles of one shape, the picked one in the text colour.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/app_theme.dart';
import 'package:hybrid_note/app_colors.dart';

Future<void> _open(
  WidgetTester tester, {
  required Brightness brightness,
  double textScale = 1,
  bool h24 = false,
  bool date = false,
  Size size = const Size(320, 640),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light
          ? AppTheme.light(languageCode: 'en')
          : AppTheme.dark(languageCode: 'en'),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: h24),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => date
                  ? showDatePicker(
                      context: context,
                      initialDate: DateTime(2026, 11, 9),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    )
                  : showTimePicker(
                      context: context,
                      initialTime: const TimeOfDay(hour: 3, minute: 29),
                      // As the app's timePickerIn gives it.
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          alwaysUse24HourFormat: h24,
                          textScaler: TextScaler.linear(textScale),
                        ),
                        // As the item editor opens it, here with no list.
                        child: Builder(
                          builder: (context) => Theme(
                            data: AppTheme.pickerTheme(context, null),
                            child: child!,
                          ),
                        ),
                      ),
                    ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  test('in the list colour, digits that read on it', () {
    // A pale colour (yellow) takes dark digits; a deep one white.
    const Color yellow = Color(0xFFF2B705);
    const Color violet = Color(0xFF6B3DFF);
    for (final (Color colour, Color digits) in [
      (yellow, AppColors.onColor(yellow)),
      (violet, AppColors.onColor(violet)),
    ]) {
      final ThemeData theme = AppTheme.withPickerAccent(
        AppTheme.light(languageCode: 'en'),
        colour,
      );
      final TimePickerThemeData time = theme.timePickerTheme;
      expect(
        WidgetStateProperty.resolveAs(time.hourMinuteColor!, {
          WidgetState.selected,
        }),
        colour,
      );
      expect(
        WidgetStateProperty.resolveAs(time.hourMinuteTextColor!, {
          WidgetState.selected,
        }),
        digits,
      );
      expect(time.dialHandColor, colour);
      expect(
        theme.datePickerTheme.dayBackgroundColor!.resolve({
          WidgetState.selected,
        }),
        colour,
      );
    }
    expect(AppColors.onColor(yellow), isNot(AppColors.onColor(violet)));
  });

  for (final Brightness brightness in Brightness.values) {
    final AppNeutrals n = AppColors.neutrals(brightness);

    testWidgets('time picker, ${brightness.name}: hour and minute as a pair', (
      tester,
    ) async {
      await _open(tester, brightness: brightness);
      expect(tester.takeException(), isNull);
      final TimePickerThemeData theme = Theme.of(
        tester.element(find.byType(TimePickerDialog)),
      ).timePickerTheme;
      final Color tile = theme.hourMinuteColor!;
      expect(
        WidgetStateProperty.resolveAs(tile, {WidgetState.selected}),
        n.text,
      );
      expect(
        WidgetStateProperty.resolveAs(tile, <WidgetState>{}),
        Colors.transparent,
      );
      // The other one's digits grey; the colon grey; AM and PM unframed.
      expect(
        WidgetStateProperty.resolveAs(
          theme.hourMinuteTextColor!,
          <WidgetState>{},
        ),
        n.muted,
      );
      expect(theme.timeSelectorSeparatorColor!.resolve({}), n.muted);
      expect(theme.dayPeriodBorderSide, BorderSide.none);
      // Circles, not ovals, and no outline on the one not picked.
      for (final ShapeBorder? shape in [
        theme.hourMinuteShape,
        theme.dayPeriodShape,
      ]) {
        expect(shape, isA<CircleBorder>());
        expect((shape! as CircleBorder).eccentricity, 0);
        expect((shape as CircleBorder).side, BorderSide.none);
      }
      expect(find.text('3'), findsWidgets);
      expect(find.text('29'), findsOneWidget);
    });

    testWidgets(
      'time picker, ${brightness.name}, 24 hours: nothing overflows',
      (tester) async {
        await _open(tester, brightness: brightness, h24: true);
        expect(tester.takeException(), isNull);
        expect(find.text('03'), findsOneWidget);
      },
    );

    for (final double scale in [1.0, 1.3, 2.0]) {
      testWidgets('time picker, ${brightness.name}, text x$scale: AM and PM '
          'stay on their circle, or an oval when too wide', (tester) async {
        await _open(tester, brightness: brightness, textScale: scale);
        expect(tester.takeException(), isNull);
        final ShapeBorder shape = Theme.of(
          tester.element(find.text('AM')),
        ).timePickerTheme.dayPeriodShape!;
        for (final String period in ['AM', 'PM']) {
          final Rect text = tester.getRect(find.text(period));
          final Rect button = tester.getRect(
            find
                .ancestor(of: find.text(period), matching: find.byType(InkWell))
                .first,
          );
          // A circle is as wide as the button is tall; an oval fills it.
          final double room = (shape as CircleBorder).eccentricity == 0
              ? button.shortestSide
              : button.width;
          expect(
            text.width,
            lessThanOrEqualTo(room),
            reason: '$period x$scale',
          );
        }
        if (scale == 1.0) {
          expect((shape as CircleBorder).eccentricity, 0);
        }
      });
    }

    testWidgets('date picker, ${brightness.name}: the picked day filled', (
      tester,
    ) async {
      await _open(tester, brightness: brightness, date: true);
      expect(tester.takeException(), isNull);
      final DatePickerThemeData theme = Theme.of(
        tester.element(find.byType(DatePickerDialog)),
      ).datePickerTheme;
      expect(theme.dayBackgroundColor!.resolve({WidgetState.selected}), n.text);
    });
  }
}
