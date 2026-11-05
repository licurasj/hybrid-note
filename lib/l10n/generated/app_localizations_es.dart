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
  String get languageFollowsDevice => 'Usar el idioma del dispositivo';

  @override
  String get signInWithGoogle => 'Iniciar sesión con Google';

  @override
  String get logOut => 'Cerrar sesión';

  @override
  String get categories => 'Categorías';

  @override
  String get createCategory => 'Crear categoría';

  @override
  String get deleteCategory => 'Eliminar categoría';

  @override
  String get category => 'Categoría';

  @override
  String get categoryName => 'Nombre de la categoría';

  @override
  String get create => 'Crear';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get clear => 'Borrar';

  @override
  String get clearTicked => 'Borrar marcados';

  @override
  String get delete => 'Eliminar';

  @override
  String get edit => 'Editar';

  @override
  String get add => 'Añadir';

  @override
  String get addTask => 'Añadir tarea';

  @override
  String get addTaskTooltip => 'Añadir tarea';

  @override
  String get editTask => 'Editar tarea';

  @override
  String get title => 'Título';

  @override
  String get notes => 'Notas';

  @override
  String get date => 'Fecha';

  @override
  String get repeat => 'Repetir';

  @override
  String get doesNotRepeat => 'No se repite';

  @override
  String get daily => 'Diario';

  @override
  String get weekly => 'Semanal';

  @override
  String get monthly => 'Mensual';

  @override
  String get yearly => 'Anual';

  @override
  String get custom => 'Personalizado';

  @override
  String get repeatEveryHowManyDays => '¿Repetir cada cuántos días?';

  @override
  String reminderText(String date) {
    return 'Recordatorio: $date';
  }

  @override
  String get today => 'Hoy';

  @override
  String get tomorrow => 'Mañana';

  @override
  String get later => 'Más tarde';

  @override
  String get noTasksHereYet => 'Aún no hay tareas.';

  @override
  String tickedCount(int count) {
    return '$count marcados';
  }

  @override
  String get addSubtask => 'Añadir subtarea';

  @override
  String get subtasks => 'Subtareas';

  @override
  String subtaskProgress(int completed, int total) {
    return 'Subtareas: $completed/$total';
  }

  @override
  String repeats(String date, String repeat) {
    return '$date • repetición: $repeat';
  }

  @override
  String repeatsEveryDays(String date, int days) {
    return '$date • cada $days días';
  }

  @override
  String get groceryList => 'Compras';

  @override
  String get addGroceryItem => 'Añadir artículo';

  @override
  String get addGroceryItemTooltip => 'Añadir artículo';

  @override
  String get editGroceryItem => 'Editar artículo';

  @override
  String get description => 'Descripción';

  @override
  String get section => 'Sección';

  @override
  String get currentGroceryRun => 'Compra actual';

  @override
  String get nextTime => 'La próxima vez';

  @override
  String get noGroceriesCurrent => 'Aún no hay nada para esta compra.';

  @override
  String get repeatsToNextTime => 'Tras borrar, vuelve a La próxima vez';

  @override
  String get addJournalEntry => 'Añadir entrada';

  @override
  String get addJournalEntryTooltip => 'Añadir entrada';

  @override
  String get editJournalEntry => 'Editar entrada';

  @override
  String get entry => 'Entrada';

  @override
  String get close => 'Cerrar';

  @override
  String get noJournalEntriesYet => 'Aún no hay entradas.';

  @override
  String get watchReadList => 'Ver/Leer';

  @override
  String get addWatchReadItem => 'Añadir título';

  @override
  String get addWatchReadItemTooltip => 'Añadir título';

  @override
  String get editWatchReadItem => 'Editar título';

  @override
  String get type => 'Tipo';

  @override
  String get status => 'Estado';

  @override
  String get movie => 'Película';

  @override
  String get tvShow => 'Serie';

  @override
  String get book => 'Libro';

  @override
  String get planned => 'Planeado';

  @override
  String get inProgress => 'En curso';

  @override
  String get completed => 'Completado';

  @override
  String get season => 'Temporada';

  @override
  String get episode => 'Episodio';

  @override
  String get noWatchReadItemsYet => 'Aún no hay nada para ver o leer.';

  @override
  String get editList => 'Editar lista';

  @override
  String get newList => 'Nueva lista';

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

  @override
  String get errorPreviewChanged =>
      'La lista ha cambiado desde esta vista previa, así que no se ha cambiado nada. Inténtalo de nuevo.';

  @override
  String get errorNeedsConnection =>
      'Esto necesita conexión. No se ha cambiado nada.';

  @override
  String get errorOutcomeUnknown =>
      'La conexión es lenta, así que esto aún puede completarse. Revisa la lista antes de volver a intentarlo.';

  @override
  String get errorAnswerTooLarge =>
      'Son demasiados cambios para una solicitud (500 como máximo). No se ha cambiado nada. Prueba con menos.';

  @override
  String get aiItemsUpdating => 'Los elementos se siguen actualizando.';

  @override
  String aiListOffOffer(String list) {
    return '\"$list\" tiene la IA desactivada. ¿Enviar para tus otras listas?';
  }

  @override
  String get aiListOffSend => 'Enviar';

  @override
  String get itemsNotUpdated =>
      'Algunos elementos de esta lista aún no se han podido actualizar. La app lo intentará de nuevo la próxima vez que se abra.';

  @override
  String get theme => 'Tema';

  @override
  String get themeFollowPhone => 'Igual que el teléfono';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get preferences => 'Preferencias';

  @override
  String get preferencesHint =>
      'Se aplican a la cuenta en todos los teléfonos.';

  @override
  String get preferencesLists => 'Listas';

  @override
  String get preferencesItems => 'Elementos';

  @override
  String get preferencesAi => 'IA';

  @override
  String get preferencesGeneral => 'General';

  @override
  String get preferencesListOrder => 'Orden de las listas';

  @override
  String get preferencesListOrderLastUsed => 'Último uso';

  @override
  String get preferencesListOrderMine => 'Mi orden';

  @override
  String get preferencesListOrderAz => 'A a la Z';

  @override
  String get preferencesStartScreen => 'Pantalla de inicio';

  @override
  String get preferencesStartLastList => 'Última lista abierta';

  @override
  String get preferencesTicked => 'Elementos marcados';

  @override
  String get preferencesTickedMove => 'Mover a Hecho';

  @override
  String get preferencesTickedStay => 'Dejar en su sitio';

  @override
  String get preferencesTickedHide => 'Ocultar';

  @override
  String get preferencesConfirmDelete => 'Confirmar antes de eliminar';

  @override
  String get preferencesShowAiBar => 'Mostrar la barra de IA';

  @override
  String get preferencesVibration => 'Vibración';

  @override
  String get preferencesTimeFormat => 'Formato de hora';

  @override
  String get preferencesFollowLanguage => 'Según el idioma';

  @override
  String get preferencesTime12 => '12 horas';

  @override
  String get preferencesTime24 => '24 horas';

  @override
  String get preferencesWeekStart => 'La semana empieza el';

  @override
  String get preferencesMonday => 'Lunes';

  @override
  String get preferencesSunday => 'Domingo';

  @override
  String confirmDeleteTitle(String name) {
    return '¿Eliminar «$name»?';
  }

  @override
  String get arrangeLists => 'Ordenar';
}
