import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The list editor folds Fields, Layout and Rules for an existing list
// (T-24, Q-115 C). Opens each one that is folded, found by a row it holds.
Future<void> openEditorSections(WidgetTester tester) async {
  const Map<String, String> inside = {
    'section-fields': 'add-field',
    'section-layout': 'view-kind',
    'section-rules': 'rule-clearCompleted',
  };
  for (final MapEntry<String, String> section in inside.entries) {
    final Finder header = find.byKey(ValueKey(section.key));
    if (header.evaluate().isEmpty ||
        find.byKey(ValueKey(section.value)).evaluate().isNotEmpty) {
      continue;
    }
    final Finder tap = find
        .descendant(of: header, matching: find.byType(InkWell))
        .first;
    await tester.ensureVisible(tap);
    await tester.pumpAndSettle();
    await tester.tap(tap);
    await tester.pumpAndSettle();
  }
}
