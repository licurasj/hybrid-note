// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '混合笔记';

  @override
  String get home => '首页';

  @override
  String get tasks => '任务';

  @override
  String get grocery => '购物';

  @override
  String get journal => '日记';

  @override
  String get watchRead => '观看/阅读';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

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
  String get chooseLanguage => '选择语言';

  @override
  String get languageFollowsDevice => '使用设备语言';

  @override
  String get switchToDarkMode => '切换到深色模式';

  @override
  String get switchToLightMode => '切换到浅色模式';

  @override
  String get pendingTasks => '待办任务';

  @override
  String get completedTasks => '已完成任务';

  @override
  String get journalEntries => '日记条目';

  @override
  String get watchReadItems => '观看/阅读项目';

  @override
  String get groceryItems => '购物项目';

  @override
  String get googleDriveSync => 'Google 云端硬盘同步';

  @override
  String get syncing => '正在同步...';

  @override
  String get notSyncedYet => '尚未同步。';

  @override
  String lastSynced(String date) {
    return '上次同步：$date';
  }

  @override
  String get signInWithGoogle => '使用 Google 登录';

  @override
  String get logOut => '退出登录';

  @override
  String get syncToGoogleDrive => '同步到 Google 云端硬盘';

  @override
  String get categories => '分类';

  @override
  String get allMyTasks => '全部任务';

  @override
  String get createCategory => '创建分类';

  @override
  String get createCategoryTooltip => '创建分类';

  @override
  String get closeCategories => '关闭分类';

  @override
  String get deleteCategory => '删除分类';

  @override
  String get category => '分类';

  @override
  String get categoryName => '分类名称';

  @override
  String get create => '创建';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get clear => '清除';

  @override
  String get clearTicked => '清除已勾选';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get add => '添加';

  @override
  String get addTask => '添加任务';

  @override
  String get addTaskTooltip => '添加任务';

  @override
  String get editTask => '编辑任务';

  @override
  String get titleRequired => '标题 *';

  @override
  String get title => '标题';

  @override
  String get notes => '备注';

  @override
  String get setReminder => '设置提醒';

  @override
  String get date => '日期';

  @override
  String get time => '时间';

  @override
  String get repeat => '重复';

  @override
  String get doesNotRepeat => '不重复';

  @override
  String get daily => '每天';

  @override
  String get weekly => '每周';

  @override
  String get monthly => '每月';

  @override
  String get yearly => '每年';

  @override
  String get custom => '自定义';

  @override
  String get repeatEveryHowManyDays => '每隔多少天重复？';

  @override
  String reminderText(String date) {
    return '提醒：$date';
  }

  @override
  String get today => '今天';

  @override
  String get tomorrow => '明天';

  @override
  String get later => '之后';

  @override
  String get noTasksHereYet => '这里还没有任务。';

  @override
  String tickedCount(int count) {
    return '已勾选 $count 项';
  }

  @override
  String get addSubtask => '添加子任务';

  @override
  String get editSubtask => '编辑子任务';

  @override
  String get subtaskTitleRequired => '子任务标题 *';

  @override
  String get subtasks => '子任务';

  @override
  String get noSubtasksYet => '还没有子任务。';

  @override
  String subtaskProgress(int completed, int total) {
    return '子任务：$completed/$total';
  }

  @override
  String repeats(String date, String repeat) {
    return '$date • 重复：$repeat';
  }

  @override
  String repeatsEveryDays(String date, int days) {
    return '$date • 每 $days 天重复';
  }

  @override
  String get groceryList => '购物清单';

  @override
  String get addGroceryItem => '添加购物项目';

  @override
  String get addGroceryItemTooltip => '添加购物项目';

  @override
  String get editGroceryItem => '编辑购物项目';

  @override
  String get description => '描述';

  @override
  String get section => '区域';

  @override
  String get currentGroceryRun => '本次购物';

  @override
  String get nextTime => '下次';

  @override
  String get addAgainNextTime => '完成后再次加入下次';

  @override
  String get addAgainNextTimeDescription => '从本次购物清除/删除后，该项目会出现在下次。';

  @override
  String get noGroceriesCurrent => '本次购物还没有项目。';

  @override
  String get noGroceriesNext => '下次还没有保存的项目。';

  @override
  String get moveToCurrentRun => '移到本次购物';

  @override
  String get moveToNextTime => '移到下次';

  @override
  String get repeatsToNextTime => '清除后会重复到下次';

  @override
  String get addJournalEntry => '添加日记';

  @override
  String get addJournalEntryTooltip => '添加日记';

  @override
  String get editJournalEntry => '编辑日记';

  @override
  String get entry => '正文';

  @override
  String get close => '关闭';

  @override
  String get noJournalEntriesYet => '还没有日记。';

  @override
  String get watchReadList => '观看/阅读清单';

  @override
  String get addWatchReadItem => '添加观看/阅读项目';

  @override
  String get addWatchReadItemTooltip => '添加观看/阅读项目';

  @override
  String get editWatchReadItem => '编辑观看/阅读项目';

  @override
  String get type => '类型';

  @override
  String get status => '状态';

  @override
  String get movie => '电影';

  @override
  String get tvShow => '电视剧';

  @override
  String get book => '书';

  @override
  String get planned => '计划中';

  @override
  String get inProgress => '进行中';

  @override
  String get completed => '已完成';

  @override
  String get season => '季';

  @override
  String get episode => '集';

  @override
  String seasonNumber(int number) {
    return '第 $number 季';
  }

  @override
  String episodeNumber(int number) {
    return '第 $number 集';
  }

  @override
  String get noWatchReadItemsYet => '还没有观看/阅读项目。';

  @override
  String get editList => '编辑列表';

  @override
  String get newList => '新建列表';

  @override
  String get untitledList => '未命名列表';

  @override
  String get listName => '列表名称';

  @override
  String get listIcon => '图标';

  @override
  String get listColor => '颜色';

  @override
  String get fields => '字段';

  @override
  String get addField => '添加字段';

  @override
  String get fieldName => '字段名称';

  @override
  String get fieldType => '字段类型';

  @override
  String get required => '必填';

  @override
  String get options => '选项';

  @override
  String get addOption => '添加选项';

  @override
  String get layout => '布局';

  @override
  String get groupBy => '分组依据';

  @override
  String get sectionBy => '分区依据';

  @override
  String get dateField => '日期字段';

  @override
  String get splitByDate => '按今天 / 明天 / 以后划分';

  @override
  String get filterBy => '筛选依据';

  @override
  String get none => '无';

  @override
  String get dateCreated => '创建日期';

  @override
  String get rules => '规则';

  @override
  String get ruleClearCompleted => '清除已完成项';

  @override
  String get ruleRecurOnClear => '清除时重复';

  @override
  String get ruleCopyOnClear => '清除时复制';

  @override
  String get ruleMoveAll => '全部移动按钮';

  @override
  String get allowAi => '允许 AI 读取此列表';

  @override
  String get deleteList => '删除列表';

  @override
  String get listDeleted => '列表已删除';

  @override
  String get undo => '撤销';

  @override
  String get builtinListNote => '在迁移到 Firestore 之前，内置列表的字段保持不变。可以修改名称、图标和颜色。';

  @override
  String get localOnlyNote => '在迁移到 Firestore 之前，新列表只保存在此设备上。';

  @override
  String get typeText => '文本';

  @override
  String get typeLongText => '长文本';

  @override
  String get typeCheckbox => '复选框';

  @override
  String get typeToggle => '开关';

  @override
  String get typeNumber => '数字';

  @override
  String get typeCounter => '计数器';

  @override
  String get typeRating => '评分';

  @override
  String get typeDateTime => '日期和时间';

  @override
  String get typeChoice => '选择';

  @override
  String get typeTags => '标签';

  @override
  String get typeUrl => '链接';

  @override
  String get typeChecklist => '子项';

  @override
  String get viewChecklist => '清单';

  @override
  String get viewSectioned => '分区';

  @override
  String get viewTimeline => '时间线';

  @override
  String get viewGrouped => '分组';

  @override
  String get viewTable => '表格';

  @override
  String get viewCards => '卡片';

  @override
  String get launcherHub => '列表';

  @override
  String get previous => '上一页';

  @override
  String get next => '下一页';

  @override
  String get launcherNoteHint => '双击打开，长按编辑';

  @override
  String hiddenValuesWarning(int count) {
    return '$count 个值与新类型不符，将被隐藏保留';
  }

  @override
  String itemsCount(String name, int count) {
    return '$name，$count 项';
  }

  @override
  String get moveHub => '移动';

  @override
  String errorFormatTooNew(String version) {
    return '此列表来自更新版本的应用（格式 $version）。';
  }

  @override
  String get errorEmptyId => '列表没有 ID。';

  @override
  String get errorMissingName => '列表需要名称。';

  @override
  String get errorBadColor => '颜色必须是 #RRGGBB 格式。';

  @override
  String get errorNoFields => '列表至少需要一个字段。';

  @override
  String get errorPrimaryCount => '必须恰好有一个主字段。';

  @override
  String get errorPrimaryNotText => '主字段必须是文本字段。';

  @override
  String errorDuplicateRole(String role) {
    return '只有一个字段可以具有角色 $role。';
  }

  @override
  String errorBadFieldKey(String field) {
    return '字段键“$field”必须以字母开头，且只能包含字母、数字或 _。';
  }

  @override
  String errorReservedFieldKey(String field) {
    return '字段键“$field”是保留的。';
  }

  @override
  String errorDuplicateFieldKey(String field) {
    return '两个字段使用了同一个键“$field”。';
  }

  @override
  String errorMissingFieldLabel(String field) {
    return '字段“$field”需要名称。';
  }

  @override
  String errorMissingOptions(String field) {
    return '字段“$field”至少需要一个选项。';
  }

  @override
  String errorOptionsNotAllowed(String field, String type) {
    return '字段“$field”：$type 类型的字段不能有选项。';
  }

  @override
  String errorDuplicateOption(String field, String option) {
    return '字段“$field”：选项“$option”重复。';
  }

  @override
  String errorDefaultNotOption(String field) {
    return '字段“$field”：默认值不在选项中。';
  }

  @override
  String errorMinAboveMax(String field) {
    return '字段“$field”：最小值大于最大值。';
  }

  @override
  String errorConditionNotChoice(String field) {
    return '字段“$field”只能依赖于选择字段。';
  }

  @override
  String errorConditionOnItself(String field) {
    return '字段“$field”不能依赖于自身。';
  }

  @override
  String errorConditionNotOption(String field, String value, String target) {
    return '字段“$field”：“$value”不是“$target”的选项。';
  }

  @override
  String errorRoleNeedsType(String field, String role, String type) {
    return '字段“$field”：角色 $role 需要 $type 类型。';
  }

  @override
  String errorViewNeedsParam(String view, String param) {
    return '布局“$view”需要为“$param”指定字段。';
  }

  @override
  String errorViewParamNotField(String param, String field) {
    return '“$param”：“$field”不是此列表的字段。';
  }

  @override
  String errorViewParamWrongType(String param, String field, String types) {
    return '“$param”：“$field”必须是 $types 类型。';
  }

  @override
  String get errorChecklistNeedsCompletion => '清单布局需要一个用于标记完成的字段。';

  @override
  String errorRuleNeedsCompletion(String rule) {
    return '规则“$rule”需要一个用于标记完成的字段。';
  }

  @override
  String errorRuleNeedsParam(String rule, String param) {
    return '规则“$rule”：缺少“$param”。';
  }

  @override
  String errorRuleParamNotField(String rule, String param, String field) {
    return '规则“$rule”的“$param”：“$field”不是此列表的字段。';
  }

  @override
  String errorRuleParamWrongType(
    String rule,
    String param,
    String field,
    String types,
  ) {
    return '规则“$rule”的“$param”：“$field”必须是 $types 类型。';
  }

  @override
  String errorRuleUnknownField(String rule, String param, String field) {
    return '规则“$rule”的“$param”：没有字段“$field”。';
  }

  @override
  String errorRuleValueNotOption(
    String rule,
    String param,
    String value,
    String field,
  ) {
    return '规则“$rule”的“$param”：“$value”不是“$field”的选项。';
  }

  @override
  String errorRuleParamNotOption(String rule, String param, String field) {
    return '规则“$rule”：“$param”必须是“$field”的选项。';
  }

  @override
  String get errorWrongList => '此条目属于另一个列表。';

  @override
  String errorFieldRequired(String field) {
    return '“$field”为必填项。';
  }

  @override
  String errorWrongValueType(String field, String type) {
    return '“$field”：值不符合 $type 类型。';
  }

  @override
  String errorValueEmpty(String field) {
    return '“$field”不能为空。';
  }

  @override
  String errorBelowMin(String field, String min) {
    return '“$field”必须至少为 $min。';
  }

  @override
  String errorAboveMax(String field, String max) {
    return '“$field”不能超过 $max。';
  }

  @override
  String errorNotAnOption(String field, String value) {
    return '“$field”：“$value”不在选项中。';
  }

  @override
  String errorBadSubItem(String field) {
    return '“$field”：每个子项都需要标题和完成标记。';
  }

  @override
  String errorUnknownFrequency(String field, String value) {
    return '“$field”：未知的重复方式“$value”。';
  }

  @override
  String errorCustomDaysMissing(String field) {
    return '“$field”：自定义重复需要大于 0 的天数。';
  }

  @override
  String errorOpNoField(String field) {
    return '没有字段“$field”。';
  }

  @override
  String errorFieldExists(String field) {
    return '键为“$field”的字段已存在。';
  }

  @override
  String errorUnknownFieldType(String type) {
    return '未知的字段类型“$type”。';
  }

  @override
  String errorBadOp(String detail) {
    return '无法读取一项更改：$detail';
  }

  @override
  String get errorListExists => '已存在具有此 ID 的列表。';

  @override
  String get errorDuplicateItemId => '两个条目的 ID 相同。';

  @override
  String get errorItemIdTaken => '某个条目的 ID 已被另一个列表使用。';

  @override
  String get errorItemInOtherList => '有条目属于另一个列表。';

  @override
  String get errorBuiltinOnlyInfo => '内置列表只能修改名称、图标、颜色和 AI 设置。';

  @override
  String get addRule => '添加规则';

  @override
  String get ruleKind => '规则';

  @override
  String get ruleRepeatField => '重复字段';

  @override
  String get ruleMoveField => '字段';

  @override
  String get ruleMoveFrom => '移动自';

  @override
  String get ruleMoveTo => '移动到';

  @override
  String get listFilterAll => '全部';

  @override
  String get listDoneGroup => '已完成';

  @override
  String listOpenDoneCount(int open, int done) {
    return '$open 项未完成 · $done 项已完成';
  }

  @override
  String listItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
    );
    return '$_temp0';
  }

  @override
  String get itemSheetNew => '新建项目';

  @override
  String get itemSheetEdit => '编辑项目';
}
