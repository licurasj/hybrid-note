// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Hybrid Note App';

  @override
  String get home => 'Accueil';

  @override
  String get tasks => 'Tâches';

  @override
  String get grocery => 'Courses';

  @override
  String get journal => 'Journal';

  @override
  String get watchRead => 'Voir/Lire';

  @override
  String get language => 'Langue';

  @override
  String get languageSystem => 'Par défaut du système';

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
  String get chooseLanguage => 'Choisir la langue';

  @override
  String get languageFollowsDevice => 'Use device language';

  @override
  String get switchToDarkMode => 'Passer au mode sombre';

  @override
  String get switchToLightMode => 'Passer au mode clair';

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
  String get syncing => 'Synchronisation...';

  @override
  String get notSyncedYet => 'Pas encore synchronisé.';

  @override
  String lastSynced(String date) {
    return 'Last synced: $date';
  }

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get logOut => 'Log out';

  @override
  String get syncToGoogleDrive => 'Synchroniser avec Google Drive';

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
  String get cancel => 'Annuler';

  @override
  String get save => 'Enregistrer';

  @override
  String get clear => 'Clear';

  @override
  String get clearTicked => 'Clear Ticked';

  @override
  String get delete => 'Supprimer';

  @override
  String get edit => 'Modifier';

  @override
  String get add => 'Ajouter';

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
  String get editList => 'Modifier la liste';

  @override
  String get newList => 'Nouvelle liste';

  @override
  String get untitledList => 'Liste sans titre';

  @override
  String get listName => 'Nom de la liste';

  @override
  String get listIcon => 'Icône';

  @override
  String get listColor => 'Couleur';

  @override
  String get fields => 'Champs';

  @override
  String get addField => 'Ajouter un champ';

  @override
  String get fieldName => 'Nom du champ';

  @override
  String get fieldType => 'Type de champ';

  @override
  String get required => 'Obligatoire';

  @override
  String get options => 'Options';

  @override
  String get addOption => 'Ajouter une option';

  @override
  String get layout => 'Disposition';

  @override
  String get groupBy => 'Grouper par';

  @override
  String get sectionBy => 'Sections par';

  @override
  String get dateField => 'Champ de date';

  @override
  String get splitByDate => 'Aujourd\'hui / Demain / Plus tard selon';

  @override
  String get filterBy => 'Filtrer par';

  @override
  String get none => 'Aucun';

  @override
  String get dateCreated => 'Date de création';

  @override
  String get rules => 'Règles';

  @override
  String get ruleClearCompleted => 'Effacer les éléments terminés';

  @override
  String get ruleRecurOnClear => 'Répéter à l\'effacement';

  @override
  String get ruleCopyOnClear => 'Copier à l\'effacement';

  @override
  String get ruleMoveAll => 'Bouton tout déplacer';

  @override
  String get allowAi => 'L\'IA peut lire cette liste';

  @override
  String get deleteList => 'Supprimer la liste';

  @override
  String get listDeleted => 'Liste supprimée';

  @override
  String get undo => 'Annuler';

  @override
  String get builtinListNote =>
      'Les listes intégrées gardent leurs champs jusqu\'au passage à Firestore. Vous pouvez changer le nom, l\'icône et la couleur.';

  @override
  String get localOnlyNote =>
      'Les nouvelles listes sont enregistrées sur cet appareil uniquement jusqu\'au passage à Firestore.';

  @override
  String get typeText => 'Texte';

  @override
  String get typeLongText => 'Texte long';

  @override
  String get typeCheckbox => 'Case à cocher';

  @override
  String get typeToggle => 'Interrupteur';

  @override
  String get typeNumber => 'Nombre';

  @override
  String get typeCounter => 'Compteur';

  @override
  String get typeRating => 'Note';

  @override
  String get typeDateTime => 'Date et heure';

  @override
  String get typeChoice => 'Choix';

  @override
  String get typeTags => 'Étiquettes';

  @override
  String get typeUrl => 'Lien';

  @override
  String get typeChecklist => 'Sous-éléments';

  @override
  String get viewChecklist => 'Liste de contrôle';

  @override
  String get viewSectioned => 'Sections';

  @override
  String get viewTimeline => 'Chronologie';

  @override
  String get viewGrouped => 'Groupes';

  @override
  String get viewTable => 'Tableau';

  @override
  String get viewCards => 'Cartes';

  @override
  String get launcherHub => 'Listes';

  @override
  String get previous => 'Précédent';

  @override
  String get next => 'Suivant';

  @override
  String get launcherNoteHint =>
      'Touchez deux fois pour ouvrir, appuyez longuement pour modifier';

  @override
  String hiddenValuesWarning(int count) {
    return '$count valeurs ne correspondent pas au nouveau type et seront conservées masquées';
  }

  @override
  String itemsCount(String name, int count) {
    return '$name, $count éléments';
  }

  @override
  String get moveHub => 'Déplacer';

  @override
  String errorFormatTooNew(String version) {
    return 'Cette liste vient d\'une version plus récente de l\'app (format $version).';
  }

  @override
  String get errorEmptyId => 'La liste n\'a pas d\'identifiant.';

  @override
  String get errorMissingName => 'La liste a besoin d\'un nom.';

  @override
  String get errorBadColor => 'La couleur doit avoir la forme #RRGGBB.';

  @override
  String get errorNoFields => 'La liste a besoin d\'au moins un champ.';

  @override
  String get errorPrimaryCount => 'Un seul champ doit être le champ principal.';

  @override
  String get errorPrimaryNotText =>
      'Le champ principal doit être un champ texte.';

  @override
  String errorDuplicateRole(String role) {
    return 'Un seul champ peut avoir le rôle $role.';
  }

  @override
  String errorBadFieldKey(String field) {
    return 'La clé de champ « $field » doit commencer par une lettre et ne contenir que des lettres, chiffres ou _.';
  }

  @override
  String errorReservedFieldKey(String field) {
    return 'La clé de champ « $field » est réservée.';
  }

  @override
  String errorDuplicateFieldKey(String field) {
    return 'Deux champs utilisent la clé « $field ».';
  }

  @override
  String errorMissingFieldLabel(String field) {
    return 'Le champ « $field » a besoin d\'un nom.';
  }

  @override
  String errorMissingOptions(String field) {
    return 'Le champ « $field » a besoin d\'au moins une option.';
  }

  @override
  String errorOptionsNotAllowed(String field, String type) {
    return 'Champ « $field » : les champs de type $type ne peuvent pas avoir d\'options.';
  }

  @override
  String errorDuplicateOption(String field, String option) {
    return 'Champ « $field » : l\'option « $option » apparaît deux fois.';
  }

  @override
  String errorDefaultNotOption(String field) {
    return 'Champ « $field » : la valeur par défaut ne fait pas partie des options.';
  }

  @override
  String errorMinAboveMax(String field) {
    return 'Champ « $field » : le minimum est supérieur au maximum.';
  }

  @override
  String errorConditionNotChoice(String field) {
    return 'Le champ « $field » ne peut dépendre que d\'un champ à choix.';
  }

  @override
  String errorConditionOnItself(String field) {
    return 'Le champ « $field » ne peut pas dépendre de lui-même.';
  }

  @override
  String errorConditionNotOption(String field, String value, String target) {
    return 'Champ « $field » : « $value » n\'est pas une option de « $target ».';
  }

  @override
  String errorRoleNeedsType(String field, String role, String type) {
    return 'Champ « $field » : le rôle $role nécessite le type $type.';
  }

  @override
  String errorViewNeedsParam(String view, String param) {
    return 'La disposition $view a besoin d\'un champ pour « $param ».';
  }

  @override
  String errorViewParamNotField(String param, String field) {
    return '« $param » : « $field » n\'est pas un champ de cette liste.';
  }

  @override
  String errorViewParamWrongType(String param, String field, String types) {
    return '« $param » : « $field » doit être de type $types.';
  }

  @override
  String get errorChecklistNeedsCompletion =>
      'La disposition liste de contrôle a besoin d\'un champ qui marque les éléments comme faits.';

  @override
  String errorRuleNeedsCompletion(String rule) {
    return 'La règle « $rule » a besoin d\'un champ qui marque les éléments comme faits.';
  }

  @override
  String errorRuleNeedsParam(String rule, String param) {
    return 'Règle « $rule » : « $param » manque.';
  }

  @override
  String errorRuleParamNotField(String rule, String param, String field) {
    return 'Règle « $rule », « $param » : « $field » n\'est pas un champ de cette liste.';
  }

  @override
  String errorRuleParamWrongType(
    String rule,
    String param,
    String field,
    String types,
  ) {
    return 'Règle « $rule », « $param » : « $field » doit être de type $types.';
  }

  @override
  String errorRuleUnknownField(String rule, String param, String field) {
    return 'Règle « $rule », « $param » : il n\'y a pas de champ « $field ».';
  }

  @override
  String errorRuleValueNotOption(
    String rule,
    String param,
    String value,
    String field,
  ) {
    return 'Règle « $rule », « $param » : « $value » n\'est pas une option de « $field ».';
  }

  @override
  String errorRuleParamNotOption(String rule, String param, String field) {
    return 'Règle « $rule » : « $param » doit être une option de « $field ».';
  }

  @override
  String get errorWrongList => 'Cet élément appartient à une autre liste.';

  @override
  String errorFieldRequired(String field) {
    return '« $field » est obligatoire.';
  }

  @override
  String errorWrongValueType(String field, String type) {
    return '« $field » : la valeur ne correspond pas au type $type.';
  }

  @override
  String errorValueEmpty(String field) {
    return '« $field » ne doit pas être vide.';
  }

  @override
  String errorBelowMin(String field, String min) {
    return '« $field » doit être au moins $min.';
  }

  @override
  String errorAboveMax(String field, String max) {
    return '« $field » doit être au plus $max.';
  }

  @override
  String errorNotAnOption(String field, String value) {
    return '« $field » : « $value » ne fait pas partie des options.';
  }

  @override
  String errorBadSubItem(String field) {
    return '« $field » : chaque sous-élément a besoin d\'un titre et d\'une marque « fait ».';
  }

  @override
  String errorUnknownFrequency(String field, String value) {
    return '« $field » : répétition inconnue « $value ».';
  }

  @override
  String errorCustomDaysMissing(String field) {
    return '« $field » : une répétition personnalisée a besoin d\'un nombre de jours supérieur à 0.';
  }

  @override
  String errorOpNoField(String field) {
    return 'Il n\'y a pas de champ « $field ».';
  }

  @override
  String errorFieldExists(String field) {
    return 'Un champ avec la clé « $field » existe déjà.';
  }

  @override
  String errorUnknownFieldType(String type) {
    return 'Type de champ inconnu « $type ».';
  }

  @override
  String errorBadOp(String detail) {
    return 'Une modification n\'a pas pu être lue : $detail';
  }

  @override
  String get errorListExists => 'Une liste avec cet identifiant existe déjà.';

  @override
  String get errorDuplicateItemId => 'Deux éléments ont le même identifiant.';

  @override
  String get errorItemIdTaken =>
      'L\'identifiant d\'un élément est déjà utilisé par une autre liste.';

  @override
  String get errorItemInOtherList => 'Un élément appartient à une autre liste.';

  @override
  String get errorBuiltinOnlyInfo =>
      'Pour les listes intégrées, seuls le nom, l\'icône, la couleur et le réglage IA peuvent changer.';

  @override
  String get addRule => 'Ajouter une règle';

  @override
  String get ruleKind => 'Règle';

  @override
  String get ruleRepeatField => 'Champ de répétition';

  @override
  String get ruleMoveField => 'Champ';

  @override
  String get ruleMoveFrom => 'Déplacer de';

  @override
  String get ruleMoveTo => 'Déplacer vers';

  @override
  String get account => 'Compte';

  @override
  String get blankList => 'Vide';

  @override
  String get signInFailed => 'La connexion a échoué. Veuillez réessayer.';

  @override
  String get signInOffline =>
      'Pas de connexion. Connectez-vous à Internet pour vous connecter.';

  @override
  String get signOutFailed => 'La déconnexion a échoué. Veuillez réessayer.';

  @override
  String get signOutCleanupFailed =>
      'Déconnecté, mais les listes enregistrées sur cet appareil n\'ont pas pu être supprimées.';

  @override
  String get tryAgain => 'Réessayer';

  @override
  String get listChangeNotSaved =>
      'Une modification de liste n\'a pas pu être enregistrée et a été annulée.';

  @override
  String get starterListsFailed =>
      'Les listes de départ n\'ont pas pu être créées.';

  @override
  String get startEmpty => 'Commencer sans listes';

  @override
  String errorMissingArg(String arg) {
    return 'Il manque « $arg » à une modification.';
  }

  @override
  String errorWrongArgType(String arg) {
    return 'Une modification a une valeur du mauvais type pour « $arg ».';
  }

  @override
  String errorUnknownArg(String arg) {
    return 'Une modification a un paramètre inconnu « $arg ».';
  }

  @override
  String get errorUnknownList => 'La liste est introuvable.';

  @override
  String get errorUnknownItem =>
      'Un élément à modifier est introuvable dans la liste.';

  @override
  String errorUnknownField(String field) {
    return '« $field » n’est pas un champ de cette liste.';
  }

  @override
  String get errorListChanged =>
      'La liste a changé depuis, cette action ne peut donc pas être annulée.';

  @override
  String get errorAiNotAllowed =>
      'L’IA n’a pas le droit de modifier cette liste.';

  @override
  String get listFilterAll => 'Tout';

  @override
  String get listDoneGroup => 'Terminé';

  @override
  String listOpenDoneCount(int open, int done) {
    return '$open en cours · $done terminés';
  }

  @override
  String listItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments',
      one: '1 élément',
    );
    return '$_temp0';
  }

  @override
  String get itemSheetNew => 'Nouvel élément';

  @override
  String get itemSheetEdit => 'Modifier l’élément';

  @override
  String get settings => 'Réglages';

  @override
  String get darkMode => 'Mode sombre';

  @override
  String homeThingsToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count choses aujourd\'hui',
      one: '1 chose aujourd\'hui',
      zero: 'Rien pour aujourd\'hui',
    );
    return '$_temp0';
  }

  @override
  String listColorName(String name) {
    String _temp0 = intl.Intl.selectLogic(name, {
      'orange': 'Orange',
      'green': 'Vert',
      'magenta': 'Magenta',
      'violet': 'Violet',
      'yellow': 'Jaune',
      'rose': 'Rose',
      'teal': 'Bleu canard',
      'blue': 'Bleu',
      'other': 'Couleur',
    });
    return '$_temp0';
  }

  @override
  String listIconName(String name) {
    String _temp0 = intl.Intl.selectLogic(name, {
      'pending_actions': 'Presse-papiers',
      'checklist': 'Liste de contrôle',
      'shopping_cart': 'Panier',
      'book': 'Livre',
      'movie': 'Film',
      'local_florist': 'Fleur',
      'other': 'Liste',
    });
    return '$_temp0';
  }

  @override
  String get aiBarHint => 'Ajouter ou modifier';

  @override
  String aiBarHintList(String list) {
    return 'Ajouter à $list';
  }

  @override
  String get aiBarHintNewList => 'Décrivez la liste';

  @override
  String get aiSend => 'Envoyer';

  @override
  String get aiBarLabel => 'Demande à l’IA';

  @override
  String get aiDescribeNewList => 'Décrire une nouvelle liste';

  @override
  String get aiDescribeNewListMeta => 'L’IA choisit ses champs';

  @override
  String get aiNoticeTitle => 'Avant votre première demande';

  @override
  String get aiNoticeDeepSeek =>
      'Votre demande, les noms, descriptions et champs de vos listes et la liste ouverte, ou une liste dont parle votre demande, avec jusqu’à 20 éléments récents sont envoyés à DeepSeek, un fournisseur d’IA qui traite et stocke les données en Chine. Les listes dont l’IA est désactivée ne sont jamais envoyées. Le texte de votre demande est conservé environ 7 jours pour trouver les problèmes, puis supprimé.';

  @override
  String get aiNoticeContinue => 'Continuer';

  @override
  String get aiApply => 'Appliquer';

  @override
  String aiAddItems(String list, String items) {
    return '$list : ajouter $items';
  }

  @override
  String aiEditItems(String list, String items) {
    return '$list : modifier $items';
  }

  @override
  String aiDeleteItems(String list, String items) {
    return '$list : supprimer $items';
  }

  @override
  String aiOpAddField(String list, String field) {
    return '$list : ajouter le champ $field';
  }

  @override
  String aiOpRemoveField(String list, String field) {
    return '$list : retirer le champ $field';
  }

  @override
  String aiOpRenameField(String list, String field, String label) {
    return '$list : renommer $field en $label';
  }

  @override
  String aiOpChangeField(String list, String field) {
    return '$list : modifier le champ $field';
  }

  @override
  String aiOpSetView(String list, String view) {
    return '$list : afficher en $view';
  }

  @override
  String aiOpBehavior(String list, String behavior) {
    return '$list : modifier $behavior';
  }

  @override
  String aiOpListInfo(String list) {
    return '$list : modifier le nom, l’icône ou la couleur';
  }

  @override
  String aiHiddenValues(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count valeurs ne conviennent plus et restent masquées',
      one: '1 valeur ne convient plus et reste masquée',
    );
    return '$_temp0';
  }

  @override
  String aiNewList(String name, String fields) {
    return 'Nouvelle liste $name : $fields';
  }

  @override
  String aiDoneAdded(String lists) {
    return 'Ajouté à $lists';
  }

  @override
  String aiDoneChanged(String lists) {
    return 'Modifié : $lists';
  }

  @override
  String aiDoneCreated(String list) {
    return 'Créée : $list';
  }

  @override
  String get aiUndone => 'Annulé';

  @override
  String get aiDeclinedOffTopic => 'Je ne peux aider qu’avec vos listes.';

  @override
  String get aiDeclinedNotSupported =>
      'Je ne peux pas faire cette modification.';

  @override
  String get aiRefusedAiNotAllowed => 'L’IA est désactivée pour cette liste.';

  @override
  String get aiRefusedOutputTooLong =>
      'La réponse était trop longue. Essayez une demande plus courte.';

  @override
  String get aiRefusedNoValidTool =>
      'La réponse n’a pas pu être utilisée. Essayez d’autres mots.';

  @override
  String get aiRefusedDailyCount =>
      'Vous avez atteint la limite de demandes à l’IA pour aujourd’hui.';

  @override
  String get aiRefusedBudget => 'L’IA est en pause jusqu’à demain.';

  @override
  String get aiRefusedPromptTooLong => 'La demande est trop longue.';

  @override
  String get aiRefusedContextTooLarge =>
      'Vos listes sont trop grandes pour être envoyées.';

  @override
  String get aiRefusedAccess =>
      'Ce compte ou cette app ne peut pas utiliser l’IA.';

  @override
  String get aiRefusedUnavailable =>
      'L’IA n’est pas disponible pour le moment. Réessayez plus tard.';

  @override
  String get aiRefusedBadRequest => 'La demande n’a pas pu être envoyée.';

  @override
  String get aiInvalidAnswer =>
      'Les modifications ne correspondent pas à la liste, rien n’a donc été appliqué.';

  @override
  String get errorUndoTooLarge =>
      'Cette modification a touché trop d’éléments pour être annulée.';

  @override
  String get aiPartlyNotDone =>
      'Une partie de la demande n’a pas pu être faite.';

  @override
  String get aiRefusedProviderAccount =>
      'Le compte du fournisseur d’IA demande votre attention : vérifiez la clé ou le solde.';

  @override
  String aiListOff(String list) {
    return 'L’IA est désactivée pour « $list ».';
  }

  @override
  String get aiAutoApplyOffer =>
      'Appliquer désormais les changements de ce type sans demander ? Annuler reste possible.';

  @override
  String get aiAutoApplyYes => 'Oui';

  @override
  String get aiAutoApplyNo => 'Pas maintenant';

  @override
  String get settingsAiAutoApply =>
      'Appliquer les changements de l’IA sans demander';

  @override
  String get aiAnswerHint => 'Votre réponse';

  @override
  String aiAnswering(String reply) {
    return 'Réponse à : $reply';
  }

  @override
  String get aiNewRequest => 'Nouvelle demande';

  @override
  String get listDescription => 'Description de la liste';

  @override
  String get listDescriptionHint => 'À quoi sert cette liste (facultatif)';

  @override
  String errorDescriptionTooLong(String max) {
    return 'La description peut faire au plus $max caractères.';
  }

  @override
  String get tasksDescription => 'Choses à faire.';

  @override
  String get groceryDescription =>
      'Nourriture et articles ménagers à acheter aux prochaines courses.';

  @override
  String get journalDescription => 'Notes et pensées du jour, par date.';

  @override
  String get watchReadDescription =>
      'Films, séries et livres à voir ou à lire.';

  @override
  String get settingsAiAsk => 'À quelle fréquence l’IA vous consulte';

  @override
  String get aiAskMore => 'Demander d’abord';

  @override
  String get aiAskMoreHint =>
      'Vous consulte dès qu’elle n’est pas sûre et ne crée de listes que si vous le demandez.';

  @override
  String get aiAskBalanced => 'Équilibré';

  @override
  String get aiAskBalancedHint =>
      'Fait tout de suite ce qui est clair et vous consulte pour ce qui est vague.';

  @override
  String get aiAskLess => 'Faire directement';

  @override
  String get aiAskLessHint =>
      'Suit sa meilleure hypothèse et ne consulte que si deux listes conviennent autant.';

  @override
  String get errorPreviewChanged =>
      'La liste a changé depuis cet aperçu, rien n’a donc été modifié. Réessayez.';

  @override
  String get errorNeedsConnection =>
      'Cette action nécessite une connexion. Rien n’a été modifié.';
}
