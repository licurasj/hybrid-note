import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app_colors.dart';
import '../l10n/generated/app_localizations.dart';
import '../lists/generic_item_dialog.dart';
import '../lists/list_editor_style.dart';
import 'account_preferences.dart';
import 'app_theme.dart';

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
// (Q-48 A). Theme, language and the hub stay per phone and are not here.
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
            look.sectionLabel(loc.preferencesLists),
            _ChoiceRow<ListOrder>(
              key: const ValueKey('preferences-list-order'),
              label: loc.preferencesListOrder,
              selected: preferences.listOrder,
              choices: [
                (
                  value: ListOrder.lastUsed,
                  label: loc.preferencesListOrderLastUsed,
                ),
                (value: ListOrder.myOrder, label: loc.preferencesListOrderMine),
                (
                  value: ListOrder.alphabetical,
                  label: loc.preferencesListOrderAz,
                ),
              ],
              onChanged: cubit.setListOrder,
            ),
            _ChoiceRow<StartScreen>(
              key: const ValueKey('preferences-start-screen'),
              label: loc.preferencesStartScreen,
              selected: preferences.startScreen,
              choices: [
                (value: StartScreen.home, label: loc.home),
                (
                  value: StartScreen.lastOpenList,
                  label: loc.preferencesStartLastList,
                ),
              ],
              onChanged: cubit.setStartScreen,
            ),
            look.sectionLabel(loc.preferencesItems),
            _ChoiceRow<TickedItems>(
              key: const ValueKey('preferences-ticked-items'),
              label: loc.preferencesTicked,
              selected: preferences.tickedItems,
              choices: [
                (
                  value: TickedItems.moveToDone,
                  label: loc.preferencesTickedMove,
                ),
                (
                  value: TickedItems.stayInPlace,
                  label: loc.preferencesTickedStay,
                ),
                (value: TickedItems.hide, label: loc.preferencesTickedHide),
              ],
              onChanged: cubit.setTickedItems,
            ),
            _SwitchRow(
              key: const ValueKey('preferences-confirm-delete'),
              label: loc.preferencesConfirmDelete,
              value: preferences.confirmDelete,
              onChanged: cubit.setConfirmDelete,
            ),
            look.sectionLabel(loc.preferencesAi),
            _SwitchRow(
              key: const ValueKey('preferences-show-ai-bar'),
              label: loc.preferencesShowAiBar,
              value: preferences.showAiBar,
              onChanged: cubit.setShowAiBar,
            ),
            _SwitchRow(
              key: const ValueKey('settings-ai-auto-apply'),
              label: loc.settingsAiAutoApply,
              value: preferences.aiAutoApply,
              onChanged: cubit.setAiAutoApply,
            ),
            _AiAskSlider(
              level: preferences.aiAskLevel,
              onChanged: cubit.setAiAskLevel,
            ),
            look.sectionLabel(loc.preferencesGeneral),
            _SwitchRow(
              key: const ValueKey('preferences-vibration'),
              label: loc.preferencesVibration,
              value: preferences.vibration,
              onChanged: cubit.setVibration,
            ),
            _ChoiceRow<TimeFormat>(
              key: const ValueKey('preferences-time-format'),
              label: loc.preferencesTimeFormat,
              selected: preferences.timeFormat,
              choices: [
                (
                  value: TimeFormat.followLanguage,
                  label: loc.preferencesFollowLanguage,
                ),
                (value: TimeFormat.h12, label: loc.preferencesTime12),
                (value: TimeFormat.h24, label: loc.preferencesTime24),
              ],
              onChanged: cubit.setTimeFormat,
            ),
            _ChoiceRow<WeekStart>(
              key: const ValueKey('preferences-week-start'),
              label: loc.preferencesWeekStart,
              selected: preferences.weekStart,
              choices: [
                (
                  value: WeekStart.followLanguage,
                  label: loc.preferencesFollowLanguage,
                ),
                (value: WeekStart.monday, label: loc.preferencesMonday),
                (value: WeekStart.sunday, label: loc.preferencesSunday),
              ],
              onChanged: cubit.setWeekStart,
            ),
          ],
        ),
      ),
    );
  }
}

// A label and the current choice over a hairline; a tap opens the choices.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.choices,
    required this.onChanged,
  });

  final String label;
  final T selected;
  final List<({T value, String label})> choices;
  final ValueChanged<T> onChanged;

  Future<void> _choose(BuildContext context) async {
    final T? chosen = await showChoiceSheet<T>(
      context,
      title: label,
      selected: selected,
      choices: choices,
    );
    if (chosen != null) {
      onChanged(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final EditorLook look = EditorLook.of(context);
    final String current = choices
        .firstWhere((choice) => choice.value == selected)
        .label;
    return look.hairline(
      child: InkWell(
        onTap: () => _choose(context),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(label, style: look.type.row)),
              const SizedBox(width: 12),
              // At the right edge; a long value wraps past half the width.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width / 2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        current,
                        style: look.type.meta.copyWith(fontSize: 15),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: look.neutrals.muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// A label and a switch over a hairline; a tap anywhere on the row flips it.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final EditorLook look = EditorLook.of(context);
    return look.hairline(
      child: MergeSemantics(
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text(label, style: look.type.row)),
                const SizedBox(width: 12),
                Switch(
                  value: value,
                  activeTrackColor: AppColors.appBlue,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// How often the AI checks with you (Q-43): a slider from asking to just doing
// it, with what the stop means under it.
class _AiAskSlider extends StatelessWidget {
  const _AiAskSlider({required this.level, required this.onChanged});

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
      key: const ValueKey('settings-ai-ask'),
      child: Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(loc.settingsAiAsk, style: look.type.row),
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
