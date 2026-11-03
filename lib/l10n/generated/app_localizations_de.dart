// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Hybrid Note App';

  @override
  String get home => 'Start';

  @override
  String get tasks => 'Aufgaben';

  @override
  String get grocery => 'Einkauf';

  @override
  String get journal => 'Journal';

  @override
  String get watchRead => 'Ansehen/Lesen';

  @override
  String get language => 'Sprache';

  @override
  String get languageSystem => 'Systemstandard';

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
  String get chooseLanguage => 'Sprache auswählen';

  @override
  String get languageFollowsDevice => 'Use device language';

  @override
  String get switchToDarkMode => 'In den Dunkelmodus wechseln';

  @override
  String get switchToLightMode => 'In den Hellmodus wechseln';

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
  String get syncing => 'Synchronisiere...';

  @override
  String get notSyncedYet => 'Noch nicht synchronisiert.';

  @override
  String lastSynced(String date) {
    return 'Last synced: $date';
  }

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get logOut => 'Log out';

  @override
  String get syncToGoogleDrive => 'Mit Google Drive synchronisieren';

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
  String get cancel => 'Abbrechen';

  @override
  String get save => 'Speichern';

  @override
  String get clear => 'Clear';

  @override
  String get clearTicked => 'Clear Ticked';

  @override
  String get delete => 'Löschen';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get add => 'Hinzufügen';

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
  String get addSubtask => 'Add Subtask';

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
  String get editList => 'Liste bearbeiten';

  @override
  String get newList => 'Neue Liste';

  @override
  String get untitledList => 'Unbenannte Liste';

  @override
  String get listName => 'Listenname';

  @override
  String get listIcon => 'Symbol';

  @override
  String get listColor => 'Farbe';

  @override
  String get fields => 'Felder';

  @override
  String get addField => 'Feld hinzufügen';

  @override
  String get fieldName => 'Feldname';

  @override
  String get fieldType => 'Feldtyp';

  @override
  String get required => 'Pflichtfeld';

  @override
  String get options => 'Optionen';

  @override
  String get addOption => 'Option hinzufügen';

  @override
  String get layout => 'Darstellung';

  @override
  String get groupBy => 'Gruppieren nach';

  @override
  String get sectionBy => 'Abschnitte nach';

  @override
  String get dateField => 'Datumsfeld';

  @override
  String get splitByDate => 'Heute / Morgen / Später nach';

  @override
  String get filterBy => 'Filter nach';

  @override
  String get none => 'Keine';

  @override
  String get dateCreated => 'Erstellungsdatum';

  @override
  String get rules => 'Regeln';

  @override
  String get ruleClearCompleted => 'Erledigte entfernen';

  @override
  String get ruleRecurOnClear => 'Beim Entfernen wiederholen';

  @override
  String get ruleCopyOnClear => 'Beim Entfernen kopieren';

  @override
  String get ruleMoveAll => 'Alle verschieben';

  @override
  String get allowAi => 'KI darf diese Liste lesen';

  @override
  String get deleteList => 'Liste löschen';

  @override
  String get listDeleted => 'Liste gelöscht';

  @override
  String get undo => 'Rückgängig';

  @override
  String get builtinListNote =>
      'Integrierte Listen behalten ihre Felder bis zum Umzug nach Firestore. Name, Symbol und Farbe lassen sich ändern.';

  @override
  String get localOnlyNote =>
      'Neue Listen werden bis zum Umzug nach Firestore nur auf diesem Gerät gespeichert.';

  @override
  String get typeText => 'Text';

  @override
  String get typeLongText => 'Langer Text';

  @override
  String get typeCheckbox => 'Kontrollkästchen';

  @override
  String get typeToggle => 'Schalter';

  @override
  String get typeNumber => 'Zahl';

  @override
  String get typeCounter => 'Zähler';

  @override
  String get typeRating => 'Bewertung';

  @override
  String get typeDateTime => 'Datum und Uhrzeit';

  @override
  String get typeChoice => 'Auswahl';

  @override
  String get typeTags => 'Schlagwörter';

  @override
  String get typeUrl => 'Link';

  @override
  String get typeChecklist => 'Unterpunkte';

  @override
  String get viewChecklist => 'Checkliste';

  @override
  String get viewSectioned => 'Abschnitte';

  @override
  String get viewTimeline => 'Zeitleiste';

  @override
  String get viewGrouped => 'Gruppen';

  @override
  String get viewTable => 'Tabelle';

  @override
  String get viewCards => 'Karten';

  @override
  String get launcherHub => 'Listen';

  @override
  String get previous => 'Zurück';

  @override
  String get next => 'Weiter';

  @override
  String get launcherNoteHint =>
      'Doppeltippen zum Öffnen, lange drücken zum Bearbeiten';

  @override
  String hiddenValuesWarning(int count) {
    return '$count Werte passen nicht zum neuen Typ und werden ausgeblendet aufbewahrt';
  }

  @override
  String itemsCount(String name, int count) {
    return '$name, $count Einträge';
  }

  @override
  String get moveHub => 'Verschieben';

  @override
  String errorFormatTooNew(String version) {
    return 'Diese Liste stammt aus einer neueren App-Version (Format $version).';
  }

  @override
  String get errorEmptyId => 'Die Liste hat keine ID.';

  @override
  String get errorMissingName => 'Die Liste braucht einen Namen.';

  @override
  String get errorBadColor => 'Die Farbe muss die Form #RRGGBB haben.';

  @override
  String get errorNoFields => 'Die Liste braucht mindestens ein Feld.';

  @override
  String get errorPrimaryCount => 'Genau ein Feld muss das Hauptfeld sein.';

  @override
  String get errorPrimaryNotText => 'Das Hauptfeld muss ein Textfeld sein.';

  @override
  String errorDuplicateRole(String role) {
    return 'Nur ein Feld kann die Rolle $role haben.';
  }

  @override
  String errorBadFieldKey(String field) {
    return 'Feldschlüssel „$field“ muss mit einem Buchstaben beginnen und darf nur Buchstaben, Ziffern oder _ enthalten.';
  }

  @override
  String errorReservedFieldKey(String field) {
    return 'Feldschlüssel „$field“ ist reserviert.';
  }

  @override
  String errorDuplicateFieldKey(String field) {
    return 'Zwei Felder verwenden den Schlüssel „$field“.';
  }

  @override
  String errorMissingFieldLabel(String field) {
    return 'Feld „$field“ braucht einen Namen.';
  }

  @override
  String errorMissingOptions(String field) {
    return 'Feld „$field“ braucht mindestens eine Option.';
  }

  @override
  String errorOptionsNotAllowed(String field, String type) {
    return 'Feld „$field“: Felder vom Typ $type können keine Optionen haben.';
  }

  @override
  String errorDuplicateOption(String field, String option) {
    return 'Feld „$field“: Die Option „$option“ kommt doppelt vor.';
  }

  @override
  String errorDefaultNotOption(String field) {
    return 'Feld „$field“: Der Standardwert ist keine der Optionen.';
  }

  @override
  String errorMinAboveMax(String field) {
    return 'Feld „$field“: Das Minimum ist größer als das Maximum.';
  }

  @override
  String errorConditionNotChoice(String field) {
    return 'Feld „$field“ kann nur von einem Auswahlfeld abhängen.';
  }

  @override
  String errorConditionOnItself(String field) {
    return 'Feld „$field“ kann nicht von sich selbst abhängen.';
  }

  @override
  String errorConditionNotOption(String field, String value, String target) {
    return 'Feld „$field“: „$value“ ist keine Option von „$target“.';
  }

  @override
  String errorRoleNeedsType(String field, String role, String type) {
    return 'Feld „$field“: Die Rolle $role braucht den Typ $type.';
  }

  @override
  String errorViewNeedsParam(String view, String param) {
    return 'Die Darstellung $view braucht ein Feld für „$param“.';
  }

  @override
  String errorViewParamNotField(String param, String field) {
    return '„$param“: „$field“ ist kein Feld dieser Liste.';
  }

  @override
  String errorViewParamWrongType(String param, String field, String types) {
    return '„$param“: „$field“ muss vom Typ $types sein.';
  }

  @override
  String get errorChecklistNeedsCompletion =>
      'Die Darstellung Checkliste braucht ein Feld, das Einträge als erledigt markiert.';

  @override
  String errorRuleNeedsCompletion(String rule) {
    return 'Regel „$rule“ braucht ein Feld, das Einträge als erledigt markiert.';
  }

  @override
  String errorRuleNeedsParam(String rule, String param) {
    return 'Regel „$rule“: „$param“ fehlt.';
  }

  @override
  String errorRuleParamNotField(String rule, String param, String field) {
    return 'Regel „$rule“, „$param“: „$field“ ist kein Feld dieser Liste.';
  }

  @override
  String errorRuleParamWrongType(
    String rule,
    String param,
    String field,
    String types,
  ) {
    return 'Regel „$rule“, „$param“: „$field“ muss vom Typ $types sein.';
  }

  @override
  String errorRuleUnknownField(String rule, String param, String field) {
    return 'Regel „$rule“, „$param“: Es gibt kein Feld „$field“.';
  }

  @override
  String errorRuleValueNotOption(
    String rule,
    String param,
    String value,
    String field,
  ) {
    return 'Regel „$rule“, „$param“: „$value“ ist keine Option von „$field“.';
  }

  @override
  String errorRuleParamNotOption(String rule, String param, String field) {
    return 'Regel „$rule“: „$param“ muss eine Option von „$field“ sein.';
  }

  @override
  String get errorWrongList => 'Dieser Eintrag gehört zu einer anderen Liste.';

  @override
  String errorFieldRequired(String field) {
    return '„$field“ ist ein Pflichtfeld.';
  }

  @override
  String errorWrongValueType(String field, String type) {
    return '„$field“: Der Wert passt nicht zum Typ $type.';
  }

  @override
  String errorValueEmpty(String field) {
    return '„$field“ darf nicht leer sein.';
  }

  @override
  String errorBelowMin(String field, String min) {
    return '„$field“ muss mindestens $min sein.';
  }

  @override
  String errorAboveMax(String field, String max) {
    return '„$field“ darf höchstens $max sein.';
  }

  @override
  String errorNotAnOption(String field, String value) {
    return '„$field“: „$value“ ist keine der Optionen.';
  }

  @override
  String errorBadSubItem(String field) {
    return '„$field“: Jeder Unterpunkt braucht einen Titel und einen Erledigt-Status.';
  }

  @override
  String errorUnknownFrequency(String field, String value) {
    return '„$field“: Unbekannte Wiederholung „$value“.';
  }

  @override
  String errorCustomDaysMissing(String field) {
    return '„$field“: Eine eigene Wiederholung braucht eine Anzahl Tage über 0.';
  }

  @override
  String errorOpNoField(String field) {
    return 'Es gibt kein Feld „$field“.';
  }

  @override
  String errorFieldExists(String field) {
    return 'Ein Feld mit dem Schlüssel „$field“ gibt es schon.';
  }

  @override
  String errorUnknownFieldType(String type) {
    return 'Unbekannter Feldtyp „$type“.';
  }

  @override
  String errorBadOp(String detail) {
    return 'Eine Änderung konnte nicht gelesen werden: $detail';
  }

  @override
  String get errorListExists => 'Eine Liste mit dieser ID gibt es schon.';

  @override
  String get errorDuplicateItemId => 'Zwei Einträge haben dieselbe ID.';

  @override
  String get errorItemIdTaken =>
      'Die ID eines Eintrags wird schon von einer anderen Liste verwendet.';

  @override
  String get errorItemInOtherList =>
      'Ein Eintrag gehört zu einer anderen Liste.';

  @override
  String get errorBuiltinOnlyInfo =>
      'Bei integrierten Listen lassen sich nur Name, Symbol, Farbe und KI-Einstellung ändern.';

  @override
  String get addRule => 'Regel hinzufügen';

  @override
  String get ruleKind => 'Regel';

  @override
  String get ruleRepeatField => 'Wiederholungsfeld';

  @override
  String get ruleMoveField => 'Feld';

  @override
  String get ruleMoveFrom => 'Verschieben von';

  @override
  String get ruleMoveTo => 'Verschieben nach';

  @override
  String get account => 'Konto';

  @override
  String get blankList => 'Leer';

  @override
  String get signInFailed =>
      'Anmeldung fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get signInOffline =>
      'Keine Verbindung. Zum Anmelden mit dem Internet verbinden.';

  @override
  String get signOutFailed =>
      'Abmeldung fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get signOutCleanupFailed =>
      'Abgemeldet, aber die auf diesem Gerät gespeicherten Listen konnten nicht gelöscht werden.';

  @override
  String get tryAgain => 'Erneut versuchen';

  @override
  String get listChangeNotSaved =>
      'Eine Listenänderung konnte nicht gespeichert werden und wurde rückgängig gemacht.';

  @override
  String get starterListsFailed =>
      'Die Startlisten konnten nicht eingerichtet werden.';

  @override
  String get startEmpty => 'Leer beginnen';

  @override
  String errorMissingArg(String arg) {
    return 'Einer Änderung fehlt „$arg“.';
  }

  @override
  String errorWrongArgType(String arg) {
    return 'Eine Änderung hat für „$arg“ einen Wert der falschen Art.';
  }

  @override
  String errorUnknownArg(String arg) {
    return 'Eine Änderung hat eine unbekannte Einstellung „$arg“.';
  }

  @override
  String get errorUnknownList => 'Die Liste wurde nicht gefunden.';

  @override
  String get errorUnknownItem =>
      'Ein zu ändernder Eintrag wurde in der Liste nicht gefunden.';

  @override
  String errorUnknownField(String field) {
    return '„$field“ ist kein Feld dieser Liste.';
  }

  @override
  String get errorListChanged =>
      'Die Liste hat sich inzwischen geändert, daher kann dies nicht rückgängig gemacht werden.';
}
