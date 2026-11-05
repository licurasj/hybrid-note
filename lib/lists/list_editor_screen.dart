import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../app/app_theme.dart';
import '../app_colors.dart';
import '../l10n/generated/app_localizations.dart';
import 'confirm_delete_sheet.dart';
import 'list_definition.dart';
import 'list_editor_rules.dart';
import 'list_editor_style.dart';
import 'list_icons.dart';
import 'list_item.dart';
import 'list_labels.dart';
import 'list_patch.dart';
import 'list_vocabulary.dart';

// What the editor hands back. `deleted` asks the caller to delete the list
// (with an Undo snackbar, D-5); otherwise `ops` and their checked `result`
// are ready to save.
class ListEditorOutcome {
  const ListEditorOutcome.saved(this.ops, this.result) : deleted = false;
  const ListEditorOutcome.deleted()
    : ops = const [],
      result = null,
      deleted = true;

  final List<ListPatchOp> ops;
  final ListPatchResult? result;
  final bool deleted;
}

// A blank list to start from: a title and a done checkbox.
ListDefinition blankListDefinition(AppLocalizations loc) {
  return ListDefinition(
    id: 'list-${const Uuid().v4()}',
    name: '',
    icon: 'list',
    color: listColorChoices.first,
    fields: [
      FieldDefinition(
        key: 'title',
        type: FieldType.text,
        label: loc.title,
        required: true,
        primary: true,
      ),
      FieldDefinition(
        key: 'done',
        type: FieldType.checkbox,
        label: loc.completed,
        role: FieldRole.completion,
      ),
    ],
    view: const ViewDefinition(kind: ViewKind.checklist),
    behaviors: const [BehaviorDefinition(kind: BehaviorKind.clearCompleted)],
    updatedAt: DateTime.now().toUtc(),
  );
}

// Edits a list's definition. Every control produces a patch operation (the
// same ones the AI uses, D-7); the screen shows the result of applying them
// so far, including validation errors and values that would be hidden.
// The look is direction A "Eclipse" (docs/AESTHETICS.md): a serif title,
// uppercase section labels, hairline rows and the eclipse ring on the chosen
// colour.
class ListEditorScreen extends StatefulWidget {
  const ListEditorScreen({
    super.key,
    required this.definition,
    this.items = const [],
    this.isNew = false,
  });

  final ListDefinition definition;
  final List<ListItem> items;
  final bool isNew;

  @override
  State<ListEditorScreen> createState() => _ListEditorScreenState();
}

class _ListEditorScreenState extends State<ListEditorScreen> {
  final List<ListPatchOp> _ops = [];
  late ListPatchResult _result;
  final TextEditingController _newOption = TextEditingController();
  // Code points in the description box, counted like validate() (review L2).
  int? _descriptionLength;

  ListDefinition get _draft => _result.definition;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void dispose() {
    _newOption.dispose();
    super.dispose();
  }

  void _recompute() {
    _result = ListPatch.apply(
      widget.definition,
      widget.items,
      _ops,
      DateTime.now().toUtc(),
    );
  }

  // Adds an op; typing in a text box replaces its previous op instead of
  // piling up one per keystroke.
  void _push(ListPatchOp op) {
    setState(() {
      final ListPatchOp? last = _ops.isEmpty ? null : _ops.last;
      final bool sameTarget =
          last != null &&
          last.kind == op.kind &&
          last.key == op.key &&
          (op.kind == PatchOpKind.renameField ||
              (op.kind == PatchOpKind.setListInfo &&
                  last.args.keys.toSet().containsAll(op.args.keys)));
      if (sameTarget) {
        _ops[_ops.length - 1] = ListPatchOp(op.kind, {
          ...last.args,
          ...op.args,
        });
      } else {
        _ops.add(op);
      }
      _recompute();
    });
  }

  String _newKey(String label) {
    final String base = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final String start = base.isEmpty || !RegExp(r'^[a-z]').hasMatch(base)
        ? 'field${base.isEmpty ? '' : '_$base'}'
        : base;
    String key = start;
    int counter = 2;
    while (_draft.field(key) != null || itemMetaFields.contains(key)) {
      key = '$start$counter';
      counter++;
    }
    return key;
  }

  Future<void> _addField(ListLabels labels) async {
    final AppLocalizations loc = labels.loc;
    final TextEditingController name = TextEditingController();
    FieldType type = FieldType.text;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(loc.addField),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const ValueKey('new-field-name'),
                    controller: name,
                    autofocus: true,
                    decoration: InputDecoration(labelText: loc.fieldName),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<FieldType>(
                    key: const ValueKey('new-field-type'),
                    initialValue: type,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: loc.fieldType),
                    items: [
                      for (final FieldType value in FieldType.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(labels.fieldType(value)),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => type = value ?? type),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(loc.cancel),
                ),
                FilledButton(
                  onPressed: name.text.trim().isEmpty
                      ? null
                      : () => Navigator.of(dialogContext).pop(true),
                  child: Text(loc.add),
                ),
              ],
            );
          },
        );
      },
    );

    final String label = name.text.trim();
    name.dispose();
    if (confirmed != true || label.isEmpty) {
      return;
    }

    // The first checkbox becomes the "done" box that clearing works with.
    final bool completion =
        type == FieldType.checkbox &&
        _draft.fieldWithRole(FieldRole.completion) == null;
    _push(
      ListPatchOp(PatchOpKind.addField, {
        'field': FieldDefinition(
          key: _newKey(label),
          type: type,
          label: label,
          role: completion ? FieldRole.completion : null,
          options: type == FieldType.choice
              ? [FieldOption(value: label, label: label)]
              : const [],
        ).toJson(),
      }),
    );
  }

  void _setView(ViewKind kind, {Map<String, dynamic> params = const {}}) {
    final Map<String, dynamic> current = _draft.view.toJson();
    final Map<String, dynamic> view = {
      'kind': kind.wire,
      if (current['filterChipsBy'] != null)
        'filterChipsBy': current['filterChipsBy'],
    };

    String? first(Set<FieldType> types) {
      return _draft.fields
          .where((field) => types.contains(field.type))
          .firstOrNull
          ?.key;
    }

    if (kind != _draft.view.kind) {
      switch (kind) {
        case ViewKind.sectioned:
          view['sectionBy'] = first({FieldType.choice});
        case ViewKind.grouped:
          view['groupBy'] = first({FieldType.choice, FieldType.category});
        case ViewKind.timeline:
          view['dateField'] = 'createdAt';
          view['timelineGrouping'] = TimelineGrouping.month.wire;
        case ViewKind.checklist:
        case ViewKind.table:
        case ViewKind.cards:
          break;
      }
    } else {
      view.addAll(current);
    }
    view.addAll(params);
    view.removeWhere((key, value) => value == null);
    _push(ListPatchOp(PatchOpKind.setView, {'view': view}));
  }

  // A picked value in a row, with a chevron; on the right of a setting row,
  // or at the start under a field's name.
  Widget _picker<T>(
    EditorLook look, {
    required Key key,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    bool alignEnd = true,
    TextStyle? style,
  }) {
    final AlignmentDirectional alignment = alignEnd
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        key: key,
        value: value,
        isExpanded: true,
        icon: Icon(
          alignEnd ? Icons.chevron_right : Icons.expand_more,
          size: 18,
          color: look.neutrals.muted,
        ),
        style: look.label,
        dropdownColor: look.neutrals.ground,
        borderRadius: BorderRadius.circular(AppShapes.fieldRadius),
        selectedItemBuilder: (_) => [
          for (final DropdownMenuItem<T> item in items)
            Align(
              alignment: alignment,
              child: DefaultTextStyle.merge(
                style: style ?? look.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: item.child,
              ),
            ),
        ],
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _fieldDropdown(
    EditorLook look, {
    required String label,
    required String? value,
    required Iterable<FieldDefinition> choices,
    required ValueChanged<String?> onChanged,
    required ListLabels labels,
    List<DropdownMenuItem<String?>> extra = const [],
    String? keyName,
  }) {
    // A view can still name a field that was just removed or retyped; the
    // dropdown then shows nothing, and the validation errors say what is wrong.
    final String? shown = choices.any((field) => field.key == value)
        ? value
        : null;
    return look.settingRow(
      label: label,
      value: _picker<String?>(
        look,
        key: ValueKey('${keyName ?? label}-$shown-${choices.length}'),
        value: shown,
        items: [
          ...extra,
          for (final FieldDefinition field in choices)
            DropdownMenuItem(
              value: field.key,
              child: Text(labels.field(field)),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _layoutSection(EditorLook look, ListLabels labels) {
    final AppLocalizations loc = labels.loc;
    final ViewDefinition view = _draft.view;
    Iterable<FieldDefinition> ofType(Set<FieldType> types) =>
        _draft.fields.where((field) => types.contains(field.type));
    final DropdownMenuItem<String?> noneItem = DropdownMenuItem(
      value: null,
      child: Text(loc.none),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        look.sectionLabel(loc.layout),
        look.settingRow(
          label: loc.layout,
          value: _picker<ViewKind>(
            look,
            key: const ValueKey('view-kind'),
            value: view.kind,
            items: [
              for (final ViewKind kind in ViewKind.values)
                DropdownMenuItem(
                  value: kind,
                  child: Text(labels.viewKind(kind)),
                ),
            ],
            onChanged: (kind) {
              if (kind != null) {
                _setView(kind);
              }
            },
          ),
        ),
        if (view.kind == ViewKind.sectioned)
          _fieldDropdown(
            look,
            labels: labels,
            label: loc.sectionBy,
            value: view.sectionBy,
            choices: ofType({FieldType.choice}),
            onChanged: (key) => _setView(view.kind, params: {'sectionBy': key}),
          ),
        if (view.kind == ViewKind.grouped)
          _fieldDropdown(
            look,
            labels: labels,
            label: loc.groupBy,
            value: view.groupBy,
            choices: ofType({FieldType.choice, FieldType.category}),
            onChanged: (key) => _setView(view.kind, params: {'groupBy': key}),
          ),
        if (view.kind == ViewKind.timeline)
          _fieldDropdown(
            look,
            labels: labels,
            label: loc.dateField,
            value: view.dateField,
            choices: ofType({FieldType.date, FieldType.dateTime}),
            extra: [
              DropdownMenuItem(
                value: 'createdAt',
                child: Text(loc.dateCreated),
              ),
            ],
            onChanged: (key) => _setView(view.kind, params: {'dateField': key}),
          ),
        if (view.kind == ViewKind.checklist)
          _fieldDropdown(
            look,
            labels: labels,
            label: loc.splitByDate,
            value: view.bucketBy,
            choices: ofType({FieldType.date, FieldType.dateTime}),
            extra: [noneItem],
            onChanged: (key) => _setView(view.kind, params: {'bucketBy': key}),
          ),
        _fieldDropdown(
          look,
          labels: labels,
          keyName: 'filter',
          label: loc.filterBy,
          value: view.filterChipsBy,
          choices: ofType({
            FieldType.choice,
            FieldType.category,
            FieldType.tags,
          }),
          extra: [noneItem],
          onChanged: (key) =>
              _setView(view.kind, params: {'filterChipsBy': key}),
        ),
      ],
    );
  }

  Widget _optionsEditor(
    EditorLook look,
    ListLabels labels,
    FieldDefinition field,
  ) {
    void setOptions(List<FieldOption> options) {
      _push(
        ListPatchOp(PatchOpKind.setOptions, {
          'key': field.key,
          'options': options.map((option) => option.toJson()).toList(),
        }),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(_handleWidth, 0, 0, 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final FieldOption option in field.options)
            InputChip(
              label: Text(labels.option(option)),
              labelStyle: look.label,
              visualDensity: VisualDensity.compact,
              deleteIconColor: look.neutrals.muted,
              onDeleted:
                  field.options.length > 1 || field.type != FieldType.choice
                  ? () => setOptions(
                      field.options
                          .where((other) => other.value != option.value)
                          .toList(),
                    )
                  : null,
            ),
          SizedBox(
            width: 150,
            child: TextField(
              key: ValueKey('add-option-${field.key}'),
              style: look.label,
              decoration:
                  EditorLook.bare(
                    hint: labels.loc.addOption,
                    hintStyle: look.value,
                  ).copyWith(
                    prefixIcon: Icon(
                      Icons.add,
                      size: 18,
                      color: look.neutrals.muted,
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 26),
                  ),
              onSubmitted: (text) {
                final String value = text.trim();
                if (value.isNotEmpty && !field.hasOption(value)) {
                  setOptions([
                    ...field.options,
                    FieldOption(value: value, label: value),
                  ]);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // Room for the drag handle; the type and options line up after it.
  static const double _handleWidth = 36;

  // One field over a hairline: the drag handle, its name and Delete, then its
  // type and Required, then its options.
  Widget _fieldRow(
    EditorLook look,
    ListLabels labels,
    FieldDefinition field,
    int index,
  ) {
    final AppLocalizations loc = labels.loc;
    final bool locked = field.primary || field.role != null;

    return look.hairline(
      key: ValueKey('field-card-${field.key}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: SizedBox(
                    width: _handleWidth,
                    height: 48,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Icon(
                        Icons.drag_indicator,
                        size: 20,
                        color: look.neutrals.muted,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('field-label-${field.key}'),
                    initialValue: labels.field(field),
                    style: look.strong,
                    decoration: EditorLook.bare(
                      hint: loc.fieldName,
                      hintStyle: look.value,
                    ),
                    onChanged: (text) => _push(
                      ListPatchOp(PatchOpKind.renameField, {
                        'key': field.key,
                        'label': text,
                      }),
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('remove-field-${field.key}'),
                  tooltip: loc.delete,
                  color: look.neutrals.muted,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: field.primary
                      ? null
                      : () => _push(
                          ListPatchOp(PatchOpKind.removeField, {
                            'key': field.key,
                          }),
                        ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: _handleWidth),
              child: Row(
                children: [
                  Expanded(
                    child: _picker<FieldType>(
                      look,
                      key: ValueKey(
                        'field-type-${field.key}-${field.type.wire}',
                      ),
                      value: field.type,
                      alignEnd: false,
                      style: look.type.meta,
                      items: [
                        for (final FieldType type in FieldType.values)
                          DropdownMenuItem(
                            value: type,
                            child: Text(labels.fieldType(type)),
                          ),
                      ],
                      // The title and fields with a special job keep their type.
                      onChanged: locked
                          ? null
                          : (type) {
                              if (type != null && type != field.type) {
                                _push(
                                  ListPatchOp(PatchOpKind.changeFieldType, {
                                    'key': field.key,
                                    'type': type.wire,
                                  }),
                                );
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(loc.required, style: look.type.meta),
                  Checkbox(
                    key: ValueKey('field-required-${field.key}'),
                    value: field.required,
                    visualDensity: VisualDensity.compact,
                    onChanged: field.primary
                        ? null
                        : (value) => _push(
                            ListPatchOp(PatchOpKind.setFieldProps, {
                              'key': field.key,
                              'required': value ?? false,
                            }),
                          ),
                  ),
                ],
              ),
            ),
            if (field.type == FieldType.choice ||
                field.type == FieldType.category)
              _optionsEditor(look, labels, field),
          ],
        ),
      ),
    );
  }

  // An icon in a ring; the chosen one is filled with the text colour. The
  // whole 48 dp square takes the tap.
  Widget _iconChoice(EditorLook look, String name, IconData icon) {
    final bool selected = _draft.icon == name;
    return Semantics(
      button: true,
      selected: selected,
      label: AppLocalizations.of(context).listIconName(name),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('icon-$name'),
        customBorder: const CircleBorder(),
        onTap: () =>
            _push(ListPatchOp(PatchOpKind.setListInfo, {'icon': name})),
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? look.neutrals.text : Colors.transparent,
                shape: BoxShape.circle,
                border: selected
                    ? null
                    : Border.all(color: look.neutrals.line),
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected ? look.neutrals.ground : look.neutrals.text,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // A colour disc, in its dark variant in dark mode. The chosen one gets the
  // eclipse: a ring in the text colour overlapping it, shifted up and right.
  // The whole 48 dp square takes the tap.
  Widget _swatch(EditorLook look, String color) {
    final Brightness brightness = Theme.of(context).brightness;
    final bool selected = _draft.color.toUpperCase() == color;
    const double disc = 36;
    final int value = listColor(color).toARGB32();
    final String name = listPalette
            .where((entry) => entry.light.toARGB32() == value)
            .firstOrNull
            ?.name ??
        '';
    return Semantics(
      button: true,
      selected: selected,
      label: AppLocalizations.of(context).listColorName(name),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('color-$color'),
        customBorder: const CircleBorder(),
        onTap: () => _push(
          ListPatchOp(PatchOpKind.setListInfo, {'color': color}),
        ),
        child: SizedBox.square(
          dimension: 48,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: disc,
                height: disc,
                decoration: BoxDecoration(
                  color: listColor(color, brightness: brightness),
                  shape: BoxShape.circle,
                ),
              ),
              if (selected)
                Transform.translate(
                  offset: const Offset(6, -4),
                  child: Container(
                    key: const ValueKey('color-selected'),
                    width: disc,
                    height: disc,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: look.neutrals.text, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canSave => _result.isValid && (_ops.isNotEmpty || widget.isNew);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final ListLabels labels = ListLabels(loc);
    final ListDefinition draft = _draft;
    final EditorLook look = EditorLook.of(context);
    final int descriptionLength = _descriptionLength ??=
        (labels.listDescription(widget.definition) ?? '').runes.length;
    final TextStyle nameStyle = look.type.row.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w500,
    );
    final Color errorColor = Theme.of(context).colorScheme.error;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            key: const ValueKey('save-list'),
            tooltip: loc.save,
            icon: const Icon(Icons.check, size: 26),
            onPressed: _canSave
                ? () => Navigator.of(
                    context,
                  ).pop(ListEditorOutcome.saved(List.of(_ops), _result))
                : null,
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Built whole (no lazy list): the editor is a few screens long at most.
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppShapes.sideMargin,
          0,
          AppShapes.sideMargin,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.isNew ? loc.newList : loc.editList,
              style: look.type.screenTitle,
            ),
            look.sectionLabel(loc.listName),
            TextFormField(
              key: const ValueKey('list-name'),
              // A blank new list starts without a name; a template copy shows
              // the template's.
              initialValue:
                  (widget.definition.name ?? '').isEmpty &&
                      widget.definition.nameKey == null
                  ? ''
                  : labels.listName(widget.definition),
              autofocus: widget.isNew,
              style: nameStyle,
              decoration: InputDecoration(
                hintText: loc.listName,
                hintStyle: nameStyle.copyWith(color: look.neutrals.muted),
                isDense: true,
                contentPadding: const EdgeInsets.only(top: 4, bottom: 10),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: look.neutrals.line),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: look.neutrals.line),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: look.neutrals.text, width: 1.5),
                ),
              ),
              onChanged: (text) =>
                  _push(ListPatchOp(PatchOpKind.setListInfo, {'name': text})),
            ),
            look.sectionLabel(loc.listDescription),
            TextFormField(
              key: const ValueKey('list-description'),
              initialValue: labels.listDescription(widget.definition) ?? '',
              style: look.label,
              minLines: 1,
              maxLines: 3,
              // Limited and counted in code points, as validate() and the
              // function count; the counter shows only near the limit.
              inputFormatters: [
                TextInputFormatter.withFunction((before, after) {
                  final List<int> runes = after.text.runes.toList();
                  if (runes.length <= ListDefinition.descriptionMaxLength) {
                    return after;
                  }
                  final String cut = String.fromCharCodes(
                    runes.take(ListDefinition.descriptionMaxLength),
                  );
                  return TextEditingValue(
                    text: cut,
                    selection: TextSelection.collapsed(offset: cut.length),
                  );
                }),
              ],
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                  descriptionLength > ListDefinition.descriptionMaxLength - 40
                  ? Text(
                      '$descriptionLength/${ListDefinition.descriptionMaxLength}',
                      key: const ValueKey('list-description-counter'),
                      style: look.value,
                    )
                  : null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: loc.listDescriptionHint,
                hintStyle: look.value,
                isDense: true,
                contentPadding: const EdgeInsets.only(top: 4, bottom: 10),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: look.neutrals.line),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: look.neutrals.line),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: look.neutrals.text, width: 1.5),
                ),
              ),
              onChanged: (text) {
                _descriptionLength = text.runes.length;
                _push(ListPatchOp(PatchOpKind.setListInfo, {'description': text}));
              },
            ),
            look.sectionLabel(loc.listIcon),
            Wrap(
              spacing: 4,
              children: [
                for (final MapEntry<String, IconData> icon in listIcons.entries)
                  _iconChoice(look, icon.key, icon.value),
              ],
            ),
            look.sectionLabel(loc.listColor),
            Wrap(
              spacing: 8,
              children: [
                for (final String color in listColorChoices)
                  _swatch(look, color),
              ],
            ),
            look.sectionLabel(loc.fields),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (from, to) {
                final FieldDefinition field = draft.fields[from];
                _push(
                  ListPatchOp(PatchOpKind.moveField, {
                    'key': field.key,
                    'index': to > from ? to - 1 : to,
                  }),
                );
              },
              children: [
                for (int index = 0; index < draft.fields.length; index++)
                  _fieldRow(look, labels, draft.fields[index], index),
              ],
            ),
            look.addButton(
              key: const ValueKey('add-field'),
              text: loc.addField,
              onPressed: () => _addField(labels),
            ),
            _layoutSection(look, labels),
            ListEditorRules(
              definition: draft,
              labels: labels,
              onOp: _push,
              extraRows: [
                look.hairline(
                  child: SwitchListTile(
                    key: const ValueKey('allow-ai'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(loc.allowAi, style: look.label),
                    value: draft.aiAllowed,
                    onChanged: (on) => _push(
                      ListPatchOp(PatchOpKind.setListInfo, {'aiAllowed': on}),
                    ),
                  ),
                ),
              ],
            ),
            if (_result.hiddenValues > 0)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  loc.hiddenValuesWarning(_result.hiddenValues),
                  style: look.value,
                ),
              ),
            // Problems that keep Save disabled.
            if (!_result.isValid && (_ops.isNotEmpty || widget.isNew))
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _result.errors
                      .map((error) => labels.error(error, _result.definition))
                      .join('\n'),
                  key: const ValueKey('editor-errors'),
                  style: look.label.copyWith(color: errorColor),
                ),
              ),
            if (!widget.isNew)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('delete-list'),
                    style: TextButton.styleFrom(
                      foregroundColor: errorColor,
                      minimumSize: const Size(0, 48),
                      padding: EdgeInsets.zero,
                      textStyle: look.strong,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    label: Text(loc.deleteList),
                    onPressed: () async {
                      final NavigatorState navigator = Navigator.of(context);
                      final String name = ListLabels(
                        loc,
                      ).listName(widget.definition);
                      if (await confirmDelete(context, name)) {
                        navigator.pop(const ListEditorOutcome.deleted());
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
