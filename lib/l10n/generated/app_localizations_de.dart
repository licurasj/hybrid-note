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
  String get languageFollowsDevice => 'Gerätesprache verwenden';

  @override
  String get signInWithGoogle => 'Mit Google anmelden';

  @override
  String get logOut => 'Abmelden';

  @override
  String get categories => 'Kategorien';

  @override
  String get createCategory => 'Kategorie erstellen';

  @override
  String get deleteCategory => 'Kategorie löschen';

  @override
  String get category => 'Kategorie';

  @override
  String get categoryName => 'Kategoriename';

  @override
  String get create => 'Erstellen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get save => 'Speichern';

  @override
  String get clear => 'Entfernen';

  @override
  String get clearTicked => 'Abgehakte entfernen';

  @override
  String get delete => 'Löschen';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get add => 'Hinzufügen';

  @override
  String get addTask => 'Aufgabe hinzufügen';

  @override
  String get addTaskTooltip => 'Aufgabe hinzufügen';

  @override
  String get editTask => 'Aufgabe bearbeiten';

  @override
  String get title => 'Titel';

  @override
  String get notes => 'Notizen';

  @override
  String get date => 'Datum';

  @override
  String get repeat => 'Wiederholen';

  @override
  String get doesNotRepeat => 'Keine Wiederholung';

  @override
  String get daily => 'Täglich';

  @override
  String get weekly => 'Wöchentlich';

  @override
  String get monthly => 'Monatlich';

  @override
  String get yearly => 'Jährlich';

  @override
  String get custom => 'Benutzerdefiniert';

  @override
  String get repeatEveryHowManyDays => 'Alle wie viele Tage wiederholen?';

  @override
  String reminderText(String date) {
    return 'Erinnerung: $date';
  }

  @override
  String get today => 'Heute';

  @override
  String get tomorrow => 'Morgen';

  @override
  String get later => 'Später';

  @override
  String get noTasksHereYet => 'Noch keine Aufgaben.';

  @override
  String tickedCount(int count) {
    return '$count abgehakt';
  }

  @override
  String get addSubtask => 'Unteraufgabe hinzufügen';

  @override
  String get subtasks => 'Unteraufgaben';

  @override
  String subtaskProgress(int completed, int total) {
    return 'Unteraufgaben: $completed/$total';
  }

  @override
  String repeats(String date, String repeat) {
    return '$date • Wiederholung: $repeat';
  }

  @override
  String repeatsEveryDays(String date, int days) {
    return '$date • alle $days Tage';
  }

  @override
  String get groceryList => 'Einkauf';

  @override
  String get addGroceryItem => 'Einkauf hinzufügen';

  @override
  String get addGroceryItemTooltip => 'Einkauf hinzufügen';

  @override
  String get editGroceryItem => 'Einkauf bearbeiten';

  @override
  String get description => 'Beschreibung';

  @override
  String get section => 'Abschnitt';

  @override
  String get currentGroceryRun => 'Aktueller Einkauf';

  @override
  String get nextTime => 'Nächstes Mal';

  @override
  String get noGroceriesCurrent => 'Noch nichts für diesen Einkauf.';

  @override
  String get repeatsToNextTime =>
      'Nach dem Entfernen wieder unter Nächstes Mal';

  @override
  String get addJournalEntry => 'Eintrag hinzufügen';

  @override
  String get addJournalEntryTooltip => 'Eintrag hinzufügen';

  @override
  String get editJournalEntry => 'Eintrag bearbeiten';

  @override
  String get entry => 'Eintrag';

  @override
  String get close => 'Schließen';

  @override
  String get noJournalEntriesYet => 'Noch keine Einträge.';

  @override
  String get watchReadList => 'Ansehen/Lesen';

  @override
  String get addWatchReadItem => 'Titel hinzufügen';

  @override
  String get addWatchReadItemTooltip => 'Titel hinzufügen';

  @override
  String get editWatchReadItem => 'Titel bearbeiten';

  @override
  String get type => 'Art';

  @override
  String get status => 'Status';

  @override
  String get movie => 'Film';

  @override
  String get tvShow => 'Serie';

  @override
  String get book => 'Buch';

  @override
  String get planned => 'Geplant';

  @override
  String get inProgress => 'Läuft';

  @override
  String get completed => 'Erledigt';

  @override
  String get season => 'Staffel';

  @override
  String get episode => 'Folge';

  @override
  String get noWatchReadItemsYet => 'Noch nichts zum Ansehen oder Lesen.';

  @override
  String get editList => 'Liste bearbeiten';

  @override
  String get newList => 'Neue Liste';

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

  @override
  String get errorAiNotAllowed => 'Die KI darf diese Liste nicht ändern.';

  @override
  String get listFilterAll => 'Alle';

  @override
  String get listDoneGroup => 'Erledigt';

  @override
  String listOpenDoneCount(int open, int done) {
    return '$open offen · $done erledigt';
  }

  @override
  String listItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge',
      one: '1 Eintrag',
    );
    return '$_temp0';
  }

  @override
  String get itemSheetNew => 'Neuer Eintrag';

  @override
  String get itemSheetEdit => 'Eintrag bearbeiten';

  @override
  String get settings => 'Einstellungen';

  @override
  String homeThingsToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Sachen heute',
      one: '1 Sache heute',
      zero: 'Heute nichts fällig',
    );
    return '$_temp0';
  }

  @override
  String listColorName(String name) {
    String _temp0 = intl.Intl.selectLogic(name, {
      'orange': 'Orange',
      'green': 'Grün',
      'magenta': 'Magenta',
      'violet': 'Violett',
      'yellow': 'Gelb',
      'rose': 'Rosa',
      'teal': 'Petrol',
      'blue': 'Blau',
      'other': 'Farbe',
    });
    return '$_temp0';
  }

  @override
  String listIconName(String name) {
    String _temp0 = intl.Intl.selectLogic(name, {
      'pending_actions': 'Klemmbrett',
      'checklist': 'Checkliste',
      'shopping_cart': 'Einkaufswagen',
      'book': 'Buch',
      'movie': 'Film',
      'local_florist': 'Blume',
      'other': 'Liste',
    });
    return '$_temp0';
  }

  @override
  String get aiBarHint => 'Hinzufügen oder ändern';

  @override
  String aiBarHintList(String list) {
    return 'Zu $list hinzufügen';
  }

  @override
  String get aiBarHintNewList => 'Liste beschreiben';

  @override
  String get aiSend => 'Senden';

  @override
  String get aiDescribeNewList => 'Neue Liste beschreiben';

  @override
  String get aiDescribeNewListMeta => 'Die KI wählt ihre Felder';

  @override
  String get aiNoticeTitle => 'Vor deiner ersten Anfrage';

  @override
  String get aiNoticeDeepSeek =>
      'Deine Anfrage, die Namen, Beschreibungen und Felder deiner Listen und die offene Liste oder eine Liste, um die es in deiner Anfrage geht, mit bis zu 20 neueren Einträgen gehen an DeepSeek, einen KI-Anbieter, der Daten in China verarbeitet und speichert. Listen mit ausgeschalteter KI werden nie gesendet. Der Text deiner Anfrage wird etwa 7 Tage zur Fehlersuche aufbewahrt und dann gelöscht.';

  @override
  String get aiNoticeContinue => 'Weiter';

  @override
  String get aiApply => 'Übernehmen';

  @override
  String aiAddItems(String list, String items) {
    return '$list: $items hinzufügen';
  }

  @override
  String aiEditItems(String list, String items) {
    return '$list: $items ändern';
  }

  @override
  String aiDeleteItems(String list, String items) {
    return '$list: $items löschen';
  }

  @override
  String aiOpAddField(String list, String field) {
    return '$list: Feld $field hinzufügen';
  }

  @override
  String aiOpRemoveField(String list, String field) {
    return '$list: Feld $field entfernen';
  }

  @override
  String aiOpRenameField(String list, String field, String label) {
    return '$list: $field in $label umbenennen';
  }

  @override
  String aiOpChangeField(String list, String field) {
    return '$list: Feld $field ändern';
  }

  @override
  String aiOpSetView(String list, String view) {
    return '$list: als $view anzeigen';
  }

  @override
  String aiOpBehavior(String list, String behavior) {
    return '$list: $behavior ändern';
  }

  @override
  String aiOpListInfo(String list) {
    return '$list: Name, Symbol oder Farbe ändern';
  }

  @override
  String aiHiddenValues(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Werte passen nicht mehr und werden verborgen aufbewahrt',
      one: '1 Wert passt nicht mehr und wird verborgen aufbewahrt',
    );
    return '$_temp0';
  }

  @override
  String aiNewList(String name, String fields) {
    return 'Neue Liste $name: $fields';
  }

  @override
  String aiDoneAdded(String lists) {
    return 'Zu $lists hinzugefügt';
  }

  @override
  String aiDoneChanged(String lists) {
    return '$lists geändert';
  }

  @override
  String aiDoneCreated(String list) {
    return '$list erstellt';
  }

  @override
  String get aiUndone => 'Rückgängig gemacht';

  @override
  String get aiDeclinedOffTopic => 'Ich kann nur bei deinen Listen helfen.';

  @override
  String get aiDeclinedNotSupported =>
      'Diese Änderung kann ich nicht vornehmen.';

  @override
  String get aiRefusedAiNotAllowed =>
      'Die KI ist für diese Liste ausgeschaltet.';

  @override
  String get aiRefusedOutputTooLong =>
      'Die Antwort war zu lang. Versuche eine kürzere Anfrage.';

  @override
  String get aiRefusedNoValidTool =>
      'Die Antwort ließ sich nicht verwenden. Versuche andere Worte.';

  @override
  String get aiRefusedDailyCount =>
      'Du hast das heutige Limit für KI-Anfragen erreicht.';

  @override
  String get aiRefusedBudget => 'Die KI pausiert bis morgen.';

  @override
  String get aiRefusedPromptTooLong => 'Die Anfrage ist zu lang.';

  @override
  String get aiRefusedContextTooLarge =>
      'Deine Listen sind zu groß zum Senden.';

  @override
  String get aiRefusedAccess =>
      'Dieses Konto oder diese App darf die KI nicht nutzen.';

  @override
  String get aiRefusedUnavailable =>
      'Die KI ist gerade nicht erreichbar. Versuche es später noch einmal.';

  @override
  String get aiRefusedBadRequest => 'Die Anfrage konnte nicht gesendet werden.';

  @override
  String get aiInvalidAnswer =>
      'Die Änderungen passen nicht zur Liste, daher wurde nichts übernommen.';

  @override
  String get errorUndoTooLarge =>
      'Diese Änderung betraf zu viele Einträge, um rückgängig gemacht zu werden.';

  @override
  String get aiPartlyNotDone =>
      'Ein Teil der Anfrage konnte nicht ausgeführt werden.';

  @override
  String get aiRefusedProviderAccount =>
      'Das Konto beim KI-Anbieter braucht Aufmerksamkeit: Schlüssel oder Guthaben prüfen.';

  @override
  String aiListOff(String list) {
    return 'Für „$list“ ist die KI ausgeschaltet.';
  }

  @override
  String get aiAutoApplyOffer =>
      'Änderungen wie diese künftig ohne Nachfrage übernehmen? Rückgängig bleibt möglich.';

  @override
  String get aiAutoApplyYes => 'Ja';

  @override
  String get aiAutoApplyNo => 'Jetzt nicht';

  @override
  String get settingsAiAutoApply => 'KI-Änderungen ohne Nachfrage übernehmen';

  @override
  String get aiAnswerHint => 'Deine Antwort';

  @override
  String get listDescription => 'Listenbeschreibung';

  @override
  String get listDescriptionHint => 'Wofür diese Liste ist (optional)';

  @override
  String errorDescriptionTooLong(String max) {
    return 'Die Beschreibung darf höchstens $max Zeichen lang sein.';
  }

  @override
  String get tasksDescription => 'Dinge, die zu erledigen sind.';

  @override
  String get groceryDescription =>
      'Lebensmittel und Haushaltsdinge für den nächsten Einkauf.';

  @override
  String get journalDescription => 'Tägliche Notizen und Gedanken, nach Datum.';

  @override
  String get watchReadDescription =>
      'Filme, Serien und Bücher zum Schauen oder Lesen.';

  @override
  String get settingsAiAsk => 'Wie oft die KI nachfragt';

  @override
  String get aiAskMore => 'Erst fragen';

  @override
  String get aiAskMoreHint =>
      'Fragt nach, sobald sie unsicher ist, und legt neue Listen nur auf Wunsch an.';

  @override
  String get aiAskBalanced => 'Ausgewogen';

  @override
  String get aiAskBalancedHint =>
      'Erledigt klare Anfragen sofort und fragt bei vagen nach.';

  @override
  String get aiAskLess => 'Einfach machen';

  @override
  String get aiAskLessHint =>
      'Folgt ihrer besten Vermutung und fragt nur, wenn zwei Listen gleich gut passen.';

  @override
  String get errorPreviewChanged =>
      'Die Liste hat sich seit dieser Vorschau geändert, daher wurde nichts geändert. Versuche es noch einmal.';

  @override
  String get errorNeedsConnection =>
      'Dafür ist eine Verbindung nötig. Es wurde nichts geändert.';

  @override
  String get errorOutcomeUnknown =>
      'Die Verbindung ist langsam, daher kann dies noch durchgehen. Prüfe die Liste, bevor du es noch einmal versuchst.';

  @override
  String get errorAnswerTooLarge =>
      'Das sind zu viele Änderungen für eine Anfrage (höchstens 500). Es wurde nichts geändert. Versuche es mit weniger.';

  @override
  String get aiItemsUpdating => 'Einträge werden noch aktualisiert.';

  @override
  String aiListOffOffer(String list) {
    return '\"$list\" hat die KI ausgeschaltet. Für deine anderen Listen senden?';
  }

  @override
  String get aiListOffSend => 'Senden';

  @override
  String get itemsNotUpdated =>
      'Einige Einträge dieser Liste konnten noch nicht aktualisiert werden. Die App versucht es beim nächsten Öffnen erneut.';

  @override
  String get theme => 'Design';

  @override
  String get themeFollowPhone => 'Wie das Telefon';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get preferences => 'Präferenzen';

  @override
  String get preferencesHint => 'Gelten für das Konto auf jedem Telefon.';

  @override
  String get preferencesLists => 'Listen';

  @override
  String get preferencesItems => 'Einträge';

  @override
  String get preferencesAi => 'KI';

  @override
  String get preferencesGeneral => 'Allgemein';

  @override
  String get preferencesListOrder => 'Reihenfolge am Rad';

  @override
  String get preferencesListOrderLastUsed => 'Zuletzt verwendet';

  @override
  String get preferencesListOrderMine => 'Eigene Reihenfolge';

  @override
  String get preferencesListOrderAz => 'A bis Z';

  @override
  String get preferencesStartScreen => 'Startbildschirm';

  @override
  String get preferencesStartLastList => 'Zuletzt geöffnete Liste';

  @override
  String get preferencesTicked => 'Abgehakte Einträge';

  @override
  String get preferencesTickedMove => 'Nach „Erledigt“';

  @override
  String get preferencesTickedStay => 'An der Stelle lassen';

  @override
  String get preferencesTickedHide => 'Ausblenden';

  @override
  String get preferencesConfirmDelete => 'Vor dem Löschen bestätigen';

  @override
  String get preferencesShowAiBar => 'KI-Leiste anzeigen';

  @override
  String get preferencesVibration => 'Vibration';

  @override
  String get preferencesTimeFormat => 'Zeitformat';

  @override
  String get preferencesFollowLanguage => 'Wie die Sprache';

  @override
  String get preferencesTime12 => '12 Stunden';

  @override
  String get preferencesTime24 => '24 Stunden';

  @override
  String get preferencesWeekStart => 'Woche beginnt am';

  @override
  String get preferencesMonday => 'Montag';

  @override
  String get preferencesSunday => 'Sonntag';

  @override
  String confirmDeleteTitle(String name) {
    return '„$name“ löschen?';
  }

  @override
  String get arrangeLists => 'Anordnen';

  @override
  String get preferenceNotSaved =>
      'Eine Einstellung konnte nicht in deinem Konto gespeichert werden. Auf diesem Telefon bleibt sie, wie du sie gewählt hast.';

  @override
  String get homeNothingOpen => 'Nichts offen';

  @override
  String get homePin => 'Auf Startseite anheften';

  @override
  String get homeUnpin => 'Von Startseite lösen';

  @override
  String get preferencesHomeContent => 'Startseite zeigt';

  @override
  String get preferencesHomeContentBoth => 'Listenkarten und heute Fälliges';

  @override
  String get preferencesHomeContentCards => 'Listenkarten';

  @override
  String get preferencesHomeContentDue => 'Heute Fälliges';

  @override
  String get preferencesHomeSuggestions => 'Vorschläge anzeigen';

  @override
  String get homeNothingDue => 'Nichts fällig. Der Tag gehört dir.';

  @override
  String get homeRearrange => 'Neu anordnen';

  @override
  String get homeUnpinShort => 'Lösen';

  @override
  String get homePinShort => 'Anheften';

  @override
  String get homeRemove => 'Entfernen';

  @override
  String get homeNoSuggestions => 'Keine Vorschläge';

  @override
  String get homeArrangeDone => 'Fertig';

  @override
  String get homeRemovedBanner => 'Von der Startseite entfernt';

  @override
  String get homeTick => 'Abhaken';

  @override
  String get homeSuggestionsOffBanner => 'Vorschläge aus';

  @override
  String get homeMoveEarlier => 'Nach vorn';

  @override
  String get homeMoveLater => 'Nach hinten';

  @override
  String get preferencesHomeListOrder => 'Reihenfolge auf der Startseite';

  @override
  String get preferencesHomeListOrderSame => 'Wie am Rad';

  @override
  String clearedBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entfernt',
      one: 'Entfernt',
    );
    return '$_temp0';
  }

  @override
  String noTickLine(String field) {
    return 'Ohne das Feld „$field“ lassen sich Einträge nicht mehr abhaken.';
  }

  @override
  String noTickView(String view) {
    return 'Die Checkliste wird als $view angezeigt.';
  }

  @override
  String noTickRules(String rules) {
    return 'Diese Regeln entfallen: $rules.';
  }

  @override
  String get noTickCopies =>
      'Das Kopieren für das nächste Mal kann nur die KI wieder hinzufügen.';
}
