import 'package:flutter/material.dart';

import '../app_colors.dart';

// Icon names a list definition may use. Flutter cannot look icons up by
// name at runtime, so the supported names are listed; others fall back.
const Map<String, IconData> listIcons = {
  'pending_actions': Icons.pending_actions,
  'checklist': Icons.checklist,
  'shopping_cart': Icons.shopping_cart,
  'book': Icons.book,
  'movie': Icons.movie,
  'local_florist': Icons.local_florist,
  'list': Icons.list_alt,
};

IconData listIcon(String name) => listIcons[name] ?? Icons.list_alt;

// Colours offered in the list editor: the light values of the palette.
final List<String> listColorChoices = [
  for (final ListPaletteColor color in listPalette) _hex(color.light),
];

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

// #RRGGBB to a Color. The stored value is the light one (Q-19 A): in dark mode
// a palette colour maps to its dark variant, and any other colour is used as
// it is. A value that is not a colour falls back to the muted grey.
Color listColor(String hex, {Brightness brightness = Brightness.light}) {
  final int? value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  if (value == null || hex.length != 7 || !hex.startsWith('#')) {
    return AppColors.neutrals(brightness).muted;
  }
  return resolveListColor(Color(0xFF000000 | value), brightness);
}

// Maps a stored (light) list colour to the one for this brightness.
Color resolveListColor(Color color, Brightness brightness) {
  if (brightness == Brightness.light) {
    return color;
  }
  for (final ListPaletteColor entry in listPalette) {
    if (entry.light.toARGB32() == color.toARGB32()) {
      return entry.dark;
    }
  }
  return color;
}
