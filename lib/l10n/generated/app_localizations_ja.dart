// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Hybrid Note App';

  @override
  String get home => 'ホーム';

  @override
  String get tasks => 'タスク';

  @override
  String get grocery => '買い物';

  @override
  String get journal => '日記';

  @override
  String get watchRead => '視聴/読書';

  @override
  String get language => '言語';

  @override
  String get languageSystem => 'システム既定';

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
  String get chooseLanguage => '言語を選択';

  @override
  String get languageFollowsDevice => '端末の言語を使用';

  @override
  String get signInWithGoogle => 'Google でサインイン';

  @override
  String get logOut => 'サインアウト';

  @override
  String get categories => 'カテゴリ';

  @override
  String get createCategory => 'カテゴリを作成';

  @override
  String get deleteCategory => 'カテゴリを削除';

  @override
  String get category => 'カテゴリ';

  @override
  String get categoryName => 'カテゴリ名';

  @override
  String get create => '作成';

  @override
  String get cancel => 'キャンセル';

  @override
  String get save => '保存';

  @override
  String get clear => '消去';

  @override
  String get clearTicked => 'チェック済みを消去';

  @override
  String get delete => '削除';

  @override
  String get edit => '編集';

  @override
  String get add => '追加';

  @override
  String get addTask => 'タスクを追加';

  @override
  String get addTaskTooltip => 'タスクを追加';

  @override
  String get editTask => 'タスクを編集';

  @override
  String get title => 'タイトル';

  @override
  String get notes => 'メモ';

  @override
  String get date => '日付';

  @override
  String get repeat => '繰り返し';

  @override
  String get doesNotRepeat => '繰り返しなし';

  @override
  String get daily => '毎日';

  @override
  String get weekly => '毎週';

  @override
  String get monthly => '毎月';

  @override
  String get yearly => '毎年';

  @override
  String get custom => 'カスタム';

  @override
  String get repeatEveryHowManyDays => '何日ごとに繰り返しますか?';

  @override
  String reminderText(String date) {
    return 'リマインダー: $date';
  }

  @override
  String get today => '今日';

  @override
  String get tomorrow => '明日';

  @override
  String get later => '後で';

  @override
  String get noTasksHereYet => 'タスクはまだありません。';

  @override
  String tickedCount(int count) {
    return '$count 件チェック済み';
  }

  @override
  String get addSubtask => 'サブタスクを追加';

  @override
  String get subtasks => 'サブタスク';

  @override
  String subtaskProgress(int completed, int total) {
    return 'サブタスク: $completed/$total';
  }

  @override
  String repeats(String date, String repeat) {
    return '$date • 繰り返し: $repeat';
  }

  @override
  String repeatsEveryDays(String date, int days) {
    return '$date • $days 日ごと';
  }

  @override
  String get groceryList => '買い物';

  @override
  String get addGroceryItem => '買い物を追加';

  @override
  String get addGroceryItemTooltip => '買い物を追加';

  @override
  String get editGroceryItem => '買い物を編集';

  @override
  String get description => '説明';

  @override
  String get section => 'セクション';

  @override
  String get currentGroceryRun => '今回の買い物';

  @override
  String get nextTime => '次回';

  @override
  String get noGroceriesCurrent => '今回の買い物はまだありません。';

  @override
  String get repeatsToNextTime => '消去後に次回へ戻す';

  @override
  String get addJournalEntry => '日記を追加';

  @override
  String get addJournalEntryTooltip => '日記を追加';

  @override
  String get editJournalEntry => '日記を編集';

  @override
  String get entry => '本文';

  @override
  String get close => '閉じる';

  @override
  String get noJournalEntriesYet => '日記はまだありません。';

  @override
  String get watchReadList => '視聴/読書';

  @override
  String get addWatchReadItem => '作品を追加';

  @override
  String get addWatchReadItemTooltip => '作品を追加';

  @override
  String get editWatchReadItem => '作品を編集';

  @override
  String get type => '種類';

  @override
  String get status => '状態';

  @override
  String get movie => '映画';

  @override
  String get tvShow => 'テレビ番組';

  @override
  String get book => '本';

  @override
  String get planned => '予定';

  @override
  String get inProgress => '進行中';

  @override
  String get completed => '完了';

  @override
  String get season => 'シーズン';

  @override
  String get episode => 'エピソード';

  @override
  String get noWatchReadItemsYet => '視聴・読書する作品はまだありません。';

  @override
  String get editList => 'リストを編集';

  @override
  String get newList => '新しいリスト';

  @override
  String get listName => 'リスト名';

  @override
  String get listIcon => 'アイコン';

  @override
  String get listColor => '色';

  @override
  String get fields => '項目';

  @override
  String get addField => '項目を追加';

  @override
  String get fieldName => '項目名';

  @override
  String get fieldType => '項目の種類';

  @override
  String get required => '必須';

  @override
  String get addOption => '選択肢を追加';

  @override
  String get layout => 'レイアウト';

  @override
  String get groupBy => 'グループ化';

  @override
  String get sectionBy => 'セクション';

  @override
  String get dateField => '日付の項目';

  @override
  String get splitByDate => '今日 / 明日 / 後で の基準';

  @override
  String get filterBy => '絞り込み';

  @override
  String get none => 'なし';

  @override
  String get dateCreated => '作成日';

  @override
  String get rules => 'ルール';

  @override
  String get ruleClearCompleted => '完了した項目を消去';

  @override
  String get ruleRecurOnClear => '消去時に繰り返す';

  @override
  String get ruleCopyOnClear => '消去時にコピー';

  @override
  String get ruleMoveAll => 'すべて移動ボタン';

  @override
  String get allowAi => 'AIがこのリストを読むことを許可';

  @override
  String get deleteList => 'リストを削除';

  @override
  String get listDeleted => 'リストを削除しました';

  @override
  String get undo => '元に戻す';

  @override
  String get typeText => 'テキスト';

  @override
  String get typeLongText => '長いテキスト';

  @override
  String get typeCheckbox => 'チェックボックス';

  @override
  String get typeToggle => 'スイッチ';

  @override
  String get typeNumber => '数値';

  @override
  String get typeCounter => 'カウンター';

  @override
  String get typeRating => '評価';

  @override
  String get typeDateTime => '日時';

  @override
  String get typeChoice => '選択';

  @override
  String get typeTags => 'タグ';

  @override
  String get typeUrl => 'リンク';

  @override
  String get typeChecklist => 'サブ項目';

  @override
  String get viewChecklist => 'チェックリスト';

  @override
  String get viewSectioned => 'セクション';

  @override
  String get viewTimeline => 'タイムライン';

  @override
  String get viewGrouped => 'グループ';

  @override
  String get viewTable => '表';

  @override
  String get viewCards => 'カード';

  @override
  String get launcherHub => 'リスト';

  @override
  String get previous => '前へ';

  @override
  String get next => '次へ';

  @override
  String get launcherNoteHint => 'ダブルタップで開く、長押しで編集';

  @override
  String hiddenValuesWarning(int count) {
    return '$count 件の値は新しい種類に合わないため、非表示で保持されます';
  }

  @override
  String itemsCount(String name, int count) {
    return '$name、$count 件';
  }

  @override
  String get moveHub => '移動';

  @override
  String errorFormatTooNew(String version) {
    return 'このリストは新しいバージョンのアプリで作成されています（形式 $version）。';
  }

  @override
  String get errorEmptyId => 'リストに ID がありません。';

  @override
  String get errorMissingName => 'リストには名前が必要です。';

  @override
  String get errorBadColor => '色は #RRGGBB の形式にしてください。';

  @override
  String get errorNoFields => 'リストには項目が 1 つ以上必要です。';

  @override
  String get errorPrimaryCount => 'メイン項目はちょうど 1 つにしてください。';

  @override
  String get errorPrimaryNotText => 'メイン項目はテキストにしてください。';

  @override
  String errorDuplicateRole(String role) {
    return '役割 $role を持てる項目は 1 つだけです。';
  }

  @override
  String errorBadFieldKey(String field) {
    return '項目キー「$field」は英字で始め、英字・数字・_ だけを使ってください。';
  }

  @override
  String errorReservedFieldKey(String field) {
    return '項目キー「$field」は予約されています。';
  }

  @override
  String errorDuplicateFieldKey(String field) {
    return '2 つの項目がキー「$field」を使っています。';
  }

  @override
  String errorMissingFieldLabel(String field) {
    return '項目「$field」には名前が必要です。';
  }

  @override
  String errorMissingOptions(String field) {
    return '項目「$field」には選択肢が 1 つ以上必要です。';
  }

  @override
  String errorOptionsNotAllowed(String field, String type) {
    return '項目「$field」: 種類「$type」の項目には選択肢を設定できません。';
  }

  @override
  String errorDuplicateOption(String field, String option) {
    return '項目「$field」: 選択肢「$option」が重複しています。';
  }

  @override
  String errorDefaultNotOption(String field) {
    return '項目「$field」: 既定値が選択肢にありません。';
  }

  @override
  String errorMinAboveMax(String field) {
    return '項目「$field」: 最小値が最大値より大きくなっています。';
  }

  @override
  String errorConditionNotChoice(String field) {
    return '項目「$field」は選択項目にしか連動できません。';
  }

  @override
  String errorConditionOnItself(String field) {
    return '項目「$field」は自分自身に連動できません。';
  }

  @override
  String errorConditionNotOption(String field, String value, String target) {
    return '項目「$field」: 「$value」は「$target」の選択肢ではありません。';
  }

  @override
  String errorRoleNeedsType(String field, String role, String type) {
    return '項目「$field」: 役割 $role には種類「$type」が必要です。';
  }

  @override
  String errorViewNeedsParam(String view, String param) {
    return 'レイアウト「$view」には「$param」の項目が必要です。';
  }

  @override
  String errorViewParamNotField(String param, String field) {
    return '「$param」: 「$field」はこのリストの項目ではありません。';
  }

  @override
  String errorViewParamWrongType(String param, String field, String types) {
    return '「$param」: 「$field」の種類は $types にしてください。';
  }

  @override
  String get errorChecklistNeedsCompletion => 'チェックリストのレイアウトには完了を示す項目が必要です。';

  @override
  String errorRuleNeedsCompletion(String rule) {
    return 'ルール「$rule」には完了を示す項目が必要です。';
  }

  @override
  String errorRuleNeedsParam(String rule, String param) {
    return 'ルール「$rule」: 「$param」がありません。';
  }

  @override
  String errorRuleParamNotField(String rule, String param, String field) {
    return 'ルール「$rule」の「$param」: 「$field」はこのリストの項目ではありません。';
  }

  @override
  String errorRuleParamWrongType(
    String rule,
    String param,
    String field,
    String types,
  ) {
    return 'ルール「$rule」の「$param」: 「$field」の種類は $types にしてください。';
  }

  @override
  String errorRuleUnknownField(String rule, String param, String field) {
    return 'ルール「$rule」の「$param」: 項目「$field」はありません。';
  }

  @override
  String errorRuleValueNotOption(
    String rule,
    String param,
    String value,
    String field,
  ) {
    return 'ルール「$rule」の「$param」: 「$value」は「$field」の選択肢ではありません。';
  }

  @override
  String errorRuleParamNotOption(String rule, String param, String field) {
    return 'ルール「$rule」: 「$param」は「$field」の選択肢にしてください。';
  }

  @override
  String get errorWrongList => 'このエントリは別のリストのものです。';

  @override
  String errorFieldRequired(String field) {
    return '「$field」は必須です。';
  }

  @override
  String errorWrongValueType(String field, String type) {
    return '「$field」: 値が種類「$type」に合いません。';
  }

  @override
  String errorValueEmpty(String field) {
    return '「$field」を空にすることはできません。';
  }

  @override
  String errorBelowMin(String field, String min) {
    return '「$field」は $min 以上にしてください。';
  }

  @override
  String errorAboveMax(String field, String max) {
    return '「$field」は $max 以下にしてください。';
  }

  @override
  String errorNotAnOption(String field, String value) {
    return '「$field」: 「$value」は選択肢にありません。';
  }

  @override
  String errorBadSubItem(String field) {
    return '「$field」: サブ項目にはタイトルと完了マークが必要です。';
  }

  @override
  String errorUnknownFrequency(String field, String value) {
    return '「$field」: 不明な繰り返し「$value」です。';
  }

  @override
  String errorCustomDaysMissing(String field) {
    return '「$field」: カスタムの繰り返しには 1 日以上の日数が必要です。';
  }

  @override
  String errorOpNoField(String field) {
    return '項目「$field」はありません。';
  }

  @override
  String errorFieldExists(String field) {
    return 'キー「$field」の項目はすでにあります。';
  }

  @override
  String errorUnknownFieldType(String type) {
    return '不明な項目の種類「$type」です。';
  }

  @override
  String errorBadOp(String detail) {
    return '変更を読み取れませんでした: $detail';
  }

  @override
  String get errorListExists => 'この ID のリストはすでにあります。';

  @override
  String get errorDuplicateItemId => '2 つのエントリが同じ ID を持っています。';

  @override
  String get errorItemIdTaken => 'エントリの ID が別のリストですでに使われています。';

  @override
  String get errorItemInOtherList => '別のリストのエントリが含まれています。';

  @override
  String get addRule => 'ルールを追加';

  @override
  String get ruleKind => 'ルール';

  @override
  String get ruleRepeatField => '繰り返しの項目';

  @override
  String get ruleMoveField => '項目';

  @override
  String get ruleMoveFrom => '移動元';

  @override
  String get ruleMoveTo => '移動先';

  @override
  String get account => 'アカウント';

  @override
  String get blankList => '空白';

  @override
  String get signInFailed => 'サインインに失敗しました。もう一度お試しください。';

  @override
  String get signInOffline => '接続がありません。サインインするにはインターネットに接続してください。';

  @override
  String get signOutFailed => 'サインアウトに失敗しました。もう一度お試しください。';

  @override
  String get signOutCleanupFailed => 'サインアウトしましたが、この端末に保存されたリストを削除できませんでした。';

  @override
  String get tryAgain => '再試行';

  @override
  String get listChangeNotSaved => 'リストの変更を保存できなかったため、元に戻しました。';

  @override
  String get starterListsFailed => '初期リストを作成できませんでした。';

  @override
  String get startEmpty => '空で始める';

  @override
  String errorMissingArg(String arg) {
    return '変更に「$arg」がありません。';
  }

  @override
  String errorWrongArgType(String arg) {
    return '変更の「$arg」の値の種類が正しくありません。';
  }

  @override
  String errorUnknownArg(String arg) {
    return '変更に不明な設定「$arg」があります。';
  }

  @override
  String get errorUnknownList => 'リストが見つかりません。';

  @override
  String get errorUnknownItem => '変更する項目がリストに見つかりません。';

  @override
  String errorUnknownField(String field) {
    return '「$field」はこのリストのフィールドではありません。';
  }

  @override
  String get errorListChanged => 'リストがその後変更されたため、元に戻せません。';

  @override
  String get errorAiNotAllowed => 'AIはこのリストを変更できません。';

  @override
  String get listFilterAll => 'すべて';

  @override
  String get listDoneGroup => '完了';

  @override
  String listOpenDoneCount(int open, int done) {
    return '未完了 $open · 完了 $done';
  }

  @override
  String listItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件',
    );
    return '$_temp0';
  }

  @override
  String get itemSheetNew => '新しい項目';

  @override
  String get itemSheetEdit => '項目を編集';

  @override
  String get settings => '設定';

  @override
  String homeThingsToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '今日 $count 件',
      zero: '今日の予定はありません',
    );
    return '$_temp0';
  }

  @override
  String listColorName(String name) {
    String _temp0 = intl.Intl.selectLogic(name, {
      'orange': 'オレンジ',
      'green': 'グリーン',
      'magenta': 'マゼンタ',
      'violet': 'バイオレット',
      'yellow': 'イエロー',
      'rose': 'ローズ',
      'teal': 'ティール',
      'blue': 'ブルー',
      'other': '色',
    });
    return '$_temp0';
  }

  @override
  String listIconName(String name) {
    String _temp0 = intl.Intl.selectLogic(name, {
      'pending_actions': 'クリップボード',
      'checklist': 'チェックリスト',
      'shopping_cart': 'ショッピングカート',
      'book': '本',
      'movie': '映画',
      'local_florist': '花',
      'other': 'リスト',
    });
    return '$_temp0';
  }

  @override
  String get aiBarHint => '追加・変更';

  @override
  String aiBarHintList(String list) {
    return '$listに追加';
  }

  @override
  String get aiBarHintNewList => 'リストを説明';

  @override
  String get aiSend => '送信';

  @override
  String get aiDescribeNewList => '新しいリストを説明する';

  @override
  String get aiDescribeNewListMeta => 'AIが項目を選びます';

  @override
  String get aiNoticeTitle => '最初のリクエストの前に';

  @override
  String get aiNoticeDeepSeek =>
      'リクエスト、リストの名前・説明・項目、開いているリスト（またはリクエストが対象とするリスト）と最近の項目最大20件がDeepSeekに送られます。DeepSeekはデータを中国で処理・保存するAIプロバイダーです。AIをオフにしたリストは送信されません。リクエストの文章は不具合調査のため約7日間保存され、その後削除されます。';

  @override
  String get aiNoticeContinue => '続ける';

  @override
  String get aiApply => '適用';

  @override
  String aiAddItems(String list, String items) {
    return '$list：$itemsを追加';
  }

  @override
  String aiEditItems(String list, String items) {
    return '$list：$itemsを変更';
  }

  @override
  String aiDeleteItems(String list, String items) {
    return '$list：$itemsを削除';
  }

  @override
  String aiOpAddField(String list, String field) {
    return '$list：項目「$field」を追加';
  }

  @override
  String aiOpRemoveField(String list, String field) {
    return '$list：項目「$field」を削除';
  }

  @override
  String aiOpRenameField(String list, String field, String label) {
    return '$list：「$field」を「$label」に名前変更';
  }

  @override
  String aiOpChangeField(String list, String field) {
    return '$list：項目「$field」を変更';
  }

  @override
  String aiOpSetView(String list, String view) {
    return '$list：$viewで表示';
  }

  @override
  String aiOpBehavior(String list, String behavior) {
    return '$list：$behaviorを変更';
  }

  @override
  String aiOpListInfo(String list) {
    return '$list：名前・アイコン・色を変更';
  }

  @override
  String aiHiddenValues(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の値が合わなくなり、非表示で保存されます',
    );
    return '$_temp0';
  }

  @override
  String aiNewList(String name, String fields) {
    return '新しいリスト「$name」：$fields';
  }

  @override
  String aiDoneAdded(String lists) {
    return '$listsに追加しました';
  }

  @override
  String aiDoneChanged(String lists) {
    return '$listsを変更しました';
  }

  @override
  String aiDoneCreated(String list) {
    return '$listを作成しました';
  }

  @override
  String get aiUndone => '元に戻しました';

  @override
  String get aiDeclinedOffTopic => 'お手伝いできるのはリストのことだけです。';

  @override
  String get aiDeclinedNotSupported => 'その変更はできません。';

  @override
  String get aiRefusedAiNotAllowed => 'このリストではAIがオフになっています。';

  @override
  String get aiRefusedOutputTooLong => '回答が長すぎました。短いリクエストでお試しください。';

  @override
  String get aiRefusedNoValidTool => '回答を使えませんでした。別の言葉でお試しください。';

  @override
  String get aiRefusedDailyCount => '本日のAIリクエストの上限に達しました。';

  @override
  String get aiRefusedBudget => 'AIは明日まで停止中です。';

  @override
  String get aiRefusedPromptTooLong => 'リクエストが長すぎます。';

  @override
  String get aiRefusedContextTooLarge => 'リストが大きすぎて送信できません。';

  @override
  String get aiRefusedAccess => 'このアカウントまたはアプリはAIを使えません。';

  @override
  String get aiRefusedUnavailable => 'AIは現在利用できません。後でもう一度お試しください。';

  @override
  String get aiRefusedBadRequest => 'リクエストを送信できませんでした。';

  @override
  String get aiInvalidAnswer => '変更がリストに合わないため、何も適用されませんでした。';

  @override
  String get errorUndoTooLarge => 'この変更は項目が多すぎるため、元に戻せません。';

  @override
  String get aiPartlyNotDone => 'リクエストの一部は実行できませんでした。';

  @override
  String get aiRefusedProviderAccount =>
      'AIプロバイダーのアカウントに問題があります。キーまたは残高を確認してください。';

  @override
  String aiListOff(String list) {
    return '「$list」はAIがオフです。';
  }

  @override
  String get aiAutoApplyOffer => '今後このような変更を確認せずに適用しますか？元に戻すは引き続き使えます。';

  @override
  String get aiAutoApplyYes => 'はい';

  @override
  String get aiAutoApplyNo => '今はしない';

  @override
  String get settingsAiAutoApply => 'AIの変更を確認せずに適用';

  @override
  String get aiAnswerHint => '返答';

  @override
  String get listDescription => 'リストの説明';

  @override
  String get listDescriptionHint => 'このリストの用途（任意）';

  @override
  String errorDescriptionTooLong(String max) {
    return '説明は$max文字以内にしてください。';
  }

  @override
  String get tasksDescription => 'やること。';

  @override
  String get groceryDescription => '次の買い物で買う食品や日用品。';

  @override
  String get journalDescription => '日付ごとの毎日のメモや考え。';

  @override
  String get watchReadDescription => '観たい・読みたい映画、ドラマ、本。';

  @override
  String get settingsAiAsk => 'AIが確認する頻度';

  @override
  String get aiAskMore => 'まず確認';

  @override
  String get aiAskMoreHint => '確信がないときは必ず確認し、新しいリストは頼まれたときだけ作ります。';

  @override
  String get aiAskBalanced => 'バランス';

  @override
  String get aiAskBalancedHint => 'はっきりした依頼はすぐ実行し、あいまいな依頼は確認します。';

  @override
  String get aiAskLess => 'すぐ実行';

  @override
  String get aiAskLessHint => '最も可能性の高い案で実行し、2つのリストが同じくらい合うときだけ確認します。';

  @override
  String get errorPreviewChanged =>
      'このプレビューの後にリストが変更されたため、何も変更しませんでした。もう一度お試しください。';

  @override
  String get errorNeedsConnection => '接続が必要です。何も変更していません。';

  @override
  String get errorOutcomeUnknown =>
      '接続が遅いため、この変更はまだ反映される可能性があります。もう一度試す前にリストを確認してください。';

  @override
  String get errorAnswerTooLarge =>
      '1回のリクエストには変更が多すぎます（最大500件）。何も変更していません。件数を減らしてください。';

  @override
  String get aiItemsUpdating => '項目はまだ更新中です。';

  @override
  String aiListOffOffer(String list) {
    return '「$list」はAIがオフです。他のリスト向けに送信しますか？';
  }

  @override
  String get aiListOffSend => '送信';

  @override
  String get itemsNotUpdated =>
      'このリストの一部の項目をまだ更新できませんでした。次回アプリを開いたときにもう一度試します。';

  @override
  String get theme => 'テーマ';

  @override
  String get themeFollowPhone => 'スマホに合わせる';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeDark => 'ダーク';

  @override
  String get preferences => '環境設定';

  @override
  String get preferencesHint => 'アカウントに紐づき、すべてのスマホに反映されます。';

  @override
  String get preferencesLists => 'リスト';

  @override
  String get preferencesItems => '項目';

  @override
  String get preferencesAi => 'AI';

  @override
  String get preferencesGeneral => '一般';

  @override
  String get preferencesListOrder => 'ダイヤルの順序';

  @override
  String get preferencesListOrderLastUsed => '最近使った順';

  @override
  String get preferencesListOrderMine => '自分の順序';

  @override
  String get preferencesListOrderAz => '名前順';

  @override
  String get preferencesStartScreen => '起動時の画面';

  @override
  String get preferencesStartLastList => '最後に開いたリスト';

  @override
  String get preferencesTicked => 'チェック済みの項目';

  @override
  String get preferencesTickedMove => '完了へ移動';

  @override
  String get preferencesTickedStay => 'その場に残す';

  @override
  String get preferencesTickedHide => '隠す';

  @override
  String get preferencesConfirmDelete => '削除前に確認';

  @override
  String get preferencesShowAiBar => 'AIバーを表示';

  @override
  String get preferencesVibration => 'バイブレーション';

  @override
  String get preferencesTimeFormat => '時刻の形式';

  @override
  String get preferencesFollowLanguage => '言語に合わせる';

  @override
  String get preferencesTime12 => '12時間';

  @override
  String get preferencesTime24 => '24時間';

  @override
  String get preferencesWeekStart => '週の始まり';

  @override
  String get preferencesMonday => '月曜日';

  @override
  String get preferencesSunday => '日曜日';

  @override
  String confirmDeleteTitle(String name) {
    return '「$name」を削除しますか?';
  }

  @override
  String get arrangeLists => '並べ替え';

  @override
  String get preferenceNotSaved => '設定をアカウントに保存できませんでした。この端末では選んだとおりのままです。';

  @override
  String get homeNothingOpen => '未完了の項目はありません';

  @override
  String get homePin => 'ホームにピン留め';

  @override
  String get homeUnpin => 'ホームのピン留めを解除';

  @override
  String get preferencesHomeContent => 'ホームの表示';

  @override
  String get preferencesHomeContentBoth => 'リストカードと今日が期限の項目';

  @override
  String get preferencesHomeContentCards => 'リストカード';

  @override
  String get preferencesHomeContentDue => '今日が期限の項目';

  @override
  String get preferencesHomeSuggestions => 'おすすめを表示';

  @override
  String get homeNothingDue => '予定なし。今日は自由です。';

  @override
  String get homeRearrange => '並べ替え';

  @override
  String get homeUnpinShort => 'ピン留め解除';

  @override
  String get homePinShort => 'ピン留め';

  @override
  String get homeRemove => '削除';

  @override
  String get homeNoSuggestions => 'おすすめなし';

  @override
  String get homeArrangeDone => '完了';

  @override
  String get homeRemovedBanner => 'ホームから削除しました';

  @override
  String get homeTick => '完了にする';

  @override
  String get homeSuggestionsOffBanner => 'おすすめをオフにしました';

  @override
  String get homeMoveEarlier => '前へ移動';

  @override
  String get homeMoveLater => '後ろへ移動';

  @override
  String get preferencesHomeListOrder => 'ホームの順序';

  @override
  String get preferencesHomeListOrderSame => 'ダイヤルと同じ';

  @override
  String clearedBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件消去しました',
    );
    return '$_temp0';
  }

  @override
  String noTickLine(String field) {
    return '「$field」フィールドがないと、項目にチェックを付けられなくなります。';
  }

  @override
  String noTickView(String view) {
    return 'チェックリストは$viewで表示されます。';
  }

  @override
  String noTickRules(String rules) {
    return '次のルールがなくなります: $rules。';
  }

  @override
  String get noTickCopies => '「次回へコピー」は AI でのみ追加し直せます。';

  @override
  String get homeHide => 'ホームから外す';

  @override
  String get homeHiddenBanner => 'ホームに表示しません';

  @override
  String get suggestOnHome => 'ホームでおすすめする';

  @override
  String get suggestOnHomeOff => '環境設定でおすすめがオフになっています。';

  @override
  String get preferencesListsAndDial => 'Lists and dial';

  @override
  String get preferencesStartScreenLine => 'What opens when you start the app.';

  @override
  String get preferencesSuggestionsLine =>
      'Fills home up to 3 cards with lists you may want.';

  @override
  String get preferencesOnlyWithCards => 'Only when home shows list cards.';

  @override
  String get preferencesDialOrderLine => 'The order of lists on the dial.';

  @override
  String get preferencesHomeOrderSameLine =>
      'Pinned cards follow the dial\'s order.';

  @override
  String get preferencesHomeOrderLastUsedLine =>
      'Pinned cards in the order you last opened them.';

  @override
  String get preferencesHomeOrderAzLine => 'Pinned cards by name.';

  @override
  String get preferencesHomeOrderMineLine => 'The order you arranged on home.';

  @override
  String get preferencesConfirmDeleteLine =>
      'Asks before an item or a list is deleted.';

  @override
  String get preferencesAiBarOffLine =>
      'The AI bar is hidden. Your lists stay as they are.';

  @override
  String get preferencesWeekStartLine => 'Used by the date pickers and the AI.';

  @override
  String get preferencesTickedMoveLine =>
      'Ticked items go to an open Done group at the bottom of each list.';

  @override
  String get preferencesTickedStayLine =>
      'Ticked items stay where they are, crossed out.';

  @override
  String get preferencesTickedHideLine =>
      'Ticked items wait in a closed Done group at the bottom of each list. Tap it to see them.';

  @override
  String get preferencesSuggestionsOffLine =>
      'Home shows only the lists you pinned.';

  @override
  String get preferencesAiBarOnLine =>
      'The AI bar sits beside the hub on every screen.';

  @override
  String get preferencesTickedClear => 'Clear straight away';

  @override
  String get preferencesTickedClearLine =>
      'Ticking clears an item at once, with Undo. Repeats and Next time copies still happen.';
}
