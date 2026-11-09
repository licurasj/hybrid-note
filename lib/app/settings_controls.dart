import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../lists/list_editor_style.dart';

// The settings controls of the Preferences page and the list editor (T-24,
// Q-112 to Q-114): every choice is on the page, one tap to change it, with no
// pop-up; a short grey line under a row says what the current choice does
// and changes with it; a row that does not apply now stays where it is,
// greyed, with a line saying why, so nothing below it moves (Q-113, rule 7).

// One choice: what is stored, its name, and an optional line shown under the
// control while it is the one picked.
typedef SettingChoice<T> = ({T value, String label, String? line});

SettingChoice<T> choice<T>(T value, String label, {String? line}) =>
    (value: value, label: label, line: line);

// The grey line under a row.
class SettingLine extends StatelessWidget {
  const SettingLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final EditorLook look = EditorLook.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Text(text, style: look.type.meta),
    );
  }
}

// Greys a row that does not apply now; it cannot be changed meanwhile.
Widget _greyed(bool enabled, Widget child) => enabled
    ? child
    : Opacity(opacity: 0.45, child: IgnorePointer(child: child));

// A label with its choices as a row of pill buttons under it, the picked one
// filled; for a few short choices. Long names wrap onto a second line.
class SettingButtonsRow<T> extends StatelessWidget {
  const SettingButtonsRow({
    super.key,
    required this.label,
    required this.selected,
    required this.choices,
    required this.onChanged,
    this.line,
    this.enabled = true,
  });

  final String label;
  final T selected;
  final List<SettingChoice<T>> choices;
  final ValueChanged<T>? onChanged;
  // Shown under the buttons; a picked choice's own line comes first.
  final String? line;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final EditorLook look = EditorLook.of(context);
    final AppNeutrals n = look.neutrals;
    final String? shown =
        choices.where((c) => c.value == selected).firstOrNull?.line ?? line;
    return look.hairline(
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _greyed(
              enabled,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(label, style: look.type.row),
                  const SizedBox(height: 10),
                  Semantics(
                    label: label,
                    explicitChildNodes: true,
                    child: Row(
                      children: [
                        for (final (int i, SettingChoice<T> c)
                            in choices.indexed) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: Semantics(
                              selected: c.value == selected,
                              inMutuallyExclusiveGroup: true,
                              button: true,
                              child: _Pill(
                                key: ValueKey('choice-${c.value}'),
                                text: c.label,
                                picked: c.value == selected,
                                neutrals: n,
                                style: look.type.meta.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                onTap: onChanged == null || !enabled
                                    ? null
                                    : () => onChanged!(c.value),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (shown != null)
              SettingLine(shown)
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.text,
    required this.picked,
    required this.neutrals,
    required this.style,
    required this.onTap,
  });

  final String text;
  final bool picked;
  final AppNeutrals neutrals;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: picked ? neutrals.text : neutrals.ground,
      shape: StadiumBorder(
        side: BorderSide(color: picked ? neutrals.text : neutrals.line),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: style.copyWith(
              color: picked ? neutrals.ground : neutrals.text,
            ),
          ),
        ),
      ),
    );
  }
}

// A label with its choices listed under it, one per line with a round mark,
// each with an optional line of its own under the picked one; for longer
// names.
class SettingOptionList<T> extends StatelessWidget {
  const SettingOptionList({
    super.key,
    required this.label,
    required this.selected,
    required this.choices,
    required this.onChanged,
    this.line,
    this.enabled = true,
  });

  final String label;
  final T selected;
  final List<SettingChoice<T>> choices;
  final ValueChanged<T>? onChanged;
  // Under the whole list, for a reason it is greyed.
  final String? line;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final EditorLook look = EditorLook.of(context);
    final AppNeutrals n = look.neutrals;
    return look.hairline(
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _greyed(
              enabled,
              Semantics(
                label: label,
                explicitChildNodes: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(label, style: look.type.row),
                    const SizedBox(height: 4),
                    for (final SettingChoice<T> c in choices)
                      Semantics(
                        selected: c.value == selected,
                        inMutuallyExclusiveGroup: true,
                        button: true,
                        child: InkWell(
                          key: ValueKey('choice-${c.value}'),
                          onTap: onChanged == null || !enabled
                              ? null
                              : () => onChanged!(c.value),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 44),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Icon(
                                    c.value == selected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 22,
                                    color: n.text,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(c.label, style: look.label),
                                      if (c.value == selected && c.line != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            c.line!,
                                            key: ValueKey(
                                              'choice-line-${c.value}',
                                            ),
                                            style: look.type.meta,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (line != null) SettingLine(line!) else const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// A label and a switch, a tap anywhere on the row flips it, with an optional
// grey line under it. Greyed and fixed while [onChanged] is null.
class SettingSwitchRow extends StatelessWidget {
  const SettingSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.line,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? line;

  @override
  Widget build(BuildContext context) {
    final EditorLook look = EditorLook.of(context);
    final ValueChanged<bool>? change = onChanged;
    return look.hairline(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _greyed(
            change != null,
            MergeSemantics(
              child: InkWell(
                onTap: change == null ? null : () => change(!value),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(label, style: look.type.row)),
                      const SizedBox(width: 12),
                      Switch(
                        value: value,
                        activeTrackColor: AppColors.appBlue,
                        onChanged: change,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (line != null)
            Padding(
              padding: const EdgeInsets.only(top: 0),
              child: SettingLine(line!),
            ),
        ],
      ),
    );
  }
}

// A picked value that opens its choices in place, under it, instead of a
// drop-down or pop-up (T-24, Q-112); picking one closes it again. For the
// list editor's field types, layout details and rule settings.
class SettingFoldPicker<T> extends StatefulWidget {
  const SettingFoldPicker({
    super.key,
    this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.alignEnd = true,
    this.style,
  });

  // On the left of the row; without one the value starts the row.
  final String? label;
  final T? value;
  // Each choice's value and what it shows.
  final List<({T value, Widget child})> choices;
  final ValueChanged<T?>? onChanged;
  final bool alignEnd;
  final TextStyle? style;

  @override
  State<SettingFoldPicker<T>> createState() => _SettingFoldPickerState<T>();
}

class _SettingFoldPickerState<T> extends State<SettingFoldPicker<T>> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final EditorLook look = EditorLook.of(context);
    final AppNeutrals n = look.neutrals;
    final ({T value, Widget child})? current = widget.choices
        .where((c) => c.value == widget.value)
        .firstOrNull;
    final bool enabled = widget.onChanged != null;
    final Widget shown = DefaultTextStyle.merge(
      style: widget.style ?? look.value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      child: current?.child ?? const SizedBox.shrink(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: enabled ? () => setState(() => _open = !_open) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                if (widget.label != null) ...[
                  Text(widget.label!, style: look.label),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Align(
                    alignment: widget.alignEnd
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    child: shown,
                  ),
                ),
                if (enabled)
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: n.muted,
                  ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final ({T value, Widget child}) c in widget.choices)
                  Semantics(
                    selected: c.value == widget.value,
                    inMutuallyExclusiveGroup: true,
                    button: true,
                    child: InkWell(
                      onTap: () {
                        setState(() => _open = false);
                        widget.onChanged?.call(c.value);
                      },
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 40),
                        padding: const EdgeInsetsDirectional.only(start: 4),
                        child: Row(
                          children: [
                            Icon(
                              c.value == widget.value
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              size: 20,
                              color: n.text,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DefaultTextStyle.merge(
                                style: look.label,
                                child: c.child,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// A section whose rows fold away under its header, which names what it holds
// ("Fields · 4") (Q-115 C). [open] starts it open; [forceOpen] keeps it open,
// for a section with a problem in it.
class FoldSection extends StatefulWidget {
  const FoldSection({
    super.key,
    required this.title,
    required this.children,
    this.open = false,
    this.forceOpen = false,
  });

  final String title;
  final List<Widget> children;
  final bool open;
  final bool forceOpen;

  @override
  State<FoldSection> createState() => _FoldSectionState();
}

class _FoldSectionState extends State<FoldSection> {
  late bool _open = widget.open;

  @override
  Widget build(BuildContext context) {
    final EditorLook look = EditorLook.of(context);
    final bool open = _open || widget.forceOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            onTap: widget.forceOpen ? null : () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.only(top: 22, bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title.toUpperCase(),
                      style: look.type.sectionLabel,
                    ),
                  ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: look.neutrals.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open) ...widget.children,
      ],
    );
  }
}
