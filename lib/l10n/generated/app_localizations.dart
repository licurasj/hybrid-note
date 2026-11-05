import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('ja'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Hybrid Note App'**
  String get appTitle;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @tasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasks;

  /// No description provided for @grocery.
  ///
  /// In en, this message translates to:
  /// **'Grocery'**
  String get grocery;

  /// No description provided for @journal.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get journal;

  /// No description provided for @watchRead.
  ///
  /// In en, this message translates to:
  /// **'Watch/Read'**
  String get watchRead;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get languageChinese;

  /// No description provided for @languageJapanese.
  ///
  /// In en, this message translates to:
  /// **'日本語'**
  String get languageJapanese;

  /// No description provided for @languageFrench.
  ///
  /// In en, this message translates to:
  /// **'Français'**
  String get languageFrench;

  /// No description provided for @languageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get languageSpanish;

  /// No description provided for @languageGerman.
  ///
  /// In en, this message translates to:
  /// **'Deutsch'**
  String get languageGerman;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose Language'**
  String get chooseLanguage;

  /// No description provided for @languageFollowsDevice.
  ///
  /// In en, this message translates to:
  /// **'Use device language'**
  String get languageFollowsDevice;

  /// No description provided for @switchToDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Switch to dark mode'**
  String get switchToDarkMode;

  /// No description provided for @switchToLightMode.
  ///
  /// In en, this message translates to:
  /// **'Switch to light mode'**
  String get switchToLightMode;

  /// No description provided for @pendingTasks.
  ///
  /// In en, this message translates to:
  /// **'Pending Tasks'**
  String get pendingTasks;

  /// No description provided for @completedTasks.
  ///
  /// In en, this message translates to:
  /// **'Completed Tasks'**
  String get completedTasks;

  /// No description provided for @journalEntries.
  ///
  /// In en, this message translates to:
  /// **'Journal Entries'**
  String get journalEntries;

  /// No description provided for @watchReadItems.
  ///
  /// In en, this message translates to:
  /// **'Watch/Read Items'**
  String get watchReadItems;

  /// No description provided for @groceryItems.
  ///
  /// In en, this message translates to:
  /// **'Grocery Items'**
  String get groceryItems;

  /// No description provided for @googleDriveSync.
  ///
  /// In en, this message translates to:
  /// **'Google Drive Sync'**
  String get googleDriveSync;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncing;

  /// No description provided for @notSyncedYet.
  ///
  /// In en, this message translates to:
  /// **'Not synced yet.'**
  String get notSyncedYet;

  /// No description provided for @lastSynced.
  ///
  /// In en, this message translates to:
  /// **'Last synced: {date}'**
  String lastSynced(String date);

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOut;

  /// No description provided for @syncToGoogleDrive.
  ///
  /// In en, this message translates to:
  /// **'Sync to Google Drive'**
  String get syncToGoogleDrive;

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// No description provided for @allMyTasks.
  ///
  /// In en, this message translates to:
  /// **'All My Tasks'**
  String get allMyTasks;

  /// No description provided for @createCategory.
  ///
  /// In en, this message translates to:
  /// **'Create Category'**
  String get createCategory;

  /// No description provided for @createCategoryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Create category'**
  String get createCategoryTooltip;

  /// No description provided for @closeCategories.
  ///
  /// In en, this message translates to:
  /// **'Close categories'**
  String get closeCategories;

  /// No description provided for @deleteCategory.
  ///
  /// In en, this message translates to:
  /// **'Delete category'**
  String get deleteCategory;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @categoryName.
  ///
  /// In en, this message translates to:
  /// **'Category name'**
  String get categoryName;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @clearTicked.
  ///
  /// In en, this message translates to:
  /// **'Clear Ticked'**
  String get clearTicked;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @addTask.
  ///
  /// In en, this message translates to:
  /// **'Add Task'**
  String get addTask;

  /// No description provided for @addTaskTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add task'**
  String get addTaskTooltip;

  /// No description provided for @editTask.
  ///
  /// In en, this message translates to:
  /// **'Edit Task'**
  String get editTask;

  /// No description provided for @titleRequired.
  ///
  /// In en, this message translates to:
  /// **'Title *'**
  String get titleRequired;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @setReminder.
  ///
  /// In en, this message translates to:
  /// **'Set reminder'**
  String get setReminder;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @repeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeat;

  /// No description provided for @doesNotRepeat.
  ///
  /// In en, this message translates to:
  /// **'Does not repeat'**
  String get doesNotRepeat;

  /// No description provided for @daily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get daily;

  /// No description provided for @weekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get weekly;

  /// No description provided for @monthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get monthly;

  /// No description provided for @yearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get yearly;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @repeatEveryHowManyDays.
  ///
  /// In en, this message translates to:
  /// **'Repeat every how many days?'**
  String get repeatEveryHowManyDays;

  /// No description provided for @reminderText.
  ///
  /// In en, this message translates to:
  /// **'Reminder: {date}'**
  String reminderText(String date);

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @noTasksHereYet.
  ///
  /// In en, this message translates to:
  /// **'No tasks here yet.'**
  String get noTasksHereYet;

  /// No description provided for @tickedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} ticked'**
  String tickedCount(int count);

  /// No description provided for @addSubtask.
  ///
  /// In en, this message translates to:
  /// **'Add subtask'**
  String get addSubtask;

  /// No description provided for @editSubtask.
  ///
  /// In en, this message translates to:
  /// **'Edit Subtask'**
  String get editSubtask;

  /// No description provided for @subtaskTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Subtask title *'**
  String get subtaskTitleRequired;

  /// No description provided for @subtasks.
  ///
  /// In en, this message translates to:
  /// **'Subtasks'**
  String get subtasks;

  /// No description provided for @noSubtasksYet.
  ///
  /// In en, this message translates to:
  /// **'No subtasks yet.'**
  String get noSubtasksYet;

  /// No description provided for @subtaskProgress.
  ///
  /// In en, this message translates to:
  /// **'Subtasks: {completed}/{total}'**
  String subtaskProgress(int completed, int total);

  /// No description provided for @repeats.
  ///
  /// In en, this message translates to:
  /// **'{date} • repeats {repeat}'**
  String repeats(String date, String repeat);

  /// No description provided for @repeatsEveryDays.
  ///
  /// In en, this message translates to:
  /// **'{date} • repeats every {days} day(s)'**
  String repeatsEveryDays(String date, int days);

  /// No description provided for @groceryList.
  ///
  /// In en, this message translates to:
  /// **'Grocery List'**
  String get groceryList;

  /// No description provided for @addGroceryItem.
  ///
  /// In en, this message translates to:
  /// **'Add Grocery Item'**
  String get addGroceryItem;

  /// No description provided for @addGroceryItemTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add grocery item'**
  String get addGroceryItemTooltip;

  /// No description provided for @editGroceryItem.
  ///
  /// In en, this message translates to:
  /// **'Edit Grocery Item'**
  String get editGroceryItem;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @section.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get section;

  /// No description provided for @currentGroceryRun.
  ///
  /// In en, this message translates to:
  /// **'Current Grocery Run'**
  String get currentGroceryRun;

  /// No description provided for @nextTime.
  ///
  /// In en, this message translates to:
  /// **'Next Time'**
  String get nextTime;

  /// No description provided for @addAgainNextTime.
  ///
  /// In en, this message translates to:
  /// **'Add again to Next Time when completed'**
  String get addAgainNextTime;

  /// No description provided for @addAgainNextTimeDescription.
  ///
  /// In en, this message translates to:
  /// **'The item will appear in Next Time after you clear/delete it from Current Grocery Run.'**
  String get addAgainNextTimeDescription;

  /// No description provided for @noGroceriesCurrent.
  ///
  /// In en, this message translates to:
  /// **'No groceries for this run yet.'**
  String get noGroceriesCurrent;

  /// No description provided for @noGroceriesNext.
  ///
  /// In en, this message translates to:
  /// **'No saved groceries for next time yet.'**
  String get noGroceriesNext;

  /// No description provided for @moveToCurrentRun.
  ///
  /// In en, this message translates to:
  /// **'Move to current run'**
  String get moveToCurrentRun;

  /// No description provided for @moveToNextTime.
  ///
  /// In en, this message translates to:
  /// **'Move to next time'**
  String get moveToNextTime;

  /// No description provided for @repeatsToNextTime.
  ///
  /// In en, this message translates to:
  /// **'Repeats to Next Time after clearing'**
  String get repeatsToNextTime;

  /// No description provided for @addJournalEntry.
  ///
  /// In en, this message translates to:
  /// **'Add Journal Entry'**
  String get addJournalEntry;

  /// No description provided for @addJournalEntryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add journal entry'**
  String get addJournalEntryTooltip;

  /// No description provided for @editJournalEntry.
  ///
  /// In en, this message translates to:
  /// **'Edit Journal Entry'**
  String get editJournalEntry;

  /// No description provided for @entry.
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get entry;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @noJournalEntriesYet.
  ///
  /// In en, this message translates to:
  /// **'No journal entries yet.'**
  String get noJournalEntriesYet;

  /// No description provided for @watchReadList.
  ///
  /// In en, this message translates to:
  /// **'Watch/Read List'**
  String get watchReadList;

  /// No description provided for @addWatchReadItem.
  ///
  /// In en, this message translates to:
  /// **'Add Watch/Read Item'**
  String get addWatchReadItem;

  /// No description provided for @addWatchReadItemTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add watch/read item'**
  String get addWatchReadItemTooltip;

  /// No description provided for @editWatchReadItem.
  ///
  /// In en, this message translates to:
  /// **'Edit Watch/Read Item'**
  String get editWatchReadItem;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @movie.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get movie;

  /// No description provided for @tvShow.
  ///
  /// In en, this message translates to:
  /// **'TV Show'**
  String get tvShow;

  /// No description provided for @book.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get book;

  /// No description provided for @planned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get planned;

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get inProgress;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @season.
  ///
  /// In en, this message translates to:
  /// **'Season'**
  String get season;

  /// No description provided for @episode.
  ///
  /// In en, this message translates to:
  /// **'Episode'**
  String get episode;

  /// No description provided for @seasonNumber.
  ///
  /// In en, this message translates to:
  /// **'Season {number}'**
  String seasonNumber(int number);

  /// No description provided for @episodeNumber.
  ///
  /// In en, this message translates to:
  /// **'Episode {number}'**
  String episodeNumber(int number);

  /// No description provided for @noWatchReadItemsYet.
  ///
  /// In en, this message translates to:
  /// **'No watch/read items yet.'**
  String get noWatchReadItemsYet;

  /// No description provided for @editList.
  ///
  /// In en, this message translates to:
  /// **'Edit list'**
  String get editList;

  /// No description provided for @newList.
  ///
  /// In en, this message translates to:
  /// **'New list'**
  String get newList;

  /// No description provided for @untitledList.
  ///
  /// In en, this message translates to:
  /// **'Untitled list'**
  String get untitledList;

  /// No description provided for @listName.
  ///
  /// In en, this message translates to:
  /// **'List name'**
  String get listName;

  /// No description provided for @listIcon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get listIcon;

  /// No description provided for @listColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get listColor;

  /// No description provided for @fields.
  ///
  /// In en, this message translates to:
  /// **'Fields'**
  String get fields;

  /// No description provided for @addField.
  ///
  /// In en, this message translates to:
  /// **'Add field'**
  String get addField;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Field name'**
  String get fieldName;

  /// No description provided for @fieldType.
  ///
  /// In en, this message translates to:
  /// **'Field type'**
  String get fieldType;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @options.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get options;

  /// No description provided for @addOption.
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get addOption;

  /// No description provided for @layout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layout;

  /// No description provided for @groupBy.
  ///
  /// In en, this message translates to:
  /// **'Group by'**
  String get groupBy;

  /// No description provided for @sectionBy.
  ///
  /// In en, this message translates to:
  /// **'Sections by'**
  String get sectionBy;

  /// No description provided for @dateField.
  ///
  /// In en, this message translates to:
  /// **'Date field'**
  String get dateField;

  /// No description provided for @splitByDate.
  ///
  /// In en, this message translates to:
  /// **'Today / Tomorrow / Later by'**
  String get splitByDate;

  /// No description provided for @filterBy.
  ///
  /// In en, this message translates to:
  /// **'Filter chips by'**
  String get filterBy;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @dateCreated.
  ///
  /// In en, this message translates to:
  /// **'Date created'**
  String get dateCreated;

  /// No description provided for @rules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get rules;

  /// No description provided for @ruleClearCompleted.
  ///
  /// In en, this message translates to:
  /// **'Clear completed items'**
  String get ruleClearCompleted;

  /// No description provided for @ruleRecurOnClear.
  ///
  /// In en, this message translates to:
  /// **'Repeat when cleared'**
  String get ruleRecurOnClear;

  /// No description provided for @ruleCopyOnClear.
  ///
  /// In en, this message translates to:
  /// **'Copy when cleared'**
  String get ruleCopyOnClear;

  /// No description provided for @ruleMoveAll.
  ///
  /// In en, this message translates to:
  /// **'Move all button'**
  String get ruleMoveAll;

  /// No description provided for @allowAi.
  ///
  /// In en, this message translates to:
  /// **'AI may read this list'**
  String get allowAi;

  /// No description provided for @deleteList.
  ///
  /// In en, this message translates to:
  /// **'Delete list'**
  String get deleteList;

  /// No description provided for @listDeleted.
  ///
  /// In en, this message translates to:
  /// **'List deleted'**
  String get listDeleted;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @builtinListNote.
  ///
  /// In en, this message translates to:
  /// **'Built-in lists keep their fields until sync moves to Firestore. You can change the name, icon and color.'**
  String get builtinListNote;

  /// No description provided for @localOnlyNote.
  ///
  /// In en, this message translates to:
  /// **'New lists are saved on this device only until sync moves to Firestore.'**
  String get localOnlyNote;

  /// No description provided for @typeText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get typeText;

  /// No description provided for @typeLongText.
  ///
  /// In en, this message translates to:
  /// **'Long text'**
  String get typeLongText;

  /// No description provided for @typeCheckbox.
  ///
  /// In en, this message translates to:
  /// **'Checkbox'**
  String get typeCheckbox;

  /// No description provided for @typeToggle.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get typeToggle;

  /// No description provided for @typeNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get typeNumber;

  /// No description provided for @typeCounter.
  ///
  /// In en, this message translates to:
  /// **'Counter'**
  String get typeCounter;

  /// No description provided for @typeRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get typeRating;

  /// No description provided for @typeDateTime.
  ///
  /// In en, this message translates to:
  /// **'Date and time'**
  String get typeDateTime;

  /// No description provided for @typeChoice.
  ///
  /// In en, this message translates to:
  /// **'Choice'**
  String get typeChoice;

  /// No description provided for @typeTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get typeTags;

  /// No description provided for @typeUrl.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get typeUrl;

  /// No description provided for @typeChecklist.
  ///
  /// In en, this message translates to:
  /// **'Sub-items'**
  String get typeChecklist;

  /// No description provided for @viewChecklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get viewChecklist;

  /// No description provided for @viewSectioned.
  ///
  /// In en, this message translates to:
  /// **'Sections'**
  String get viewSectioned;

  /// No description provided for @viewTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get viewTimeline;

  /// No description provided for @viewGrouped.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get viewGrouped;

  /// No description provided for @viewTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get viewTable;

  /// No description provided for @viewCards.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get viewCards;

  /// No description provided for @launcherHub.
  ///
  /// In en, this message translates to:
  /// **'Lists'**
  String get launcherHub;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @launcherNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Double-tap to open, long-press to edit'**
  String get launcherNoteHint;

  /// No description provided for @hiddenValuesWarning.
  ///
  /// In en, this message translates to:
  /// **'{count} values do not fit the new type and will be kept hidden'**
  String hiddenValuesWarning(int count);

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'{name}, {count} items'**
  String itemsCount(String name, int count);

  /// No description provided for @moveHub.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get moveHub;

  /// No description provided for @errorFormatTooNew.
  ///
  /// In en, this message translates to:
  /// **'This list comes from a newer version of the app (format {version}).'**
  String errorFormatTooNew(String version);

  /// No description provided for @errorEmptyId.
  ///
  /// In en, this message translates to:
  /// **'The list has no ID.'**
  String get errorEmptyId;

  /// No description provided for @errorMissingName.
  ///
  /// In en, this message translates to:
  /// **'The list needs a name.'**
  String get errorMissingName;

  /// No description provided for @errorBadColor.
  ///
  /// In en, this message translates to:
  /// **'The color must look like #RRGGBB.'**
  String get errorBadColor;

  /// No description provided for @errorNoFields.
  ///
  /// In en, this message translates to:
  /// **'The list needs at least one field.'**
  String get errorNoFields;

  /// No description provided for @errorPrimaryCount.
  ///
  /// In en, this message translates to:
  /// **'Exactly one field must be the main field.'**
  String get errorPrimaryCount;

  /// No description provided for @errorPrimaryNotText.
  ///
  /// In en, this message translates to:
  /// **'The main field must be a text field.'**
  String get errorPrimaryNotText;

  /// No description provided for @errorDuplicateRole.
  ///
  /// In en, this message translates to:
  /// **'Only one field can have the role {role}.'**
  String errorDuplicateRole(String role);

  /// No description provided for @errorBadFieldKey.
  ///
  /// In en, this message translates to:
  /// **'Field key \"{field}\" must start with a letter and use only letters, digits or _.'**
  String errorBadFieldKey(String field);

  /// No description provided for @errorReservedFieldKey.
  ///
  /// In en, this message translates to:
  /// **'Field key \"{field}\" is reserved.'**
  String errorReservedFieldKey(String field);

  /// No description provided for @errorDuplicateFieldKey.
  ///
  /// In en, this message translates to:
  /// **'Two fields use the key \"{field}\".'**
  String errorDuplicateFieldKey(String field);

  /// No description provided for @errorMissingFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Field \"{field}\" needs a name.'**
  String errorMissingFieldLabel(String field);

  /// No description provided for @errorMissingOptions.
  ///
  /// In en, this message translates to:
  /// **'Field \"{field}\" needs at least one option.'**
  String errorMissingOptions(String field);

  /// No description provided for @errorOptionsNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Field \"{field}\": {type} fields cannot have options.'**
  String errorOptionsNotAllowed(String field, String type);

  /// No description provided for @errorDuplicateOption.
  ///
  /// In en, this message translates to:
  /// **'Field \"{field}\": the option \"{option}\" appears twice.'**
  String errorDuplicateOption(String field, String option);

  /// No description provided for @errorDefaultNotOption.
  ///
  /// In en, this message translates to:
  /// **'Field \"{field}\": the default value is not one of the options.'**
  String errorDefaultNotOption(String field);

  /// No description provided for @errorMinAboveMax.
  ///
  /// In en, this message translates to:
  /// **'Field \"{field}\": the minimum is greater than the maximum.'**
  String errorMinAboveMax(String field);

  /// No description provided for @errorConditionNotChoice.
  ///
  /// In en, this message translates to:
  /// **'Field \"{field}\" can only depend on a choice field.'**
  String errorConditionNotChoice(String field);

  /// No description provided for @errorConditionOnItself.
  ///
  /// In en, this message translates to:
  /// **'Field \"{field}\" cannot depend on itself.'**
  String errorConditionOnItself(String field);

  /// No description provided for @errorConditionNotOption.
  ///
  /// In en, this message translates to:
  /// **'Field \"{field}\": \"{value}\" is not an option of \"{target}\".'**
  String errorConditionNotOption(String field, String value, String target);

  /// No description provided for @errorRoleNeedsType.
  ///
  /// In en, this message translates to:
  /// **'Field \"{field}\": the role {role} needs the type {type}.'**
  String errorRoleNeedsType(String field, String role, String type);

  /// No description provided for @errorViewNeedsParam.
  ///
  /// In en, this message translates to:
  /// **'The {view} layout needs a field for \"{param}\".'**
  String errorViewNeedsParam(String view, String param);

  /// No description provided for @errorViewParamNotField.
  ///
  /// In en, this message translates to:
  /// **'\"{param}\": \"{field}\" is not a field of this list.'**
  String errorViewParamNotField(String param, String field);

  /// No description provided for @errorViewParamWrongType.
  ///
  /// In en, this message translates to:
  /// **'\"{param}\": \"{field}\" must be of type {types}.'**
  String errorViewParamWrongType(String param, String field, String types);

  /// No description provided for @errorChecklistNeedsCompletion.
  ///
  /// In en, this message translates to:
  /// **'The checklist layout needs a field that marks items as done.'**
  String get errorChecklistNeedsCompletion;

  /// No description provided for @errorRuleNeedsCompletion.
  ///
  /// In en, this message translates to:
  /// **'Rule \"{rule}\" needs a field that marks items as done.'**
  String errorRuleNeedsCompletion(String rule);

  /// No description provided for @errorRuleNeedsParam.
  ///
  /// In en, this message translates to:
  /// **'Rule \"{rule}\": \"{param}\" is missing.'**
  String errorRuleNeedsParam(String rule, String param);

  /// No description provided for @errorRuleParamNotField.
  ///
  /// In en, this message translates to:
  /// **'Rule \"{rule}\", \"{param}\": \"{field}\" is not a field of this list.'**
  String errorRuleParamNotField(String rule, String param, String field);

  /// No description provided for @errorRuleParamWrongType.
  ///
  /// In en, this message translates to:
  /// **'Rule \"{rule}\", \"{param}\": \"{field}\" must be of type {types}.'**
  String errorRuleParamWrongType(
    String rule,
    String param,
    String field,
    String types,
  );

  /// No description provided for @errorRuleUnknownField.
  ///
  /// In en, this message translates to:
  /// **'Rule \"{rule}\", \"{param}\": there is no field \"{field}\".'**
  String errorRuleUnknownField(String rule, String param, String field);

  /// No description provided for @errorRuleValueNotOption.
  ///
  /// In en, this message translates to:
  /// **'Rule \"{rule}\", \"{param}\": \"{value}\" is not an option of \"{field}\".'**
  String errorRuleValueNotOption(
    String rule,
    String param,
    String value,
    String field,
  );

  /// No description provided for @errorRuleParamNotOption.
  ///
  /// In en, this message translates to:
  /// **'Rule \"{rule}\": \"{param}\" must be an option of \"{field}\".'**
  String errorRuleParamNotOption(String rule, String param, String field);

  /// No description provided for @errorWrongList.
  ///
  /// In en, this message translates to:
  /// **'This item belongs to another list.'**
  String get errorWrongList;

  /// No description provided for @errorFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'\"{field}\" is required.'**
  String errorFieldRequired(String field);

  /// No description provided for @errorWrongValueType.
  ///
  /// In en, this message translates to:
  /// **'\"{field}\": the value does not fit the type {type}.'**
  String errorWrongValueType(String field, String type);

  /// No description provided for @errorValueEmpty.
  ///
  /// In en, this message translates to:
  /// **'\"{field}\" must not be empty.'**
  String errorValueEmpty(String field);

  /// No description provided for @errorBelowMin.
  ///
  /// In en, this message translates to:
  /// **'\"{field}\" must be at least {min}.'**
  String errorBelowMin(String field, String min);

  /// No description provided for @errorAboveMax.
  ///
  /// In en, this message translates to:
  /// **'\"{field}\" must be at most {max}.'**
  String errorAboveMax(String field, String max);

  /// No description provided for @errorNotAnOption.
  ///
  /// In en, this message translates to:
  /// **'\"{field}\": \"{value}\" is not one of the options.'**
  String errorNotAnOption(String field, String value);

  /// No description provided for @errorBadSubItem.
  ///
  /// In en, this message translates to:
  /// **'\"{field}\": each sub-item needs a title and a done mark.'**
  String errorBadSubItem(String field);

  /// No description provided for @errorUnknownFrequency.
  ///
  /// In en, this message translates to:
  /// **'\"{field}\": unknown repeat \"{value}\".'**
  String errorUnknownFrequency(String field, String value);

  /// No description provided for @errorCustomDaysMissing.
  ///
  /// In en, this message translates to:
  /// **'\"{field}\": a custom repeat needs a number of days above 0.'**
  String errorCustomDaysMissing(String field);

  /// No description provided for @errorOpNoField.
  ///
  /// In en, this message translates to:
  /// **'There is no field \"{field}\".'**
  String errorOpNoField(String field);

  /// No description provided for @errorFieldExists.
  ///
  /// In en, this message translates to:
  /// **'A field with the key \"{field}\" already exists.'**
  String errorFieldExists(String field);

  /// No description provided for @errorUnknownFieldType.
  ///
  /// In en, this message translates to:
  /// **'Unknown field type \"{type}\".'**
  String errorUnknownFieldType(String type);

  /// No description provided for @errorBadOp.
  ///
  /// In en, this message translates to:
  /// **'A change could not be read: {detail}'**
  String errorBadOp(String detail);

  /// No description provided for @errorListExists.
  ///
  /// In en, this message translates to:
  /// **'A list with this ID already exists.'**
  String get errorListExists;

  /// No description provided for @errorDuplicateItemId.
  ///
  /// In en, this message translates to:
  /// **'Two items have the same ID.'**
  String get errorDuplicateItemId;

  /// No description provided for @errorItemIdTaken.
  ///
  /// In en, this message translates to:
  /// **'An item\'s ID is already used by another list.'**
  String get errorItemIdTaken;

  /// No description provided for @errorItemInOtherList.
  ///
  /// In en, this message translates to:
  /// **'An item belongs to another list.'**
  String get errorItemInOtherList;

  /// No description provided for @errorBuiltinOnlyInfo.
  ///
  /// In en, this message translates to:
  /// **'Built-in lists can only change their name, icon, color and AI setting.'**
  String get errorBuiltinOnlyInfo;

  /// No description provided for @addRule.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get addRule;

  /// No description provided for @ruleKind.
  ///
  /// In en, this message translates to:
  /// **'Rule'**
  String get ruleKind;

  /// No description provided for @ruleRepeatField.
  ///
  /// In en, this message translates to:
  /// **'Repeat field'**
  String get ruleRepeatField;

  /// No description provided for @ruleMoveField.
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get ruleMoveField;

  /// No description provided for @ruleMoveFrom.
  ///
  /// In en, this message translates to:
  /// **'Move from'**
  String get ruleMoveFrom;

  /// No description provided for @ruleMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to'**
  String get ruleMoveTo;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @blankList.
  ///
  /// In en, this message translates to:
  /// **'Blank'**
  String get blankList;

  /// No description provided for @signInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Please try again.'**
  String get signInFailed;

  /// No description provided for @signInOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection. Connect to the internet to sign in.'**
  String get signInOffline;

  /// No description provided for @signOutFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-out failed. Please try again.'**
  String get signOutFailed;

  /// No description provided for @signOutCleanupFailed.
  ///
  /// In en, this message translates to:
  /// **'Signed out, but the lists saved on this device could not be deleted.'**
  String get signOutCleanupFailed;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @listChangeNotSaved.
  ///
  /// In en, this message translates to:
  /// **'A list change could not be saved and was undone.'**
  String get listChangeNotSaved;

  /// No description provided for @starterListsFailed.
  ///
  /// In en, this message translates to:
  /// **'The starter lists could not be set up.'**
  String get starterListsFailed;

  /// No description provided for @startEmpty.
  ///
  /// In en, this message translates to:
  /// **'Start empty'**
  String get startEmpty;

  /// No description provided for @errorMissingArg.
  ///
  /// In en, this message translates to:
  /// **'A change is missing \"{arg}\".'**
  String errorMissingArg(String arg);

  /// No description provided for @errorWrongArgType.
  ///
  /// In en, this message translates to:
  /// **'A change has the wrong kind of value for \"{arg}\".'**
  String errorWrongArgType(String arg);

  /// No description provided for @errorUnknownArg.
  ///
  /// In en, this message translates to:
  /// **'A change has an unknown setting \"{arg}\".'**
  String errorUnknownArg(String arg);

  /// No description provided for @errorUnknownList.
  ///
  /// In en, this message translates to:
  /// **'The list was not found.'**
  String get errorUnknownList;

  /// No description provided for @errorUnknownItem.
  ///
  /// In en, this message translates to:
  /// **'An item to change was not found in the list.'**
  String get errorUnknownItem;

  /// No description provided for @errorUnknownField.
  ///
  /// In en, this message translates to:
  /// **'\"{field}\" is not a field of this list.'**
  String errorUnknownField(String field);

  /// No description provided for @errorListChanged.
  ///
  /// In en, this message translates to:
  /// **'The list has changed since, so this cannot be undone.'**
  String get errorListChanged;

  /// No description provided for @errorAiNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'The AI may not change this list.'**
  String get errorAiNotAllowed;

  /// No description provided for @listFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get listFilterAll;

  /// No description provided for @listDoneGroup.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get listDoneGroup;

  /// No description provided for @listOpenDoneCount.
  ///
  /// In en, this message translates to:
  /// **'{open} open · {done} done'**
  String listOpenDoneCount(int open, int done);

  /// No description provided for @listItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String listItemCount(int count);

  /// No description provided for @itemSheetNew.
  ///
  /// In en, this message translates to:
  /// **'New item'**
  String get itemSheetNew;

  /// No description provided for @itemSheetEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit item'**
  String get itemSheetEdit;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get darkMode;

  /// No description provided for @homeThingsToday.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing due today} =1{1 thing today} other{{count} things today}}'**
  String homeThingsToday(int count);

  /// No description provided for @listColorName.
  ///
  /// In en, this message translates to:
  /// **'{name, select, orange{Orange} green{Green} magenta{Magenta} violet{Violet} yellow{Yellow} rose{Rose} teal{Teal} blue{Blue} other{Colour}}'**
  String listColorName(String name);

  /// No description provided for @listIconName.
  ///
  /// In en, this message translates to:
  /// **'{name, select, pending_actions{Clipboard} checklist{Checklist} shopping_cart{Shopping cart} book{Book} movie{Film} local_florist{Flower} other{List}}'**
  String listIconName(String name);

  /// No description provided for @aiBarHint.
  ///
  /// In en, this message translates to:
  /// **'Add or change'**
  String get aiBarHint;

  /// No description provided for @aiBarHintList.
  ///
  /// In en, this message translates to:
  /// **'Add to {list}'**
  String aiBarHintList(String list);

  /// No description provided for @aiBarHintNewList.
  ///
  /// In en, this message translates to:
  /// **'Describe the list'**
  String get aiBarHintNewList;

  /// No description provided for @aiSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get aiSend;

  /// No description provided for @aiBarLabel.
  ///
  /// In en, this message translates to:
  /// **'AI request'**
  String get aiBarLabel;

  /// No description provided for @aiDescribeNewList.
  ///
  /// In en, this message translates to:
  /// **'Describe a new list'**
  String get aiDescribeNewList;

  /// No description provided for @aiDescribeNewListMeta.
  ///
  /// In en, this message translates to:
  /// **'The AI picks its fields'**
  String get aiDescribeNewListMeta;

  /// No description provided for @aiNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Before your first request'**
  String get aiNoticeTitle;

  /// No description provided for @aiNoticeDeepSeek.
  ///
  /// In en, this message translates to:
  /// **'Your request, the names, descriptions and fields of your lists, and the open list, or a list your request is about, with up to 20 recent items go to DeepSeek, an AI provider that processes and stores data in China. Lists with AI turned off are never sent. Your request text is kept for about 7 days to find problems, then deleted.'**
  String get aiNoticeDeepSeek;

  /// No description provided for @aiNoticeContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get aiNoticeContinue;

  /// No description provided for @aiApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get aiApply;

  /// No description provided for @aiAddItems.
  ///
  /// In en, this message translates to:
  /// **'{list}: add {items}'**
  String aiAddItems(String list, String items);

  /// No description provided for @aiEditItems.
  ///
  /// In en, this message translates to:
  /// **'{list}: change {items}'**
  String aiEditItems(String list, String items);

  /// No description provided for @aiDeleteItems.
  ///
  /// In en, this message translates to:
  /// **'{list}: delete {items}'**
  String aiDeleteItems(String list, String items);

  /// No description provided for @aiOpAddField.
  ///
  /// In en, this message translates to:
  /// **'{list}: add the field {field}'**
  String aiOpAddField(String list, String field);

  /// No description provided for @aiOpRemoveField.
  ///
  /// In en, this message translates to:
  /// **'{list}: remove the field {field}'**
  String aiOpRemoveField(String list, String field);

  /// No description provided for @aiOpRenameField.
  ///
  /// In en, this message translates to:
  /// **'{list}: rename {field} to {label}'**
  String aiOpRenameField(String list, String field, String label);

  /// No description provided for @aiOpChangeField.
  ///
  /// In en, this message translates to:
  /// **'{list}: change the field {field}'**
  String aiOpChangeField(String list, String field);

  /// No description provided for @aiOpSetView.
  ///
  /// In en, this message translates to:
  /// **'{list}: show as {view}'**
  String aiOpSetView(String list, String view);

  /// No description provided for @aiOpBehavior.
  ///
  /// In en, this message translates to:
  /// **'{list}: change {behavior}'**
  String aiOpBehavior(String list, String behavior);

  /// No description provided for @aiOpListInfo.
  ///
  /// In en, this message translates to:
  /// **'{list}: change the name, icon or colour'**
  String aiOpListInfo(String list);

  /// No description provided for @aiHiddenValues.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 value no longer fits and is kept hidden} other{{count} values no longer fit and are kept hidden}}'**
  String aiHiddenValues(int count);

  /// No description provided for @aiNewList.
  ///
  /// In en, this message translates to:
  /// **'New list {name}: {fields}'**
  String aiNewList(String name, String fields);

  /// No description provided for @aiDoneAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to {lists}'**
  String aiDoneAdded(String lists);

  /// No description provided for @aiDoneChanged.
  ///
  /// In en, this message translates to:
  /// **'Changed {lists}'**
  String aiDoneChanged(String lists);

  /// No description provided for @aiDoneCreated.
  ///
  /// In en, this message translates to:
  /// **'Created {list}'**
  String aiDoneCreated(String list);

  /// No description provided for @aiUndone.
  ///
  /// In en, this message translates to:
  /// **'Undone'**
  String get aiUndone;

  /// No description provided for @aiDeclinedOffTopic.
  ///
  /// In en, this message translates to:
  /// **'I can only help with your lists.'**
  String get aiDeclinedOffTopic;

  /// No description provided for @aiDeclinedNotSupported.
  ///
  /// In en, this message translates to:
  /// **'That is not a change I can make.'**
  String get aiDeclinedNotSupported;

  /// No description provided for @aiRefusedAiNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'AI is turned off for this list.'**
  String get aiRefusedAiNotAllowed;

  /// No description provided for @aiRefusedOutputTooLong.
  ///
  /// In en, this message translates to:
  /// **'The answer was too long. Try a shorter request.'**
  String get aiRefusedOutputTooLong;

  /// No description provided for @aiRefusedNoValidTool.
  ///
  /// In en, this message translates to:
  /// **'The answer could not be used. Try other words.'**
  String get aiRefusedNoValidTool;

  /// No description provided for @aiRefusedDailyCount.
  ///
  /// In en, this message translates to:
  /// **'You have reached today’s limit of AI requests.'**
  String get aiRefusedDailyCount;

  /// No description provided for @aiRefusedBudget.
  ///
  /// In en, this message translates to:
  /// **'The AI is paused until tomorrow.'**
  String get aiRefusedBudget;

  /// No description provided for @aiRefusedPromptTooLong.
  ///
  /// In en, this message translates to:
  /// **'The request is too long.'**
  String get aiRefusedPromptTooLong;

  /// No description provided for @aiRefusedContextTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Your lists are too large to send.'**
  String get aiRefusedContextTooLarge;

  /// No description provided for @aiRefusedAccess.
  ///
  /// In en, this message translates to:
  /// **'This account or app may not use the AI.'**
  String get aiRefusedAccess;

  /// No description provided for @aiRefusedUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The AI is not available right now. Try again later.'**
  String get aiRefusedUnavailable;

  /// No description provided for @aiRefusedBadRequest.
  ///
  /// In en, this message translates to:
  /// **'The request could not be sent.'**
  String get aiRefusedBadRequest;

  /// No description provided for @aiInvalidAnswer.
  ///
  /// In en, this message translates to:
  /// **'The changes do not fit the list, so nothing was applied.'**
  String get aiInvalidAnswer;

  /// No description provided for @errorUndoTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This change touched too many items to be undone.'**
  String get errorUndoTooLarge;

  /// No description provided for @aiPartlyNotDone.
  ///
  /// In en, this message translates to:
  /// **'Part of the request could not be done.'**
  String get aiPartlyNotDone;

  /// No description provided for @aiRefusedProviderAccount.
  ///
  /// In en, this message translates to:
  /// **'The AI provider account needs attention: check its key or balance.'**
  String get aiRefusedProviderAccount;

  /// No description provided for @aiListOff.
  ///
  /// In en, this message translates to:
  /// **'\"{list}\" has AI turned off.'**
  String aiListOff(String list);

  /// No description provided for @aiAutoApplyOffer.
  ///
  /// In en, this message translates to:
  /// **'Apply changes like this without asking from now on? Undo stays.'**
  String get aiAutoApplyOffer;

  /// No description provided for @aiAutoApplyYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get aiAutoApplyYes;

  /// No description provided for @aiAutoApplyNo.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get aiAutoApplyNo;

  /// No description provided for @settingsAiAutoApply.
  ///
  /// In en, this message translates to:
  /// **'Apply AI changes without asking'**
  String get settingsAiAutoApply;

  /// No description provided for @aiAnswerHint.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get aiAnswerHint;

  /// No description provided for @aiAnswering.
  ///
  /// In en, this message translates to:
  /// **'Answering: {reply}'**
  String aiAnswering(String reply);

  /// No description provided for @aiNewRequest.
  ///
  /// In en, this message translates to:
  /// **'New request'**
  String get aiNewRequest;

  /// No description provided for @listDescription.
  ///
  /// In en, this message translates to:
  /// **'List description'**
  String get listDescription;

  /// No description provided for @listDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'What this list is for (optional)'**
  String get listDescriptionHint;

  /// No description provided for @errorDescriptionTooLong.
  ///
  /// In en, this message translates to:
  /// **'The description can be at most {max} characters.'**
  String errorDescriptionTooLong(String max);

  /// No description provided for @tasksDescription.
  ///
  /// In en, this message translates to:
  /// **'Things to do.'**
  String get tasksDescription;

  /// No description provided for @groceryDescription.
  ///
  /// In en, this message translates to:
  /// **'Food and household things to buy on the next shopping trip.'**
  String get groceryDescription;

  /// No description provided for @journalDescription.
  ///
  /// In en, this message translates to:
  /// **'Daily notes and thoughts, by date.'**
  String get journalDescription;

  /// No description provided for @watchReadDescription.
  ///
  /// In en, this message translates to:
  /// **'Films, shows and books to watch or read.'**
  String get watchReadDescription;

  /// No description provided for @settingsAiAsk.
  ///
  /// In en, this message translates to:
  /// **'How often the AI checks with you'**
  String get settingsAiAsk;

  /// No description provided for @aiAskMore.
  ///
  /// In en, this message translates to:
  /// **'Ask first'**
  String get aiAskMore;

  /// No description provided for @aiAskMoreHint.
  ///
  /// In en, this message translates to:
  /// **'Checks with you whenever it isn’t sure, and makes new lists only when you ask for one.'**
  String get aiAskMoreHint;

  /// No description provided for @aiAskBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get aiAskBalanced;

  /// No description provided for @aiAskBalancedHint.
  ///
  /// In en, this message translates to:
  /// **'Does clear requests right away and checks with you on vague ones.'**
  String get aiAskBalancedHint;

  /// No description provided for @aiAskLess.
  ///
  /// In en, this message translates to:
  /// **'Just do it'**
  String get aiAskLess;

  /// No description provided for @aiAskLessHint.
  ///
  /// In en, this message translates to:
  /// **'Goes with its best guess and checks only when two lists fit equally well.'**
  String get aiAskLessHint;

  /// No description provided for @errorPreviewChanged.
  ///
  /// In en, this message translates to:
  /// **'The list changed since this preview, so nothing was changed. Try again.'**
  String get errorPreviewChanged;

  /// No description provided for @errorNeedsConnection.
  ///
  /// In en, this message translates to:
  /// **'This needs a connection. Nothing was changed.'**
  String get errorNeedsConnection;

  /// No description provided for @errorOutcomeUnknown.
  ///
  /// In en, this message translates to:
  /// **'The connection is slow, so this may still go through. Check the list before trying again.'**
  String get errorOutcomeUnknown;

  /// No description provided for @errorAnswerTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That is too many changes for one request (at most 500). Nothing was changed. Try a smaller one.'**
  String get errorAnswerTooLarge;

  /// No description provided for @aiItemsUpdating.
  ///
  /// In en, this message translates to:
  /// **'Items are still updating.'**
  String get aiItemsUpdating;

  /// No description provided for @aiListOffOffer.
  ///
  /// In en, this message translates to:
  /// **'\"{list}\" has AI turned off. Send for your other lists?'**
  String aiListOffOffer(String list);

  /// No description provided for @aiListOffSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get aiListOffSend;

  /// No description provided for @itemsNotUpdated.
  ///
  /// In en, this message translates to:
  /// **'Some items in this list could not be updated yet. The app will try again next time it opens.'**
  String get itemsNotUpdated;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeFollowPhone.
  ///
  /// In en, this message translates to:
  /// **'Follow the phone'**
  String get themeFollowPhone;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @preferencesHint.
  ///
  /// In en, this message translates to:
  /// **'These follow your account to every phone.'**
  String get preferencesHint;

  /// No description provided for @preferencesLists.
  ///
  /// In en, this message translates to:
  /// **'Lists'**
  String get preferencesLists;

  /// No description provided for @preferencesItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get preferencesItems;

  /// No description provided for @preferencesAi.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get preferencesAi;

  /// No description provided for @preferencesGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get preferencesGeneral;

  /// No description provided for @preferencesListOrder.
  ///
  /// In en, this message translates to:
  /// **'List order'**
  String get preferencesListOrder;

  /// No description provided for @preferencesListOrderLastUsed.
  ///
  /// In en, this message translates to:
  /// **'Last used'**
  String get preferencesListOrderLastUsed;

  /// No description provided for @preferencesListOrderMine.
  ///
  /// In en, this message translates to:
  /// **'My order'**
  String get preferencesListOrderMine;

  /// No description provided for @preferencesListOrderAz.
  ///
  /// In en, this message translates to:
  /// **'A to Z'**
  String get preferencesListOrderAz;

  /// No description provided for @preferencesStartScreen.
  ///
  /// In en, this message translates to:
  /// **'Start screen'**
  String get preferencesStartScreen;

  /// No description provided for @preferencesStartLastList.
  ///
  /// In en, this message translates to:
  /// **'Last open list'**
  String get preferencesStartLastList;

  /// No description provided for @preferencesTicked.
  ///
  /// In en, this message translates to:
  /// **'Ticked items'**
  String get preferencesTicked;

  /// No description provided for @preferencesTickedMove.
  ///
  /// In en, this message translates to:
  /// **'Move to Done'**
  String get preferencesTickedMove;

  /// No description provided for @preferencesTickedStay.
  ///
  /// In en, this message translates to:
  /// **'Stay in place'**
  String get preferencesTickedStay;

  /// No description provided for @preferencesTickedHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get preferencesTickedHide;

  /// No description provided for @preferencesConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm before deleting'**
  String get preferencesConfirmDelete;

  /// No description provided for @preferencesShowAiBar.
  ///
  /// In en, this message translates to:
  /// **'Show the AI bar'**
  String get preferencesShowAiBar;

  /// No description provided for @preferencesVibration.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get preferencesVibration;

  /// No description provided for @preferencesTimeFormat.
  ///
  /// In en, this message translates to:
  /// **'Time format'**
  String get preferencesTimeFormat;

  /// No description provided for @preferencesFollowLanguage.
  ///
  /// In en, this message translates to:
  /// **'Follow the language'**
  String get preferencesFollowLanguage;

  /// No description provided for @preferencesTime12.
  ///
  /// In en, this message translates to:
  /// **'12-hour'**
  String get preferencesTime12;

  /// No description provided for @preferencesTime24.
  ///
  /// In en, this message translates to:
  /// **'24-hour'**
  String get preferencesTime24;

  /// No description provided for @preferencesWeekStart.
  ///
  /// In en, this message translates to:
  /// **'Week starts on'**
  String get preferencesWeekStart;

  /// No description provided for @preferencesMonday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get preferencesMonday;

  /// No description provided for @preferencesSunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get preferencesSunday;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'ja',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
