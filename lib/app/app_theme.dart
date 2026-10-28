import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../app_colors.dart';

// Font families bundled in assets/fonts (Q-18 A). Japanese and Chinese glyphs
// come from the system fonts; there titles are set upright in the sans.
class AppFonts {
  const AppFonts._();

  static const String serif = 'InstrumentSerif';
  static const String sans = 'Geist';
}

// Motion is translate (and size) only, quick and eased out. Code that animates
// checks MediaQuery.disableAnimationsOf and skips the animation when it is set.
class AppMotion {
  const AppMotion._();

  static const Duration quick = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 200);

  // Delay between launcher tabs growing out from under the hub.
  static const Duration tabStagger = Duration(milliseconds: 16);

  static const Curve curve = Curves.easeOutCubic;
}

class AppShapes {
  const AppShapes._();

  static const double sheetRadius = 28;
  static const double fieldRadius = 14;
  static const double sideMargin = 22;
  static const double rowPadding = 13;

  static const OutlinedBorder pill = StadiumBorder();
  static const RoundedRectangleBorder sheet = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(sheetRadius)),
  );
}

// The one soft shadow, for floating things only: the hub, the add button,
// sheets and the selected launcher tab.
class AppShadows {
  const AppShadows._();

  static List<BoxShadow> floating(Brightness brightness) => [
        BoxShadow(
          color: Colors.black.withValues(
            alpha: brightness == Brightness.dark ? 0.9 : 0.32,
          ),
          offset: const Offset(0, 10),
          blurRadius: 22,
          spreadRadius: -6,
        ),
      ];
}

// Styles that have no Material text-theme slot. Read with
// Theme.of(context).extension<AppTypography>()!.
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.listTitle,
    required this.screenTitle,
    required this.row,
    required this.meta,
    required this.sectionLabel,
  });

  // The open list's name, about 150 px, allowed to run off the right edge.
  final TextStyle listTitle;
  final TextStyle screenTitle;
  final TextStyle row;
  final TextStyle meta;

  // Uppercase the text itself; the style only sets size and tracking.
  final TextStyle sectionLabel;

  @override
  AppTypography copyWith({
    TextStyle? listTitle,
    TextStyle? screenTitle,
    TextStyle? row,
    TextStyle? meta,
    TextStyle? sectionLabel,
  }) {
    return AppTypography(
      listTitle: listTitle ?? this.listTitle,
      screenTitle: screenTitle ?? this.screenTitle,
      row: row ?? this.row,
      meta: meta ?? this.meta,
      sectionLabel: sectionLabel ?? this.sectionLabel,
    );
  }

  @override
  AppTypography lerp(AppTypography? other, double t) {
    if (other == null) {
      return this;
    }
    return AppTypography(
      listTitle: TextStyle.lerp(listTitle, other.listTitle, t)!,
      screenTitle: TextStyle.lerp(screenTitle, other.screenTitle, t)!,
      row: TextStyle.lerp(row, other.row, t)!,
      meta: TextStyle.lerp(meta, other.meta, t)!,
      sectionLabel: TextStyle.lerp(sectionLabel, other.sectionLabel, t)!,
    );
  }
}

// Screens slide in from the right; nothing fades (AESTHETICS.md, Motion).
class SlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const SlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: AppMotion.curve)),
      child: child,
    );
  }
}

class AppTheme {
  const AppTheme._();

  // languageCode is the app's chosen language; null follows the device.
  static ThemeData light({String? languageCode}) =>
      _build(Brightness.light, languageCode);

  static ThemeData dark({String? languageCode}) =>
      _build(Brightness.dark, languageCode);

  static bool _uprightTitles(String? languageCode) {
    final String code =
        languageCode ?? PlatformDispatcher.instance.locale.languageCode;
    return code == 'ja' || code == 'zh';
  }

  static ThemeData _build(Brightness brightness, String? languageCode) {
    final AppNeutrals n = AppColors.neutrals(brightness);
    final bool upright = _uprightTitles(languageCode);

    TextStyle serif(double size, {double height = 1.1}) => TextStyle(
          fontFamily: upright ? AppFonts.sans : AppFonts.serif,
          fontStyle: upright ? FontStyle.normal : FontStyle.italic,
          fontWeight: upright ? FontWeight.w500 : FontWeight.w400,
          fontSize: size,
          height: height,
          letterSpacing: upright ? 0 : -0.5,
          color: n.text,
        );

    TextStyle sans(
      double size, {
      FontWeight weight = FontWeight.w400,
      Color? color,
      double letterSpacing = 0,
    }) =>
        TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          color: color ?? n.text,
        );

    final TextTheme textTheme = TextTheme(
      displayLarge: serif(56, height: 1),
      displayMedium: serif(48, height: 1),
      displaySmall: serif(40, height: 1),
      headlineLarge: serif(34),
      headlineMedium: serif(30),
      headlineSmall: serif(26),
      titleLarge: serif(26),
      titleMedium: sans(16, weight: FontWeight.w500),
      titleSmall: sans(14, weight: FontWeight.w500),
      bodyLarge: sans(16),
      bodyMedium: sans(14),
      bodySmall: sans(13, color: n.muted),
      labelLarge: sans(14, weight: FontWeight.w500),
      labelMedium: sans(12, weight: FontWeight.w500),
      labelSmall: sans(12, color: n.muted, letterSpacing: 0.84),
    );

    final AppTypography typography = AppTypography(
      listTitle: serif(150, height: 0.9).copyWith(letterSpacing: upright ? 0 : -4),
      screenTitle: serif(48, height: 1),
      row: sans(16, weight: FontWeight.w500),
      meta: sans(13, color: n.muted),
      sectionLabel: sans(
        12,
        weight: FontWeight.w500,
        color: n.muted,
        letterSpacing: 0.84,
      ),
    );

    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.appBlue,
      brightness: brightness,
    ).copyWith(
      primary: n.text,
      onPrimary: n.ground,
      primaryContainer: n.surface,
      onPrimaryContainer: n.text,
      secondary: AppColors.appBlue,
      onSecondary: AppColors.onAppBlue,
      secondaryContainer: n.surface,
      onSecondaryContainer: n.text,
      tertiary: n.muted,
      onTertiary: n.ground,
      surface: n.ground,
      onSurface: n.text,
      onSurfaceVariant: n.muted,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: n.ground,
      surfaceContainerLow: n.ground,
      surfaceContainer: n.surface,
      surfaceContainerHigh: n.surface,
      surfaceContainerHighest: n.surface,
      outline: n.muted,
      outlineVariant: n.line,
      inverseSurface: n.text,
      onInverseSurface: n.ground,
      shadow: Colors.black,
    );

    final TextStyle buttonText = sans(15, weight: FontWeight.w500);
    const EdgeInsets buttonPadding =
        EdgeInsets.symmetric(horizontal: 20, vertical: 12);
    final OutlineInputBorder fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppShapes.fieldRadius),
      borderSide: BorderSide(color: n.line),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: AppFonts.sans,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: n.ground,
      canvasColor: n.ground,
      textTheme: textTheme,
      extensions: [typography],
      iconTheme: IconThemeData(color: n.text),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SlidePageTransitionsBuilder(),
          TargetPlatform.iOS: SlidePageTransitionsBuilder(),
          TargetPlatform.linux: SlidePageTransitionsBuilder(),
          TargetPlatform.macOS: SlidePageTransitionsBuilder(),
          TargetPlatform.windows: SlidePageTransitionsBuilder(),
          TargetPlatform.fuchsia: SlidePageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: n.ground,
        foregroundColor: n.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: serif(28),
      ),
      cardTheme: CardThemeData(
        color: n.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShapes.fieldRadius),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: n.muted,
        titleTextStyle: sans(16, weight: FontWeight.w500),
        subtitleTextStyle: sans(13, color: n.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: n.text,
          foregroundColor: n.ground,
          disabledBackgroundColor: n.surface,
          disabledForegroundColor: n.muted,
          textStyle: buttonText,
          padding: buttonPadding,
          shape: AppShapes.pill,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: n.surface,
          foregroundColor: n.text,
          elevation: 0,
          textStyle: buttonText,
          padding: buttonPadding,
          shape: AppShapes.pill,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: n.text,
          side: BorderSide(color: n.text),
          textStyle: buttonText,
          padding: buttonPadding,
          shape: AppShapes.pill,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: n.text,
          textStyle: buttonText,
          shape: AppShapes.pill,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: n.text),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: n.text,
        foregroundColor: n.ground,
        elevation: 6,
        highlightElevation: 6,
        shape: const CircleBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        labelStyle: sans(15, color: n.muted),
        hintStyle: sans(15, color: n.muted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: n.text, width: 1.5),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        side: BorderSide(color: n.muted, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? n.text
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(n.ground),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? n.text : n.muted,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? n.ground : n.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? n.text : n.surface,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : n.line,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: n.ground,
        selectedColor: n.surface,
        side: BorderSide(color: n.line),
        shape: AppShapes.pill,
        labelStyle: sans(14, weight: FontWeight.w500),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: n.ground,
        modalBackgroundColor: n.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        modalElevation: 8,
        shape: AppShapes.sheet,
        showDragHandle: true,
        dragHandleColor: n.line,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: n.ground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShapes.sheetRadius),
        ),
        titleTextStyle: serif(28),
        contentTextStyle: sans(15),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: n.ground,
        surfaceTintColor: Colors.transparent,
        textStyle: sans(15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShapes.fieldRadius),
          side: BorderSide(color: n.line),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: n.text,
        contentTextStyle: sans(14, color: n.ground),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShapes.fieldRadius),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: n.ground,
        indicatorColor: n.surface,
        labelTextStyle: WidgetStatePropertyAll(
          sans(12, weight: FontWeight.w500),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: n.text),
      dividerTheme: DividerThemeData(color: n.line, thickness: 1, space: 1),
    );
  }
}
