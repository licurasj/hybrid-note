import 'list_error.dart';
import 'list_vocabulary.dart';

// A list type described as data: its fields, how it is shown and which
// built-in rules apply. Built-in lists, lists made in the editor and lists
// proposed by the AI all use this one shape.
//
// fromJson throws FormatException when the JSON is not a definition at all
// (missing keys, wrong types, names outside the vocabulary). validate() then
// checks that the parts fit together (keys exist, behaviours point at fields
// of the right type).

class FieldOption {
  final String value;
  final String? label;
  final String? labelKey;

  const FieldOption({
    required this.value,
    this.label,
    this.labelKey,
  });

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      if (label != null) 'label': label,
      if (labelKey != null) 'labelKey': labelKey,
    };
  }

  factory FieldOption.fromJson(Object? json) {
    final Map<String, dynamic> map = _asMap(json, 'option');
    return FieldOption(
      value: _requireString(map, 'value', 'option'),
      label: _optionalString(map, 'label', 'option'),
      labelKey: _optionalString(map, 'labelKey', 'option'),
    );
  }
}

// Shows a field only while another enum field has one of the given values,
// e.g. season and episode only for TV shows. Hidden fields are cleared on save.
class FieldCondition {
  final String field;
  final List<String> values;

  const FieldCondition({
    required this.field,
    required this.values,
  });

  bool isMetBy(Map<String, dynamic> itemValues) {
    return values.contains(itemValues[field]);
  }

  Map<String, dynamic> toJson() {
    return {
      'field': field,
      'in': values,
    };
  }

  factory FieldCondition.fromJson(Object? json) {
    final Map<String, dynamic> map = _asMap(json, 'visibleWhen');
    final List<dynamic> values = _requireList(map, 'in', 'visibleWhen');

    if (values.any((value) => value is! String)) {
      throw const FormatException('visibleWhen: "in" must list strings');
    }

    return FieldCondition(
      field: _requireString(map, 'field', 'visibleWhen'),
      values: values.cast<String>(),
    );
  }
}

class FieldDefinition {
  final String key;
  final FieldType type;
  // Literal label (user or AI lists) or an l10n key (built-in lists).
  final String? label;
  final String? labelKey;
  final bool required;
  final bool primary;
  final FieldRole? role;
  final List<FieldOption> options;
  final Object? defaultValue;
  final num? min;
  final num? max;
  final FieldCondition? visibleWhen;

  const FieldDefinition({
    required this.key,
    required this.type,
    this.label,
    this.labelKey,
    this.required = false,
    this.primary = false,
    this.role,
    this.options = const [],
    this.defaultValue,
    this.min,
    this.max,
    this.visibleWhen,
  });

  bool isVisibleFor(Map<String, dynamic> itemValues) {
    return visibleWhen == null || visibleWhen!.isMetBy(itemValues);
  }

  FieldDefinition copyWith({List<FieldOption>? options}) {
    return FieldDefinition(
      key: key,
      type: type,
      label: label,
      labelKey: labelKey,
      required: required,
      primary: primary,
      role: role,
      options: options ?? this.options,
      defaultValue: defaultValue,
      min: min,
      max: max,
      visibleWhen: visibleWhen,
    );
  }

  bool hasOption(Object? value) {
    return options.any((option) => option.value == value);
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'type': type.wire,
      if (label != null) 'label': label,
      if (labelKey != null) 'labelKey': labelKey,
      if (required) 'required': true,
      if (primary) 'primary': true,
      if (role != null) 'role': role!.wire,
      if (options.isNotEmpty)
        'options': options.map((option) => option.toJson()).toList(),
      if (defaultValue != null) 'default': defaultValue,
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (visibleWhen != null) 'visibleWhen': visibleWhen!.toJson(),
    };
  }

  factory FieldDefinition.fromJson(Object? json) {
    final Map<String, dynamic> map = _asMap(json, 'field');
    final String key = _requireString(map, 'key', 'field');
    final String where = 'field "$key"';

    return FieldDefinition(
      key: key,
      type: _requireWire(FieldType.values, map['type'], '$where type'),
      label: _optionalString(map, 'label', where),
      labelKey: _optionalString(map, 'labelKey', where),
      required: _optionalBool(map, 'required', where) ?? false,
      primary: _optionalBool(map, 'primary', where) ?? false,
      role: map['role'] == null
          ? null
          : _requireWire(FieldRole.values, map['role'], '$where role'),
      options: _optionalList(map, 'options', where)
          .map(FieldOption.fromJson)
          .toList(),
      defaultValue: map['default'],
      min: _optionalNum(map, 'min', where),
      max: _optionalNum(map, 'max', where),
      visibleWhen: map['visibleWhen'] == null
          ? null
          : FieldCondition.fromJson(map['visibleWhen']),
    );
  }
}

class ViewDefinition {
  final ViewKind kind;
  final String? sectionBy;
  final String? groupBy;
  final String? dateField;
  final TimelineGrouping? timelineGrouping;
  final String? filterChipsBy;
  // Splits a checklist into Today / Tomorrow / Later by a date field; items
  // without a date count as Today.
  final String? bucketBy;

  const ViewDefinition({
    required this.kind,
    this.sectionBy,
    this.groupBy,
    this.dateField,
    this.timelineGrouping,
    this.filterChipsBy,
    this.bucketBy,
  });

  Map<String, dynamic> toJson() {
    return {
      'kind': kind.wire,
      if (sectionBy != null) 'sectionBy': sectionBy,
      if (groupBy != null) 'groupBy': groupBy,
      if (dateField != null) 'dateField': dateField,
      if (timelineGrouping != null) 'timelineGrouping': timelineGrouping!.wire,
      if (filterChipsBy != null) 'filterChipsBy': filterChipsBy,
      if (bucketBy != null) 'bucketBy': bucketBy,
    };
  }

  factory ViewDefinition.fromJson(Object? json) {
    final Map<String, dynamic> map = _asMap(json, 'view');
    return ViewDefinition(
      kind: _requireWire(ViewKind.values, map['kind'], 'view kind'),
      sectionBy: _optionalString(map, 'sectionBy', 'view'),
      groupBy: _optionalString(map, 'groupBy', 'view'),
      dateField: _optionalString(map, 'dateField', 'view'),
      timelineGrouping: map['timelineGrouping'] == null
          ? null
          : _requireWire(
              TimelineGrouping.values,
              map['timelineGrouping'],
              'view timelineGrouping',
            ),
      filterChipsBy: _optionalString(map, 'filterChipsBy', 'view'),
      bucketBy: _optionalString(map, 'bucketBy', 'view'),
    );
  }
}

// A named rule the app runs. Parameters depend on the kind:
// - recurOnClear: dateField (dateTime), recurrenceField (recurrence)
// - copyOnClear: when (toggle), optional where {field: value},
//   setField {field: value}, optional dedupeBy (field)
// - moveAll: field (enum), from, to (option values)
// - clearCompleted: no parameters
// All kinds except moveAll need a field with the completion role.
class BehaviorDefinition {
  final BehaviorKind kind;
  final Map<String, dynamic> params;

  const BehaviorDefinition({
    required this.kind,
    this.params = const {},
  });

  String? stringParam(String name) {
    final Object? value = params[name];
    return value is String ? value : null;
  }

  Map<String, dynamic> mapParam(String name) {
    final Object? value = params[name];
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind.wire,
      ...params,
    };
  }

  factory BehaviorDefinition.fromJson(Object? json) {
    final Map<String, dynamic> map = Map<String, dynamic>.from(
      _asMap(json, 'behavior'),
    );
    final BehaviorKind kind = _requireWire(
      BehaviorKind.values,
      map.remove('kind'),
      'behavior kind',
    );
    return BehaviorDefinition(kind: kind, params: map);
  }
}

class ListDefinition {
  // Version of this JSON format, so older builds can tell they are reading
  // something newer than they understand.
  static const int currentFormatVersion = 1;

  // The longest description, in characters (Q-44 D1): one or two sentences.
  static const int descriptionMaxLength = 200;

  // The translated default description of each built-in template, by
  // templateId. Lists stored before descriptions existed get it when read
  // (no descriptionKey entry at all); a stored null means the user cleared it.
  static const Map<String, String> templateDescriptionKeys = {
    'builtin.tasks': 'tasksDescription',
    'builtin.grocery': 'groceryDescription',
    'builtin.journal': 'journalDescription',
    'builtin.watchRead': 'watchReadDescription',
  };

  static const Set<String> _knownKeys = {
    'formatVersion',
    'id',
    'name',
    'nameKey',
    'description',
    'descriptionKey',
    'icon',
    'color',
    'templateId',
    'schemaRevision',
    'fields',
    'view',
    'behaviors',
    'aiAllowed',
    'updatedAt',
  };

  final int formatVersion;
  final String id;
  final String? name;
  final String? nameKey;
  // What the list is for, in the user's words (Q-44); shown under the title
  // and sent to the AI to help it pick lists. Null when there is none.
  final String? description;
  // An l10n key for the description of a built-in list, like nameKey.
  final String? descriptionKey;
  final String icon;
  final String color;
  final String? templateId;
  // Bumps on every edit of the definition.
  final int schemaRevision;
  final List<FieldDefinition> fields;
  final ViewDefinition view;
  final List<BehaviorDefinition> behaviors;
  // Per-list "never send to AI" switch.
  final bool aiAllowed;
  final DateTime updatedAt;
  // Keys written by a newer build; kept so saving does not drop them.
  final Map<String, dynamic> extra;

  const ListDefinition({
    this.formatVersion = currentFormatVersion,
    required this.id,
    this.name,
    this.nameKey,
    this.description,
    this.descriptionKey,
    required this.icon,
    required this.color,
    this.templateId,
    this.schemaRevision = 1,
    required this.fields,
    required this.view,
    this.behaviors = const [],
    this.aiAllowed = true,
    required this.updatedAt,
    this.extra = const {},
  });

  FieldDefinition? field(String key) {
    for (final FieldDefinition field in fields) {
      if (field.key == key) {
        return field;
      }
    }

    return null;
  }

  // Settings this list has its own choice of, instead of following
  // Preferences (Q-117, Q-118). Absent means it follows Preferences, so an old
  // list document needs no change. Kept with the list's other unknown keys and
  // changed through setListInfo.
  static const String ownTickedItemsKey = 'tickedItems';
  static const String ownConfirmDeleteKey = 'confirmDelete';
  // How early its reminders ring (T-13, Q-118): a list of ReminderLead wire
  // values (reminders/reminder_settings.dart), possibly empty for no rings.
  static const String ownReminderLeadsKey = 'reminderLeads';
  // The wire values of ReminderLead (reminders/reminder_settings.dart).
  static const Set<String> reminderLeadWires = {
    'atTime',
    '5m',
    '10m',
    '30m',
    '1h',
    '1d',
  };
  // The wire values of TickedItems (app/account_preferences.dart), which a
  // list's own Ticked items must be one of.
  static const Set<String> tickedItemsWires = {
    'moveToDone',
    'stayInPlace',
    'hide',
    'clearAtOnce',
  };

  // The wire value of its own Ticked items choice, or null to follow.
  String? get ownTickedItems {
    final Object? value = extra[ownTickedItemsKey];
    return value is String ? value : null;
  }

  // Its own reminder lead wire values, or null to follow.
  List<String>? get ownReminderLeads {
    final Object? value = extra[ownReminderLeadsKey];
    return value is List ? List.unmodifiable(value.whereType<String>()) : null;
  }

  // Its own Confirm before deleting, or null to follow.
  bool? get ownConfirmDelete {
    final Object? value = extra[ownConfirmDeleteKey];
    return value is bool ? value : null;
  }

  FieldDefinition? fieldWithRole(FieldRole role) {
    for (final FieldDefinition field in fields) {
      if (field.role == role) {
        return field;
      }
    }

    return null;
  }

  ListDefinition copyWith({
    String? id,
    List<FieldDefinition>? fields,
    DateTime? updatedAt,
  }) {
    return ListDefinition(
      formatVersion: formatVersion,
      id: id ?? this.id,
      name: name,
      nameKey: nameKey,
      description: description,
      descriptionKey: descriptionKey,
      icon: icon,
      color: color,
      templateId: templateId,
      schemaRevision: schemaRevision,
      fields: fields ?? this.fields,
      view: view,
      behaviors: behaviors,
      aiAllowed: aiAllowed,
      updatedAt: updatedAt ?? this.updatedAt,
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ...extra,
      'formatVersion': formatVersion,
      'id': id,
      if (name != null) 'name': name,
      if (nameKey != null) 'nameKey': nameKey,
      if (description != null) 'description': description,
      if (descriptionKey != null || templateDescriptionKeys.containsKey(templateId))
        'descriptionKey': descriptionKey,
      'icon': icon,
      'color': color,
      'templateId': templateId,
      'schemaRevision': schemaRevision,
      'fields': fields.map((field) => field.toJson()).toList(),
      'view': view.toJson(),
      'behaviors': behaviors.map((behavior) => behavior.toJson()).toList(),
      'aiAllowed': aiAllowed,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ListDefinition.fromJson(Object? json) {
    final Map<String, dynamic> map = _asMap(json, 'list definition');
    const String where = 'list definition';
    final Object? rawUpdatedAt = map['updatedAt'];
    final DateTime? updatedAt =
        rawUpdatedAt is String ? DateTime.tryParse(rawUpdatedAt) : null;

    if (updatedAt == null) {
      throw const FormatException('list definition: updatedAt must be an ISO date');
    }

    return ListDefinition(
      formatVersion: _optionalInt(map, 'formatVersion', where) ?? 1,
      id: _requireString(map, 'id', where),
      name: _optionalString(map, 'name', where),
      nameKey: _optionalString(map, 'nameKey', where),
      description: _optionalString(map, 'description', where),
      descriptionKey: map.containsKey('descriptionKey') || map.containsKey('description')
          ? _optionalString(map, 'descriptionKey', where)
          : templateDescriptionKeys[map['templateId']],
      icon: _requireString(map, 'icon', where),
      color: _requireString(map, 'color', where),
      templateId: _optionalString(map, 'templateId', where),
      schemaRevision: _optionalInt(map, 'schemaRevision', where) ?? 1,
      fields: _requireList(map, 'fields', where)
          .map(FieldDefinition.fromJson)
          .toList(),
      view: ViewDefinition.fromJson(map['view']),
      behaviors: _optionalList(map, 'behaviors', where)
          .map(BehaviorDefinition.fromJson)
          .toList(),
      aiAllowed: _optionalBool(map, 'aiAllowed', where) ?? true,
      updatedAt: updatedAt,
      extra: {
        for (final MapEntry<String, dynamic> entry in map.entries)
          if (!_knownKeys.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  // Problems that make this definition unusable; empty when it is valid.
  List<ListError> validate() {
    final List<ListError> errors = [];
    final Set<String> keys = {};

    if (formatVersion > currentFormatVersion) {
      errors.add(ListError(ListErrorCode.formatTooNew, {'version': '$formatVersion'}));
    }

    if (id.trim().isEmpty) {
      errors.add(const ListError(ListErrorCode.emptyId));
    }

    if ((name == null || name!.trim().isEmpty) && nameKey == null) {
      errors.add(const ListError(ListErrorCode.missingName));
    }

    if (description != null && description!.runes.length > descriptionMaxLength) {
      errors.add(ListError(
        ListErrorCode.descriptionTooLong,
        {'max': '$descriptionMaxLength'},
      ));
    }

    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) {
      errors.add(const ListError(ListErrorCode.badColor));
    }

    if (fields.isEmpty) {
      errors.add(const ListError(ListErrorCode.noFields));
    }

    for (final FieldDefinition field in fields) {
      void fieldError(ListErrorCode code, [Map<String, String> args = const {}]) {
        errors.add(ListError(code, {'field': field.key, ...args}));
      }

      if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(field.key)) {
        fieldError(ListErrorCode.badFieldKey);
      }

      if (itemMetaFields.contains(field.key)) {
        fieldError(ListErrorCode.reservedFieldKey);
      }

      if (!keys.add(field.key)) {
        fieldError(ListErrorCode.duplicateFieldKey);
      }

      if (field.label == null && field.labelKey == null) {
        fieldError(ListErrorCode.missingFieldLabel);
      }

      if (field.type.needsOptions && field.options.isEmpty) {
        fieldError(ListErrorCode.missingOptions);
      }

      if (field.options.isNotEmpty &&
          !field.type.needsOptions &&
          !field.type.hasUserOptions) {
        fieldError(ListErrorCode.optionsNotAllowed, {'type': field.type.wire});
      }

      final Set<String> optionValues = {};
      for (final FieldOption option in field.options) {
        if (!optionValues.add(option.value)) {
          fieldError(ListErrorCode.duplicateOption, {'option': option.value});
        }
      }

      if (field.type == FieldType.choice &&
          field.defaultValue != null &&
          !field.hasOption(field.defaultValue)) {
        fieldError(ListErrorCode.defaultNotOption);
      }

      if (field.min != null && field.max != null && field.min! > field.max!) {
        fieldError(ListErrorCode.minAboveMax);
      }

      final FieldCondition? condition = field.visibleWhen;
      if (condition != null) {
        final FieldDefinition? target = this.field(condition.field);
        if (target == null || target.type != FieldType.choice) {
          fieldError(ListErrorCode.conditionNotChoice);
        } else if (condition.field == field.key) {
          fieldError(ListErrorCode.conditionOnItself);
        } else {
          for (final String value in condition.values) {
            if (!target.hasOption(value)) {
              fieldError(
                ListErrorCode.conditionNotOption,
                {'value': value, 'target': target.key},
              );
            }
          }
        }
      }

      final Set<FieldType> roleTypes = roleFieldTypes(field.role);
      if (roleTypes.isNotEmpty && !roleTypes.contains(field.type)) {
        fieldError(
          ListErrorCode.roleNeedsType,
          {'role': field.role!.wire, 'type': _typeWires(roleTypes)},
        );
      }
    }

    final List<FieldDefinition> primaries =
        fields.where((field) => field.primary).toList();
    if (primaries.length != 1) {
      errors.add(const ListError(ListErrorCode.primaryCount));
    } else if (primaries.single.type != FieldType.text) {
      errors.add(const ListError(ListErrorCode.primaryNotText));
    }

    for (final FieldRole role in FieldRole.values) {
      if (fields.where((field) => field.role == role).length > 1) {
        errors.add(ListError(ListErrorCode.duplicateRole, {'role': role.wire}));
      }
    }

    errors.addAll(_viewErrors());

    for (final BehaviorDefinition behavior in behaviors) {
      errors.addAll(_behaviorErrors(behavior));
    }

    return errors;
  }

  // The field types a role fits; empty for no role. A reminder rings on a
  // date (in the morning) or a date and time (T-13, Q-96).
  static Set<FieldType> roleFieldTypes(FieldRole? role) {
    switch (role) {
      case null:
        return const {};
      case FieldRole.completion:
        return const {FieldType.checkbox};
      case FieldRole.reminder:
        return const {FieldType.date, FieldType.dateTime};
      case FieldRole.status:
      case FieldRole.section:
        return const {FieldType.choice};
      case FieldRole.category:
        return const {FieldType.category};
    }
  }

  List<ListError> _viewErrors() {
    final List<ListError> errors = [];

    void expectField(String? key, String param, Set<FieldType> types) {
      if (key == null) {
        errors.add(ListError(
          ListErrorCode.viewNeedsParam,
          {'view': view.kind.wire, 'param': param},
        ));
        return;
      }

      final FieldDefinition? target = field(key);
      if (target == null) {
        errors.add(ListError(
          ListErrorCode.viewParamNotField,
          {'param': param, 'field': key},
        ));
      } else if (!types.contains(target.type)) {
        errors.add(ListError(
          ListErrorCode.viewParamWrongType,
          {'param': param, 'field': key, 'types': _typeWires(types)},
        ));
      }
    }

    switch (view.kind) {
      case ViewKind.checklist:
        if (fieldWithRole(FieldRole.completion) == null) {
          errors.add(const ListError(ListErrorCode.checklistNeedsCompletion));
        }
      case ViewKind.sectioned:
        expectField(view.sectionBy, 'sectionBy', {FieldType.choice});
      case ViewKind.grouped:
        expectField(
          view.groupBy,
          'groupBy',
          {FieldType.choice, FieldType.category},
        );
      case ViewKind.timeline:
        final String? dateField = view.dateField;
        if (dateField == null || !itemMetaFields.contains(dateField)) {
          expectField(
            dateField,
            'dateField',
            {FieldType.date, FieldType.dateTime},
          );
        }
      case ViewKind.table:
      case ViewKind.cards:
        break;
    }

    if (view.filterChipsBy != null) {
      expectField(
        view.filterChipsBy,
        'filterChipsBy',
        {FieldType.choice, FieldType.category, FieldType.tags},
      );
    }

    if (view.bucketBy != null) {
      expectField(
        view.bucketBy,
        'bucketBy',
        {FieldType.date, FieldType.dateTime},
      );
    }

    return errors;
  }

  List<ListError> _behaviorErrors(BehaviorDefinition behavior) {
    final List<ListError> errors = [];

    void ruleError(ListErrorCode code, [Map<String, String> args = const {}]) {
      errors.add(ListError(code, {'rule': behavior.kind.wire, ...args}));
    }

    FieldDefinition? expectField(String param, Set<FieldType> types) {
      final String? key = behavior.stringParam(param);
      if (key == null) {
        ruleError(ListErrorCode.ruleNeedsParam, {'param': param});
        return null;
      }

      final FieldDefinition? target = field(key);
      if (target == null) {
        ruleError(ListErrorCode.ruleParamNotField, {'param': param, 'field': key});
        return null;
      }

      if (!types.contains(target.type)) {
        ruleError(
          ListErrorCode.ruleParamWrongType,
          {'param': param, 'field': key, 'types': _typeWires(types)},
        );
        return null;
      }

      return target;
    }

    void expectValues(Map<String, dynamic> values, String param) {
      for (final MapEntry<String, dynamic> entry in values.entries) {
        final FieldDefinition? target = field(entry.key);
        if (target == null) {
          ruleError(
            ListErrorCode.ruleUnknownField,
            {'param': param, 'field': entry.key},
          );
        } else if (target.type == FieldType.choice &&
            !target.hasOption(entry.value)) {
          ruleError(
            ListErrorCode.ruleValueNotOption,
            {'param': param, 'value': '${entry.value}', 'field': entry.key},
          );
        }
      }
    }

    // Every rule except moveAll acts when completed items are cleared.
    if (behavior.kind != BehaviorKind.moveAll &&
        fieldWithRole(FieldRole.completion) == null) {
      ruleError(ListErrorCode.ruleNeedsCompletion);
    }

    switch (behavior.kind) {
      case BehaviorKind.recurOnClear:
        expectField('dateField', {FieldType.date, FieldType.dateTime});
        expectField('recurrenceField', {FieldType.recurrence});
      case BehaviorKind.copyOnClear:
        expectField('when', {FieldType.toggle, FieldType.checkbox});
        expectValues(behavior.mapParam('where'), 'where');
        final Map<String, dynamic> setField = behavior.mapParam('setField');
        if (setField.isEmpty) {
          ruleError(ListErrorCode.ruleNeedsParam, {'param': 'setField'});
        }
        expectValues(setField, 'setField');
        if (behavior.params['dedupeBy'] != null) {
          expectField('dedupeBy', {FieldType.text});
        }
      case BehaviorKind.moveAll:
        final FieldDefinition? target = expectField('field', {FieldType.choice});
        if (target != null) {
          for (final String param in ['from', 'to']) {
            if (!target.hasOption(behavior.params[param])) {
              ruleError(
                ListErrorCode.ruleParamNotOption,
                {'param': param, 'field': target.key},
              );
            }
          }
        }
      case BehaviorKind.clearCompleted:
        break;
    }

    return errors;
  }

  static String _typeWires(Set<FieldType> types) {
    return types.map((type) => type.wire).join('|');
  }
}

Map<String, dynamic> _asMap(Object? json, String what) {
  if (json is Map) {
    return Map<String, dynamic>.from(json);
  }

  throw FormatException('$what must be a JSON object');
}

String _requireString(Map<String, dynamic> map, String key, String where) {
  final Object? value = map[key];
  if (value is String) {
    return value;
  }

  throw FormatException('$where: "$key" must be a string');
}

String? _optionalString(Map<String, dynamic> map, String key, String where) {
  final Object? value = map[key];
  if (value == null || value is String) {
    return value as String?;
  }

  throw FormatException('$where: "$key" must be a string');
}

bool? _optionalBool(Map<String, dynamic> map, String key, String where) {
  final Object? value = map[key];
  if (value == null || value is bool) {
    return value as bool?;
  }

  throw FormatException('$where: "$key" must be true or false');
}

int? _optionalInt(Map<String, dynamic> map, String key, String where) {
  final Object? value = map[key];
  if (value == null || value is int) {
    return value as int?;
  }

  throw FormatException('$where: "$key" must be a whole number');
}

num? _optionalNum(Map<String, dynamic> map, String key, String where) {
  final Object? value = map[key];
  if (value == null || value is num) {
    return value as num?;
  }

  throw FormatException('$where: "$key" must be a number');
}

List<dynamic> _requireList(Map<String, dynamic> map, String key, String where) {
  final Object? value = map[key];
  if (value is List) {
    return value;
  }

  throw FormatException('$where: "$key" must be a list');
}

List<dynamic> _optionalList(Map<String, dynamic> map, String key, String where) {
  return map[key] == null ? const [] : _requireList(map, key, where);
}

T _requireWire<T extends WireName>(List<T> values, Object? wire, String where) {
  final T? value = enumFromWire(values, wire);
  if (value != null) {
    return value;
  }

  final String allowed = values.map((value) => value.wire).join(', ');
  throw FormatException('$where: "$wire" is not one of $allowed');
}
