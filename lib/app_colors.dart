import 'package:flutter/material.dart';

// Colour tokens for direction A "Eclipse" (docs/AESTHETICS.md): black, white
// and grey carry every screen, the open list's colour speaks, and the logo
// blue marks app-level controls only.
class AppColors {
  const AppColors._();

  // App blue (logo) and the glyph colour on it.
  static const Color appBlue = Color(0xFF70D9FF);
  static const Color onAppBlue = Color(0xFF06151C);

  // Text or check marks on a list colour: whichever contrasts more.
  static const Color onColorLight = Color(0xFFFFFFFF);
  static const Color onColorDark = Color(0xFF111111);

  // Behind a sheet, in both themes. It appears and goes at once, without a fade.
  static const Color scrim = Color(0x57000000);

  static Color onColor(Color background) {
    final double luminance = background.computeLuminance();
    final double withLight =
        (onColorLight.computeLuminance() + 0.05) / (luminance + 0.05);
    final double withDark =
        (luminance + 0.05) / (onColorDark.computeLuminance() + 0.05);
    return withLight >= withDark ? onColorLight : onColorDark;
  }

  static AppNeutrals neutrals(Brightness brightness) =>
      brightness == Brightness.dark ? AppNeutrals.dark : AppNeutrals.light;
}

// Ground, text and line greys for one brightness.
class AppNeutrals {
  const AppNeutrals({
    required this.ground,
    required this.text,
    required this.muted,
    required this.line,
    required this.surface,
    required this.promptDark,
  });

  final Color ground;
  final Color text;
  final Color muted;
  final Color line;
  final Color surface;

  // The dark fill a prompt starts from before it fills with its colour.
  final Color promptDark;

  static const AppNeutrals light = AppNeutrals(
    ground: Color(0xFFFFFFFF),
    text: Color(0xFF0B0B0C),
    muted: Color(0xFF66666C),
    line: Color(0xFFECECEE),
    surface: Color(0xFFF3F3F4),
    promptDark: Color(0xFF1E1E21),
  );

  static const AppNeutrals dark = AppNeutrals(
    ground: Color(0xFF000000),
    text: Color(0xFFF4F4F5),
    muted: Color(0xFF8F8F96),
    line: Color(0xFF1C1C1F),
    surface: Color(0xFF141416),
    promptDark: Color(0xFF2A2A2E),
  );
}

// One list colour: the light value is what a list definition stores.
class ListPaletteColor {
  const ListPaletteColor(this.name, this.light, this.dark);

  final String name;
  final Color light;
  final Color dark;

  Color resolve(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

const List<ListPaletteColor> listPalette = [
  ListPaletteColor('orange', Color(0xFFFF4D12), Color(0xFFFF6A3D)),
  ListPaletteColor('green', Color(0xFF00A63E), Color(0xFF2BD46A)),
  ListPaletteColor('magenta', Color(0xFFE5007E), Color(0xFFFF3FA4)),
  ListPaletteColor('violet', Color(0xFF6B3BFF), Color(0xFF8F6BFF)),
  ListPaletteColor('yellow', Color(0xFFF5B800), Color(0xFFFFCA2C)),
  ListPaletteColor('rose', Color(0xFFFF2D55), Color(0xFFFF5470)),
  ListPaletteColor('teal', Color(0xFF00A99D), Color(0xFF2ED9C8)),
  ListPaletteColor('blue', Color(0xFF2F5BFF), Color(0xFF5C7CFF)),
];
