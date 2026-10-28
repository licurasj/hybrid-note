import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../l10n/generated/app_localizations.dart';
import 'list_definition.dart';
import 'list_editor_rules.dart';
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

  Widget _fieldDropdown({
    required String label,
    required String? value,
    required Iterable<FieldDefinition> choices,
    required ValueChanged<String?> onChanged,
    List<DropdownMenuItem<String?>> extra = const [],
    String? keyName,
  }) {
    // A view can still name a field that was just removed or retyped; the
    // dropdown then shows nothing, and the validation errors say what is wrong.
    final String? shown =
        choices.any((field) => field.key == value) ? value : null;
    return DropdownButtonFormField<String?>(
      key: ValueKey('${keyName ?? label}-$shown-${choices.length}'),
      initialValue: shown,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        ...extra,
        for (final FieldDefinition field in choices)
          DropdownMenuItem(
            value: field.key,
            child: Text(field.label ?? field.key),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _layoutSection(ListLabels labels) {
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
        _heading(loc.layout),
        DropdownButtonFormField<ViewKind>(
          key: const ValueKey('view-kind'),
          initialValue: view.kind,
          isExpanded: true,
          decoration: InputDecoration(labelText: loc.layout),
          items: [
            for (final ViewKind kind in ViewKind.values)
              DropdownMenuItem(value: kind, child: Text(labels.viewKind(kind))),
          ],
          onChanged: (kind) {
            if (kind != null) {
              _setView(kind);
            }
          },
        ),
        const SizedBox(height: 12),
        if (view.kind == ViewKind.sectioned)
          _fieldDropdown(
            label: loc.sectionBy,
            value: view.sectionBy,
            choices: ofType({FieldType.choice}),
            onChanged: (key) => _setView(view.kind, params: {'sectionBy': key}),
          ),
        if (view.kind == ViewKind.grouped)
          _fieldDropdown(
            label: loc.groupBy,
            value: view.groupBy,
            choices: ofType({FieldType.choice, FieldType.category}),
            onChanged: (key) => _setView(view.kind, params: {'groupBy': key}),
          ),
        if (view.kind == ViewKind.timeline)
          _fieldDropdown(
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
            label: loc.splitByDate,
            value: view.bucketBy,
            choices: ofType({FieldType.date, FieldType.dateTime}),
            extra: [noneItem],
            onChanged: (key) => _setView(view.kind, params: {'bucketBy': key}),
          ),
        const SizedBox(height: 12),
        _fieldDropdown(
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

  Widget _optionsEditor(ListLabels labels, FieldDefinition field) {
    void setOptions(List<FieldOption> options) {
      _push(
        ListPatchOp(PatchOpKind.setOptions, {
          'key': field.key,
          'options': options.map((option) => option.toJson()).toList(),
        }),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final FieldOption option in field.options)
            InputChip(
              label: Text(labels.option(option)),
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
            width: 140,
            child: TextField(
              key: ValueKey('add-option-${field.key}'),
              decoration: InputDecoration(
                hintText: labels.loc.addOption,
                isDense: true,
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

  Widget _fieldCard(ListLabels labels, FieldDefinition field, int index) {
    final AppLocalizations loc = labels.loc;
    final bool locked = field.primary || field.role != null;

    return Card(
      key: ValueKey('field-card-${field.key}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_indicator),
            ),
            title: TextFormField(
              key: ValueKey('field-label-${field.key}'),
              initialValue: labels.field(field),
              decoration: InputDecoration(
                labelText: loc.fieldName,
                isDense: true,
              ),
              onChanged: (text) => _push(
                ListPatchOp(PatchOpKind.renameField, {
                  'key': field.key,
                  'label': text,
                }),
              ),
            ),
            trailing: IconButton(
              key: ValueKey('remove-field-${field.key}'),
              tooltip: loc.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: field.primary
                  ? null
                  : () => _push(
                      ListPatchOp(PatchOpKind.removeField, {'key': field.key}),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<FieldType>(
                    key: ValueKey('field-type-${field.key}-${field.type.wire}'),
                    initialValue: field.type,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: loc.fieldType,
                      isDense: true,
                    ),
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
                Text(loc.required),
                Checkbox(
                  key: ValueKey('field-required-${field.key}'),
                  value: field.required,
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
            _optionsEditor(labels, field),
        ],
      ),
    );
  }

  Widget _heading(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  bool get _canSave => _result.isValid && (_ops.isNotEmpty || widget.isNew);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final ListLabels labels = ListLabels(loc);
    final ListDefinition draft = _draft;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? loc.newList : loc.editList),
        actions: [
          if (!widget.isNew)
            IconButton(
              key: const ValueKey('delete-list'),
              tooltip: loc.deleteList,
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  Navigator.of(context).pop(const ListEditorOutcome.deleted()),
            ),
          IconButton(
            key: const ValueKey('save-list'),
            tooltip: loc.save,
            icon: const Icon(Icons.check),
            onPressed: _canSave
                ? () => Navigator.of(
                    context,
                  ).pop(ListEditorOutcome.saved(List.of(_ops), _result))
                : null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
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
            decoration: InputDecoration(labelText: loc.listName),
            onChanged: (text) =>
                _push(ListPatchOp(PatchOpKind.setListInfo, {'name': text})),
          ),
          _heading(loc.listIcon),
          Wrap(
            spacing: 6,
            children: [
              for (final MapEntry<String, IconData> icon in listIcons.entries)
                ChoiceChip(
                  label: Icon(icon.value, size: 20),
                  selected: draft.icon == icon.key,
                  onSelected: (_) => _push(
                    ListPatchOp(PatchOpKind.setListInfo, {'icon': icon.key}),
                  ),
                ),
            ],
          ),
          _heading(loc.listColor),
          Wrap(
            spacing: 8,
            children: [
              for (final String color in listColorChoices)
                InkWell(
                  key: ValueKey('color-$color'),
                  customBorder: const CircleBorder(),
                  onTap: () => _push(
                    ListPatchOp(PatchOpKind.setListInfo, {'color': color}),
                  ),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: listColor(color),
                      shape: BoxShape.circle,
                      border: draft.color.toUpperCase() == color
                          ? Border.all(
                              width: 3,
                              color: Theme.of(context).colorScheme.onSurface,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.allowAi),
            value: draft.aiAllowed,
            onChanged: (on) =>
                _push(ListPatchOp(PatchOpKind.setListInfo, {'aiAllowed': on})),
          ),
          _heading(loc.fields),
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
                _fieldCard(labels, draft.fields[index], index),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('add-field'),
              icon: const Icon(Icons.add),
              label: Text(loc.addField),
              onPressed: () => _addField(labels),
            ),
          ),
          _layoutSection(labels),
          ListEditorRules(definition: draft, labels: labels, onOp: _push),
          if (_result.hiddenValues > 0)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                loc.hiddenValuesWarning(_result.hiddenValues),
                style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
              ),
            ),
          // Problems that keep Save disabled.
          if (!_result.isValid && (_ops.isNotEmpty || widget.isNew))
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _result.errors.map((error) => labels.error(error, _result.definition)).join('\n'),
                key: const ValueKey('editor-errors'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
