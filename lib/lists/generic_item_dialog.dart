import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';

import '../app/account_preferences.dart';
import '../app/app_theme.dart';
import '../app/date_preferences.dart';
import '../app_colors.dart';
import '../l10n/generated/app_localizations.dart';
import 'builtin_templates.dart';
import 'item_dates.dart';
import 'list_definition.dart';
import 'list_error.dart';
import 'list_icons.dart';
import 'list_item.dart';
import 'list_labels.dart';
import 'list_rules.dart';
import 'list_vocabulary.dart';

// Add/edit sheet generated from a definition's fields, in direction A
// "Eclipse" (docs/AESTHETICS.md): a large title field, the description, label
// and value rows, subtasks, and Save in the list's colour. Open it with
// showItemSheet. Pops the edited item, or nothing when cancelled. Values of
// fields it does not show are kept.
class GenericItemDialog extends StatefulWidget {
  const GenericItemDialog({
    super.key,
    required this.definition,
    required this.title,
    this.item,
    this.initialValues = const {},
  });

  final ListDefinition definition;
  final String title;
  final ListItem? item;
  // Pre-filled values for a new item, e.g. the category filter in use.
  final Map<String, dynamic> initialValues;

  @override
  State<GenericItemDialog> createState() {
    return _GenericItemDialogState();
  }
}

class _SubItemDraft {
  _SubItemDraft({
    required this.id,
    required this.done,
    required String title,
    this.original,
  }) : controller = TextEditingController(text: title);

  final String id;
  bool done;
  final TextEditingController controller;
  final FocusNode focus = FocusNode();
  final Map<String, dynamic>? original;
}

class _GenericItemDialogState extends State<GenericItemDialog>
    with SingleTickerProviderStateMixin {
  // A Journal entry's sheet grows for reading (Q-71): a tap on the bar at its top,
  // or a drag up, takes it to almost the full screen, where the text fills the
  // space, and a drag down brings it back. Every other list keeps the small sheet.
  bool get _canGrow =>
      widget.item != null &&
      widget.definition.templateId == BuiltinTemplates.journalId;
  double _smallHeight = 0;
  // How far above the small height it stands now.
  double _grown = 0;
  bool _big = false;
  // Where the press on the bar began, and whether it can still be a tap.
  Offset _barPressedAt = Offset.zero;
  bool _barTapping = false;
  // The text in the big sheet is being edited; until then, no keyboard.
  bool _editingBig = false;
  final ScrollController _bigScroll = ScrollController();
  late final AnimationController _settle;

  double _mostGrown(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final double most =
        media.size.height - media.viewInsets.bottom - media.padding.top - 24;
    return math.max(0, most - _smallHeight);
  }

  void _barDown(PointerDownEvent event) {
    _settle.stop();
    _barPressedAt = event.position;
    _barTapping = true;
    if (_grown == 0) {
      _smallHeight = context.size?.height ?? 0;
    }
  }

  void _barMoved(PointerMoveEvent event) {
    if ((event.position - _barPressedAt).distance > kTouchSlop) {
      _barTapping = false;
    }
    final double dy = event.delta.dy;
    if (dy < 0 || _grown > 0) {
      setState(() {
        _grown = (_grown - dy).clamp(0.0, _mostGrown(context));
        _editingBig = false;
      });
    }
  }

  void _barUp(PointerEvent event) {
    final double most = _mostGrown(context);
    final bool tapped = event is PointerUpEvent && _barTapping;
    if (_grown == 0 && !_big && !tapped) {
      return;
    }
    // A tap expands it. Otherwise, past a third of the way, from either end, it
    // goes on to that end.
    final bool big =
        most > 0 && (tapped || _grown > most * (_big ? 2 / 3 : 1 / 3));
    final double target = big ? most : 0;
    _big = big;
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route is _ItemSheetRoute) {
      route.setDragEnabled(!big);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _grown = target);
    } else {
      _settle
        ..value = _grown
        ..animateTo(
          target,
          duration: AppMotion.standard,
          curve: AppMotion.curve,
        );
    }
  }

  // The entry's text, filling the big sheet, with the bar only when it is too
  // long. A tap makes it editable, and the keyboard comes then.
  Widget _bigText(_Look look, FieldDefinition field, String label) {
    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(look.neutrals.muted),
        thickness: const WidgetStatePropertyAll(4),
        radius: const Radius.circular(2),
      ),
      child: Scrollbar(
        controller: _bigScroll,
        thumbVisibility: true,
        child: TextField(
          key: ValueKey('field-${field.key}'),
          controller: _controllers[field.key],
          scrollController: _bigScroll,
          readOnly: !_editingBig,
          showCursor: _editingBig,
          expands: true,
          minLines: null,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
          style: look.body,
          onTap: () => setState(() => _editingBig = true),
          onChanged: (_) => setState(() {}),
          decoration: _bare(
            label,
            look.body.copyWith(color: look.neutrals.muted),
          ),
        ),
      ),
    );
  }

  late final Map<String, dynamic> _values;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, List<_SubItemDraft>> _subItems = {};
  // Removed subtask drafts, kept until the sheet closes: their text field may
  // still be unmounting when they are removed.
  final List<_SubItemDraft> _removedDrafts = [];
  final Map<String, TextEditingController> _customDays = {};
  String? _error;

  static bool _isTextType(FieldType type) {
    return type == FieldType.text ||
        type == FieldType.longText ||
        type == FieldType.url;
  }

  static bool _isNumberType(FieldType type) {
    return type == FieldType.counter ||
        type == FieldType.number ||
        type == FieldType.rating;
  }

  @override
  void initState() {
    super.initState();
    _settle = AnimationController.unbounded(vsync: this)
      ..addListener(() => setState(() => _grown = _settle.value));
    _values = Map<String, dynamic>.from(widget.item?.values ?? const {});

    for (final FieldDefinition field in widget.definition.fields) {
      if (widget.item == null) {
        if (widget.initialValues.containsKey(field.key)) {
          _values[field.key] = widget.initialValues[field.key];
        } else if (field.defaultValue != null) {
          _values[field.key] = field.defaultValue;
        }
      }

      final Object? value = _values[field.key];
      if (_isTextType(field.type)) {
        _controllers[field.key] = TextEditingController(
          text: value is String ? value : '',
        );
      } else if (_isNumberType(field.type)) {
        // 0 shows as blank, as on the old screens.
        _controllers[field.key] = TextEditingController(
          text: value is num && value != 0 ? '$value' : '',
        );
      } else if (field.type == FieldType.tags) {
        _controllers[field.key] = TextEditingController(
          text: value is List ? value.join(', ') : '',
        );
      } else if (field.type == FieldType.checklist) {
        _subItems[field.key] = [
          if (value is List)
            for (final Object? entry in value)
              if (entry is Map)
                _SubItemDraft(
                  id: '${entry['id']}',
                  done: entry['done'] == true,
                  title: '${entry['title'] ?? ''}',
                  original: Map<String, dynamic>.from(entry),
                ),
        ];
      } else if (field.type == FieldType.recurrence) {
        final Object? days = value is Map ? value['customDays'] : null;
        _customDays[field.key] = TextEditingController(
          text: days is int ? '$days' : '',
        );
      }
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    _bigScroll.dispose();
    for (final TextEditingController controller in [
      ..._controllers.values,
      ..._customDays.values,
      for (final List<_SubItemDraft> drafts in _subItems.values)
        for (final _SubItemDraft draft in drafts) draft.controller,
      for (final _SubItemDraft draft in _removedDrafts) draft.controller,
    ]) {
      controller.dispose();
    }
    for (final _SubItemDraft draft in [
      for (final List<_SubItemDraft> drafts in _subItems.values) ...drafts,
      ..._removedDrafts,
    ]) {
      draft.focus.dispose();
    }
    super.dispose();
  }

  bool get _requiredFieldsFilled {
    for (final FieldDefinition field in widget.definition.fields) {
      final TextEditingController? controller = _controllers[field.key];
      if (field.required &&
          _isTextType(field.type) &&
          controller != null &&
          controller.text.trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> _collectValues(DateTime now) {
    final Map<String, dynamic> values = Map<String, dynamic>.from(_values);

    for (final FieldDefinition field in widget.definition.fields) {
      final TextEditingController? controller = _controllers[field.key];
      final String text = controller?.text.trim() ?? '';

      if (_isTextType(field.type)) {
        values[field.key] = text;
      } else if (field.type == FieldType.number) {
        final num? parsed = num.tryParse(text);
        if (parsed == null) {
          values.remove(field.key);
        } else {
          values[field.key] = parsed;
        }
      } else if (_isNumberType(field.type)) {
        values[field.key] = int.tryParse(text) ?? 0;
      } else if (field.type == FieldType.tags) {
        values[field.key] = text
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList();
      } else if (field.type == FieldType.checklist) {
        values[field.key] = [
          for (final _SubItemDraft draft in _subItems[field.key]!)
            if (draft.controller.text.trim().isNotEmpty)
              _subItemJson(draft, now),
        ];
      } else if (field.type == FieldType.recurrence) {
        final Object? current = values[field.key];
        final String frequency = current is Map
            ? '${current['frequency']}'
            : RecurrenceFrequency.none.wire;
        values[field.key] = {
          'frequency': frequency,
          if (frequency == RecurrenceFrequency.custom.wire)
            'customDays': int.tryParse(_customDays[field.key]!.text.trim()),
        };
      }
    }

    for (final FieldDefinition field in widget.definition.fields) {
      if (!field.isVisibleFor(values)) {
        values.remove(field.key);
      }
    }

    return values;
  }

  Map<String, dynamic> _subItemJson(_SubItemDraft draft, DateTime now) {
    final String title = draft.controller.text.trim();
    final Map<String, dynamic>? original = draft.original;
    final bool changed =
        original == null ||
        original['title'] != title ||
        original['done'] != draft.done;

    return {
      'id': draft.id,
      'title': title,
      'done': draft.done,
      'createdAt': original?['createdAt'] ?? now.toIso8601String(),
      'updatedAt': changed ? now.toIso8601String() : original['updatedAt'],
    };
  }

  void _save() {
    final DateTime now = DateTime.now().toUtc();
    final ListItem result = ListRules.normalize(
      widget.definition,
      ListItem(
        id: widget.item?.id ?? const Uuid().v4(),
        listId: widget.definition.id,
        values: _collectValues(now),
        createdAt: widget.item?.createdAt ?? now,
        updatedAt: now,
      ),
    );

    final List<ListError> errors = result.validateAgainst(widget.definition);
    if (errors.isNotEmpty) {
      setState(() {
        _error = ListLabels(
          AppLocalizations.of(context),
        ).error(errors.first, widget.definition);
      });
      return;
    }

    Navigator.of(context).pop(result);
  }

  // The pickers in this list's colour (Q-122 A).
  Widget _inListColour(BuildContext context, Widget child) {
    final ThemeData theme = Theme.of(context);
    return Theme(
      data: AppTheme.pickerTheme(
        context,
        listColor(widget.definition.color, brightness: theme.brightness),
      ),
      child: child,
    );
  }

  Future<void> _pickDate(FieldDefinition field) async {
    final Object? raw = _values[field.key];
    final DateTime current =
        (raw is String ? DateTime.tryParse(raw) : null)?.toLocal() ??
        DateTime.now();

    final AccountPreferences preferences = context.accountPreferences;
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => _inListColour(
        context,
        datePickerIn(preferences.weekStart, context, child),
      ),
    );
    if (day == null || !mounted) {
      return;
    }

    TimeOfDay time = ItemDates.hasTime(field.type, raw)
        ? TimeOfDay.fromDateTime(current)
        : TimeOfDay.now();
    // The time step offers No time: the day alone, which rings in the
    // morning when the field is a reminder (T-13, Q-91).
    bool noTime = false;
    if (field.type == FieldType.dateTime) {
      final TimeOfDay? picked = await showTimePicker(
        context: context,
        initialTime: time,
        builder: (context, child) => _inListColour(
          context,
          timePickerIn(
            preferences.timeFormat,
            context,
            _WithNoTime(
              label: AppLocalizations.of(context).noTime,
              onNoTime: () {
                noTime = true;
                Navigator.of(context).pop();
              },
              child: child,
            ),
          ),
        ),
      );
      if (!mounted || (picked == null && !noTime)) {
        return;
      }
      time = picked ?? time;
    }

    final String value;
    if (field.type == FieldType.dateTime && !noTime) {
      value = DateTime(day.year, day.month, day.day, time.hour, time.minute)
          .toUtc()
          .toIso8601String();
    } else if (field.type == FieldType.dateTime) {
      value = ItemDates.dayValue(day);
    } else {
      // A date field keeps the form it has always stored.
      value = DateTime(day.year, day.month, day.day).toUtc().toIso8601String();
    }

    setState(() {
      _values[field.key] = value;
    });
  }

  Future<void> _newCategory(FieldDefinition field, ListLabels labels) async {
    final TextEditingController controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(labels.loc.createCategory),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: labels.loc.categoryName),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(labels.loc.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(labels.loc.create),
            ),
          ],
        );
      },
    );

    final String cleaned = name?.trim() ?? '';
    if (cleaned.isNotEmpty && mounted) {
      setState(() {
        _values[field.key] = cleaned;
      });
    }
  }

  static IconData _icon(FieldDefinition field) {
    switch (field.type) {
      case FieldType.text:
      case FieldType.longText:
        return Icons.short_text;
      case FieldType.url:
        return Icons.link;
      case FieldType.tags:
        return Icons.tag;
      case FieldType.counter:
      case FieldType.number:
        return Icons.numbers;
      case FieldType.rating:
        return Icons.star_outline;
      case FieldType.choice:
        return Icons.radio_button_checked;
      case FieldType.category:
        return Icons.sell_outlined;
      case FieldType.checkbox:
        return Icons.check_circle_outline;
      case FieldType.toggle:
        return Icons.toggle_on_outlined;
      case FieldType.date:
      case FieldType.dateTime:
        return field.role == FieldRole.reminder
            ? Icons.notifications_none
            : Icons.event_outlined;
      case FieldType.recurrence:
        return Icons.repeat;
      case FieldType.checklist:
        return Icons.checklist;
    }
  }

  // An icon, a label and the value on the right, over a hairline.
  Widget _row(
    _Look look, {
    Key? key,
    required IconData icon,
    required String label,
    required Widget value,
    VoidCallback? onTap,
    // The value has its own width (a check or a switch): the label takes
    // the rest of the row.
    bool compact = false,
  }) {
    final Text text = Text(label, style: look.label);
    return InkWell(
      key: key,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: look.neutrals.line)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: look.neutrals.muted),
            const SizedBox(width: 12),
            if (compact) ...[
              Expanded(child: text),
              const SizedBox(width: 12),
              value,
            ] else
              // Long labels wrap at half the row instead of pushing the value
              // off it.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth / 2,
                        ),
                        child: text,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: value,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // No box and no line: the theme's outlined fields would otherwise show.
  static InputDecoration _bare(String? hint, TextStyle hintStyle) {
    return InputDecoration(
      hintText: hint,
      hintStyle: hintStyle,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
    );
  }

  // A typed value on the right of a row.
  Widget _inlineField(
    _Look look, {
    required Key key,
    required TextEditingController? controller,
    TextInputType? keyboardType,
    String? hint,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      textAlign: TextAlign.end,
      style: look.label,
      onChanged: onChanged,
      decoration: _bare(hint, look.value),
    );
  }

  // A picked value on the right of a row, with a chevron.
  Widget _dropdown<T>(
    _Look look, {
    required Key key,
    required T? value,
    required List<(T, String)> options,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        key: key,
        value: value,
        isExpanded: true,
        isDense: true,
        icon: Icon(Icons.chevron_right, size: 18, color: look.neutrals.muted),
        style: look.label,
        dropdownColor: look.neutrals.ground,
        borderRadius: BorderRadius.circular(AppShapes.fieldRadius),
        selectedItemBuilder: (_) => [
          for (final (T _, String text) in options)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                text,
                style: look.value,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        items: [
          for (final (T option, String text) in options)
            DropdownMenuItem(value: option, child: Text(text)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  // A round check in the list colour, as on the list screen.
  Widget _check(_Look look, bool value, ValueChanged<bool> onChanged) {
    const double scale = 1.15;
    return Transform.scale(
      scale: scale,
      child: Checkbox(
        value: value,
        onChanged: (value) => onChanged(value ?? false),
        shape: const CircleBorder(),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? look.color
              : Colors.transparent,
        ),
        checkColor: look.onColor,
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? look.color
                : look.neutrals.text,
            width: 1.75 / scale,
          ),
        ),
      ),
    );
  }

  // The large title field with a hairline under it.
  Widget _headline(_Look look, FieldDefinition field, String label) {
    final OutlineInputBorder none = OutlineInputBorder(
      borderSide: BorderSide.none,
      borderRadius: BorderRadius.zero,
    );
    return TextField(
      key: ValueKey('field-${field.key}'),
      controller: _controllers[field.key],
      style: look.headline,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: look.headline.copyWith(color: look.neutrals.muted),
        isDense: true,
        contentPadding: const EdgeInsets.only(top: 4, bottom: 10),
        border: none,
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: look.neutrals.line),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: look.neutrals.text),
        ),
      ),
    );
  }

  // Long text under the title, without a box.
  Widget _description(_Look look, FieldDefinition field, String label) {
    return TextField(
      key: ValueKey('field-${field.key}'),
      controller: _controllers[field.key],
      minLines: 1,
      maxLines: 4,
      style: look.body,
      onChanged: (_) => setState(() {}),
      decoration: _bare(label, look.body.copyWith(color: look.neutrals.muted)),
    );
  }

  Widget _editor(_Look look, ListLabels labels, FieldDefinition field) {
    final String label = labels.field(field) + (field.required ? ' *' : '');
    final TextEditingController? controller = _controllers[field.key];
    final Key key = ValueKey('field-${field.key}');
    final IconData icon = _icon(field);

    switch (field.type) {
      case FieldType.text:
      case FieldType.url:
        return _row(
          look,
          icon: icon,
          label: label,
          value: _inlineField(
            look,
            key: key,
            controller: controller,
            keyboardType: field.type == FieldType.url
                ? TextInputType.url
                : TextInputType.text,
            onChanged: (_) => setState(() {}),
          ),
        );
      case FieldType.longText:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: _description(look, field, label),
        );
      case FieldType.counter:
      case FieldType.number:
      case FieldType.rating:
        return _row(
          look,
          icon: icon,
          label: label,
          value: _inlineField(
            look,
            key: key,
            controller: controller,
            hint: '0',
            keyboardType: TextInputType.numberWithOptions(
              decimal: field.type == FieldType.number,
            ),
          ),
        );
      case FieldType.tags:
        return _row(
          look,
          icon: icon,
          label: label,
          value: _inlineField(
            look,
            key: key,
            controller: controller,
            hint: 'a, b, c',
          ),
        );
      case FieldType.choice:
        final Object? current = _values[field.key];
        return _row(
          look,
          icon: icon,
          label: label,
          value: _dropdown<String>(
            look,
            key: key,
            value: field.hasOption(current) ? current as String : null,
            options: [
              for (final FieldOption option in field.options)
                (option.value, labels.option(option)),
            ],
            onChanged: (value) {
              setState(() {
                _values[field.key] = value;
              });
            },
          ),
        );
      case FieldType.category:
        final Object? current = _values[field.key];
        final List<String> choices = [
          for (final FieldOption option in field.options) option.value,
          if (current is String &&
              current.isNotEmpty &&
              !field.hasOption(current))
            current,
        ];
        return _row(
          look,
          icon: icon,
          label: label,
          value: Row(
            children: [
              Expanded(
                child: _dropdown<String>(
                  look,
                  // Rebuild when a new category is typed in.
                  key: ValueKey('field-${field.key}-$current'),
                  value: current is String && current.isNotEmpty ? current : '',
                  options: [
                    ('', labels.loc.none),
                    for (final String choice in choices) (choice, choice),
                  ],
                  onChanged: (value) {
                    setState(() {
                      if (value == null || value.isEmpty) {
                        _values.remove(field.key);
                      } else {
                        _values[field.key] = value;
                      }
                    });
                  },
                ),
              ),
              IconButton(
                tooltip: labels.loc.createCategory,
                icon: Icon(Icons.add, size: 20, color: look.neutrals.muted),
                onPressed: () => _newCategory(field, labels),
              ),
            ],
          ),
        );
      case FieldType.checkbox:
        final bool checked = _values[field.key] == true;
        void flip(bool value) {
          setState(() {
            _values[field.key] = value;
          });
        }
        return _row(
          look,
          key: key,
          icon: icon,
          label: label,
          onTap: () => flip(!checked),
          compact: true,
          value: _check(look, checked, flip),
        );
      case FieldType.toggle:
        final bool on = _values[field.key] == true;
        void flip(bool value) {
          setState(() {
            _values[field.key] = value;
          });
        }
        return _row(
          look,
          key: key,
          icon: icon,
          label: label,
          onTap: () => flip(!on),
          compact: true,
          value: Switch(value: on, onChanged: flip),
        );
      case FieldType.date:
      case FieldType.dateTime:
        final Object? raw = _values[field.key];
        final DateTime? date = raw is String
            ? DateTime.tryParse(raw)?.toLocal()
            : null;
        final String locale = Localizations.localeOf(context).toLanguageTag();
        final DateFormat format = ItemDates.hasTime(field.type, raw)
            ? dateTimeFormat(locale, context.watchAccountPreferences.timeFormat)
            : DateFormat.yMMMd(locale);
        return _row(
          look,
          key: key,
          icon: icon,
          label: label,
          onTap: () => _pickDate(field),
          value: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  date == null ? labels.loc.none : format.format(date),
                  style: look.value,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (date == null)
                Icon(Icons.chevron_right, size: 18, color: look.neutrals.muted)
              else
                IconButton(
                  tooltip: labels.loc.clear,
                  icon: Icon(Icons.close, size: 18, color: look.neutrals.muted),
                  onPressed: () {
                    setState(() {
                      _values.remove(field.key);
                    });
                  },
                ),
            ],
          ),
        );
      case FieldType.recurrence:
        final Object? current = _values[field.key];
        final RecurrenceFrequency frequency =
            enumFromWire(
              RecurrenceFrequency.values,
              current is Map ? current['frequency'] : null,
            ) ??
            RecurrenceFrequency.none;
        return Column(
          key: key,
          children: [
            _row(
              look,
              icon: icon,
              label: label,
              value: _dropdown<RecurrenceFrequency>(
                look,
                key: ValueKey('field-${field.key}-frequency'),
                value: frequency,
                options: [
                  for (final RecurrenceFrequency value
                      in RecurrenceFrequency.values)
                    (value, labels.recurrence(value)),
                ],
                onChanged: (value) {
                  setState(() {
                    _values[field.key] = {
                      'frequency': (value ?? RecurrenceFrequency.none).wire,
                    };
                  });
                },
              ),
            ),
            if (frequency == RecurrenceFrequency.custom)
              _row(
                look,
                icon: Icons.calendar_view_day_outlined,
                label: labels.loc.repeatEveryHowManyDays,
                value: _inlineField(
                  look,
                  key: ValueKey('field-${field.key}-days'),
                  controller: _customDays[field.key],
                  hint: '0',
                  keyboardType: TextInputType.number,
                ),
              ),
          ],
        );
      case FieldType.checklist:
        final List<_SubItemDraft> drafts = _subItems[field.key]!;
        return Column(
          key: key,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 22, bottom: 4),
              child: Text(label.toUpperCase(), style: look.type.sectionLabel),
            ),
            for (final _SubItemDraft draft in drafts)
              // The row sits 12 px outside the margin, so the circle lines up
              // with it, as on the list screen.
              Transform.translate(
                key: ValueKey('sub-${draft.id}'),
                offset: Offset(
                  Directionality.of(context) == TextDirection.rtl ? 12 : -12,
                  0,
                ),
                child: Row(
                  children: [
                    _check(look, draft.done, (value) {
                      setState(() {
                        draft.done = value;
                      });
                    }),
                    Expanded(
                      child: TextField(
                        controller: draft.controller,
                        focusNode: draft.focus,
                        style: draft.done
                            ? look.label.copyWith(
                                color: look.neutrals.muted,
                                decoration: TextDecoration.lineThrough,
                              )
                            : look.label,
                        decoration: _bare(null, look.value),
                      ),
                    ),
                    IconButton(
                      tooltip: labels.loc.delete,
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: look.neutrals.muted,
                      ),
                      onPressed: () {
                        setState(() {
                          drafts.remove(draft);
                          _removedDrafts.add(draft);
                        });
                      },
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              key: ValueKey('field-${field.key}-add'),
              style: AppInk.pressless(
                TextButton.styleFrom(
                  foregroundColor: look.neutrals.muted,
                  textStyle: look.body,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 44),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(labels.loc.addSubtask),
              onPressed: () {
                final _SubItemDraft draft = _SubItemDraft(
                  id: const Uuid().v4(),
                  done: false,
                  title: '',
                );
                setState(() {
                  drafts.add(draft);
                });
                // The new subtask gets the cursor, even while another field
                // has it.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    draft.focus.requestFocus();
                  }
                });
              },
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final ListLabels labels = ListLabels(loc);
    final _Look look = _Look.of(context, widget.definition);
    final List<Widget> editors = [];
    final bool grown = _canGrow && _grown > 0;

    // The headline is the primary text field; long text follows it as the
    // description, then the rows, then the subtask sections.
    final List<FieldDefinition> visible = [
      for (final FieldDefinition field in widget.definition.fields)
        if (field.isVisibleFor(_values)) field,
    ];
    final FieldDefinition? headline = visible
        .where((field) => field.primary && _isTextType(field.type))
        .firstOrNull;
    int rank(FieldDefinition field) {
      if (field == headline) {
        return 0;
      }
      switch (field.type) {
        case FieldType.longText:
          return 1;
        case FieldType.checklist:
          return 3;
        default:
          return 2;
      }
    }

    final List<FieldDefinition> ordered = [
      for (int r = 0; r < 4; r++)
        for (final FieldDefinition field in visible)
          if (rank(field) == r) field,
    ];
    for (final FieldDefinition field in ordered) {
      if (field == headline) {
        editors.add(_headline(look, field, labels.field(field)));
      } else if (grown && field.type == FieldType.longText) {
        editors.add(
          Expanded(child: _bigText(look, field, labels.field(field))),
        );
      } else {
        editors.add(_editor(look, labels, field));
      }
    }

    if (_error != null) {
      editors.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _error!,
            style: look.body.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      );
    }

    final String heading = [
      labels.listName(widget.definition),
      widget.item == null ? loc.itemSheetNew : loc.itemSheetEdit,
    ].join(' · ');

    final Widget bar = Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 12),
        decoration: BoxDecoration(
          color: look.neutrals.line,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

    return Semantics(
      label: widget.title,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: look.neutrals.ground,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppShapes.sheetRadius),
          ),
          boxShadow: look.shadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            height: grown ? _smallHeight + _grown : null,
            child: Column(
              mainAxisSize: grown ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_canGrow)
                  Listener(
                    key: const ValueKey('item-sheet-bar'),
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _barDown,
                    onPointerMove: _barMoved,
                    onPointerUp: _barUp,
                    onPointerCancel: _barUp,
                    child: bar,
                  )
                else
                  bar,
                if (grown)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppShapes.sideMargin,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(heading, style: look.type.meta),
                          ),
                          ...editors,
                        ],
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppShapes.sideMargin,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(heading, style: look.type.meta),
                          ),
                          ...editors,
                        ],
                      ),
                    ),
                  ),
                // Cancel and Save stay at the bottom, within thumb reach.
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppShapes.sideMargin - 8,
                      12,
                      AppShapes.sideMargin,
                      16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          style: AppInk.pressless(
                            TextButton.styleFrom(
                              foregroundColor: look.neutrals.text,
                              minimumSize: const Size(0, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text(loc.cancel),
                        ),
                        FilledButton(
                          style: AppInk.pressless(
                            FilledButton.styleFrom(
                              backgroundColor: look.color,
                              foregroundColor: look.onColor,
                              disabledBackgroundColor: look.neutrals.surface,
                              disabledForegroundColor: look.neutrals.muted,
                              minimumSize: const Size(0, 52),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 30,
                              ),
                              textStyle: look.label.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              shape: AppShapes.pill,
                            ),
                          ),
                          onPressed: _requiredFieldsFilled ? _save : null,
                          child: Text(loc.save),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// The colours and styles the sheet uses for the current theme: the neutrals
// and the list's colour (docs/AESTHETICS.md).
class _Look {
  const _Look._({
    required this.neutrals,
    required this.type,
    required this.color,
    required this.onColor,
    required this.shadow,
  });

  factory _Look.of(BuildContext context, ListDefinition definition) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color color = listColor(definition.color, brightness: brightness);
    return _Look._(
      neutrals: AppColors.neutrals(brightness),
      type: AppTypography.of(context),
      color: color,
      onColor: AppColors.onColor(color),
      shadow: AppShadows.floating(brightness),
    );
  }

  final AppNeutrals neutrals;
  final AppTypography type;
  final Color color;
  final Color onColor;
  final List<BoxShadow> shadow;

  TextStyle get headline =>
      type.row.copyWith(fontSize: 22, fontWeight: FontWeight.w500);
  TextStyle get label =>
      type.row.copyWith(fontSize: 15, fontWeight: FontWeight.w400);
  TextStyle get value => label.copyWith(color: neutrals.muted);
  TextStyle get body =>
      type.row.copyWith(fontSize: 15, fontWeight: FontWeight.w400, height: 1.4);
}

// Slides the item sheet up from the bottom edge. Only the sheet moves: the
// scrim appears and goes at once, and with reduced motion nothing animates.
// The sheet can be dragged down to close it.
class _ItemSheetRoute<T> extends PopupRoute<T> {
  _ItemSheetRoute({
    required this.builder,
    required this.reduceMotion,
    required this.barrierLabel,
  });

  final WidgetBuilder builder;
  final bool reduceMotion;

  // Once the sheet is dragged it follows the finger, without the ease-out.
  bool _dragged = false;

  // The grown Journal sheet is dragged by its bar alone.
  final ValueNotifier<bool> _dragEnabled = ValueNotifier(true);

  void setDragEnabled(bool enabled) => _dragEnabled.value = enabled;

  @override
  void dispose() {
    _dragEnabled.dispose();
    super.dispose();
  }

  @override
  final String barrierLabel;

  // The barrier only catches taps; the scrim is drawn in buildTransitions.
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : AppMotion.slow;

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : AppMotion.standard;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final MediaQueryData media = MediaQuery.of(context);
    final double bottomInset = media.viewInsets.bottom;
    final Animation<double> curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.curve,
    );
    // The page is built once, so what changes has its own builder.
    final Widget sheet = ValueListenableBuilder<bool>(
      valueListenable: _dragEnabled,
      builder: (context, dragEnabled, _) => BottomSheet(
        animationController: controller,
        enableDrag: dragEnabled,
        onDragStart: (_) => _dragged = true,
        onClosing: () {
          if (isCurrent) {
            Navigator.of(context).pop();
          }
        },
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        showDragHandle: false,
        shape: AppShapes.sheet,
        builder: builder,
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: media.size.height - bottomInset - media.padding.top - 24,
          ),
          child: AnimatedBuilder(
            animation: animation,
            child: sheet,
            builder: (context, child) {
              final double shown = _dragged ? animation.value : curved.value;
              return FractionalTranslation(
                translation: Offset(0, 1 - shown),
                child: child,
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final AnimationStatus status = animation.status;
        final bool showScrim =
            status == AnimationStatus.forward ||
            status == AnimationStatus.completed;
        return Stack(
          children: [
            if (showScrim)
              const Positioned.fill(
                child: IgnorePointer(child: ColoredBox(color: AppColors.scrim)),
              ),
            child!,
          ],
        );
      },
    );
  }
}

// Opens the item editor as a bottom sheet. Completes with the saved item, or
// null when cancelled.
Future<ListItem?> showItemSheet({
  required BuildContext context,
  required ListDefinition definition,
  required String title,
  ListItem? item,
  Map<String, dynamic> initialValues = const {},
}) {
  return showSlideUpSheet<ListItem>(
    context: context,
    builder: (_) {
      return GenericItemDialog(
        definition: definition,
        item: item,
        title: title,
        initialValues: initialValues,
      );
    },
  );
}

// Opens [builder]'s content as a sheet the way the item sheet opens: it slides
// up, the scrim appears at once, and it can be dragged down to close. The
// content draws its own background (top corners AppShapes.sheetRadius).
Future<T?> showSlideUpSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return Navigator.of(context).push(
    _ItemSheetRoute<T>(
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: builder,
    ),
  );
}

// The time picker with a No time button under it, on the scrim: the picker
// keeps its own Cancel and OK (T-13, Q-91). The picker sizes itself, so the
// column only stacks the two and scrolls on a short screen.
class _WithNoTime extends StatelessWidget {
  const _WithNoTime({
    required this.label,
    required this.onNoTime,
    required this.child,
  });

  final String label;
  final VoidCallback onNoTime;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?child,
            FilledButton(
              key: const ValueKey('time-none'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.surfaceContainerHigh,
                foregroundColor: scheme.onSurface,
                shape: const StadiumBorder(),
                minimumSize: const Size(120, 48),
              ),
              onPressed: onNoTime,
              child: Text(label),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
