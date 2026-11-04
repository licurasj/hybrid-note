// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Hybrid Note App';

  @override
  String get home => 'Inicio';

  @override
  String get tasks => 'Tareas';

  @override
  String get grocery => 'Compras';

  @override
  String get journal => 'Diario';

  @override
  String get watchRead => 'Ver/Leer';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystem => 'Predeterminado del sistema';

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
  String get chooseLanguage => 'Elegir idioma';

  @override
  String get languageFollowsDevice => 'Use device language';

  @override
  String get switchToDarkMode => 'Cambiar a modo oscuro';

  @override
  String get switchToLightMode => 'Cambiar a modo claro';

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
  String get syncing => 'Sincronizando...';

  @override
  String get notSyncedYet => 'Aún no sincronizado.';

  @override
  String lastSynced(String date) {
    return 'Last synced: $date';
  }

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get logOut => 'Log out';

  @override
  String get syncToGoogleDrive => 'Sincronizar con Google Drive';

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
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get clear => 'Clear';

  @override
  String get clearTicked => 'Clear Ticked';

  @override
  String get delete => 'Eliminar';

  @override
  String get edit => 'Editar';

  @override
  String get add => 'Añadir';

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
  String get editList => 'Editar lista';

  @override
  String get newList => 'Nueva lista';

  @override
  String get untitledList => 'Lista sin título';

  @override
  String get listName => 'Nombre de la lista';

  @override
  String get listIcon => 'Icono';

  @override
  String get listColor => 'Color';

  @override
  String get fields => 'Campos';

  @override
  String get addField => 'Añadir campo';

  @override
  String get fieldName => 'Nombre del campo';

  @override
  String get fieldType => 'Tipo de campo';

  @override
  String get required => 'Obligatorio';

  @override
  String get options => 'Opciones';

  @override
  String get addOption => 'Añadir opción';

  @override
  String get layout => 'Diseño';

  @override
  String get groupBy => 'Agrupar por';

  @override
  String get sectionBy => 'Secciones por';

  @override
  String get dateField => 'Campo de fecha';

  @override
  String get splitByDate => 'Hoy / Mañana / Más tarde por';

  @override
  String get filterBy => 'Filtrar por';

  @override
  String get none => 'Ninguno';

  @override
  String get dateCreated => 'Fecha de creación';

  @override
  String get rules => 'Reglas';

  @override
  String get ruleClearCompleted => 'Borrar completados';

  @override
  String get ruleRecurOnClear => 'Repetir al borrar';

  @override
  String get ruleCopyOnClear => 'Copiar al borrar';

  @override
  String get ruleMoveAll => 'Botón mover todo';

  @override
  String get allowAi => 'La IA puede leer esta lista';

  @override
  String get deleteList => 'Eliminar lista';

  @override
  String get listDeleted => 'Lista eliminada';

  @override
  String get undo => 'Deshacer';

  @override
  String get builtinListNote =>
      'Las listas integradas conservan sus campos hasta el paso a Firestore. Puedes cambiar el nombre, el icono y el color.';

  @override
  String get localOnlyNote =>
      'Las listas nuevas se guardan solo en este dispositivo hasta el paso a Firestore.';

  @override
  String get typeText => 'Texto';

  @override
  String get typeLongText => 'Texto largo';

  @override
  String get typeCheckbox => 'Casilla';

  @override
  String get typeToggle => 'Interruptor';

  @override
  String get typeNumber => 'Número';

  @override
  String get typeCounter => 'Contador';

  @override
  String get typeRating => 'Valoración';

  @override
  String get typeDateTime => 'Fecha y hora';

  @override
  String get typeChoice => 'Opción';

  @override
  String get typeTags => 'Etiquetas';

  @override
  String get typeUrl => 'Enlace';

  @override
  String get typeChecklist => 'Subelementos';

  @override
  String get viewChecklist => 'Lista de control';

  @override
  String get viewSectioned => 'Secciones';

  @override
  String get viewTimeline => 'Cronología';

  @override
  String get viewGrouped => 'Grupos';

  @override
  String get viewTable => 'Tabla';

  @override
  String get viewCards => 'Tarjetas';

  @override
  String get launcherHub => 'Listas';

  @override
  String get previous => 'Anterior';

  @override
  String get next => 'Siguiente';

  @override
  String get launcherNoteHint =>
      'Toca dos veces para abrir, mantén pulsado para editar';

  @override
  String hiddenValuesWarning(int count) {
    return '$count valores no encajan con el nuevo tipo y se guardarán ocultos';
  }

  @override
  String itemsCount(String name, int count) {
    return '$name, $count elementos';
  }

  @override
  String get moveHub => 'Mover';

  @override
  String errorFormatTooNew(String version) {
    return 'Esta lista viene de una versión más reciente de la app (formato $version).';
  }

  @override
  String get errorEmptyId => 'La lista no tiene ID.';

  @override
  String get errorMissingName => 'La lista necesita un nombre.';

  @override
  String get errorBadColor => 'El color debe tener la forma #RRGGBB.';

  @override
  String get errorNoFields => 'La lista necesita al menos un campo.';

  @override
  String get errorPrimaryCount =>
      'Exactamente un campo debe ser el campo principal.';

  @override
  String get errorPrimaryNotText => 'El campo principal debe ser de texto.';

  @override
  String errorDuplicateRole(String role) {
    return 'Solo un campo puede tener el rol $role.';
  }

  @override
  String errorBadFieldKey(String field) {
    return 'La clave de campo «$field» debe empezar por una letra y usar solo letras, dígitos o _.';
  }

  @override
  String errorReservedFieldKey(String field) {
    return 'La clave de campo «$field» está reservada.';
  }

  @override
  String errorDuplicateFieldKey(String field) {
    return 'Dos campos usan la clave «$field».';
  }

  @override
  String errorMissingFieldLabel(String field) {
    return 'El campo «$field» necesita un nombre.';
  }

  @override
  String errorMissingOptions(String field) {
    return 'El campo «$field» necesita al menos una opción.';
  }

  @override
  String errorOptionsNotAllowed(String field, String type) {
    return 'Campo «$field»: los campos de tipo $type no pueden tener opciones.';
  }

  @override
  String errorDuplicateOption(String field, String option) {
    return 'Campo «$field»: la opción «$option» aparece dos veces.';
  }

  @override
  String errorDefaultNotOption(String field) {
    return 'Campo «$field»: el valor predeterminado no es una de las opciones.';
  }

  @override
  String errorMinAboveMax(String field) {
    return 'Campo «$field»: el mínimo es mayor que el máximo.';
  }

  @override
  String errorConditionNotChoice(String field) {
    return 'El campo «$field» solo puede depender de un campo de opción.';
  }

  @override
  String errorConditionOnItself(String field) {
    return 'El campo «$field» no puede depender de sí mismo.';
  }

  @override
  String errorConditionNotOption(String field, String value, String target) {
    return 'Campo «$field»: «$value» no es una opción de «$target».';
  }

  @override
  String errorRoleNeedsType(String field, String role, String type) {
    return 'Campo «$field»: el rol $role necesita el tipo $type.';
  }

  @override
  String errorViewNeedsParam(String view, String param) {
    return 'El diseño $view necesita un campo para «$param».';
  }

  @override
  String errorViewParamNotField(String param, String field) {
    return '«$param»: «$field» no es un campo de esta lista.';
  }

  @override
  String errorViewParamWrongType(String param, String field, String types) {
    return '«$param»: «$field» debe ser de tipo $types.';
  }

  @override
  String get errorChecklistNeedsCompletion =>
      'El diseño de lista de control necesita un campo que marque los elementos como hechos.';

  @override
  String errorRuleNeedsCompletion(String rule) {
    return 'La regla «$rule» necesita un campo que marque los elementos como hechos.';
  }

  @override
  String errorRuleNeedsParam(String rule, String param) {
    return 'Regla «$rule»: falta «$param».';
  }

  @override
  String errorRuleParamNotField(String rule, String param, String field) {
    return 'Regla «$rule», «$param»: «$field» no es un campo de esta lista.';
  }

  @override
  String errorRuleParamWrongType(
    String rule,
    String param,
    String field,
    String types,
  ) {
    return 'Regla «$rule», «$param»: «$field» debe ser de tipo $types.';
  }

  @override
  String errorRuleUnknownField(String rule, String param, String field) {
    return 'Regla «$rule», «$param»: no existe el campo «$field».';
  }

  @override
  String errorRuleValueNotOption(
    String rule,
    String param,
    String value,
    String field,
  ) {
    return 'Regla «$rule», «$param»: «$value» no es una opción de «$field».';
  }

  @override
  String errorRuleParamNotOption(String rule, String param, String field) {
    return 'Regla «$rule»: «$param» debe ser una opción de «$field».';
  }

  @override
  String get errorWrongList => 'Este elemento pertenece a otra lista.';

  @override
  String errorFieldRequired(String field) {
    return '«$field» es obligatorio.';
  }

  @override
  String errorWrongValueType(String field, String type) {
    return '«$field»: el valor no corresponde al tipo $type.';
  }

  @override
  String errorValueEmpty(String field) {
    return '«$field» no puede estar vacío.';
  }

  @override
  String errorBelowMin(String field, String min) {
    return '«$field» debe ser al menos $min.';
  }

  @override
  String errorAboveMax(String field, String max) {
    return '«$field» debe ser como máximo $max.';
  }

  @override
  String errorNotAnOption(String field, String value) {
    return '«$field»: «$value» no es una de las opciones.';
  }

  @override
  String errorBadSubItem(String field) {
    return '«$field»: cada subelemento necesita un título y una marca de hecho.';
  }

  @override
  String errorUnknownFrequency(String field, String value) {
    return '«$field»: repetición desconocida «$value».';
  }

  @override
  String errorCustomDaysMissing(String field) {
    return '«$field»: una repetición personalizada necesita un número de días mayor que 0.';
  }

  @override
  String errorOpNoField(String field) {
    return 'No existe el campo «$field».';
  }

  @override
  String errorFieldExists(String field) {
    return 'Ya existe un campo con la clave «$field».';
  }

  @override
  String errorUnknownFieldType(String type) {
    return 'Tipo de campo desconocido «$type».';
  }

  @override
  String errorBadOp(String detail) {
    return 'No se pudo leer un cambio: $detail';
  }

  @override
  String get errorListExists => 'Ya existe una lista con este ID.';

  @override
  String get errorDuplicateItemId => 'Dos elementos tienen el mismo ID.';

  @override
  String get errorItemIdTaken => 'El ID de un elemento ya lo usa otra lista.';

  @override
  String get errorItemInOtherList => 'Un elemento pertenece a otra lista.';

  @override
  String get errorBuiltinOnlyInfo =>
      'En las listas integradas solo se pueden cambiar el nombre, el icono, el color y el ajuste de IA.';

  @override
  String get addRule => 'Añadir regla';

  @override
  String get ruleKind => 'Regla';

  @override
  String get ruleRepeatField => 'Campo de repetición';

  @override
  String get ruleMoveField => 'Campo';

  @override
  String get ruleMoveFrom => 'Mover de';

  @override
  String get ruleMoveTo => 'Mover a';

  @override
  String get account => 'Cuenta';

  @override
  String get blankList => 'En blanco';

  @override
  String get signInFailed => 'No se pudo iniciar sesión. Inténtalo de nuevo.';

  @override
  String get signInOffline =>
      'Sin conexión. Conéctate a internet para iniciar sesión.';

  @override
  String get signOutFailed => 'No se pudo cerrar sesión. Inténtalo de nuevo.';

  @override
  String get signOutCleanupFailed =>
      'Sesión cerrada, pero no se pudieron borrar las listas guardadas en este dispositivo.';

  @override
  String get tryAgain => 'Reintentar';

  @override
  String get listChangeNotSaved =>
      'No se pudo guardar un cambio en una lista y se ha deshecho.';

  @override
  String get starterListsFailed => 'No se pudieron crear las listas iniciales.';

  @override
  String get startEmpty => 'Empezar sin listas';

  @override
  String errorMissingArg(String arg) {
    return 'A un cambio le falta «$arg».';
  }

  @override
  String errorWrongArgType(String arg) {
    return 'Un cambio tiene un valor de tipo incorrecto para «$arg».';
  }

  @override
  String errorUnknownArg(String arg) {
    return 'Un cambio tiene un ajuste desconocido «$arg».';
  }

  @override
  String get errorUnknownList => 'No se encontró la lista.';

  @override
  String get errorUnknownItem =>
      'No se encontró en la lista un elemento que se iba a cambiar.';

  @override
  String errorUnknownField(String field) {
    return '«$field» no es un campo de esta lista.';
  }

  @override
  String get errorListChanged =>
      'La lista ha cambiado desde entonces, así que no se puede deshacer.';

  @override
  String get errorAiNotAllowed => 'La IA no puede cambiar esta lista.';

  @override
  String get listFilterAll => 'Todo';

  @override
  String get listDoneGroup => 'Hecho';

  @override
  String listOpenDoneCount(int open, int done) {
    return '$open pendientes · $done hechos';
  }

  @override
  String listItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get itemSheetNew => 'Nuevo elemento';

  @override
  String get itemSheetEdit => 'Editar elemento';

  @override
  String get settings => 'Ajustes';

  @override
  String get darkMode => 'Modo oscuro';

  @override
  String homeThingsToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cosas hoy',
      one: '1 cosa hoy',
      zero: 'Nada para hoy',
    );
    return '$_temp0';
  }

  @override
  String listColorName(String name) {
    String _temp0 = intl.Intl.selectLogic(name, {
      'orange': 'Naranja',
      'green': 'Verde',
      'magenta': 'Magenta',
      'violet': 'Violeta',
      'yellow': 'Amarillo',
      'rose': 'Rosa',
      'teal': 'Verde azulado',
      'blue': 'Azul',
      'other': 'Color',
    });
    return '$_temp0';
  }

  @override
  String listIconName(String name) {
    String _temp0 = intl.Intl.selectLogic(name, {
      'pending_actions': 'Portapapeles',
      'checklist': 'Lista de control',
      'shopping_cart': 'Carrito',
      'book': 'Libro',
      'movie': 'Película',
      'local_florist': 'Flor',
      'other': 'Lista',
    });
    return '$_temp0';
  }

  @override
  String get aiBarHint => 'Añadir o cambiar';

  @override
  String aiBarHintList(String list) {
    return 'Añadir a $list';
  }

  @override
  String get aiBarHintNewList => 'Describe la lista';

  @override
  String get aiSend => 'Enviar';

  @override
  String get aiBarLabel => 'Solicitud a la IA';

  @override
  String get aiDescribeNewList => 'Describir una lista nueva';

  @override
  String get aiDescribeNewListMeta => 'La IA elige sus campos';

  @override
  String get aiNoticeTitle => 'Antes de tu primera solicitud';

  @override
  String get aiNoticeDeepSeek =>
      'Tu solicitud, los nombres, descripciones y campos de tus listas y la lista abierta, o una lista de la que trata tu solicitud, con hasta 20 elementos recientes se envían a DeepSeek, un proveedor de IA que procesa y almacena los datos en China. Las listas con la IA desactivada nunca se envían. El texto de tu solicitud se guarda unos 7 días para buscar errores y después se borra.';

  @override
  String get aiNoticeContinue => 'Continuar';

  @override
  String get aiApply => 'Aplicar';

  @override
  String aiAddItems(String list, String items) {
    return '$list: añadir $items';
  }

  @override
  String aiEditItems(String list, String items) {
    return '$list: cambiar $items';
  }

  @override
  String aiDeleteItems(String list, String items) {
    return '$list: eliminar $items';
  }

  @override
  String aiOpAddField(String list, String field) {
    return '$list: añadir el campo $field';
  }

  @override
  String aiOpRemoveField(String list, String field) {
    return '$list: quitar el campo $field';
  }

  @override
  String aiOpRenameField(String list, String field, String label) {
    return '$list: renombrar $field como $label';
  }

  @override
  String aiOpChangeField(String list, String field) {
    return '$list: cambiar el campo $field';
  }

  @override
  String aiOpSetView(String list, String view) {
    return '$list: mostrar como $view';
  }

  @override
  String aiOpBehavior(String list, String behavior) {
    return '$list: cambiar $behavior';
  }

  @override
  String aiOpListInfo(String list) {
    return '$list: cambiar el nombre, el icono o el color';
  }

  @override
  String aiHiddenValues(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count valores ya no encajan y se guardan ocultos',
      one: '1 valor ya no encaja y se guarda oculto',
    );
    return '$_temp0';
  }

  @override
  String aiNewList(String name, String fields) {
    return 'Lista nueva $name: $fields';
  }

  @override
  String aiDoneAdded(String lists) {
    return 'Añadido a $lists';
  }

  @override
  String aiDoneChanged(String lists) {
    return 'Cambios en $lists';
  }

  @override
  String aiDoneCreated(String list) {
    return 'Creada: $list';
  }

  @override
  String get aiUndone => 'Deshecho';

  @override
  String get aiDeclinedOffTopic => 'Solo puedo ayudarte con tus listas.';

  @override
  String get aiDeclinedNotSupported => 'No puedo hacer ese cambio.';

  @override
  String get aiRefusedAiNotAllowed => 'La IA está desactivada para esta lista.';

  @override
  String get aiRefusedOutputTooLong =>
      'La respuesta era demasiado larga. Prueba con una solicitud más corta.';

  @override
  String get aiRefusedNoValidTool =>
      'No se pudo usar la respuesta. Prueba con otras palabras.';

  @override
  String get aiRefusedDailyCount =>
      'Has alcanzado el límite de hoy de solicitudes a la IA.';

  @override
  String get aiRefusedBudget => 'La IA está en pausa hasta mañana.';

  @override
  String get aiRefusedPromptTooLong => 'La solicitud es demasiado larga.';

  @override
  String get aiRefusedContextTooLarge =>
      'Tus listas son demasiado grandes para enviarlas.';

  @override
  String get aiRefusedAccess => 'Esta cuenta o esta app no puede usar la IA.';

  @override
  String get aiRefusedUnavailable =>
      'La IA no está disponible ahora. Inténtalo más tarde.';

  @override
  String get aiRefusedBadRequest => 'No se pudo enviar la solicitud.';

  @override
  String get aiInvalidAnswer =>
      'Los cambios no encajan en la lista, así que no se aplicó nada.';

  @override
  String get errorUndoTooLarge =>
      'Este cambio afectó a demasiados elementos para poder deshacerlo.';

  @override
  String get aiPartlyNotDone => 'Una parte de la solicitud no se pudo hacer.';

  @override
  String get aiRefusedProviderAccount =>
      'La cuenta del proveedor de IA necesita atención: revisa la clave o el saldo.';

  @override
  String aiListOff(String list) {
    return '«$list» tiene la IA desactivada.';
  }

  @override
  String get aiAutoApplyOffer =>
      '¿Aplicar cambios como este sin preguntar a partir de ahora? Deshacer sigue disponible.';

  @override
  String get aiAutoApplyYes => 'Sí';

  @override
  String get aiAutoApplyNo => 'Ahora no';

  @override
  String get settingsAiAutoApply => 'Aplicar cambios de la IA sin preguntar';

  @override
  String get aiAnswerHint => 'Tu respuesta';

  @override
  String aiAnswering(String reply) {
    return 'Respondiendo a: $reply';
  }

  @override
  String get aiNewRequest => 'Nueva solicitud';

  @override
  String get listDescription => 'Descripción de la lista';

  @override
  String get listDescriptionHint => 'Para qué es esta lista (opcional)';

  @override
  String errorDescriptionTooLong(String max) {
    return 'La descripción puede tener como máximo $max caracteres.';
  }

  @override
  String get tasksDescription => 'Cosas por hacer.';

  @override
  String get groceryDescription =>
      'Comida y cosas de casa para la próxima compra.';

  @override
  String get journalDescription => 'Notas y pensamientos del día, por fecha.';

  @override
  String get watchReadDescription =>
      'Películas, series y libros por ver o leer.';

  @override
  String get settingsAiAsk => 'Con qué frecuencia te consulta la IA';

  @override
  String get aiAskMore => 'Preguntar antes';

  @override
  String get aiAskMoreHint =>
      'Te consulta siempre que no está segura y solo crea listas nuevas si las pides.';

  @override
  String get aiAskBalanced => 'Equilibrado';

  @override
  String get aiAskBalancedHint =>
      'Hace al momento lo que está claro y te consulta lo que es vago.';

  @override
  String get aiAskLess => 'Hazlo y ya';

  @override
  String get aiAskLessHint =>
      'Sigue su mejor suposición y solo consulta si dos listas encajan igual de bien.';
}
