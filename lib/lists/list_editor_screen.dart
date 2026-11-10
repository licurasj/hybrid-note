import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../app/account_preferences.dart';
import '../app/app_theme.dart';
import '../app/preferences_screen.dart' show tickedItemsChoices;
import '../app/settings_controls.dart';
import '../app_colors.dart';
import '../l10n/generated/app_localizations.dart';
import 'confirm_delete_sheet.dart';
import 'list_definition.dart';
import 'list_editor_rules.dart';
import 'list_editor_style.dart';
import 'list_error.dart';
import 'list_icons.dart';
import 'list_item.dart';
import 'list_labels.dart';
import 'list_patch.dart';
import 'list_store.dart';
import 'list_vocabulary.dart';

// What the editor hands back. `deleted` asks the caller to delete the list
// (with an Undo snackbar, D-5); otherwise `ops` and their checked `result`
// are ready to save.
class ListEditorOutcome {
  const ListEditorOutcome.saved(
    this.ops,
    this.result, {
    this.hideFromHome = false,
    this.suggestOnHome,
  }) : deleted = false;
  const ListEditorOutcome.deleted()
    : ops = const [],
      result = null,
      hideFromHome = false,
      suggestOnHome = null,
      deleted = true;

  final List<ListPatchOp> ops;
  final ListPatchResult? result;
  final bool deleted;
  // A new list with Suggest on home off: the caller writes it to homeRemoved
  // once the list is created, so a failed create leaves no stray id there.
  final bool hideFromHome;
  // An existing list's changed Suggest on home, saved with other list
  // changes: the caller writes it only once those are saved (Codex review
  // M3). Null when it did not change, or when it was the only change (the
  // editor then saved it itself).
  final bool? suggestOnHome;
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
    final (String, FieldType)? picked = await showDialog<(String, FieldType)>(
      context: context,
      builder: (_) => _AddFieldDialog(labels: labels),
    );
    if (picked == null) {
      return;
    }
    final (String label, FieldType type) = picked;

    // The first checkbox becomes the "done" box that clearing works with,
    // with the Clear ticked rule. On a list that had a tick it takes the old
    // tick's key, so the ticks still kept on its items come back (Q-103).
    final bool completion =
        type == FieldType.checkbox &&
        _draft.fieldWithRole(FieldRole.completion) == null;
    final String? oldTick = completion ? _oldTickKey() : null;
    _push(
      ListPatchOp(PatchOpKind.addField, {
        'field': FieldDefinition(
          key: oldTick ?? _newKey(label),
          type: type,
          label: label,
          role: completion ? FieldRole.completion : null,
          options: type == FieldType.choice
              ? [FieldOption(value: label, label: label)]
              : const [],
        ).toJson(),
      }),
    );
    final ListDefinition before = widget.definition;
    if (oldTick != null &&
        oldTick == before.fieldWithRole(FieldRole.completion)?.key) {
      // The tick removed in this edit comes back: so do the rules and the
      // checklist view that went with it, as the list had them.
      _restoreWithTick(before);
      return;
    }
    if (completion &&
        !_draft.behaviors.any((rule) => rule.kind == BehaviorKind.clearCompleted)) {
      _push(
        ListEditorRules.addOp(
          const BehaviorDefinition(kind: BehaviorKind.clearCompleted),
        ),
      );
    }
  }

  // Undoes what [_removeField] did with the tick: the list's rules that are
  // gone (some, such as Copy when cleared, cannot be added in the editor)
  // and its checklist view, unless the view was changed since.
  void _restoreWithTick(ListDefinition before) {
    for (final BehaviorDefinition rule in before.behaviors) {
      if (!_draft.behaviors.any((now) => now.kind == rule.kind)) {
        _push(ListEditorRules.addOp(rule));
      }
    }
    if (before.view.kind == ViewKind.checklist &&
        _draft.view.kind == ViewKind.table &&
        _draft.view.filterChipsBy == before.view.filterChipsBy) {
      _push(ListPatchOp(PatchOpKind.setView, {'view': before.view.toJson()}));
    }
  }

  // The key of the tick this list had, when its items still hold ticks under
  // it and no field uses it now: the one removed in this edit, or the
  // built-in lists' "done".
  String? _oldTickKey() {
    final String? removed =
        widget.definition.fieldWithRole(FieldRole.completion)?.key;
    for (final String key in [?removed, 'done']) {
      if (_draft.field(key) == null &&
          (key == removed || widget.items.any((item) => item[key] is bool))) {
        return key;
      }
    }
    return null;
  }

  // Removing the tick (the Done field) just works (Q-103): the rules that act
  // on ticked items go with it and a checklist becomes a table, so the list
  // saves with no errors. The ticks stay on the items, out of sight.
  void _removeField(FieldDefinition field) {
    _push(ListPatchOp(PatchOpKind.removeField, {'key': field.key}));
    if (field.role != FieldRole.completion) {
      return;
    }
    for (final BehaviorKind kind in {
      for (final BehaviorDefinition rule in _draft.behaviors)
        if (rule.kind != BehaviorKind.moveAll) rule.kind,
    }) {
      _push(ListEditorRules.removeOp(kind));
    }
    if (_draft.view.kind == ViewKind.checklist) {
      final String? chips = _draft.view.filterChipsBy;
      _push(ListPatchOp(PatchOpKind.setView, {
        'view': {'kind': ViewKind.table.wire, 'filterChipsBy': ?chips},
      }));
    }
  }

  // What removing the tick changed, said before saving (Q-103).
  Widget? _noTickLine(EditorLook look, ListLabels labels) {
    final ListDefinition before = widget.definition;
    final FieldDefinition? tick = before.fieldWithRole(FieldRole.completion);
    if (tick == null || _draft.fieldWithRole(FieldRole.completion) != null) {
      return null;
    }
    final AppLocalizations loc = labels.loc;
    final List<String> rules = [
      for (final BehaviorKind kind in {
        for (final BehaviorDefinition rule in before.behaviors)
          if (rule.kind != BehaviorKind.moveAll) rule.kind,
      })
        if (!_draft.behaviors.any((rule) => rule.kind == kind))
          labels.behavior(kind),
    ];
    final bool copies =
        before.behaviors.any((rule) => rule.kind == BehaviorKind.copyOnClear) &&
        !_draft.behaviors.any((rule) => rule.kind == BehaviorKind.copyOnClear);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        [
          loc.noTickLine(labels.field(tick)),
          if (before.view.kind == ViewKind.checklist &&
              _draft.view.kind != ViewKind.checklist)
            loc.noTickView(labels.viewKind(_draft.view.kind)),
          if (rules.isNotEmpty) loc.noTickRules(rules.join(', ')),
          if (copies) loc.noTickCopies,
        ].join(' '),
        key: const ValueKey('no-tick-line'),
        style: look.type.meta,
      ),
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
    // DropdownMenuItem only carries each choice's value and what it shows:
    // the choices open in place, under the row, not as a drop-down (T-24).
    return SettingFoldPicker<T>(
      key: key,
      value: value,
      alignEnd: alignEnd,
      style: style,
      choices: [
        for (final DropdownMenuItem<T> item in items)
          (value: item.value as T, child: item.child),
      ],
      onChanged: onChanged,
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
    return look.hairline(
      child: SettingFoldPicker<String?>(
        key: ValueKey('${keyName ?? label}-$shown-${choices.length}'),
        label: label,
        value: shown,
        choices: [
          for (final DropdownMenuItem<String?> item in extra)
            (value: item.value, child: item.child),
          for (final FieldDefinition field in choices)
            (value: field.key, child: Text(labels.field(field))),
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

    return FoldSection(
      key: const ValueKey('section-layout'),
      title: '${loc.layout} · ${labels.viewKind(view.kind)}',
      open: widget.isNew,
      forceOpen: _errorsIn(_EditorPart.layout),
      children: [
        SettingOptionList<ViewKind>(
          key: const ValueKey('view-kind'),
          label: loc.layout,
          selected: view.kind,
          choices: [
            for (final ViewKind kind in ViewKind.values)
              choice(kind, labels.viewKind(kind), line: _viewLine(loc, kind)),
          ],
          onChanged: _setView,
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
                // The field ticking works with (Q-103, T-24).
                if (field.role == FieldRole.completion)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: Text(
                      loc.editorTickField,
                      key: ValueKey('tick-mark-${field.key}'),
                      style: look.type.meta,
                    ),
                  ),
                IconButton(
                  key: ValueKey('remove-field-${field.key}'),
                  tooltip: loc.delete,
                  color: look.neutrals.muted,
                  highlightColor: Colors.transparent,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: field.primary ? null : () => _removeField(field),
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

  // Problems that keep Save disabled are shown, and their sections open.
  // Which fold section a problem belongs to, so only that one opens (Q-113).
  bool _errorsIn(_EditorPart part) =>
      _showErrors && _result.errors.any((error) => _partOf(error.code) == part);

  static _EditorPart? _partOf(ListErrorCode code) => switch (code) {
    ListErrorCode.noFields ||
    ListErrorCode.primaryCount ||
    ListErrorCode.primaryNotText ||
    ListErrorCode.duplicateRole ||
    ListErrorCode.badFieldKey ||
    ListErrorCode.reservedFieldKey ||
    ListErrorCode.duplicateFieldKey ||
    ListErrorCode.missingFieldLabel ||
    ListErrorCode.missingOptions ||
    ListErrorCode.optionsNotAllowed ||
    ListErrorCode.duplicateOption ||
    ListErrorCode.defaultNotOption ||
    ListErrorCode.minAboveMax ||
    ListErrorCode.conditionNotChoice ||
    ListErrorCode.conditionOnItself ||
    ListErrorCode.conditionNotOption ||
    ListErrorCode.roleNeedsType ||
    ListErrorCode.opNoField ||
    ListErrorCode.fieldExists ||
    ListErrorCode.unknownFieldType => _EditorPart.fields,
    ListErrorCode.viewNeedsParam ||
    ListErrorCode.viewParamNotField ||
    ListErrorCode.viewParamWrongType ||
    ListErrorCode.checklistNeedsCompletion => _EditorPart.layout,
    ListErrorCode.ruleNeedsCompletion ||
    ListErrorCode.ruleNeedsParam ||
    ListErrorCode.ruleParamNotField ||
    ListErrorCode.ruleParamWrongType ||
    ListErrorCode.ruleUnknownField ||
    ListErrorCode.ruleValueNotOption ||
    ListErrorCode.ruleParamNotOption => _EditorPart.rules,
    _ => null,
  };

  bool get _showErrors => !_result.isValid && (_ops.isNotEmpty || widget.isNew);

  static String _viewLine(AppLocalizations loc, ViewKind kind) => switch (kind) {
    ViewKind.checklist => loc.viewChecklistLine,
    ViewKind.sectioned => loc.viewSectionedLine,
    ViewKind.timeline => loc.viewTimelineLine,
    ViewKind.grouped => loc.viewGroupedLine,
    ViewKind.table => loc.viewTableLine,
    ViewKind.cards => loc.viewCardsLine,
  };

  // Ticked items and Confirm before deleting, each following Preferences
  // until this list picks its own (Q-117, Q-118). Following, the choice shows
  // the general value, greyed. Saved with the list, through setListInfo.
  List<Widget> _itemsSection(EditorLook look, AppLocalizations loc) {
    final AccountPreferences preferences = context.watchAccountPreferences;
    final ListDefinition draft = _draft;
    final bool hasTick = draft.fieldWithRole(FieldRole.completion) != null;

    final String? ownTicked = draft.ownTickedItems;
    final bool tickedFollows = ownTicked == null;
    final String? tickedReason = !hasTick
        ? loc.editorNoTick
        : !preferences.listsOwnTickedItems
        ? loc.editorEveryListFollows
        : null;

    final bool? ownConfirm = draft.ownConfirmDelete;
    final bool confirmFollows = ownConfirm == null;
    final String? confirmReason = preferences.listsOwnConfirmDelete
        ? null
        : loc.editorEveryListFollows;

    void set(String key, Object? value) =>
        _push(ListPatchOp(PatchOpKind.setListInfo, {key: value}));

    // Each setting with Follow Preferences as its sub-option (owner,
    // 2026-11-09), as Lists can have their own in Preferences.
    return [
      SettingOptionList<TickedItems>(
        key: const ValueKey('ticked-own'),
        label: loc.preferencesTicked,
        selected: tickedFollows || tickedReason != null
            ? preferences.tickedItems
            : TickedItems.of(ownTicked),
        enabled: !tickedFollows && tickedReason == null,
        choices: tickedItemsChoices(loc),
        onChanged: (value) => set(ListDefinition.ownTickedItemsKey, value.wire),
        sub: SettingSubSwitch(
          key: const ValueKey('ticked-follow'),
          label: loc.editorFollowPreferences,
          value: tickedFollows,
          line: tickedReason,
          onChanged: tickedReason != null
              ? null
              : (follow) => set(
                  ListDefinition.ownTickedItemsKey,
                  follow ? null : preferences.tickedItems.wire,
                ),
        ),
      ),
      SettingSwitchRow(
        key: const ValueKey('confirm-own'),
        label: loc.preferencesConfirmDelete,
        value: confirmFollows || confirmReason != null
            ? preferences.confirmDelete
            : ownConfirm,
        line: loc.preferencesConfirmDeleteLine,
        onChanged: confirmFollows || confirmReason != null
            ? null
            : (value) => set(ListDefinition.ownConfirmDeleteKey, value),
        sub: SettingSubSwitch(
          key: const ValueKey('confirm-follow'),
          label: loc.editorFollowPreferences,
          value: confirmFollows,
          line: confirmReason,
          onChanged: confirmReason != null
              ? null
              : (follow) => set(
                  ListDefinition.ownConfirmDeleteKey,
                  follow ? null : preferences.confirmDelete,
                ),
        ),
      ),
    ];
  }

  bool get _canSave =>
      _result.isValid && (_ops.isNotEmpty || widget.isNew || _suggestChanged);

  // "Suggest on home" (Q-106): the same synced value as Remove on a suggested
  // home card (homeRemoved), so the two always agree. Changed here, it is
  // saved with the list. Null until the switch is touched.
  bool? _suggest;

  bool get _suggestsNow =>
      !context.accountPreferences.homeRemoved.contains(widget.definition.id);

  bool get _suggestChanged => _suggest != null && _suggest != _suggestsNow;

  void _saveSuggest() {
    final AccountPreferencesCubit? preferences =
        context.read<AccountPreferencesCubit?>();
    if (preferences == null || !_suggestChanged || widget.isNew) {
      return;
    }
    final String id = widget.definition.id;
    if (_suggest!) {
      preferences.undoRemoveFromHome(id);
    } else {
      preferences.removeFromHome(
        id,
        existing: [
          id,
          for (final ListDefinition list
              in context.read<ListStore?>()?.current.definitions ?? const [])
            list.id,
        ],
      );
    }
  }

  // Off while Show suggestions is off in Preferences, which no list
  // overrides (Q-118), with a line saying so.
  Widget _suggestRow(EditorLook look, AppLocalizations loc) {
    final bool suggestionsOn = context.watchAccountPreferences.homeSuggestions;
    return look.hairline(
      child: SwitchListTile(
        key: const ValueKey('suggest-on-home'),
        contentPadding: EdgeInsets.zero,
        activeTrackColor: AppColors.appBlue,
        title: Text(loc.suggestOnHome, style: look.type.row),
        subtitle: Text(
          suggestionsOn ? loc.suggestOnHomeLine : loc.suggestOnHomeOff,
          style: look.type.meta,
        ),
        value: _suggest ?? _suggestsNow,
        onChanged: suggestionsOn
            ? (on) => setState(() => _suggest = on)
            : null,
      ),
    );
  }

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
                ? () {
                    // Alone, Suggest on home is saved here; with other list
                    // changes, after them (M3).
                    final bool alone = _ops.isEmpty;
                    if (alone) {
                      _saveSuggest();
                    }
                    Navigator.of(
                      context,
                    ).pop(
                      ListEditorOutcome.saved(
                        List.of(_ops),
                        _result,
                        hideFromHome:
                            widget.isNew && _suggestChanged && !_suggest!,
                        suggestOnHome:
                            !alone && !widget.isNew && _suggestChanged
                            ? _suggest
                            : null,
                      ),
                    );
                  }
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
            look.section(loc.editorIconAndColour),
            Wrap(
              spacing: 4,
              children: [
                for (final MapEntry<String, IconData> icon in listIcons.entries)
                  _iconChoice(look, icon.key, icon.value),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final String color in listColorChoices)
                  _swatch(look, color),
              ],
            ),
            look.section(loc.editorHomeAndAi),
            _suggestRow(look, loc),
            look.hairline(
              child: SwitchListTile(
                key: const ValueKey('allow-ai'),
                contentPadding: EdgeInsets.zero,
                activeTrackColor: AppColors.appBlue,
                title: Text(loc.allowAi, style: look.type.row),
                subtitle: Text(loc.allowAiLine, style: look.type.meta),
                value: draft.aiAllowed,
                onChanged: (on) => _push(
                  ListPatchOp(PatchOpKind.setListInfo, {'aiAllowed': on}),
                ),
              ),
            ),
            look.section(loc.preferencesItems),
            ..._itemsSection(look, loc),
            FoldSection(
              key: const ValueKey('section-fields'),
              title: '${loc.fields} · ${draft.fields.length}',
              open: widget.isNew,
              forceOpen: _errorsIn(_EditorPart.fields),
              children: [
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
                ?_noTickLine(look, labels),
              ],
            ),
            _layoutSection(look, labels),
            FoldSection(
              key: const ValueKey('section-rules'),
              title: '${loc.rules} · ${draft.behaviors.length}',
              open: widget.isNew,
              forceOpen: _errorsIn(_EditorPart.rules),
              children: [
                ListEditorRules(
                  definition: draft,
                  labels: labels,
                  onOp: _push,
                  showLabel: false,
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
            if (_showErrors)
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
                    style: AppInk.pressless(TextButton.styleFrom(
                      foregroundColor: errorColor,
                      minimumSize: const Size(0, 48),
                      padding: EdgeInsets.zero,
                      textStyle: look.strong,
                    )),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    label: Text(loc.deleteList),
                    onPressed: () async {
                      final NavigatorState navigator = Navigator.of(context);
                      final String name = ListLabels(
                        loc,
                      ).listName(widget.definition);
                      if (await confirmDelete(
                        context,
                        name,
                        list: widget.definition,
                      )) {
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

// Add field: a name and a type, the types opening in place (T-24). It owns
// its text controller, so nothing is disposed while it slides away.
class _AddFieldDialog extends StatefulWidget {
  const _AddFieldDialog({required this.labels});

  final ListLabels labels;

  @override
  State<_AddFieldDialog> createState() => _AddFieldDialogState();
}

class _AddFieldDialogState extends State<_AddFieldDialog> {
  final TextEditingController _name = TextEditingController();
  FieldType _type = FieldType.text;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ListLabels labels = widget.labels;
    final AppLocalizations loc = labels.loc;
    final String label = _name.text.trim();
    return AlertDialog(
      title: Text(loc.addField),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('new-field-name'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: loc.fieldName),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          SettingFoldPicker<FieldType>(
            key: const ValueKey('new-field-type'),
            label: loc.fieldType,
            value: _type,
            choices: [
              for (final FieldType value in FieldType.values)
                (value: value, child: Text(labels.fieldType(value))),
            ],
            onChanged: (value) => setState(() => _type = value ?? _type),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(loc.cancel),
        ),
        FilledButton(
          onPressed: label.isEmpty
              ? null
              : () => Navigator.of(context).pop((label, _type)),
          child: Text(loc.add),
        ),
      ],
    );
  }
}

// The editor's fold sections.
enum _EditorPart { fields, layout, rules }
