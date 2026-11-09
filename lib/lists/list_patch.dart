import 'list_definition.dart';
import 'list_error.dart';
import 'list_input.dart';
import 'list_item.dart';
import 'list_vocabulary.dart';

// Changes to a list's definition, as small operations (plan 6.2). The list
// editor produces them, and the AI will produce the same ones through
// patch_list(listId, ops), so both share validation, item migration,
// preview and undo (D-7).
enum PatchOpKind implements WireName {
  setListInfo('setListInfo'),
  addField('addField'),
  removeField('removeField'),
  renameField('renameField'),
  changeFieldType('changeFieldType'),
  setFieldProps('setFieldProps'),
  setOptions('setOptions'),
  moveField('moveField'),
  setView('setView'),
  addBehavior('addBehavior'),
  removeBehavior('removeBehavior');

  const PatchOpKind(this.wire);

  @override
  final String wire;
}

// One operation. Arguments by kind:
//   setListInfo {name?, description?, icon?, color?, aiAllowed?,
//                tickedItems?, confirmDelete?}   (null: follow Preferences)
//     (a blank description removes it)
//   addField {field, index?}           removeField {key}
//   renameField {key, label}           changeFieldType {key, type, options?}
//   setFieldProps {key, required?}     setOptions {key, options}
//   moveField {key, index}             setView {view}
//   addBehavior {behavior}             removeBehavior {kind}
class ListPatchOp {
  const ListPatchOp(this.kind, [this.args = const {}]);

  final PatchOpKind kind;
  final Map<String, dynamic> args;

  // The arguments of each kind and their JSON types (the comment above);
  // [requiredArgs] must be present. Ops come from the editor and from the
  // AI (T-19), so apply checks them before using them.
  static const Map<PatchOpKind, Map<String, ArgType>> argTypes = {
    PatchOpKind.setListInfo: {
      'name': ArgType.string,
      'description': ArgType.string,
      'icon': ArgType.string,
      'color': ArgType.string,
      'aiAllowed': ArgType.boolean,
      // The list's own choice, or null to follow Preferences (Q-117). Not
      // offered to the AI.
      'tickedItems': ArgType.any,
      'confirmDelete': ArgType.any,
    },
    PatchOpKind.addField: {'field': ArgType.object, 'index': ArgType.integer},
    PatchOpKind.removeField: {'key': ArgType.string},
    PatchOpKind.renameField: {'key': ArgType.string, 'label': ArgType.string},
    PatchOpKind.changeFieldType: {
      'key': ArgType.string,
      'type': ArgType.string,
      'options': ArgType.list,
    },
    PatchOpKind.setFieldProps: {'key': ArgType.string, 'required': ArgType.boolean},
    PatchOpKind.setOptions: {'key': ArgType.string, 'options': ArgType.list},
    PatchOpKind.moveField: {'key': ArgType.string, 'index': ArgType.integer},
    PatchOpKind.setView: {'view': ArgType.object},
    PatchOpKind.addBehavior: {'behavior': ArgType.object},
    PatchOpKind.removeBehavior: {'kind': ArgType.string},
  };

  static const Map<PatchOpKind, Set<String>> requiredArgs = {
    PatchOpKind.setListInfo: {},
    PatchOpKind.addField: {'field'},
    PatchOpKind.removeField: {'key'},
    PatchOpKind.renameField: {'key', 'label'},
    PatchOpKind.changeFieldType: {'key', 'type'},
    PatchOpKind.setFieldProps: {'key'},
    PatchOpKind.setOptions: {'key', 'options'},
    PatchOpKind.moveField: {'key'},
    PatchOpKind.setView: {'view'},
    PatchOpKind.addBehavior: {'behavior'},
    PatchOpKind.removeBehavior: {'kind'},
  };

  String? get key {
    final Object? key = args['key'];
    return key is String ? key : null;
  }

  // Unknown, missing or wrongly typed arguments, also inside the field,
  // option, view and behavior objects; empty when the op can be applied.
  List<ListError> argErrors() {
    final String op = kind.wire;
    final List<ListError> errors = ListInput.checkArgs(
      args,
      op,
      argTypes[kind]!,
      required: requiredArgs[kind]!,
    );
    if (errors.isNotEmpty) {
      return errors;
    }
    final Object? options = args['options'];
    if (options is List) {
      for (int i = 0; i < options.length; i++) {
        errors.addAll(ListInput.unknownKeys(options[i], InputShape.option, op, 'options[$i]'));
      }
    }
    errors.addAll(ListInput.unknownKeys(args['field'], InputShape.field, op, 'field'));
    errors.addAll(ListInput.unknownKeys(args['view'], InputShape.view, op, 'view'));
    errors.addAll(ListInput.unknownKeys(args['behavior'], InputShape.behavior, op, 'behavior'));
    return errors;
  }

  Map<String, dynamic> toJson() => {'op': kind.wire, ...args};

  factory ListPatchOp.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('patch op must be a JSON object');
    }
    final Map<String, dynamic> map = Map<String, dynamic>.from(json);
    final PatchOpKind? kind = enumFromWire(PatchOpKind.values, map.remove('op'));
    if (kind == null) {
      throw FormatException('unknown patch op "${json['op']}"');
    }
    return ListPatchOp(kind, map);
  }
}

class ListPatchResult {
  const ListPatchResult({
    required this.definition,
    required this.items,
    required this.changedItemIds,
    required this.hiddenValues,
    required this.errors,
    required this.definitionBefore,
    required this.itemsBefore,
    this.itemsPending = false,
  });

  // The same result, saved with its items still to come.
  ListPatchResult withItemsPending() => ListPatchResult(
    definition: definition,
    items: items,
    changedItemIds: changedItemIds,
    hiddenValues: hiddenValues,
    errors: errors,
    definitionBefore: definitionBefore,
    itemsBefore: itemsBefore,
    itemsPending: true,
  );

  final ListDefinition definition;
  final List<ListItem> items;
  // What the ops were applied to: in a store, the list as its write read it,
  // which is what an Undo must bring back (H6 of the Codex review).
  final ListDefinition definitionBefore;
  final List<ListItem> itemsBefore;
  // A store saved the definition and is still fitting more items than one
  // write holds; no Undo can cover a change this size (Q-59).
  final bool itemsPending;
  final Set<String> changedItemIds;
  // Values that could not be converted and were moved to the item's hidden
  // `_legacy` slot, so nothing is destroyed (Q-4, plan 4.4).
  final int hiddenValues;
  // Empty when the patched definition is valid.
  final List<ListError> errors;

  bool get isValid => errors.isEmpty;
}

class ListPatch {
  // Key under which unconvertible values are kept on an item.
  static const String legacyKey = '_legacy';

  // The values archived for one field in an item's `_legacy` map, oldest
  // first (D-10). Older data kept a single value there, which reads as a
  // one-entry list; a List is taken as the list of archived values, so an
  // old archived list may read as several entries, but nothing is lost.
  static List<Object?> archivedValues(Map? legacy, String key) {
    final Object? archived = legacy?[key];
    if (archived == null) {
      return const [];
    }
    return archived is List ? List<Object?>.from(archived) : [archived];
  }

  static ListPatchResult apply(
    ListDefinition definition,
    List<ListItem> items,
    List<ListPatchOp> ops,
    DateTime now,
  ) {
    final List<ListError> errors = [];
    final List<FieldDefinition> fields = [...definition.fields];
    final Map<String, dynamic> info = {};
    ViewDefinition view = definition.view;
    final List<BehaviorDefinition> behaviors = [...definition.behaviors];
    final Map<String, Map<String, dynamic>> values = {
      for (final ListItem item in items) item.id: Map<String, dynamic>.from(item.values),
    };
    final Set<String> changed = {};
    int hidden = 0;

    int indexOf(String? key) => fields.indexWhere((field) => field.key == key);

    // Moves a value that does not fit any more into the hidden slot.
    void hide(String itemId, String key) {
      final Map<String, dynamic> itemValues = values[itemId]!;
      // A stored `_legacy` that is not a map is replaced, not cast (N5).
      final Object? stored = itemValues[legacyKey];
      final Map<String, dynamic> legacy = Map<String, dynamic>.from(
        stored is Map ? stored : const {},
      );
      legacy[key] = [...archivedValues(legacy, key), itemValues.remove(key)];
      itemValues[legacyKey] = legacy;
      changed.add(itemId);
      hidden++;
    }

    for (final ListPatchOp op in ops) {
      final List<ListError> argErrors = op.argErrors();
      if (argErrors.isNotEmpty) {
        errors.addAll(argErrors);
        continue;
      }
      final int index = indexOf(op.key);
      final bool needsField = const {
        PatchOpKind.removeField,
        PatchOpKind.renameField,
        PatchOpKind.changeFieldType,
        PatchOpKind.setFieldProps,
        PatchOpKind.setOptions,
        PatchOpKind.moveField,
      }.contains(op.kind);
      if (needsField && index < 0) {
        errors.add(ListError(
          ListErrorCode.opNoField,
          {'op': op.kind.wire, 'field': '${op.key}'},
        ));
        continue;
      }

      try {
        switch (op.kind) {
          case PatchOpKind.setListInfo:
            final Object? ticked = op.args[ListDefinition.ownTickedItemsKey];
            final Object? confirm = op.args[ListDefinition.ownConfirmDeleteKey];
            if (ticked is! String? || confirm is! bool?) {
              errors.add(ListError(
                ListErrorCode.badOp,
                {'op': op.kind.wire, 'detail': 'tickedItems must be a string and confirmDelete true or false, or null'},
              ));
              continue;
            }
            info.addAll(op.args);
          case PatchOpKind.addField:
            final FieldDefinition field = FieldDefinition.fromJson(op.args['field']);
            if (indexOf(field.key) >= 0) {
              errors.add(ListError(ListErrorCode.fieldExists, {'field': field.key}));
              continue;
            }
            final int? at = op.args['index'] as int?;
            fields.insert((at ?? fields.length).clamp(0, fields.length), field);
          case PatchOpKind.removeField:
            // Values stay on the items, hidden, so an undo restores them.
            fields.removeAt(index);
          case PatchOpKind.renameField:
            final FieldDefinition field = fields[index];
            fields[index] = _copy(field, label: op.args['label'] as String?, clearLabelKey: true);
          case PatchOpKind.setFieldProps:
            final FieldDefinition field = fields[index];
            fields[index] = _copy(field, required: op.args['required'] as bool?);
          case PatchOpKind.moveField:
            final FieldDefinition field = fields.removeAt(index);
            final int to = (op.args['index'] as int? ?? fields.length).clamp(0, fields.length);
            fields.insert(to, field);
          case PatchOpKind.changeFieldType:
            final FieldDefinition field = fields[index];
            final FieldType? type = enumFromWire(FieldType.values, op.args['type']);
            if (type == null) {
              errors.add(ListError(
                ListErrorCode.unknownFieldType,
                {'type': '${op.args['type']}'},
              ));
              continue;
            }
            List<FieldOption> options = op.args['options'] is List
                ? (op.args['options'] as List).map(FieldOption.fromJson).toList()
                : field.options;
            // Turning free text into a choice offers the values already used.
            if (type == FieldType.choice && options.isEmpty) {
              options = _optionsFromValues(values.values, field.key);
            }
            final FieldDefinition next = _copy(
              field,
              type: type,
              options: type.needsOptions || type.hasUserOptions ? options : const [],
              role: _roleFits(field.role, type) ? field.role : null,
              clearRole: !_roleFits(field.role, type),
            );
            fields[index] = next;
            for (final MapEntry<String, Map<String, dynamic>> entry in values.entries) {
              final Object? value = entry.value[field.key];
              if (value == null) {
                continue;
              }
              final (bool ok, Object? converted) = convertValue(value, next);
              if (!ok) {
                hide(entry.key, field.key);
              } else if (converted != value) {
                if (converted == null) {
                  entry.value.remove(field.key);
                } else {
                  entry.value[field.key] = converted;
                }
                changed.add(entry.key);
              }
            }
          case PatchOpKind.setOptions:
            final FieldDefinition field = fields[index];
            final List<FieldOption> options =
                (op.args['options'] as List).map(FieldOption.fromJson).toList();
            fields[index] = _copy(field, options: options);
            if (field.type == FieldType.choice) {
              for (final MapEntry<String, Map<String, dynamic>> entry in values.entries) {
                final Object? value = entry.value[field.key];
                if (value != null && !options.any((option) => option.value == value)) {
                  hide(entry.key, field.key);
                }
              }
            }
          case PatchOpKind.setView:
            view = ViewDefinition.fromJson(op.args['view']);
          case PatchOpKind.addBehavior:
            behaviors.add(BehaviorDefinition.fromJson(op.args['behavior']));
          case PatchOpKind.removeBehavior:
            behaviors.removeWhere((behavior) => behavior.kind.wire == op.args['kind']);
        }
      } on FormatException catch (error) {
        errors.add(ListError(
          ListErrorCode.badOp,
          {'op': op.kind.wire, 'detail': error.message},
        ));
      }
    }

    final ListDefinition patched = ListDefinition(
      formatVersion: definition.formatVersion,
      id: definition.id,
      name: info.containsKey('name') ? info['name'] as String? : definition.name,
      nameKey: info.containsKey('name') ? null : definition.nameKey,
      description: info.containsKey('description')
          ? _description(info['description'] as String?)
          : definition.description,
      descriptionKey: info.containsKey('description') ? null : definition.descriptionKey,
      icon: info['icon'] as String? ?? definition.icon,
      color: info['color'] as String? ?? definition.color,
      templateId: definition.templateId,
      schemaRevision: definition.schemaRevision + (ops.isEmpty ? 0 : 1),
      fields: fields,
      view: view,
      behaviors: behaviors,
      aiAllowed: info['aiAllowed'] as bool? ?? definition.aiAllowed,
      updatedAt: ops.isEmpty ? definition.updatedAt : now,
      extra: {
        ...definition.extra,
        for (final String key in const [
          ListDefinition.ownTickedItemsKey,
          ListDefinition.ownConfirmDeleteKey,
        ])
          if (info.containsKey(key) && info[key] != null) key: info[key],
      }..removeWhere((key, value) => info.containsKey(key) && info[key] == null),
    );
    errors.addAll(patched.validate());

    return ListPatchResult(
      definitionBefore: definition,
      itemsBefore: items,
      definition: patched,
      items: [
        for (final ListItem item in items)
          changed.contains(item.id)
              ? ListItem(
                  id: item.id,
                  listId: item.listId,
                  values: values[item.id]!,
                  createdAt: item.createdAt,
                  updatedAt: now,
                )
              : item,
      ],
      changedItemIds: changed,
      hiddenValues: hidden,
      errors: errors,
    );
  }

  // Converts a value to fit `field`. Returns (false, _) when it cannot be
  // done without losing information; empty text becomes null (no value).
  static (bool, Object?) convertValue(Object value, FieldDefinition field) {
    final String? text = value is String ? value.trim() : null;
    if (text != null && text.isEmpty && field.type != FieldType.text &&
        field.type != FieldType.longText) {
      return (true, null);
    }

    switch (field.type) {
      case FieldType.text:
      case FieldType.longText:
      case FieldType.url:
      case FieldType.category:
        if (value is String) {
          return (true, value);
        }
        if (value is num || value is bool) {
          return (true, '$value');
        }
        if (value is List && value.every((entry) => entry is String)) {
          return (true, value.join(', '));
        }
        return (false, null);
      case FieldType.number:
        if (value is num) {
          return (true, value);
        }
        final num? parsed = text == null ? null : num.tryParse(text);
        return parsed == null ? (false, null) : (true, parsed);
      case FieldType.counter:
      case FieldType.rating:
        final num? number = value is num ? value : (text == null ? null : num.tryParse(text));
        if (number == null || number != number.roundToDouble()) {
          return (false, null);
        }
        return (true, number.toInt());
      case FieldType.checkbox:
      case FieldType.toggle:
        if (value is bool) {
          return (true, value);
        }
        final String? lower = text?.toLowerCase();
        if (const {'true', 'yes', 'y', '1'}.contains(lower)) {
          return (true, true);
        }
        if (const {'false', 'no', 'n', '0'}.contains(lower)) {
          return (true, false);
        }
        return (false, null);
      case FieldType.date:
      case FieldType.dateTime:
        return text != null && DateTime.tryParse(text) != null
            ? (true, text)
            : (false, null);
      case FieldType.choice:
        if (text == null) {
          return (false, null);
        }
        for (final FieldOption option in field.options) {
          if (option.value.toLowerCase() == text.toLowerCase() ||
              option.label?.toLowerCase() == text.toLowerCase()) {
            return (true, option.value);
          }
        }
        return (false, null);
      case FieldType.tags:
        if (value is List && value.every((entry) => entry is String)) {
          return (true, value);
        }
        if (text != null) {
          return (true, text.split(',').map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList());
        }
        return (false, null);
      // The two structured types have different shapes: a checklist is a list
      // of sub-items, a recurrence a {frequency, ...} map.
      case FieldType.checklist:
        return value is List ? (true, value) : (false, null);
      case FieldType.recurrence:
        return value is Map ? (true, value) : (false, null);
    }
  }

  static List<FieldOption> _optionsFromValues(
    Iterable<Map<String, dynamic>> values,
    String key,
  ) {
    final Set<String> seen = {};
    final List<FieldOption> options = [];
    for (final Map<String, dynamic> itemValues in values) {
      final Object? value = itemValues[key];
      final String text = value is String ? value.trim() : '';
      if (text.isNotEmpty && seen.add(text.toLowerCase())) {
        options.add(FieldOption(value: text, label: text));
      }
    }
    return options;
  }

  // A description as stored: trimmed, and none when blank.
  static String? _description(String? text) {
    final String trimmed = (text ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _roleFits(FieldRole? role, FieldType type) {
    switch (role) {
      case null:
        return true;
      case FieldRole.completion:
        return type == FieldType.checkbox;
      case FieldRole.reminder:
        return type == FieldType.dateTime;
      case FieldRole.status:
      case FieldRole.section:
        return type == FieldType.choice;
      case FieldRole.category:
        return type == FieldType.category;
    }
  }

  static FieldDefinition _copy(
    FieldDefinition field, {
    FieldType? type,
    String? label,
    bool clearLabelKey = false,
    bool? required,
    FieldRole? role,
    bool clearRole = false,
    List<FieldOption>? options,
  }) {
    return FieldDefinition(
      key: field.key,
      type: type ?? field.type,
      label: label ?? field.label,
      labelKey: clearLabelKey && label != null ? null : field.labelKey,
      required: required ?? field.required,
      primary: field.primary,
      role: clearRole ? null : role ?? field.role,
      options: options ?? field.options,
      defaultValue: type == null || type == field.type ? field.defaultValue : null,
      min: field.min,
      max: field.max,
      visibleWhen: field.visibleWhen,
    );
  }
}
