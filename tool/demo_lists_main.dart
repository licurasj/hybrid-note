// Phone test build with many lists on the dial, without touching the
// account's data (T-16 unit 6): the real app plus made-up lists that show on
// the dial only and open nothing.
//
//   flutter build apk --release --target-platform android-arm64 \
//     -t tool/demo_lists_main.dart
import 'package:flutter/material.dart';

import 'package:hybrid_note/launcher/dial_launcher.dart';
import 'package:hybrid_note/launcher/radial_launcher.dart';
import 'package:hybrid_note/main.dart' as app;

const List<(String, Color)> _lists = [
  ('Books', Color(0xFF3D5AFE)),
  ('Recipes', Color(0xFFE64A19)),
  ('Gifts', Color(0xFFC2185B)),
  ('Travel', Color(0xFF00897B)),
  ('Gym', Color(0xFF5D4037)),
  ('Movies', Color(0xFF7B1FA2)),
  ('Ideas', Color(0xFFF5B800)),
  ('Errands', Color(0xFF2E7D32)),
  ('Garden', Color(0xFF00ACC1)),
  ('Music', Color(0xFFD81B60)),
];

Future<void> main() async {
  debugDialExtraNotes.addAll([
    for (final (String name, Color color) in _lists)
      LauncherNote(
        id: 'demo-$name',
        label: name,
        icon: Icons.list_alt,
        color: color,
        semanticsLabel: name,
      ),
  ]);
  await app.main();
}
