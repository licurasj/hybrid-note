import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app_colors.dart';
import '../l10n/generated/app_localizations.dart';
import '../lists/generic_item_dialog.dart';
import '../lists/list_catalog.dart';
import '../lists/list_definition.dart';
import '../lists/list_editor_style.dart';
import '../lists/list_store.dart';
import '../lists/list_vocabulary.dart';
import 'account_preferences.dart';
import 'list_order.dart';
import 'app_theme.dart';
import 'settings_controls.dart';

// Opens [title]'s choices as a slide-up sheet with [selected] marked, and gives
// back the one tapped (null when the sheet is dismissed).
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required T selected,
  required List<({T value, String label})> choices,
}) {
  return showSlideUpSheet<T>(
    context: context,
    builder: (_) =>
        _ChoiceSheet<T>(title: title, selected: selected, choices: choices),
  );
}

class _ChoiceSheet<T> extends StatelessWidget {
  const _ChoiceSheet({
    required this.title,
    required this.selected,
    required this.choices,
  });

  final String title;
  final T selected;
  final List<({T value, String label})> choices;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final AppTypography type = AppTypography.of(context);

    return Semantics(
      label: title,
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
                    child: Text(title, style: type.screenTitle),
                  ),
                  for (final ({T value, String label}) choice in choices) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppShapes.sideMargin,
                      ),
                      child: Divider(color: neutrals.line, height: 1),
                    ),
                    Semantics(
                      selected: choice.value == selected,
                      inMutuallyExclusiveGroup: true,
                      child: InkWell(
                        key: ValueKey('choice-${choice.value}'),
                        onTap: () => Navigator.of(context).pop(choice.value),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 56),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppShapes.sideMargin,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                choice.value == selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 22,
                                color: neutrals.text,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(choice.label, style: type.row),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Preferences, in groups (T-21 unit 2): everything here follows the account
// (Q-48 A). What was in Settings before stays there (owner, 2026-11-05): theme
// and language, and the two AI choices, which sync all the same.
class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final EditorLook look = EditorLook.of(context);
    final AccountPreferences preferences = context
        .watch<AccountPreferencesCubit>()
        .state;
    final AccountPreferencesCubit cubit = context
        .read<AccountPreferencesCubit>();
    // For the lines saying how many lists have their own choice, kept up to
    // date while lists sync with the page open.
    return _LiveLists(
      builder: (context, lists) =>
          _page(context, loc, look, preferences, cubit, lists),
    );
  }

  Widget _page(
    BuildContext context,
    AppLocalizations loc,
    EditorLook look,
    AccountPreferences preferences,
    AccountPreferencesCubit cubit,
    List<ListDefinition> lists,
  ) {
    final bool cards = preferences.homeContent.showsCards;
    final bool sameAsDial =
        preferences.homeListOrder == HomeListOrder.sameAsDial;
    // A choice's own line only while home has its own order to pick.
    final bool homeLines = cards && !sameAsDial;
    return Scaffold(
      appBar: AppBar(),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppShapes.sideMargin,
          0,
          AppShapes.sideMargin,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(loc.preferences, style: look.type.screenTitle),
            const SizedBox(height: 4),
            Text(loc.preferencesHint, style: look.type.meta),
            // T-24 (Q-111): grouped by where in the app a setting acts. Every
            // row is always there; one that does not apply now is greyed with
            // a line saying why (Q-113), so nothing below it moves.
            look.section(loc.home),
            SettingButtonsRow<StartScreen>(
              key: const ValueKey('preferences-start-screen'),
              label: loc.preferencesStartScreen,
              selected: preferences.startScreen,
              line: loc.preferencesStartScreenLine,
              choices: [
                choice(StartScreen.home, loc.home),
                choice(StartScreen.lastOpenList, loc.preferencesStartLastList),
              ],
              onChanged: cubit.setStartScreen,
            ),
            SettingOptionList<HomeContent>(
              key: const ValueKey('preferences-home-content'),
              label: loc.preferencesHomeContent,
              selected: preferences.homeContent,
              choices: [
                choice(HomeContent.both, loc.preferencesHomeContentBoth),
                choice(HomeContent.cards, loc.preferencesHomeContentCards),
                choice(HomeContent.dueToday, loc.preferencesHomeContentDue),
              ],
              onChanged: cubit.setHomeContent,
            ),
            // It means nothing without cards, and keeps its value meanwhile.
            SettingSwitchRow(
              key: const ValueKey('preferences-home-suggestions'),
              label: loc.preferencesHomeSuggestions,
              value: preferences.homeSuggestions,
              line: !cards
                  ? loc.preferencesOnlyWithCards
                  : preferences.homeSuggestions
                  ? loc.preferencesSuggestionsLine
                  : loc.preferencesSuggestionsOffLine,
              onChanged: cards ? cubit.setHomeSuggestions : null,
            ),
            look.section(loc.preferencesListsAndDial),
            SettingButtonsRow<ListOrder>(
              key: const ValueKey('preferences-list-order'),
              label: loc.preferencesListOrder,
              selected: preferences.listOrder,
              line: loc.preferencesDialOrderLine,
              choices: [
                choice(ListOrder.lastUsed, loc.preferencesListOrderLastUsed),
                choice(ListOrder.alphabetical, loc.preferencesListOrderAz),
                choice(ListOrder.myOrder, loc.preferencesListOrderMine),
              ],
              onChanged: cubit.setListOrder,
            ),
            // Right under the dial's, the same three choices, and under them
            // whether home follows the dial (Q-108; a switch since the owner's
            // note of 2026-11-09). While it does, the choices show the dial's,
            // greyed. A drag on home turns it off and picks My order. It all
            // means nothing without cards, and keeps its value meanwhile.
            SettingButtonsRow<HomeListOrder>(
              key: const ValueKey('preferences-home-list-order'),
              label: loc.preferencesHomeListOrder,
              selected: sameAsDial
                  ? HomeListOrder.ofDial(preferences.listOrder)
                  : preferences.homeListOrder,
              enabled: cards && !sameAsDial,
              line: !cards
                  ? loc.preferencesOnlyWithCards
                  : sameAsDial
                  ? loc.preferencesHomeOrderFollowing
                  : null,
              choices: [
                choice(
                  HomeListOrder.lastUsed,
                  loc.preferencesListOrderLastUsed,
                  line: homeLines ? loc.preferencesHomeOrderLastUsedLine : null,
                ),
                choice(
                  HomeListOrder.alphabetical,
                  loc.preferencesListOrderAz,
                  line: homeLines ? loc.preferencesHomeOrderAzLine : null,
                ),
                choice(
                  HomeListOrder.myOrder,
                  loc.preferencesListOrderMine,
                  line: homeLines ? loc.preferencesHomeOrderMineLine : null,
                ),
              ],
              onChanged: cubit.setHomeListOrder,
              sub: SettingSubSwitch(
                key: const ValueKey('preferences-home-same-as-dial'),
                label: loc.preferencesHomeListOrderSame,
                value: sameAsDial,
                line: sameAsDial
                    ? loc.preferencesHomeOrderSameLine
                    : loc.preferencesHomeOrderOwnLine,
                onChanged: cards
                    ? (follow) => cubit.setHomeFollowsDial(
                        follow,
                        dialOrder: [
                          for (final ListDefinition list in orderLists(
                            lists,
                            order: ListOrder.myOrder,
                            myOrder: preferences.myListOrder,
                            recent: const [],
                            nameOf: (list) => list.id,
                          ))
                            list.id,
                        ],
                      )
                    : null,
              ),
            ),
            look.section(loc.preferencesItems),
            SettingOptionList<TickedItems>(
              key: const ValueKey('preferences-ticked-items'),
              label: loc.preferencesTicked,
              selected: preferences.tickedItems,
              choices: tickedItemsChoices(loc),
              onChanged: cubit.setTickedItems,
              // Lasting, on by default (Q-117): off, every list follows the
              // choice above and keeps its own for when it is on again.
              sub: SettingSubSwitch(
                key: const ValueKey('preferences-lists-own-ticked'),
                label: loc.preferencesListsOwn,
                value: preferences.listsOwnTickedItems,
                line: preferences.listsOwnTickedItems
                    ? loc.preferencesListsOwnCount(
                        // Only lists with a tick use their choice.
                        lists
                            .where(
                              (list) =>
                                  list.ownTickedItems != null &&
                                  list.fieldWithRole(FieldRole.completion) !=
                                      null,
                            )
                            .length,
                      )
                    : loc.preferencesListsOwnOff,
                onChanged: cubit.setListsOwnTickedItems,
              ),
            ),
            SettingSwitchRow(
              key: const ValueKey('preferences-confirm-delete'),
              label: loc.preferencesConfirmDelete,
              value: preferences.confirmDelete,
              line: loc.preferencesConfirmDeleteLine,
              onChanged: cubit.setConfirmDelete,
              sub: SettingSubSwitch(
                key: const ValueKey('preferences-lists-own-confirm'),
                label: loc.preferencesListsOwn,
                value: preferences.listsOwnConfirmDelete,
                line: preferences.listsOwnConfirmDelete
                    ? loc.preferencesListsOwnCount(
                        lists
                            .where((list) => list.ownConfirmDelete != null)
                            .length,
                      )
                    : loc.preferencesListsOwnOff,
                onChanged: cubit.setListsOwnConfirmDelete,
              ),
            ),
            look.section(loc.preferencesAi),
            SettingSwitchRow(
              key: const ValueKey('preferences-show-ai-bar'),
              label: loc.preferencesShowAiBar,
              value: preferences.showAiBar,
              // A line either way, so nothing below moves when it flips.
              line: preferences.showAiBar
                  ? loc.preferencesAiBarOnLine
                  : loc.preferencesAiBarOffLine,
              onChanged: cubit.setShowAiBar,
            ),
            look.section(loc.preferencesGeneral),
            SettingButtonsRow<TimeFormat>(
              key: const ValueKey('preferences-time-format'),
              label: loc.preferencesTimeFormat,
              selected: preferences.timeFormat,
              choices: [
                choice(
                  TimeFormat.followLanguage,
                  loc.preferencesFollowLanguage,
                ),
                choice(TimeFormat.h12, loc.preferencesTime12),
                choice(TimeFormat.h24, loc.preferencesTime24),
              ],
              onChanged: cubit.setTimeFormat,
            ),
            SettingButtonsRow<WeekStart>(
              key: const ValueKey('preferences-week-start'),
              label: loc.preferencesWeekStart,
              selected: preferences.weekStart,
              line: loc.preferencesWeekStartLine,
              choices: [
                choice(WeekStart.followLanguage, loc.preferencesFollowLanguage),
                choice(WeekStart.monday, loc.preferencesMonday),
                choice(WeekStart.sunday, loc.preferencesSunday),
              ],
              onChanged: cubit.setWeekStart,
            ),
            SettingSwitchRow(
              key: const ValueKey('preferences-vibration'),
              label: loc.preferencesVibration,
              value: preferences.vibration,
              onChanged: cubit.setVibration,
            ),
          ],
        ),
      ),
    );
  }
}

// The Ticked items choices with what each does (Q-109), for Preferences and
// the list editor.
List<SettingChoice<TickedItems>> tickedItemsChoices(AppLocalizations loc) => [
  choice(
    TickedItems.moveToDone,
    loc.preferencesTickedMove,
    line: loc.preferencesTickedMoveLine,
  ),
  choice(
    TickedItems.stayInPlace,
    loc.preferencesTickedStay,
    line: loc.preferencesTickedStayLine,
  ),
  choice(
    TickedItems.hide,
    loc.preferencesTickedHide,
    line: loc.preferencesTickedHideLine,
  ),
  choice(
    TickedItems.clearAtOnce,
    loc.preferencesTickedClear,
    line: loc.preferencesTickedClearLine,
  ),
];

// How often the AI checks with you (Q-43): a slider from asking to just doing
// it, with what the stop means under it.
class AiAskSlider extends StatelessWidget {
  const AiAskSlider({super.key, required this.level, required this.onChanged});

  final AiAskLevel level;
  final ValueChanged<AiAskLevel> onChanged;

  static String _label(AppLocalizations loc, AiAskLevel level) =>
      switch (level) {
        AiAskLevel.more => loc.aiAskMore,
        AiAskLevel.balanced => loc.aiAskBalanced,
        AiAskLevel.less => loc.aiAskLess,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final EditorLook look = EditorLook.of(context);
    final AppNeutrals neutrals = look.neutrals;

    return look.hairline(
      child: Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, size: 22, color: neutrals.text),
                const SizedBox(width: 14),
                Expanded(child: Text(loc.settingsAiAsk, style: look.type.row)),
              ],
            ),
            // Styled like the switches: a thick track as tall as theirs, a
            // round knob, and the settings blue (owner, 2026-11-04).
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 32,
                activeTrackColor: AppColors.appBlue,
                inactiveTrackColor: neutrals.line,
                thumbColor: neutrals.ground,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 12,
                  elevation: 1,
                  pressedElevation: 2,
                ),
                trackShape: const RoundedRectSliderTrackShape(),
                tickMarkShape: const RoundSliderTickMarkShape(
                  tickMarkRadius: 3,
                ),
                activeTickMarkColor: AppColors.onAppBlue.withValues(
                  alpha: 0.35,
                ),
                inactiveTickMarkColor: neutrals.muted,
                overlayColor: AppColors.appBlue.withValues(alpha: 0.18),
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: Slider(
                key: const ValueKey('settings-ai-ask-slider'),
                value: level.index.toDouble(),
                max: AiAskLevel.values.length - 1,
                divisions: AiAskLevel.values.length - 1,
                label: _label(loc, level),
                semanticFormatterCallback: (value) =>
                    _label(loc, AiAskLevel.values[value.round()]),
                onChanged: (value) =>
                    onChanged(AiAskLevel.values[value.round()]),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A third each, so a long translation wraps under its own stop.
                for (final AiAskLevel stop in AiAskLevel.values)
                  Expanded(
                    child: Text(
                      _label(loc, stop),
                      textAlign: switch (stop) {
                        AiAskLevel.more => TextAlign.start,
                        AiAskLevel.balanced => TextAlign.center,
                        AiAskLevel.less => TextAlign.end,
                      },
                      style: look.type.meta.copyWith(
                        color: stop == level ? neutrals.text : neutrals.muted,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              switch (level) {
                AiAskLevel.more => loc.aiAskMoreHint,
                AiAskLevel.balanced => loc.aiAskBalancedHint,
                AiAskLevel.less => loc.aiAskLessHint,
              },
              key: const ValueKey('settings-ai-ask-hint'),
              style: look.type.meta,
            ),
          ],
        ),
      ),
    );
  }
}

// The lists as they are now, rebuilt whenever they change.
class _LiveLists extends StatefulWidget {
  const _LiveLists({required this.builder});

  final Widget Function(BuildContext context, List<ListDefinition> lists)
  builder;

  @override
  State<_LiveLists> createState() => _LiveListsState();
}

class _LiveListsState extends State<_LiveLists> {
  StreamSubscription<ListCatalog>? _watch;
  List<ListDefinition> _lists = const [];

  @override
  void initState() {
    super.initState();
    final ListStore? store = context.read<ListStore?>();
    _lists = store?.current.definitions ?? const [];
    _watch = store?.watch().listen((catalog) {
      if (mounted) {
        setState(() => _lists = catalog.definitions);
      }
    });
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _lists);
}
