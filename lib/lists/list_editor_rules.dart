import 'package:flutter/material.dart';

import '../app/settings_controls.dart';
import '../l10n/generated/app_localizations.dart';
import 'list_definition.dart';
import 'list_editor_style.dart';
import 'list_error.dart';
import 'list_labels.dart';
import 'list_patch.dart';
import 'list_vocabulary.dart';

// The rules the editor can add with pickers (Q-13 B). copyOnClear needs a
// condition builder and stays with templates and the AI; it can be removed here.
const List<BehaviorKind> editorAddableRules = [
  BehaviorKind.recurOnClear,
  BehaviorKind.moveAll,
];

// The list editor's rules section. Every control hands an addBehavior or
// removeBehavior op to [onOp], the same ops the AI uses (D-7). removeBehavior
// works by kind, so the editor offers one rule of each kind. Rules are
// hairline rows; [extraRows] (the editor's Allow AI switch) follow them.
class ListEditorRules extends StatelessWidget {
  const ListEditorRules({
    super.key,
    required this.definition,
    required this.labels,
    required this.onOp,
    this.extraRows = const [],
    this.showLabel = true,
  });

  // The editor's current draft.
  final ListDefinition definition;
  final ListLabels labels;
  final ValueChanged<ListPatchOp> onOp;
  final List<Widget> extraRows;
  // Off inside the editor's folded Rules section, whose header names it.
  final bool showLabel;

  static ListPatchOp addOp(BehaviorDefinition behavior) {
    return ListPatchOp(PatchOpKind.addBehavior, {'behavior': behavior.toJson()});
  }

  static ListPatchOp removeOp(BehaviorKind kind) {
    return ListPatchOp(PatchOpKind.removeBehavior, {'kind': kind.wire});
  }

  bool _has(BehaviorKind kind) {
    return definition.behaviors.any((behavior) => behavior.kind == kind);
  }

  // "Field: value" pairs that say what a rule does, from the list's labels.
  String? _summary(BehaviorDefinition behavior) {
    final AppLocalizations loc = labels.loc;
    String fieldName(String? key) {
      final FieldDefinition? field = definition.field(key ?? '');
      return field == null ? key ?? '' : labels.field(field);
    }

    String optionName(String? value) {
      final FieldOption? option = definition
          .field(behavior.stringParam('field') ?? '')
          ?.options
          .where((option) => option.value == value)
          .firstOrNull;
      return option == null ? value ?? '' : labels.option(option);
    }

    switch (behavior.kind) {
      case BehaviorKind.recurOnClear:
        return '${loc.dateField}: ${fieldName(behavior.stringParam('dateField'))}'
            ' · ${loc.ruleRepeatField}: '
            '${fieldName(behavior.stringParam('recurrenceField'))}';
      case BehaviorKind.moveAll:
        return '${fieldName(behavior.stringParam('field'))}: '
            '${optionName(behavior.stringParam('from'))} → '
            '${optionName(behavior.stringParam('to'))}';
      case BehaviorKind.copyOnClear:
      case BehaviorKind.clearCompleted:
        return null;
    }
  }

  Future<void> _addRule(BuildContext context) async {
    final BehaviorDefinition? behavior = await showDialog<BehaviorDefinition>(
      context: context,
      builder: (_) => _AddRuleDialog(
        definition: definition,
        labels: labels,
        kinds: [
          for (final BehaviorKind kind in editorAddableRules)
            if (!_has(kind)) kind,
        ],
      ),
    );
    if (behavior != null) {
      onOp(addOp(behavior));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = labels.loc;
    final EditorLook look = EditorLook.of(context);
    final List<BehaviorDefinition> others = definition.behaviors
        .where((behavior) => behavior.kind != BehaviorKind.clearCompleted)
        .toList();
    // A stored list may hold several rules of one kind (the schema allows
    // it), so tiles are keyed by kind and their place among that kind.
    final Map<BehaviorKind, int> seen = {};
    final List<String> ids = [];
    for (final BehaviorDefinition behavior in others) {
      final int place = seen[behavior.kind] ?? 0;
      seen[behavior.kind] = place + 1;
      ids.add('${behavior.kind.wire}-$place');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLabel) look.sectionLabel(loc.rules),
        look.hairline(
          child: SwitchListTile(
            key: const ValueKey('rule-clearCompleted'),
            contentPadding: EdgeInsets.zero,
            title: Text(loc.ruleClearCompleted, style: look.label),
            subtitle: Text(loc.ruleClearCompletedLine, style: look.type.meta),
            value: _has(BehaviorKind.clearCompleted),
            // It needs a tick: without a Done field it cannot be turned on.
            onChanged: definition.fieldWithRole(FieldRole.completion) == null &&
                    !_has(BehaviorKind.clearCompleted)
                ? null
                : (on) => onOp(
              on
                  ? addOp(const BehaviorDefinition(kind: BehaviorKind.clearCompleted))
                  : removeOp(BehaviorKind.clearCompleted),
            ),
          ),
        ),
        for (final (int index, BehaviorDefinition behavior) in others.indexed)
          look.hairline(
            child: ListTile(
              key: ValueKey('rule-${ids[index]}'),
              contentPadding: EdgeInsets.zero,
              title: Text(labels.behavior(behavior.kind), style: look.label),
              subtitle: switch (_summary(behavior)) {
                final String summary => Text(summary, style: look.type.meta),
                null => null,
              },
              trailing: IconButton(
                key: ValueKey('remove-rule-${ids[index]}'),
                tooltip: loc.delete,
                color: look.neutrals.muted,
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => onOp(removeOp(behavior.kind)),
              ),
            ),
          ),
        ...extraRows,
        if (editorAddableRules.any((kind) => !_has(kind)))
          look.addButton(
            key: const ValueKey('add-rule'),
            text: loc.addRule,
            onPressed: () => _addRule(context),
          ),
      ],
    );
  }
}

// Picks a rule and its parameters from the list's own fields. The rule is
// checked on the draft as it would be saved; while it has errors they show
// translated and Add stays disabled.
class _AddRuleDialog extends StatefulWidget {
  const _AddRuleDialog({
    required this.definition,
    required this.labels,
    required this.kinds,
  });

  final ListDefinition definition;
  final ListLabels labels;
  final List<BehaviorKind> kinds;

  @override
  State<_AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends State<_AddRuleDialog> {
  late BehaviorKind _kind;
  final Map<String, String?> _params = {};

  ListDefinition get _definition => widget.definition;

  Iterable<FieldDefinition> _ofType(Set<FieldType> types) {
    return _definition.fields.where((field) => types.contains(field.type));
  }

  FieldDefinition? get _moveField => _definition.field(_params['field'] ?? '');

  @override
  void initState() {
    super.initState();
    _selectKind(widget.kinds.first);
  }

  // Starts each parameter on the first field or option that fits.
  void _selectKind(BehaviorKind kind) {
    _kind = kind;
    _params.clear();
    switch (kind) {
      case BehaviorKind.recurOnClear:
        _params['dateField'] = _ofType({FieldType.date, FieldType.dateTime}).firstOrNull?.key;
        _params['recurrenceField'] = _ofType({FieldType.recurrence}).firstOrNull?.key;
      case BehaviorKind.moveAll:
        _selectMoveField(_ofType({FieldType.choice}).firstOrNull?.key);
      case BehaviorKind.copyOnClear:
      case BehaviorKind.clearCompleted:
        break;
    }
  }

  void _selectMoveField(String? key) {
    _params['field'] = key;
    _params['to'] = null;
    _selectFrom(_moveField?.options.firstOrNull?.value);
  }

  // Moving to the same option does nothing, so "to" offers only the others.
  void _selectFrom(String? value) {
    _params['from'] = value;
    if (_params['to'] == null || _params['to'] == value) {
      _params['to'] = _toChoices.firstOrNull?.value;
    }
  }

  List<FieldOption> get _toChoices {
    return (_moveField?.options ?? const <FieldOption>[])
        .where((option) => option.value != _params['from'])
        .toList();
  }

  BehaviorDefinition get _behavior {
    return BehaviorDefinition(
      kind: _kind,
      params: {
        for (final MapEntry<String, String?> param in _params.entries)
          if (param.value != null) param.key: param.value,
      },
    );
  }

  List<ListError> get _errors {
    final ListPatchResult result = ListPatch.apply(
      _definition,
      const [],
      [ListEditorRules.addOp(_behavior)],
      DateTime.now().toUtc(),
    );
    return result.errors
        .where((error) => error.arg('rule') == _kind.wire)
        .toList();
  }

  Widget _picker<T>({
    required String param,
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: KeyedSubtree(
        key: ValueKey('rule-$param'),
        // The choices open in place, not as a drop-down (T-24). The inner
        // key resets it when the choice is made elsewhere.
        child: SettingFoldPicker<T>(
          key: ValueKey('rule-$param-$value-${items.length}'),
          label: label,
          value: items.any((item) => item.value == value) ? value : null,
          choices: [
            for (final DropdownMenuItem<T> item in items)
              (value: item.value as T, child: item.child),
          ],
          onChanged: items.isEmpty ? null : onChanged,
        ),
      ),
    );
  }

  Widget _fieldPicker(String param, String label, Set<FieldType> types, ValueChanged<String?> onChanged) {
    return _picker<String>(
      param: param,
      label: label,
      value: _params[param],
      items: [
        for (final FieldDefinition field in _ofType(types))
          DropdownMenuItem(value: field.key, child: Text(widget.labels.field(field))),
      ],
      onChanged: onChanged,
    );
  }

  Widget _optionPicker(String param, String label, List<FieldOption> options, ValueChanged<String?> onChanged) {
    return _picker<String>(
      param: param,
      label: label,
      value: _params[param],
      items: [
        for (final FieldOption option in options)
          DropdownMenuItem(value: option.value, child: Text(widget.labels.option(option))),
      ],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ListLabels labels = widget.labels;
    final AppLocalizations loc = labels.loc;
    final List<ListError> errors = _errors;

    return AlertDialog(
      title: Text(loc.addRule),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _picker<BehaviorKind>(
              param: 'kind',
              label: loc.ruleKind,
              value: _kind,
              items: [
                for (final BehaviorKind kind in widget.kinds)
                  DropdownMenuItem(value: kind, child: Text(labels.behavior(kind))),
              ],
              onChanged: (kind) => setState(() => _selectKind(kind ?? _kind)),
            ),
            if (_kind == BehaviorKind.recurOnClear) ...[
              _fieldPicker(
                'dateField',
                loc.dateField,
                {FieldType.date, FieldType.dateTime},
                (key) => setState(() => _params['dateField'] = key),
              ),
              _fieldPicker(
                'recurrenceField',
                loc.ruleRepeatField,
                {FieldType.recurrence},
                (key) => setState(() => _params['recurrenceField'] = key),
              ),
            ],
            if (_kind == BehaviorKind.moveAll) ...[
              _fieldPicker(
                'field',
                loc.ruleMoveField,
                {FieldType.choice},
                (key) => setState(() => _selectMoveField(key)),
              ),
              _optionPicker(
                'from',
                loc.ruleMoveFrom,
                _moveField?.options ?? const [],
                (value) => setState(() => _selectFrom(value)),
              ),
              _optionPicker(
                'to',
                loc.ruleMoveTo,
                _toChoices,
                (value) => setState(() => _params['to'] = value),
              ),
            ],
            if (errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  errors.map((error) => labels.error(error, _definition)).join('\n'),
                  key: const ValueKey('rule-errors'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(loc.cancel),
        ),
        FilledButton(
          key: const ValueKey('add-rule-confirm'),
          onPressed: errors.isEmpty ? () => Navigator.of(context).pop(_behavior) : null,
          child: Text(loc.add),
        ),
      ],
    );
  }
}
