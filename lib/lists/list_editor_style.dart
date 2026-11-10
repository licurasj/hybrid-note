import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../app_colors.dart';

// Shared pieces of the list editor's look, direction A "Eclipse"
// (docs/AESTHETICS.md): uppercase section labels, hairline rows and bare
// fields. Black, white and grey only; the list's colour shows in its swatch.
class EditorLook {
  const EditorLook._(this.neutrals, this.type);

  factory EditorLook.of(BuildContext context) {
    return EditorLook._(
      AppColors.neutrals(Theme.of(context).brightness),
      AppTypography.of(context),
    );
  }

  final AppNeutrals neutrals;
  final AppTypography type;

  TextStyle get label =>
      type.row.copyWith(fontSize: 15, fontWeight: FontWeight.w400);
  TextStyle get strong => label.copyWith(fontWeight: FontWeight.w500);
  TextStyle get value => label.copyWith(color: neutrals.muted);

  // The settings hierarchy (owner, 2026-11-09), largest first: a section's
  // heading in the serif, a setting's name (type.row), then a sub-option
  // ([subLabel]) and the grey line (type.meta).
  TextStyle get heading =>
      type.screenTitle.copyWith(fontSize: 26, height: 1.15);
  TextStyle get subLabel =>
      type.row.copyWith(fontSize: 14, fontWeight: FontWeight.w400);

  // A settings section's heading ("Items"), with room above it.
  Widget section(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 34, bottom: 2),
      child: Text(text, style: heading),
    );
  }

  // A field's small label ("LIST NAME"), with room above it.
  Widget sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 6),
      child: Text(text.toUpperCase(), style: type.sectionLabel),
    );
  }

  // A row over a hairline.
  Widget hairline({Key? key, required Widget child}) {
    return DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: neutrals.line)),
      ),
      child: child,
    );
  }

  // A label on the left and its value on the right, over a hairline.
  Widget settingRow({required String label, required Widget value}) {
    return hairline(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        // The label takes at most half the row; what it leaves goes before
        // the value, so values line up at the right edge.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text(label, style: this.label)),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 16),
                child: value,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // A text-style button with a leading "+", as "Add field" and "Add rule".
  Widget addButton({
    required Key key,
    required String text,
    required VoidCallback onPressed,
  }) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: key,
        style: AppInk.pressless(
          TextButton.styleFrom(
            foregroundColor: neutrals.text,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 0),
            textStyle: strong,
          ),
        ),
        icon: const Icon(Icons.add, size: 20),
        label: Text(text),
        onPressed: onPressed,
      ),
    );
  }

  // No box and no line: the theme's outlined fields would otherwise show.
  static InputDecoration bare({String? hint, TextStyle? hintStyle}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: hintStyle,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
    );
  }
}
