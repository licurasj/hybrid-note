import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'app/account_preferences.dart';
import 'app/app_settings.dart';
import 'app/app_theme.dart';
import 'app/date_preferences.dart';
import 'app/home_cards.dart';
import 'app/hybrid_note_app.dart';
import 'app/list_order.dart';
import 'app/preferences_screen.dart';
import 'app/starter_note.dart';
import 'app_colors.dart';
import 'home_cards_view.dart';
import 'l10n/generated/app_localizations.dart';
import 'lists/generic_item_dialog.dart';
import 'lists/list_catalog.dart';
import 'lists/list_catalog_builder.dart';
import 'lists/list_definition.dart';
import 'lists/list_icons.dart';
import 'lists/list_item.dart';
import 'lists/list_labels.dart';
import 'lists/list_rules.dart';
import 'lists/list_store.dart';
import 'lists/list_vocabulary.dart';

// One open item whose reminder date is today or earlier.
class HomeDueItem {
  const HomeDueItem({
    required this.definition,
    required this.item,
    required this.due,
    required this.hasTime,
  });

  final ListDefinition definition;
  final ListItem item;
  final DateTime due;
  // Date-and-time fields show their time; date fields only their day.
  final bool hasTime;
}

// What is due today or overdue across every list, earliest first: open items
// (not marked done) whose reminder-role date falls before tomorrow. Lists
// without a reminder field have nothing due.
List<HomeDueItem> homeDueItems(ListCatalog catalog, DateTime now) {
  final DateTime tomorrow = DateTime(now.year, now.month, now.day + 1);
  final List<HomeDueItem> due = [];
  for (final ListDefinition definition in catalog.definitions) {
    final FieldDefinition? field = definition.fieldWithRole(FieldRole.reminder);
    if (field == null) {
      continue;
    }
    for (final ListItem item in catalog.itemsOf(definition.id)) {
      final Object? raw = item[field.key];
      final DateTime? date =
          raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
      if (date == null ||
          !date.isBefore(tomorrow) ||
          ListRules.isCompleted(definition, item)) {
        continue;
      }
      due.add(
        HomeDueItem(
          definition: definition,
          item: item,
          due: date,
          hasTime: field.type == FieldType.dateTime,
        ),
      );
    }
  }
  due.sort((a, b) => a.due.compareTo(b.due));
  return due;
}

// The home behind the hub (Q-20 A, Q-65, docs/AESTHETICS.md Layout): a fixed
// header with the weekday very large, the date with "N things today" and the
// blue settings button, and scrolling behind it what is due today or overdue
// across lists, then the list cards. Lists come from the ListStore catalog;
// nothing keys on list ids.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.onOpenList,
    this.recentLists,
    this.returned,
  });

  final ValueChanged<String>? onOpenList;
  // The phone's Last used order, newest first (Q-49).
  final List<String> Function()? recentLists;
  // Fires on coming back to home from a list.
  final Listenable? returned;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// The cards hold still once worked out, with only the items inside them
// updating, until coming back from a list, a new start or a pull down (Q-74).
// A change to the account's choices that this screen did not make also counts,
// as they arrive after the first frame on a new phone or from another phone.
class _HomeScreenState extends State<HomeScreen> {
  List<String>? _pinned;
  List<String> _suggested = const [];
  // Unpinned here, and showing an unfilled pin until the next refresh (Q-65).
  final Set<String> _unfilled = {};
  String? _workedOutFrom;

  @override
  void initState() {
    super.initState();
    widget.returned?.addListener(_refresh);
  }

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (old.returned != widget.returned) {
      old.returned?.removeListener(_refresh);
      widget.returned?.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.returned?.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() => _pinned = null);
    }
  }

  Future<void> _pullDown() async {
    await context.read<ListStore>().refresh();
    _refresh();
  }

  static String _choices(AccountPreferences preferences) => jsonEncode([
    preferences.homeSuggestions,
    preferences.homePins,
    preferences.homeRemoved,
    preferences.homeOrder,
    preferences.homeArranged,
    preferences.listOrder.wire,
    preferences.myListOrder,
  ]);

  void _workOutCards(
    ListCatalog catalog,
    AccountPreferences preferences,
    ListLabels labels,
    DateTime now,
  ) {
    final String choices = _choices(preferences);
    if (_pinned != null &&
        _workedOutFrom == choices &&
        (_pinned!.isNotEmpty || _suggested.isNotEmpty)) {
      return;
    }
    final List<String> dialOrder = [
      for (final ListDefinition list in orderLists(
        catalog.definitions,
        order: preferences.listOrder,
        myOrder: preferences.myListOrder,
        recent: widget.recentLists?.call() ?? const [],
        nameOf: labels.listName,
      ))
        list.id,
    ];
    final List<String> pinned = homePinnedOrder(
      pins: preferences.homePins,
      dialOrder: dialOrder,
      homeOrder: preferences.homeOrder,
      homeArranged: preferences.homeArranged,
    );
    _pinned = pinned;
    _suggested = [
      for (final ListDefinition list
          in chooseHomeCards(
            catalog,
            pinnedOrder: pinned,
            removed: preferences.homeRemoved,
            showSuggestions: preferences.homeSuggestions,
            now: now,
          ).suggested)
        list.id,
    ];
    _unfilled.clear();
    _workedOutFrom = choices;
  }

  // The pin on a card: the card stays, and a second tap puts it back in place.
  void _tapPin(String listId, ListCatalog catalog) {
    final AccountPreferencesCubit cubit = context
        .read<AccountPreferencesCubit>();
    setState(() {
      if (_unfilled.remove(listId)) {
        cubit.pinToHome(
          listId,
          existing: [for (final list in catalog.definitions) list.id],
          keepPlace: true,
        );
      } else {
        _unfilled.add(listId);
        cubit.unpinFromHome(listId);
      }
      _workedOutFrom = _choices(cubit.state);
    });
  }

  Widget _card(ListCatalog catalog, String listId, {required bool suggested}) {
    final ListDefinition? definition = catalog.definition(listId);
    if (definition == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: HomeListCard(
        definition: definition,
        openItems: homeTopItems(definition, catalog.itemsOf(listId)),
        pinned: suggested ? null : !_unfilled.contains(listId),
        onTap: () => widget.onOpenList?.call(listId),
        onPin: suggested ? null : () => _tapPin(listId, catalog),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final ListLabels labels = ListLabels(loc);
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final AppTypography type = AppTypography.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final AccountPreferences preferences = context.watchAccountPreferences;
    final double top = MediaQuery.paddingOf(context).top;
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    // What the fixed header takes: its padding, the button, the weekday and the
    // date line, with room to spare under them.
    final double headerHeight =
        top + 8 + 40 + 20 + 76 + 10 + scaler.scale(15) * 1.5 + 8;

    Widget hairline() => Divider(color: neutrals.line, height: 1);

    Widget row(HomeDueItem due) {
      final ListDefinition definition = due.definition;
      final Object? title = due.item[
          definition.fields
              .firstWhere(
                (field) => field.primary,
                orElse: () => definition.fields.first,
              )
              .key];
      final bool overdue = due.due.isBefore(today);
      final String when = overdue
          ? DateFormat.MMMd(locale).format(due.due)
          : due.hasTime
              ? timeFormat(locale, preferences.timeFormat).format(due.due)
              : '';
      return InkWell(
        key: ValueKey('home-due-${due.item.id}'),
        onTap: () => widget.onOpenList?.call(definition.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              _EclipseDot(
                color: listColor(definition.color, brightness: brightness),
                ring: neutrals.text,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title is String ? title : '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.row,
                    ),
                    Text(
                      labels.listName(definition),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.meta,
                    ),
                  ],
                ),
              ),
              if (when.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(when, style: type.meta),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: ListCatalogBuilder(
        builder: (context, catalog) {
          final List<HomeDueItem> due = homeDueItems(catalog, now);
          _workOutCards(catalog, preferences, labels, now);
          return Stack(
            children: [
              Positioned.fill(
                child: RefreshIndicator(
                  onRefresh: _pullDown,
                  color: AppColors.appBlue,
                  edgeOffset: headerHeight,
                  child: ListView(
                    key: const ValueKey('home-scroll'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      AppShapes.sideMargin,
                      headerHeight,
                      AppShapes.sideMargin,
                      // Room so the hub does not cover the last card.
                      140,
                    ),
                    children: [
                      if (catalog.definitions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 28),
                          child: StarterNote(),
                        ),
                      if (preferences.homeContent.showsDue &&
                          due.isNotEmpty) ...[
                        const SizedBox(height: 40),
                        Text(loc.today.toUpperCase(), style: type.sectionLabel),
                        const SizedBox(height: 10),
                        hairline(),
                        for (final HomeDueItem item in due) ...[
                          row(item),
                          hairline(),
                        ],
                      ],
                      if (preferences.homeContent.showsCards &&
                          (_pinned!.isNotEmpty || _suggested.isNotEmpty)) ...[
                        const SizedBox(height: 40),
                        for (final String listId in _pinned!)
                          _card(catalog, listId, suggested: false),
                        for (final String listId in _suggested)
                          _card(catalog, listId, suggested: true),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppShapes.sideMargin,
                    8 + top,
                    AppShapes.sideMargin,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: IconButton(
                          key: const ValueKey('settings'),
                          tooltip: loc.settings,
                          onPressed: () => showSettingsSheet(context),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.appBlue,
                            foregroundColor: AppColors.onAppBlue,
                            fixedSize: const Size(40, 40),
                            minimumSize: const Size(40, 40),
                          ),
                          icon: const Icon(Icons.settings_outlined, size: 20),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // The weekday stays whole: long names shrink to the width.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          DateFormat.EEEE(locale).format(now),
                          key: const ValueKey('home-weekday'),
                          style: type.screenTitle.copyWith(
                            fontSize: 76,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${DateFormat.MMMMd(locale).format(now)} · '
                        '${loc.homeThingsToday(due.length)}',
                        key: const ValueKey('home-date'),
                        style: type.meta.copyWith(fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// A list-colour dot with a ring in the text colour overlapping it, shifted up
// and right: the eclipse at its smallest.
class _EclipseDot extends StatelessWidget {
  const _EclipseDot({required this.color, required this.ring});

  final Color color;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    const double size = 14;
    return SizedBox(
      width: 22,
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 4,
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          Positioned(
            left: 5,
            top: 1,
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// The settings sheet: theme and language (this phone), the two AI choices, the
// way to Preferences, and the account (email, Log out).
Future<void> showSettingsSheet(BuildContext context) {
  return showSlideUpSheet<void>(
    context: context,
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  String _languageLabel(AppLocalizations loc, String? code) {
    switch (code) {
      case 'en':
        return loc.languageEnglish;
      case 'zh':
        return loc.languageChinese;
      case 'ja':
        return loc.languageJapanese;
      case 'fr':
        return loc.languageFrench;
      case 'es':
        return loc.languageSpanish;
      case 'de':
        return loc.languageGerman;
      case null:
      default:
        return loc.languageSystem;
    }
  }

  Future<void> _chooseTheme(BuildContext context, AppSettings settings) async {
    final AppLocalizations loc = AppLocalizations.of(context);
    final AppSettingsCubit cubit = context.read<AppSettingsCubit>();
    final ThemeMode? mode = await showChoiceSheet<ThemeMode>(
      context,
      title: loc.theme,
      selected: settings.themeMode,
      choices: [
        (value: ThemeMode.system, label: loc.themeFollowPhone),
        (value: ThemeMode.light, label: loc.themeLight),
        (value: ThemeMode.dark, label: loc.themeDark),
      ],
    );
    if (mode != null) {
      await cubit.setThemeMode(mode);
    }
  }

  Future<void> _showLanguageDialog(
    BuildContext context,
    AppSettings settings,
  ) async {
    final AppLocalizations loc = AppLocalizations.of(context);
    final AppNeutrals neutrals = AppColors.neutrals(Theme.of(context).brightness);

    final List<({String? code, String label, String subtitle})> options = [
      (code: null, label: loc.languageSystem, subtitle: loc.languageFollowsDevice),
      (code: 'en', label: loc.languageEnglish, subtitle: 'English'),
      (code: 'zh', label: loc.languageChinese, subtitle: 'Chinese'),
      (code: 'ja', label: loc.languageJapanese, subtitle: 'Japanese'),
      (code: 'fr', label: loc.languageFrench, subtitle: 'French'),
      (code: 'es', label: loc.languageSpanish, subtitle: 'Spanish'),
      (code: 'de', label: loc.languageGerman, subtitle: 'German'),
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(loc.chooseLanguage),
          // As tall as the languages need; the dialog limits it on a small
          // screen, and then the bar shows there are more.
          content: SizedBox(
            width: 420,
            child: ScrollbarTheme(
              data: ScrollbarThemeData(
                thumbColor: WidgetStatePropertyAll(neutrals.muted),
                thickness: const WidgetStatePropertyAll(4),
                radius: const Radius.circular(2),
              ),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  primary: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final option in options)
                        ListTile(
                          selected: settings.localeCode == option.code,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(
                            settings.localeCode == option.code
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          title: Text(option.label),
                          subtitle: Text(option.subtitle),
                          onTap: () {
                            context.read<AppSettingsCubit>().setLocaleCode(option.code);
                            Navigator.of(dialogContext).pop();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text(loc.cancel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final AppTypography type = AppTypography.of(context);
    final SignedInAccount account = context.read<SignedInAccount>();

    String themeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => loc.themeFollowPhone,
      ThemeMode.light => loc.themeLight,
      ThemeMode.dark => loc.themeDark,
    };

    Widget hairline() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppShapes.sideMargin),
          child: Divider(color: neutrals.line, height: 1),
        );

    Widget row({
      required Key key,
      required IconData icon,
      required Widget label,
      Widget? trailing,
      VoidCallback? onTap,
    }) {
      return InkWell(
        key: key,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: AppShapes.sideMargin,
            vertical: 6,
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: neutrals.text),
              const SizedBox(width: 14),
              Expanded(child: label),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                // At the right edge; a long value wraps past half the width.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width / 2,
                  ),
                  child: trailing,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return BlocBuilder<AppSettingsCubit, AppSettings>(
      builder: (context, settings) {
        // The two AI choices stay here and sync with the account (Q-48).
        final AccountPreferences synced = context.watchAccountPreferences;
        final AccountPreferencesCubit preferences = context
            .read<AccountPreferencesCubit>();
        return Semantics(
          label: loc.settings,
          explicitChildNodes: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: neutrals.ground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppShapes.sheetRadius),
              ),
              boxShadow: AppShadows.floating(brightness),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(top: 10, bottom: 14),
                          decoration: BoxDecoration(
                            color: neutrals.line,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppShapes.sideMargin,
                          0,
                          AppShapes.sideMargin,
                          12,
                        ),
                        child: Text(loc.settings, style: type.screenTitle),
                      ),
                      hairline(),
                      row(
                        key: const ValueKey('settings-theme'),
                        icon: Icons.dark_mode_outlined,
                        label: Text(loc.theme, style: type.row),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                themeLabel(settings.themeMode),
                                style: type.meta.copyWith(fontSize: 15),
                              ),
                            ),
                            Icon(Icons.chevron_right, color: neutrals.muted),
                          ],
                        ),
                        onTap: () => _chooseTheme(context, settings),
                      ),
                      hairline(),
                      row(
                        key: const ValueKey('settings-language'),
                        icon: Icons.language,
                        label: Text(loc.language, style: type.row),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _languageLabel(loc, settings.localeCode),
                                style: type.meta.copyWith(fontSize: 15),
                              ),
                            ),
                            Icon(Icons.chevron_right, color: neutrals.muted),
                          ],
                        ),
                        onTap: () => _showLanguageDialog(context, settings),
                      ),
                      hairline(),
                      // One node for a screen reader: the switch with its name.
                      MergeSemantics(
                        child: row(
                          key: const ValueKey('settings-ai-auto-apply'),
                          icon: Icons.check_circle_outline,
                          label: Text(loc.settingsAiAutoApply, style: type.row),
                          trailing: Switch(
                            value: synced.aiAutoApply,
                            activeTrackColor: AppColors.appBlue,
                            onChanged: preferences.setAiAutoApply,
                          ),
                          onTap: () =>
                              preferences.setAiAutoApply(!synced.aiAutoApply),
                        ),
                      ),
                      hairline(),
                      Padding(
                        key: const ValueKey('settings-ai-ask'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppShapes.sideMargin,
                        ),
                        child: AiAskSlider(
                          level: synced.aiAskLevel,
                          onChanged: preferences.setAiAskLevel,
                        ),
                      ),
                      row(
                        key: const ValueKey('settings-preferences'),
                        icon: Icons.tune,
                        label: Text(loc.preferences, style: type.row),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: neutrals.muted,
                        ),
                        // Above the shell, like the list editor: no hub and
                        // no AI bar on it. Back comes back to this sheet.
                        onTap: () =>
                            Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const PreferencesScreen(),
                              ),
                            ),
                      ),
                      hairline(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppShapes.sideMargin,
                          26,
                          AppShapes.sideMargin,
                          8,
                        ),
                        child: Text(
                          loc.account.toUpperCase(),
                          style: type.sectionLabel,
                        ),
                      ),
                      hairline(),
                      row(
                        key: const ValueKey('settings-account'),
                        icon: Icons.account_circle_outlined,
                        label: Text(
                          account.user.email ?? loc.account,
                          key: const ValueKey('account-email'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.row,
                        ),
                        trailing: TextButton(
                          key: const ValueKey('sign-out'),
                          onPressed: () {
                            // Close the sheet first; signing out replaces the
                            // whole app with the sign-in screen.
                            Navigator.of(context).pop();
                            account.signOut();
                          },
                          child: Text(loc.logOut),
                        ),
                      ),
                      hairline(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
