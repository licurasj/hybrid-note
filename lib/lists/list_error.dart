import 'list_vocabulary.dart';

// One validation problem as a stable code plus its arguments (Q-14 A), so
// the screens can show it translated (ListLabels.error) while toString()
// keeps the English text the AI, logs and tests read. Arguments are plain
// strings: field keys, wire names, option values, ids and numbers; `types`
// holds field type wire names joined by '|'. The JSON Schema and AI tools
// (Block C) reuse the codes by their wire names.
enum ListErrorCode implements WireName {
  // The definition as a whole.
  formatTooNew('formatTooNew'), // {version}
  emptyId('emptyId'),
  missingName('missingName'),
  badColor('badColor'),
  noFields('noFields'),
  primaryCount('primaryCount'),
  primaryNotText('primaryNotText'),
  duplicateRole('duplicateRole'), // {role}

  // One field of the definition, all {field, ...}.
  badFieldKey('badFieldKey'),
  reservedFieldKey('reservedFieldKey'),
  duplicateFieldKey('duplicateFieldKey'),
  missingFieldLabel('missingFieldLabel'),
  missingOptions('missingOptions'),
  optionsNotAllowed('optionsNotAllowed'), // {type}
  duplicateOption('duplicateOption'), // {option}
  defaultNotOption('defaultNotOption'),
  minAboveMax('minAboveMax'),
  conditionNotChoice('conditionNotChoice'),
  conditionOnItself('conditionOnItself'),
  conditionNotOption('conditionNotOption'), // {value, target}
  roleNeedsType('roleNeedsType'), // {role, type}

  // The view.
  viewNeedsParam('viewNeedsParam'), // {view, param}
  viewParamNotField('viewParamNotField'), // {param, field}
  viewParamWrongType('viewParamWrongType'), // {param, field, types}
  checklistNeedsCompletion('checklistNeedsCompletion'),

  // One rule, all {rule, ...}.
  ruleNeedsCompletion('ruleNeedsCompletion'),
  ruleNeedsParam('ruleNeedsParam'), // {param}
  ruleParamNotField('ruleParamNotField'), // {param, field}
  ruleParamWrongType('ruleParamWrongType'), // {param, field, types}
  ruleUnknownField('ruleUnknownField'), // {param, field}
  ruleValueNotOption('ruleValueNotOption'), // {param, value, field}
  ruleParamNotOption('ruleParamNotOption'), // {param, field}

  // An item's values, all {field, ...} except wrongList.
  wrongList('wrongList'), // {list, expected}
  fieldRequired('fieldRequired'),
  wrongValueType('wrongValueType'), // {type}
  valueEmpty('valueEmpty'),
  belowMin('belowMin'), // {min}
  aboveMax('aboveMax'), // {max}
  notAnOption('notAnOption'), // {value}
  badSubItem('badSubItem'),
  unknownFrequency('unknownFrequency'), // {value}
  customDaysMissing('customDaysMissing'),

  // Patch ops.
  opNoField('opNoField'), // {op, field}
  fieldExists('fieldExists'), // {field}
  unknownFieldType('unknownFieldType'), // {type}
  badOp('badOp'), // {op, detail}: detail is fromJson's English message

  // Store writes.
  listExists('listExists'), // {list}
  duplicateItemId('duplicateItemId'),
  itemIdTaken('itemIdTaken'),
  itemInOtherList('itemInOtherList'); // {list}

  const ListErrorCode(this.wire);

  @override
  final String wire;
}

class ListError {
  const ListError(this.code, [this.args = const {}, this.itemId]);

  final ListErrorCode code;
  final Map<String, String> args;
  // The item the problem is about, when a write carries several items.
  final String? itemId;

  ListError forItem(String id) => ListError(code, args, id);

  String arg(String name) => args[name] ?? '';

  // Field type wire names of the `types` argument.
  List<String> get types => arg('types').split('|');

  @override
  String toString() {
    final String text = _english();
    return itemId == null ? text : 'item "$itemId": $text';
  }

  String _english() {
    final String field = 'field "${arg('field')}"';
    final String rule = 'behavior ${arg('rule')}';
    final String param = arg('param');
    final String typeNames = types.join(' or ');
    switch (code) {
      case ListErrorCode.formatTooNew:
        return 'formatVersion ${arg('version')} is newer than this app supports';
      case ListErrorCode.emptyId:
        return 'id is empty';
      case ListErrorCode.missingName:
        return 'list needs a name or nameKey';
      case ListErrorCode.badColor:
        return 'color must look like #RRGGBB';
      case ListErrorCode.noFields:
        return 'list has no fields';
      case ListErrorCode.primaryCount:
        return 'exactly one field must be primary';
      case ListErrorCode.primaryNotText:
        return 'the primary field must be text';
      case ListErrorCode.duplicateRole:
        return 'more than one field has role ${arg('role')}';
      case ListErrorCode.badFieldKey:
        return '$field: key must start with a letter and use letters, digits or _';
      case ListErrorCode.reservedFieldKey:
        return '$field: key is reserved for item metadata';
      case ListErrorCode.duplicateFieldKey:
        return '$field: duplicate key';
      case ListErrorCode.missingFieldLabel:
        return '$field: needs a label or labelKey';
      case ListErrorCode.missingOptions:
        return '$field: enum field needs options';
      case ListErrorCode.optionsNotAllowed:
        return '$field: ${arg('type')} fields cannot have options';
      case ListErrorCode.duplicateOption:
        return '$field: duplicate option "${arg('option')}"';
      case ListErrorCode.defaultNotOption:
        return '$field: default is not one of the options';
      case ListErrorCode.minAboveMax:
        return '$field: min is greater than max';
      case ListErrorCode.conditionNotChoice:
        return '$field: visibleWhen must name an enum field';
      case ListErrorCode.conditionOnItself:
        return '$field: visibleWhen cannot name the field itself';
      case ListErrorCode.conditionNotOption:
        return '$field: visibleWhen "${arg('value')}" is not an option of "${arg('target')}"';
      case ListErrorCode.roleNeedsType:
        final String type = arg('type');
        final String article = type.startsWith(RegExp('[aeiou]')) ? 'an' : 'a';
        return '$field: ${arg('role')} role needs $article $type field';
      case ListErrorCode.viewNeedsParam:
        // The timeline check has always been worded the other way round.
        return arg('view') == ViewKind.timeline.wire
            ? 'timeline view needs $param'
            : 'view ${arg('view')} needs $param';
      case ListErrorCode.viewParamNotField:
        return 'view $param "${arg('field')}" is not a field';
      case ListErrorCode.viewParamWrongType:
        return 'view $param "${arg('field')}" must be $typeNames';
      case ListErrorCode.checklistNeedsCompletion:
        return 'checklist view needs a field with the completion role';
      case ListErrorCode.ruleNeedsCompletion:
        return '$rule: needs a field with the completion role';
      case ListErrorCode.ruleNeedsParam:
        return '$rule: needs $param';
      case ListErrorCode.ruleParamNotField:
        return '$rule: $param "${arg('field')}" is not a field';
      case ListErrorCode.ruleParamWrongType:
        return '$rule: $param "${arg('field')}" must be $typeNames';
      case ListErrorCode.ruleUnknownField:
        return '$rule: $param names unknown field "${arg('field')}"';
      case ListErrorCode.ruleValueNotOption:
        return '$rule: $param "${arg('value')}" is not an option of "${arg('field')}"';
      case ListErrorCode.ruleParamNotOption:
        return '$rule: $param must be an option of "${arg('field')}"';
      case ListErrorCode.wrongList:
        return 'item belongs to list "${arg('list')}", not "${arg('expected')}"';
      case ListErrorCode.fieldRequired:
        return '$field is required';
      case ListErrorCode.wrongValueType:
        return '$field: must be ${_valueShape(arg('type'))}';
      case ListErrorCode.valueEmpty:
        return '$field: must not be empty';
      case ListErrorCode.belowMin:
        return '$field: must be at least ${arg('min')}';
      case ListErrorCode.aboveMax:
        return '$field: must be at most ${arg('max')}';
      case ListErrorCode.notAnOption:
        return '$field: "${arg('value')}" is not an option';
      case ListErrorCode.badSubItem:
        return '$field: each sub-item needs id, title and done';
      case ListErrorCode.unknownFrequency:
        return '$field: unknown frequency "${arg('value')}"';
      case ListErrorCode.customDaysMissing:
        return '$field: custom frequency needs customDays above 0';
      case ListErrorCode.opNoField:
        return '${arg('op')}: no field "${arg('field')}"';
      case ListErrorCode.fieldExists:
        return 'addField: "${arg('field')}" already exists';
      case ListErrorCode.unknownFieldType:
        return 'changeFieldType: unknown type "${arg('type')}"';
      case ListErrorCode.badOp:
        return '${arg('op')}: ${arg('detail')}';
      case ListErrorCode.listExists:
        return 'list "${arg('list')}" already exists';
      case ListErrorCode.duplicateItemId:
        return 'duplicate id';
      case ListErrorCode.itemIdTaken:
        return 'id already used by another list';
      case ListErrorCode.itemInOtherList:
        return 'belongs to list "${arg('list')}"';
    }
  }

  // What a value of each field type must look like, as validateAgainst has
  // always said it.
  static String _valueShape(String typeWire) {
    switch (enumFromWire(FieldType.values, typeWire)) {
      case FieldType.checkbox:
      case FieldType.toggle:
        return 'true or false';
      case FieldType.number:
        return 'a number';
      case FieldType.counter:
      case FieldType.rating:
        return 'a whole number';
      case FieldType.date:
      case FieldType.dateTime:
        return 'an ISO date';
      case FieldType.tags:
        return 'a list of strings';
      case FieldType.checklist:
        return 'a list of sub-items';
      case FieldType.recurrence:
        return '{frequency, customDays?}';
      case FieldType.text:
      case FieldType.longText:
      case FieldType.url:
      case FieldType.category:
      case FieldType.choice:
      case null:
        return 'a string';
    }
  }
}
