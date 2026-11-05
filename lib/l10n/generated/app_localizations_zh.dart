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
  String get signInWithGoogle => '使用 Google 登录';

  @override
  String get logOut => '退出登录';

  @override
  String get categories => '分类';

  @override
  String get createCategory => '创建分类';

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
  String get title => '标题';

  @override
  String get notes => '备注';

  @override
  String get date => '日期';

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
  String get subtasks => '子任务';

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
  String get noGroceriesCurrent => '本次购物还没有项目。';

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
  String get noWatchReadItemsYet => '还没有观看/阅读项目。';

  @override
  String get editList => '编辑列表';

  @override
  String get newList => '新建列表';

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
  String get account => '账户';

  @override
  String get blankList => '空白';

  @override
  String get signInFailed => '登录失败，请重试。';

  @override
  String get signInOffline => '无网络连接。请连接互联网后登录。';

  @override
  String get signOutFailed => '退出登录失败，请重试。';

  @override
  String get signOutCleanupFailed => '已退出登录，但无法删除保存在此设备上的列表。';

  @override
  String get tryAgain => '重试';

  @override
  String get listChangeNotSaved => '列表更改无法保存，已撤销。';

  @override
  String get starterListsFailed => '无法创建初始列表。';

  @override
  String get startEmpty => '从空白开始';

  @override
  String errorMissingArg(String arg) {
    return '某项更改缺少“$arg”。';
  }

  @override
  String errorWrongArgType(String arg) {
    return '某项更改中“$arg”的值类型不正确。';
  }

  @override
  String errorUnknownArg(String arg) {
    return '某项更改包含未知设置“$arg”。';
  }

  @override
  String get errorUnknownList => '未找到该列表。';

  @override
  String get errorUnknownItem => '在列表中未找到要更改的条目。';

  @override
  String errorUnknownField(String field) {
    return '“$field”不是此列表的字段。';
  }

  @override
  String get errorListChanged => '列表在此之后已更改，因此无法撤销。';

  @override
  String get errorAiNotAllowed => 'AI 不能更改此列表。';

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

  @override
  String get settings => '设置';

  @override
  String homeThingsToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '今天 $count 件事',
      zero: '今天没有待办',
    );
    return '$_temp0';
  }

  @override
  String listColorName(String name) {
    String _temp0 = intl.Intl.selectLogic(name, {
      'orange': '橙色',
      'green': '绿色',
      'magenta': '洋红',
      'violet': '紫罗兰',
      'yellow': '黄色',
      'rose': '玫红',
      'teal': '青色',
      'blue': '蓝色',
      'other': '颜色',
    });
    return '$_temp0';
  }

  @override
  String listIconName(String name) {
    String _temp0 = intl.Intl.selectLogic(name, {
      'pending_actions': '剪贴板',
      'checklist': '清单',
      'shopping_cart': '购物车',
      'book': '书',
      'movie': '电影',
      'local_florist': '花',
      'other': '列表',
    });
    return '$_temp0';
  }

  @override
  String get aiBarHint => '添加或更改';

  @override
  String aiBarHintList(String list) {
    return '添加到$list';
  }

  @override
  String get aiBarHintNewList => '描述列表';

  @override
  String get aiSend => '发送';

  @override
  String get aiDescribeNewList => '描述新列表';

  @override
  String get aiDescribeNewListMeta => '由 AI 选择字段';

  @override
  String get aiNoticeTitle => '首次请求之前';

  @override
  String get aiNoticeDeepSeek =>
      '你的请求、各列表的名称、说明和字段，以及打开的列表（或请求涉及的列表）和最多 20 条最近条目会发送给 DeepSeek。DeepSeek 是一家在中国处理和存储数据的 AI 提供商。关闭了 AI 的列表绝不会发送。请求文字会保留约 7 天用于排查问题，之后删除。';

  @override
  String get aiNoticeContinue => '继续';

  @override
  String get aiApply => '应用';

  @override
  String aiAddItems(String list, String items) {
    return '$list：添加$items';
  }

  @override
  String aiEditItems(String list, String items) {
    return '$list：更改$items';
  }

  @override
  String aiDeleteItems(String list, String items) {
    return '$list：删除$items';
  }

  @override
  String aiOpAddField(String list, String field) {
    return '$list：添加字段“$field”';
  }

  @override
  String aiOpRemoveField(String list, String field) {
    return '$list：移除字段“$field”';
  }

  @override
  String aiOpRenameField(String list, String field, String label) {
    return '$list：将“$field”重命名为“$label”';
  }

  @override
  String aiOpChangeField(String list, String field) {
    return '$list：更改字段“$field”';
  }

  @override
  String aiOpSetView(String list, String view) {
    return '$list：显示为$view';
  }

  @override
  String aiOpBehavior(String list, String behavior) {
    return '$list：更改$behavior';
  }

  @override
  String aiOpListInfo(String list) {
    return '$list：更改名称、图标或颜色';
  }

  @override
  String aiHiddenValues(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个值不再适用，已隐藏保存',
    );
    return '$_temp0';
  }

  @override
  String aiNewList(String name, String fields) {
    return '新列表“$name”：$fields';
  }

  @override
  String aiDoneAdded(String lists) {
    return '已添加到$lists';
  }

  @override
  String aiDoneChanged(String lists) {
    return '已更改$lists';
  }

  @override
  String aiDoneCreated(String list) {
    return '已创建$list';
  }

  @override
  String get aiUndone => '已撤销';

  @override
  String get aiDeclinedOffTopic => '我只能帮你处理列表。';

  @override
  String get aiDeclinedNotSupported => '我无法做这项更改。';

  @override
  String get aiRefusedAiNotAllowed => '此列表已关闭 AI。';

  @override
  String get aiRefusedOutputTooLong => '回答太长。请尝试更短的请求。';

  @override
  String get aiRefusedNoValidTool => '无法使用该回答。请换种说法。';

  @override
  String get aiRefusedDailyCount => '你已达到今天的 AI 请求上限。';

  @override
  String get aiRefusedBudget => 'AI 暂停到明天。';

  @override
  String get aiRefusedPromptTooLong => '请求太长。';

  @override
  String get aiRefusedContextTooLarge => '你的列表太大，无法发送。';

  @override
  String get aiRefusedAccess => '此账号或应用不能使用 AI。';

  @override
  String get aiRefusedUnavailable => 'AI 目前不可用。请稍后再试。';

  @override
  String get aiRefusedBadRequest => '请求无法发送。';

  @override
  String get aiInvalidAnswer => '这些更改与列表不符，因此没有应用任何内容。';

  @override
  String get errorUndoTooLarge => '此更改涉及的项目太多，无法撤销。';

  @override
  String get aiPartlyNotDone => '请求的一部分无法完成。';

  @override
  String get aiRefusedProviderAccount => 'AI 服务商账户需要处理：请检查密钥或余额。';

  @override
  String aiListOff(String list) {
    return '“$list”已关闭 AI。';
  }

  @override
  String get aiAutoApplyOffer => '以后像这样的更改不再询问直接应用？仍可撤销。';

  @override
  String get aiAutoApplyYes => '是';

  @override
  String get aiAutoApplyNo => '暂不';

  @override
  String get settingsAiAutoApply => '不询问直接应用 AI 更改';

  @override
  String get aiAnswerHint => '你的回答';

  @override
  String get listDescription => '列表说明';

  @override
  String get listDescriptionHint => '这个列表的用途（可选）';

  @override
  String errorDescriptionTooLong(String max) {
    return '说明最多 $max 个字符。';
  }

  @override
  String get tasksDescription => '要做的事。';

  @override
  String get groceryDescription => '下次购物要买的食品和日用品。';

  @override
  String get journalDescription => '按日期记录的每日笔记和想法。';

  @override
  String get watchReadDescription => '想看或想读的电影、剧集和书。';

  @override
  String get settingsAiAsk => 'AI 向你确认的频率';

  @override
  String get aiAskMore => '先问我';

  @override
  String get aiAskMoreHint => '不确定时就向你确认，只在你要求时才新建列表。';

  @override
  String get aiAskBalanced => '平衡';

  @override
  String get aiAskBalancedHint => '明确的请求立即执行，模糊的请求先向你确认。';

  @override
  String get aiAskLess => '直接做';

  @override
  String get aiAskLessHint => '按最可能的理解执行，只在两个列表同样合适时才确认。';

  @override
  String get errorPreviewChanged => '此预览之后列表已更改，因此未做任何更改。请重试。';

  @override
  String get errorNeedsConnection => '需要网络连接。未做任何更改。';

  @override
  String get errorOutcomeUnknown => '连接较慢，此更改可能仍会生效。请先查看列表再重试。';

  @override
  String get errorAnswerTooLarge => '一次请求的更改过多（最多 500 项）。未做任何更改。请减少数量。';

  @override
  String get aiItemsUpdating => '项目仍在更新。';

  @override
  String aiListOffOffer(String list) {
    return '“$list”已关闭 AI。要针对其他列表发送吗？';
  }

  @override
  String get aiListOffSend => '发送';

  @override
  String get itemsNotUpdated => '此列表中的部分项目尚未更新。应用下次打开时会重试。';

  @override
  String get theme => '主题';

  @override
  String get themeFollowPhone => '跟随手机';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get preferences => '偏好设置';

  @override
  String get preferencesHint => '这些设置跟随账户同步到每部手机。';

  @override
  String get preferencesLists => '列表';

  @override
  String get preferencesItems => '条目';

  @override
  String get preferencesAi => 'AI';

  @override
  String get preferencesGeneral => '通用';

  @override
  String get preferencesListOrder => '列表顺序';

  @override
  String get preferencesListOrderLastUsed => '最近使用';

  @override
  String get preferencesListOrderMine => '我的顺序';

  @override
  String get preferencesListOrderAz => '按名称';

  @override
  String get preferencesStartScreen => '启动界面';

  @override
  String get preferencesStartLastList => '上次打开的列表';

  @override
  String get preferencesTicked => '已勾选的条目';

  @override
  String get preferencesTickedMove => '移到已完成';

  @override
  String get preferencesTickedStay => '留在原位';

  @override
  String get preferencesTickedHide => '隐藏';

  @override
  String get preferencesConfirmDelete => '删除前确认';

  @override
  String get preferencesShowAiBar => '显示 AI 栏';

  @override
  String get preferencesVibration => '振动';

  @override
  String get preferencesTimeFormat => '时间格式';

  @override
  String get preferencesFollowLanguage => '跟随语言';

  @override
  String get preferencesTime12 => '12 小时制';

  @override
  String get preferencesTime24 => '24 小时制';

  @override
  String get preferencesWeekStart => '每周开始于';

  @override
  String get preferencesMonday => '星期一';

  @override
  String get preferencesSunday => '星期日';

  @override
  String confirmDeleteTitle(String name) {
    return '删除“$name”?';
  }

  @override
  String get arrangeLists => '排列';

  @override
  String get preferenceNotSaved => '设置无法保存到你的账户。在这部手机上仍保持你的选择。';

  @override
  String get homeNothingOpen => '没有未完成的项目';

  @override
  String get homePin => '固定到首页';

  @override
  String get homeUnpin => '从首页取消固定';

  @override
  String get preferencesHomeCards => '在首页显示列表卡片';

  @override
  String get preferencesHomeSuggestions => '显示建议';
}
