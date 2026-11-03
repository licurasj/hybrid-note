// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Hybrid Note App';

  @override
  String get home => 'Home';

  @override
  String get tasks => 'Tasks';

  @override
  String get grocery => 'Grocery';

  @override
  String get journal => 'Journal';

  @override
  String get watchRead => 'Watch/Read';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System Default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get languageJapanese => '日本語';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageSpanish => 'Español';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get chooseLanguage => 'Choose Language';

  @override
  String get languageFollowsDevice => 'Use device language';

  @override
  String get switchToDarkMode => 'Switch to dark mode';

  @override
  String get switchToLightMode => 'Switch to light mode';

  @override
  String get pendingTasks => 'Pending Tasks';

  @override
  String get completedTasks => 'Completed Tasks';

  @override
  String get journalEntries => 'Journal Entries';

  @override
  String get watchReadItems => 'Watch/Read Items';

  @override
  String get groceryItems => 'Grocery Items';

  @override
  String get googleDriveSync => 'Google Drive Sync';

  @override
  String get syncing => 'Syncing...';

  @override
  String get notSyncedYet => 'Not synced yet.';

  @override
  String lastSynced(String date) {
    return 'Last synced: $date';
  }

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get logOut => 'Log out';

  @override
  String get syncToGoogleDrive => 'Sync to Google Drive';

  @override
  String get categories => 'Categories';

  @override
  String get allMyTasks => 'All My Tasks';

  @override
  String get createCategory => 'Create Category';

  @override
  String get createCategoryTooltip => 'Create category';

  @override
  String get closeCategories => 'Close categories';

  @override
  String get deleteCategory => 'Delete category';

  @override
  String get category => 'Category';

  @override
  String get categoryName => 'Category name';

  @override
  String get create => 'Create';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get clear => 'Clear';

  @override
  String get clearTicked => 'Clear Ticked';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get addTask => 'Add Task';

  @override
  String get addTaskTooltip => 'Add task';

  @override
  String get editTask => 'Edit Task';

  @override
  String get titleRequired => 'Title *';

  @override
  String get title => 'Title';

  @override
  String get notes => 'Notes';

  @override
  String get setReminder => 'Set reminder';

  @override
  String get date => 'Date';

  @override
  String get time => 'Time';

  @override
  String get repeat => 'Repeat';

  @override
  String get doesNotRepeat => 'Does not repeat';

  @override
  String get daily => 'Daily';

  @override
  String get weekly => 'Weekly';

  @override
  String get monthly => 'Monthly';

  @override
  String get yearly => 'Yearly';

  @override
  String get custom => 'Custom';

  @override
  String get repeatEveryHowManyDays => 'Repeat every how many days?';

  @override
  String reminderText(String date) {
    return 'Reminder: $date';
  }

  @override
  String get today => 'Today';

  @override
  String get tomorrow => 'Tomorrow';

  @override
  String get later => 'Later';

  @override
  String get noTasksHereYet => 'No tasks here yet.';

  @override
  String tickedCount(int count) {
    return '$count ticked';
  }

  @override
  String get addSubtask => 'Add subtask';

  @override
  String get editSubtask => 'Edit Subtask';

  @override
  String get subtaskTitleRequired => 'Subtask title *';

  @override
  String get subtasks => 'Subtasks';

  @override
  String get noSubtasksYet => 'No subtasks yet.';

  @override
  String subtaskProgress(int completed, int total) {
    return 'Subtasks: $completed/$total';
  }

  @override
  String repeats(String date, String repeat) {
    return '$date • repeats $repeat';
  }

  @override
  String repeatsEveryDays(String date, int days) {
    return '$date • repeats every $days day(s)';
  }

  @override
  String get groceryList => 'Grocery List';

  @override
  String get addGroceryItem => 'Add Grocery Item';

  @override
  String get addGroceryItemTooltip => 'Add grocery item';

  @override
  String get editGroceryItem => 'Edit Grocery Item';

  @override
  String get description => 'Description';

  @override
  String get section => 'Section';

  @override
  String get currentGroceryRun => 'Current Grocery Run';

  @override
  String get nextTime => 'Next Time';

  @override
  String get addAgainNextTime => 'Add again to Next Time when completed';

  @override
  String get addAgainNextTimeDescription =>
      'The item will appear in Next Time after you clear/delete it from Current Grocery Run.';

  @override
  String get noGroceriesCurrent => 'No groceries for this run yet.';

  @override
  String get noGroceriesNext => 'No saved groceries for next time yet.';

  @override
  String get moveToCurrentRun => 'Move to current run';

  @override
  String get moveToNextTime => 'Move to next time';

  @override
  String get repeatsToNextTime => 'Repeats to Next Time after clearing';

  @override
  String get addJournalEntry => 'Add Journal Entry';

  @override
  String get addJournalEntryTooltip => 'Add journal entry';

  @override
  String get editJournalEntry => 'Edit Journal Entry';

  @override
  String get entry => 'Entry';

  @override
  String get close => 'Close';

  @override
  String get noJournalEntriesYet => 'No journal entries yet.';

  @override
  String get watchReadList => 'Watch/Read List';

  @override
  String get addWatchReadItem => 'Add Watch/Read Item';

  @override
  String get addWatchReadItemTooltip => 'Add watch/read item';

  @override
  String get editWatchReadItem => 'Edit Watch/Read Item';

  @override
  String get type => 'Type';

  @override
  String get status => 'Status';

  @override
  String get movie => 'Movie';

  @override
  String get tvShow => 'TV Show';

  @override
  String get book => 'Book';

  @override
  String get planned => 'Planned';

  @override
  String get inProgress => 'In Progress';

  @override
  String get completed => 'Completed';

  @override
  String get season => 'Season';

  @override
  String get episode => 'Episode';

  @override
  String seasonNumber(int number) {
    return 'Season $number';
  }

  @override
  String episodeNumber(int number) {
    return 'Episode $number';
  }

  @override
  String get noWatchReadItemsYet => 'No watch/read items yet.';

  @override
  String get editList => 'Edit list';

  @override
  String get newList => 'New list';

  @override
  String get untitledList => 'Untitled list';

  @override
  String get listName => 'List name';

  @override
  String get listIcon => 'Icon';

  @override
  String get listColor => 'Color';

  @override
  String get fields => 'Fields';

  @override
  String get addField => 'Add field';

  @override
  String get fieldName => 'Field name';

  @override
  String get fieldType => 'Field type';

  @override
  String get required => 'Required';

  @override
  String get options => 'Options';

  @override
  String get addOption => 'Add option';

  @override
  String get layout => 'Layout';

  @override
  String get groupBy => 'Group by';

  @override
  String get sectionBy => 'Sections by';

  @override
  String get dateField => 'Date field';

  @override
  String get splitByDate => 'Today / Tomorrow / Later by';

  @override
  String get filterBy => 'Filter chips by';

  @override
  String get none => 'None';

  @override
  String get dateCreated => 'Date created';

  @override
  String get rules => 'Rules';

  @override
  String get ruleClearCompleted => 'Clear completed items';

  @override
  String get ruleRecurOnClear => 'Repeat when cleared';

  @override
  String get ruleCopyOnClear => 'Copy when cleared';

  @override
  String get ruleMoveAll => 'Move all button';

  @override
  String get allowAi => 'AI may read this list';

  @override
  String get deleteList => 'Delete list';

  @override
  String get listDeleted => 'List deleted';

  @override
  String get undo => 'Undo';

  @override
  String get builtinListNote =>
      'Built-in lists keep their fields until sync moves to Firestore. You can change the name, icon and color.';

  @override
  String get localOnlyNote =>
      'New lists are saved on this device only until sync moves to Firestore.';

  @override
  String get typeText => 'Text';

  @override
  String get typeLongText => 'Long text';

  @override
  String get typeCheckbox => 'Checkbox';

  @override
  String get typeToggle => 'Switch';

  @override
  String get typeNumber => 'Number';

  @override
  String get typeCounter => 'Counter';

  @override
  String get typeRating => 'Rating';

  @override
  String get typeDateTime => 'Date and time';

  @override
  String get typeChoice => 'Choice';

  @override
  String get typeTags => 'Tags';

  @override
  String get typeUrl => 'Link';

  @override
  String get typeChecklist => 'Sub-items';

  @override
  String get viewChecklist => 'Checklist';

  @override
  String get viewSectioned => 'Sections';

  @override
  String get viewTimeline => 'Timeline';

  @override
  String get viewGrouped => 'Groups';

  @override
  String get viewTable => 'Table';

  @override
  String get viewCards => 'Cards';

  @override
  String get launcherHub => 'Lists';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get launcherNoteHint => 'Double-tap to open, long-press to edit';

  @override
  String hiddenValuesWarning(int count) {
    return '$count values do not fit the new type and will be kept hidden';
  }

  @override
  String itemsCount(String name, int count) {
    return '$name, $count items';
  }

  @override
  String get moveHub => 'Move';

  @override
  String errorFormatTooNew(String version) {
    return 'This list comes from a newer version of the app (format $version).';
  }

  @override
  String get errorEmptyId => 'The list has no ID.';

  @override
  String get errorMissingName => 'The list needs a name.';

  @override
  String get errorBadColor => 'The color must look like #RRGGBB.';

  @override
  String get errorNoFields => 'The list needs at least one field.';

  @override
  String get errorPrimaryCount => 'Exactly one field must be the main field.';

  @override
  String get errorPrimaryNotText => 'The main field must be a text field.';

  @override
  String errorDuplicateRole(String role) {
    return 'Only one field can have the role $role.';
  }

  @override
  String errorBadFieldKey(String field) {
    return 'Field key \"$field\" must start with a letter and use only letters, digits or _.';
  }

  @override
  String errorReservedFieldKey(String field) {
    return 'Field key \"$field\" is reserved.';
  }

  @override
  String errorDuplicateFieldKey(String field) {
    return 'Two fields use the key \"$field\".';
  }

  @override
  String errorMissingFieldLabel(String field) {
    return 'Field \"$field\" needs a name.';
  }

  @override
  String errorMissingOptions(String field) {
    return 'Field \"$field\" needs at least one option.';
  }

  @override
  String errorOptionsNotAllowed(String field, String type) {
    return 'Field \"$field\": $type fields cannot have options.';
  }

  @override
  String errorDuplicateOption(String field, String option) {
    return 'Field \"$field\": the option \"$option\" appears twice.';
  }

  @override
  String errorDefaultNotOption(String field) {
    return 'Field \"$field\": the default value is not one of the options.';
  }

  @override
  String errorMinAboveMax(String field) {
    return 'Field \"$field\": the minimum is greater than the maximum.';
  }

  @override
  String errorConditionNotChoice(String field) {
    return 'Field \"$field\" can only depend on a choice field.';
  }

  @override
  String errorConditionOnItself(String field) {
    return 'Field \"$field\" cannot depend on itself.';
  }

  @override
  String errorConditionNotOption(String field, String value, String target) {
    return 'Field \"$field\": \"$value\" is not an option of \"$target\".';
  }

  @override
  String errorRoleNeedsType(String field, String role, String type) {
    return 'Field \"$field\": the role $role needs the type $type.';
  }

  @override
  String errorViewNeedsParam(String view, String param) {
    return 'The $view layout needs a field for \"$param\".';
  }

  @override
  String errorViewParamNotField(String param, String field) {
    return '\"$param\": \"$field\" is not a field of this list.';
  }

  @override
  String errorViewParamWrongType(String param, String field, String types) {
    return '\"$param\": \"$field\" must be of type $types.';
  }

  @override
  String get errorChecklistNeedsCompletion =>
      'The checklist layout needs a field that marks items as done.';

  @override
  String errorRuleNeedsCompletion(String rule) {
    return 'Rule \"$rule\" needs a field that marks items as done.';
  }

  @override
  String errorRuleNeedsParam(String rule, String param) {
    return 'Rule \"$rule\": \"$param\" is missing.';
  }

  @override
  String errorRuleParamNotField(String rule, String param, String field) {
    return 'Rule \"$rule\", \"$param\": \"$field\" is not a field of this list.';
  }

  @override
  String errorRuleParamWrongType(
    String rule,
    String param,
    String field,
    String types,
  ) {
    return 'Rule \"$rule\", \"$param\": \"$field\" must be of type $types.';
  }

  @override
  String errorRuleUnknownField(String rule, String param, String field) {
    return 'Rule \"$rule\", \"$param\": there is no field \"$field\".';
  }

  @override
  String errorRuleValueNotOption(
    String rule,
    String param,
    String value,
    String field,
  ) {
    return 'Rule \"$rule\", \"$param\": \"$value\" is not an option of \"$field\".';
  }

  @override
  String errorRuleParamNotOption(String rule, String param, String field) {
    return 'Rule \"$rule\": \"$param\" must be an option of \"$field\".';
  }

  @override
  String get errorWrongList => 'This item belongs to another list.';

  @override
  String errorFieldRequired(String field) {
    return '\"$field\" is required.';
  }

  @override
  String errorWrongValueType(String field, String type) {
    return '\"$field\": the value does not fit the type $type.';
  }

  @override
  String errorValueEmpty(String field) {
    return '\"$field\" must not be empty.';
  }

  @override
  String errorBelowMin(String field, String min) {
    return '\"$field\" must be at least $min.';
  }

  @override
  String errorAboveMax(String field, String max) {
    return '\"$field\" must be at most $max.';
  }

  @override
  String errorNotAnOption(String field, String value) {
    return '\"$field\": \"$value\" is not one of the options.';
  }

  @override
  String errorBadSubItem(String field) {
    return '\"$field\": each sub-item needs a title and a done mark.';
  }

  @override
  String errorUnknownFrequency(String field, String value) {
    return '\"$field\": unknown repeat \"$value\".';
  }

  @override
  String errorCustomDaysMissing(String field) {
    return '\"$field\": a custom repeat needs a number of days above 0.';
  }

  @override
  String errorOpNoField(String field) {
    return 'There is no field \"$field\".';
  }

  @override
  String errorFieldExists(String field) {
    return 'A field with the key \"$field\" already exists.';
  }

  @override
  String errorUnknownFieldType(String type) {
    return 'Unknown field type \"$type\".';
  }

  @override
  String errorBadOp(String detail) {
    return 'A change could not be read: $detail';
  }

  @override
  String get errorListExists => 'A list with this ID already exists.';

  @override
  String get errorDuplicateItemId => 'Two items have the same ID.';

  @override
  String get errorItemIdTaken =>
      'An item\'s ID is already used by another list.';

  @override
  String get errorItemInOtherList => 'An item belongs to another list.';

  @override
  String get errorBuiltinOnlyInfo =>
      'Built-in lists can only change their name, icon, color and AI setting.';

  @override
  String get addRule => 'Add rule';

  @override
  String get ruleKind => 'Rule';

  @override
  String get ruleRepeatField => 'Repeat field';

  @override
  String get ruleMoveField => 'Field';

  @override
  String get ruleMoveFrom => 'Move from';

  @override
  String get ruleMoveTo => 'Move to';

  @override
  String get account => 'Account';

  @override
  String get blankList => 'Blank';

  @override
  String get signInFailed => 'Sign-in failed. Please try again.';

  @override
  String get signInOffline =>
      'No connection. Connect to the internet to sign in.';

  @override
  String get signOutFailed => 'Sign-out failed. Please try again.';

  @override
  String get signOutCleanupFailed =>
      'Signed out, but the lists saved on this device could not be deleted.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get listChangeNotSaved =>
      'A list change could not be saved and was undone.';

  @override
  String get starterListsFailed => 'The starter lists could not be set up.';

  @override
  String get startEmpty => 'Start empty';

  @override
  String errorMissingArg(String arg) {
    return 'A change is missing \"$arg\".';
  }

  @override
  String errorWrongArgType(String arg) {
    return 'A change has the wrong kind of value for \"$arg\".';
  }

  @override
  String errorUnknownArg(String arg) {
    return 'A change has an unknown setting \"$arg\".';
  }

  @override
  String get errorUnknownList => 'The list was not found.';

  @override
  String get errorUnknownItem => 'An item to change was not found in the list.';

  @override
  String errorUnknownField(String field) {
    return '\"$field\" is not a field of this list.';
  }

  @override
  String get errorListChanged =>
      'The list has changed since, so this cannot be undone.';

  @override
  String get errorAiNotAllowed => 'The AI may not change this list.';

  @override
  String get listFilterAll => 'All';

  @override
  String get listDoneGroup => 'Done';

  @override
  String listOpenDoneCount(int open, int done) {
    return '$open open · $done done';
  }

  @override
  String listItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get itemSheetNew => 'New item';

  @override
  String get itemSheetEdit => 'Edit item';

  @override
  String get settings => 'Settings';

  @override
  String get darkMode => 'Dark mode';

  @override
  String homeThingsToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count things today',
      one: '1 thing today',
      zero: 'Nothing due today',
    );
    return '$_temp0';
  }

  @override
  String listColorName(String name) {
    String _temp0 = intl.Intl.selectLogic(name, {
      'orange': 'Orange',
      'green': 'Green',
      'magenta': 'Magenta',
      'violet': 'Violet',
      'yellow': 'Yellow',
      'rose': 'Rose',
      'teal': 'Teal',
      'blue': 'Blue',
      'other': 'Colour',
    });
    return '$_temp0';
  }

  @override
  String listIconName(String name) {
    String _temp0 = intl.Intl.selectLogic(name, {
      'pending_actions': 'Clipboard',
      'checklist': 'Checklist',
      'shopping_cart': 'Shopping cart',
      'book': 'Book',
      'movie': 'Film',
      'local_florist': 'Flower',
      'other': 'List',
    });
    return '$_temp0';
  }

  @override
  String get aiBarHint => 'Add or change';

  @override
  String aiBarHintList(String list) {
    return 'Add to $list';
  }

  @override
  String get aiBarHintNewList => 'Describe the list';

  @override
  String get aiSend => 'Send';

  @override
  String get aiBarLabel => 'AI request';

  @override
  String get aiDescribeNewList => 'Describe a new list';

  @override
  String get aiDescribeNewListMeta => 'The AI picks its fields';

  @override
  String get aiNoticeTitle => 'Before your first request';

  @override
  String get aiNoticeDeepSeek =>
      'Your request, the names and fields of your lists, and the open list with up to 20 recent items go to DeepSeek, an AI provider that processes and stores data in China. Lists with AI turned off are never sent. Your request text is kept for about 7 days to find problems, then deleted.';

  @override
  String get aiNoticeContinue => 'Continue';

  @override
  String get aiApply => 'Apply';

  @override
  String aiAddItems(String list, String items) {
    return '$list: add $items';
  }

  @override
  String aiEditItems(String list, String items) {
    return '$list: change $items';
  }

  @override
  String aiDeleteItems(String list, String items) {
    return '$list: delete $items';
  }

  @override
  String aiOpAddField(String list, String field) {
    return '$list: add the field $field';
  }

  @override
  String aiOpRemoveField(String list, String field) {
    return '$list: remove the field $field';
  }

  @override
  String aiOpRenameField(String list, String field, String label) {
    return '$list: rename $field to $label';
  }

  @override
  String aiOpChangeField(String list, String field) {
    return '$list: change the field $field';
  }

  @override
  String aiOpSetView(String list, String view) {
    return '$list: show as $view';
  }

  @override
  String aiOpBehavior(String list, String behavior) {
    return '$list: change $behavior';
  }

  @override
  String aiOpListInfo(String list) {
    return '$list: change the name, icon or colour';
  }

  @override
  String aiHiddenValues(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count values no longer fit and are kept hidden',
      one: '1 value no longer fits and is kept hidden',
    );
    return '$_temp0';
  }

  @override
  String aiNewList(String name, String fields) {
    return 'New list $name: $fields';
  }

  @override
  String aiDoneAdded(String lists) {
    return 'Added to $lists';
  }

  @override
  String aiDoneChanged(String lists) {
    return 'Changed $lists';
  }

  @override
  String aiDoneCreated(String list) {
    return 'Created $list';
  }

  @override
  String get aiUndone => 'Undone';

  @override
  String get aiDeclinedOffTopic => 'I can only help with your lists.';

  @override
  String get aiDeclinedNotSupported => 'That is not a change I can make.';

  @override
  String get aiRefusedAiNotAllowed => 'AI is turned off for this list.';

  @override
  String get aiRefusedOutputTooLong =>
      'The answer was too long. Try a shorter request.';

  @override
  String get aiRefusedNoValidTool =>
      'The answer could not be used. Try other words.';

  @override
  String get aiRefusedDailyCount =>
      'You have reached today’s limit of AI requests.';

  @override
  String get aiRefusedBudget => 'The AI is paused until tomorrow.';

  @override
  String get aiRefusedPromptTooLong => 'The request is too long.';

  @override
  String get aiRefusedContextTooLarge => 'Your lists are too large to send.';

  @override
  String get aiRefusedAccess => 'This account or app may not use the AI.';

  @override
  String get aiRefusedUnavailable =>
      'The AI is not available right now. Try again later.';

  @override
  String get aiRefusedBadRequest => 'The request could not be sent.';

  @override
  String get aiInvalidAnswer =>
      'The changes do not fit the list, so nothing was applied.';

  @override
  String get errorUndoTooLarge =>
      'This change touched too many items to be undone.';

  @override
  String get aiPartlyNotDone => 'Part of the request could not be done.';

  @override
  String get aiRefusedProviderAccount =>
      'The AI provider account needs attention: check its key or balance.';
}
