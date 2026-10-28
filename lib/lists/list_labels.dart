import '../l10n/generated/app_localizations.dart';
import 'list_definition.dart';
import 'list_error.dart';
import 'list_vocabulary.dart';

// Turns the l10n keys used by built-in definitions into translated text. The
// generated AppLocalizations only has one getter per key, so the keys the
// built-ins use are listed here; a test checks none is missing.
class ListLabels {
  const ListLabels(this.loc);

  final AppLocalizations loc;

  String? lookup(String key) {
    switch (key) {
      case 'tasks':
        return loc.tasks;
      case 'grocery':
        return loc.grocery;
      case 'journal':
        return loc.journal;
      case 'watchRead':
        return loc.watchRead;
      case 'title':
        return loc.title;
      case 'description':
        return loc.description;
      case 'notes':
        return loc.notes;
      case 'entry':
        return loc.entry;
      case 'completed':
        return loc.completed;
      case 'category':
        return loc.category;
      case 'subtasks':
        return loc.subtasks;
      case 'date':
        return loc.date;
      case 'repeat':
        return loc.repeat;
      case 'section':
        return loc.section;
      case 'currentGroceryRun':
        return loc.currentGroceryRun;
      case 'nextTime':
        return loc.nextTime;
      case 'repeatsToNextTime':
        return loc.repeatsToNextTime;
      case 'type':
        return loc.type;
      case 'status':
        return loc.status;
      case 'movie':
        return loc.movie;
      case 'tvShow':
        return loc.tvShow;
      case 'book':
        return loc.book;
      case 'planned':
        return loc.planned;
      case 'inProgress':
        return loc.inProgress;
      case 'season':
        return loc.season;
      case 'episode':
        return loc.episode;
    }

    return null;
  }

  // Literal label first (user and AI lists), then the l10n key, then the
  // fallback so an unknown key still shows something readable.
  String resolve(String? label, String? labelKey, String fallback) {
    if (label != null && label.isNotEmpty) {
      return label;
    }

    if (labelKey != null) {
      return lookup(labelKey) ?? labelKey;
    }

    return fallback;
  }

  String listName(ListDefinition definition) {
    return resolve(definition.name, definition.nameKey, definition.id);
  }

  String field(FieldDefinition field) {
    return resolve(field.label, field.labelKey, field.key);
  }

  String option(FieldOption option) {
    return resolve(option.label, option.labelKey, option.value);
  }

  String fieldType(FieldType type) {
    switch (type) {
      case FieldType.text:
        return loc.typeText;
      case FieldType.longText:
        return loc.typeLongText;
      case FieldType.checkbox:
        return loc.typeCheckbox;
      case FieldType.toggle:
        return loc.typeToggle;
      case FieldType.number:
        return loc.typeNumber;
      case FieldType.counter:
        return loc.typeCounter;
      case FieldType.rating:
        return loc.typeRating;
      case FieldType.date:
        return loc.date;
      case FieldType.dateTime:
        return loc.typeDateTime;
      case FieldType.choice:
        return loc.typeChoice;
      case FieldType.category:
        return loc.category;
      case FieldType.tags:
        return loc.typeTags;
      case FieldType.url:
        return loc.typeUrl;
      case FieldType.checklist:
        return loc.typeChecklist;
      case FieldType.recurrence:
        return loc.repeat;
    }
  }

  String viewKind(ViewKind kind) {
    switch (kind) {
      case ViewKind.checklist:
        return loc.viewChecklist;
      case ViewKind.sectioned:
        return loc.viewSectioned;
      case ViewKind.timeline:
        return loc.viewTimeline;
      case ViewKind.grouped:
        return loc.viewGrouped;
      case ViewKind.table:
        return loc.viewTable;
      case ViewKind.cards:
        return loc.viewCards;
    }
  }

  String behavior(BehaviorKind kind) {
    switch (kind) {
      case BehaviorKind.recurOnClear:
        return loc.ruleRecurOnClear;
      case BehaviorKind.copyOnClear:
        return loc.ruleCopyOnClear;
      case BehaviorKind.moveAll:
        return loc.ruleMoveAll;
      case BehaviorKind.clearCompleted:
        return loc.ruleClearCompleted;
    }
  }

  String recurrence(RecurrenceFrequency frequency) {
    switch (frequency) {
      case RecurrenceFrequency.none:
        return loc.doesNotRepeat;
      case RecurrenceFrequency.daily:
        return loc.daily;
      case RecurrenceFrequency.weekly:
        return loc.weekly;
      case RecurrenceFrequency.monthly:
        return loc.monthly;
      case RecurrenceFrequency.yearly:
        return loc.yearly;
      case RecurrenceFrequency.custom:
        return loc.custom;
    }
  }

  // A validation error in the user's language (Q-14 A). Field keys are shown
  // by their label when `definition` has the field; ids are left out, and
  // wire names without a label (roles, copyOnClear's parameters) stay as they are.
  String error(ListError error, [ListDefinition? definition]) {
    String fieldName(String key) {
      final FieldDefinition? found = definition?.field(key);
      return found == null ? key : field(found);
    }

    String typeName(String wire) {
      final FieldType? type = enumFromWire(FieldType.values, wire);
      return type == null ? wire : fieldType(type);
    }

    final String key = error.arg('field');
    final String name = fieldName(key);
    final String param = _param(error.arg('param'));
    final String type = typeName(error.arg('type'));
    final String types = error.types.map(typeName).join(' / ');
    final BehaviorKind? ruleKind = enumFromWire(BehaviorKind.values, error.arg('rule'));
    final String rule = ruleKind == null ? error.arg('rule') : behavior(ruleKind);
    final ViewKind? view = enumFromWire(ViewKind.values, error.arg('view'));

    switch (error.code) {
      case ListErrorCode.formatTooNew:
        return loc.errorFormatTooNew(error.arg('version'));
      case ListErrorCode.emptyId:
        return loc.errorEmptyId;
      case ListErrorCode.missingName:
        return loc.errorMissingName;
      case ListErrorCode.badColor:
        return loc.errorBadColor;
      case ListErrorCode.noFields:
        return loc.errorNoFields;
      case ListErrorCode.primaryCount:
        return loc.errorPrimaryCount;
      case ListErrorCode.primaryNotText:
        return loc.errorPrimaryNotText;
      case ListErrorCode.duplicateRole:
        return loc.errorDuplicateRole(error.arg('role'));
      case ListErrorCode.badFieldKey:
        return loc.errorBadFieldKey(key);
      case ListErrorCode.reservedFieldKey:
        return loc.errorReservedFieldKey(key);
      case ListErrorCode.duplicateFieldKey:
        return loc.errorDuplicateFieldKey(key);
      case ListErrorCode.missingFieldLabel:
        return loc.errorMissingFieldLabel(name);
      case ListErrorCode.missingOptions:
        return loc.errorMissingOptions(name);
      case ListErrorCode.optionsNotAllowed:
        return loc.errorOptionsNotAllowed(name, type);
      case ListErrorCode.duplicateOption:
        return loc.errorDuplicateOption(name, error.arg('option'));
      case ListErrorCode.defaultNotOption:
        return loc.errorDefaultNotOption(name);
      case ListErrorCode.minAboveMax:
        return loc.errorMinAboveMax(name);
      case ListErrorCode.conditionNotChoice:
        return loc.errorConditionNotChoice(name);
      case ListErrorCode.conditionOnItself:
        return loc.errorConditionOnItself(name);
      case ListErrorCode.conditionNotOption:
        return loc.errorConditionNotOption(
          name,
          error.arg('value'),
          fieldName(error.arg('target')),
        );
      case ListErrorCode.roleNeedsType:
        return loc.errorRoleNeedsType(name, error.arg('role'), type);
      case ListErrorCode.viewNeedsParam:
        return loc.errorViewNeedsParam(
          view == null ? error.arg('view') : viewKind(view),
          param,
        );
      case ListErrorCode.viewParamNotField:
        return loc.errorViewParamNotField(param, key);
      case ListErrorCode.viewParamWrongType:
        return loc.errorViewParamWrongType(param, name, types);
      case ListErrorCode.checklistNeedsCompletion:
        return loc.errorChecklistNeedsCompletion;
      case ListErrorCode.ruleNeedsCompletion:
        return loc.errorRuleNeedsCompletion(rule);
      case ListErrorCode.ruleNeedsParam:
        return loc.errorRuleNeedsParam(rule, param);
      case ListErrorCode.ruleParamNotField:
        return loc.errorRuleParamNotField(rule, param, key);
      case ListErrorCode.ruleParamWrongType:
        return loc.errorRuleParamWrongType(rule, param, name, types);
      case ListErrorCode.ruleUnknownField:
        return loc.errorRuleUnknownField(rule, param, key);
      case ListErrorCode.ruleValueNotOption:
        return loc.errorRuleValueNotOption(rule, param, error.arg('value'), name);
      case ListErrorCode.ruleParamNotOption:
        return loc.errorRuleParamNotOption(rule, param, name);
      case ListErrorCode.wrongList:
        return loc.errorWrongList;
      case ListErrorCode.fieldRequired:
        return loc.errorFieldRequired(name);
      case ListErrorCode.wrongValueType:
        return loc.errorWrongValueType(name, type);
      case ListErrorCode.valueEmpty:
        return loc.errorValueEmpty(name);
      case ListErrorCode.belowMin:
        return loc.errorBelowMin(name, error.arg('min'));
      case ListErrorCode.aboveMax:
        return loc.errorAboveMax(name, error.arg('max'));
      case ListErrorCode.notAnOption:
        return loc.errorNotAnOption(name, error.arg('value'));
      case ListErrorCode.badSubItem:
        return loc.errorBadSubItem(name);
      case ListErrorCode.unknownFrequency:
        return loc.errorUnknownFrequency(name, error.arg('value'));
      case ListErrorCode.customDaysMissing:
        return loc.errorCustomDaysMissing(name);
      case ListErrorCode.opNoField:
        return loc.errorOpNoField(key);
      case ListErrorCode.fieldExists:
        return loc.errorFieldExists(key);
      case ListErrorCode.unknownFieldType:
        return loc.errorUnknownFieldType(error.arg('type'));
      case ListErrorCode.badOp:
        return loc.errorBadOp(error.arg('detail'));
      case ListErrorCode.listExists:
        return loc.errorListExists;
      case ListErrorCode.duplicateItemId:
        return loc.errorDuplicateItemId;
      case ListErrorCode.itemIdTaken:
        return loc.errorItemIdTaken;
      case ListErrorCode.itemInOtherList:
        return loc.errorItemInOtherList;
    }
  }

  // View and rule parameters that the editor has a label for.
  String _param(String wire) {
    switch (wire) {
      case 'sectionBy':
        return loc.sectionBy;
      case 'groupBy':
        return loc.groupBy;
      case 'dateField':
        return loc.dateField;
      case 'bucketBy':
        return loc.splitByDate;
      case 'filterChipsBy':
        return loc.filterBy;
      case 'recurrenceField':
        return loc.ruleRepeatField;
      case 'field':
        return loc.ruleMoveField;
      case 'from':
        return loc.ruleMoveFrom;
      case 'to':
        return loc.ruleMoveTo;
    }
    return wire;
  }
}
