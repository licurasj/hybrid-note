import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../app_colors.dart';
import '../l10n/generated/app_localizations.dart';
import '../launcher/launcher_hub_area.dart';
import '../lists/list_definition.dart';
import '../lists/list_error.dart';
import '../lists/list_icons.dart';
import '../lists/list_labels.dart';
import 'ai_bar_controller.dart';
import 'ai_plan.dart';

// Where the bar goes (owner, 2026-11-03): along the bottom at full width,
// narrowed only to clear the collapsed hub where the two would meet. The
// open dial is drawn over the bar, so it never narrows for that. The hub can
// be dragged anywhere (LauncherHubArea), so this is worked out from its
// current spot and works for any default, beside the bar or above it.
class PromptBarGeometry {
  const PromptBarGeometry({
    required this.left,
    required this.right,
    required this.bottom,
  });

  // The field's height.
  static const double height = 52;
  static const double margin = 12;
  // Room between the bar and the hub's blue disc.
  static const double hubGap = 8;
  // While the panel is open it may reach this share of the screen up.
  static const double panelShare = 0.6;

  final double left;
  final double right;
  final double bottom;

  // [size] is the area the shell and the launcher fill; [bottomInset] the
  // system's bottom padding. With [panelOpen] the panel above the field
  // counts too, so it never runs under the hub either.
  factory PromptBarGeometry.of(
    Size size, {
    LauncherHubArea? hub,
    double bottomInset = 0,
    bool panelOpen = false,
  }) {
    final double bottom = margin + bottomInset;
    double left = margin;
    double right = margin;
    if (hub != null) {
      final Offset centre = hub.hubCenter(size);
      final double reach = hub.hubReach;
      final double barBottom = size.height - bottom;
      final double barTop = panelOpen
          ? size.height * (1 - panelShare)
          : barBottom - height;
      final bool meets =
          centre.dy + reach > barTop && centre.dy - reach < barBottom;
      if (meets) {
        if (centre.dx >= size.width / 2) {
          right = (size.width - (centre.dx - reach - hubGap)).clamp(
            margin,
            size.width / 2,
          );
        } else {
          left = (centre.dx + reach + hubGap).clamp(margin, size.width / 2);
        }
      }
    }
    return PromptBarGeometry(left: left, right: right, bottom: bottom);
  }
}

// The AI prompt bar (T-19 unit 4, Q-36 A): one fixed place on every screen.
// On a list it targets that list; on the home the AI picks the list. It is
// built for the whole shell area; only the bar and its panel take touches.
class PromptBar extends StatelessWidget {
  const PromptBar({super.key, required this.controller, this.openList});

  final AiBarController controller;
  // The list on screen, or null on the home.
  final ListDefinition? openList;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final PromptBarGeometry geometry = PromptBarGeometry.of(
            constraints.biggest,
            hub: LauncherHubArea.maybeOf(context),
            bottomInset: MediaQuery.paddingOf(context).bottom,
            panelOpen: controller.isOpen,
          );
          return Stack(
            children: [
              Positioned(
                left: geometry.left,
                right: geometry.right,
                bottom: geometry.bottom,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        constraints.maxHeight * PromptBarGeometry.panelShare,
                  ),
                  child: _BarColumn(controller: controller, openList: openList),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BarColumn extends StatelessWidget {
  const _BarColumn({required this.controller, required this.openList});

  final AiBarController controller;
  final ListDefinition? openList;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final Widget? panel = switch (controller.phase) {
      AiBarPhase.idle || AiBarPhase.sending => null,
      _ => _Panel(controller: controller),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The panel grows up out of the bar: size only, no fade
        // (docs/AESTHETICS.md Motion).
        Flexible(
          child: AnimatedSize(
            duration: reduceMotion ? Duration.zero : AppMotion.standard,
            curve: AppMotion.curve,
            alignment: Alignment.bottomCenter,
            child: panel == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: panel,
                  ),
          ),
        ),
        _Field(controller: controller, openList: openList),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.openList});

  final AiBarController controller;
  final ListDefinition? openList;

  void _send(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    controller.submit(
      locale: Localizations.localeOf(context).toLanguageTag(),
      labels: ListLabels(loc),
      openListId: openList?.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals n = AppColors.neutrals(brightness);
    final AppTypography type = AppTypography.of(context);
    final bool sending = controller.phase == AiBarPhase.sending;
    final String hint = controller.newList
        ? loc.aiBarHintNewList
        : openList == null
        ? loc.aiBarHint
        : loc.aiBarHintList(ListLabels(loc).listName(openList!));

    return Container(
      key: const ValueKey('ai-bar'),
      constraints: const BoxConstraints(minHeight: PromptBarGeometry.height),
      decoration: ShapeDecoration(
        color: n.ground,
        shape: StadiumBorder(side: BorderSide(color: n.line)),
        shadows: AppShadows.floating(brightness),
      ),
      padding: const EdgeInsets.only(left: 18, right: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('ai-bar-field'),
              controller: controller.text,
              focusNode: controller.focus,
              enabled: !sending,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              // Enter sends, also on a hardware keyboard; long requests
              // still wrap onto up to four lines.
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(context),
              // Typed text in the theme's field size (15), as other fields.
              style: type.row.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                hintText: hint,
                hintStyle: type.row.copyWith(
                  fontSize: 15,
                  color: n.muted,
                  fontWeight: FontWeight.w400,
                ),
                hintMaxLines: 1,
                semanticCounterText: '',
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: ListenableBuilder(
                listenable: controller.text,
                builder: (context, _) {
                  final bool empty = controller.text.text.trim().isEmpty;
                  return Semantics(
                    button: true,
                    label: loc.aiSend,
                    child: InkResponse(
                      key: const ValueKey('ai-bar-send'),
                      onTap: empty || sending ? null : () => _send(context),
                      radius: 24,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: empty && !sending ? n.line : n.text,
                        ),
                        child: sending
                            ? Padding(
                                padding: const EdgeInsets.all(11),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: n.ground,
                                ),
                              )
                            : Icon(
                                Icons.arrow_upward,
                                size: 20,
                                color: empty ? n.muted : n.ground,
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.controller});

  final AiBarController controller;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final ListLabels labels = ListLabels(loc);
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals n = AppColors.neutrals(brightness);
    final AppTypography type = AppTypography.of(context);

    Widget lines(List<String> texts, TextStyle style) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final String text in texts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(text, style: style),
          ),
      ],
    );

    final Widget close = TextButton(
      key: const ValueKey('ai-close'),
      onPressed: controller.dismiss,
      child: Text(loc.close),
    );
    final Widget cancel = TextButton(
      key: const ValueKey('ai-cancel'),
      onPressed: controller.dismiss,
      child: Text(loc.cancel),
    );
    final Widget undo = TextButton(
      key: const ValueKey('ai-undo'),
      onPressed: controller.undo,
      child: Text(loc.undo),
    );

    final AiPlan? plan = controller.plan;
    // The text scrolls when the panel runs out of room; its buttons stay.
    final (Widget content, List<Widget> buttons) = switch (controller.phase) {
      AiBarPhase.notice => (
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(loc.aiNoticeTitle, style: type.row),
            const SizedBox(height: 8),
            Text(
              loc.aiNoticeDeepSeek,
              key: const ValueKey('ai-notice'),
              style: type.meta,
            ),
          ],
        ),
        [
          cancel,
          FilledButton(
            key: const ValueKey('ai-notice-continue'),
            onPressed: controller.acceptNotice,
            child: Text(loc.aiNoticeContinue),
          ),
        ],
      ),
      AiBarPhase.preview when plan != null => (
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            lines(AiPlanText(loc).lines(plan), type.row),
            if (plan.reply != null) Text(plan.reply!, style: type.meta),
          ],
        ),
        [
          cancel,
          FilledButton(
            key: const ValueKey('ai-apply'),
            onPressed: controller.apply,
            child: Text(loc.aiApply),
          ),
        ],
      ),
      AiBarPhase.question when plan?.question != null => (
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (plan!.question!.text.isNotEmpty)
              Text(plan.question!.text, style: type.row),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ListDefinition list in plan.question!.candidates)
                  _ListChip(
                    key: ValueKey('ai-chip-${list.id}'),
                    label: labels.listName(list),
                    color: listColor(list.color, brightness: brightness),
                    onTap: () => controller.choose(list.id),
                  ),
              ],
            ),
          ],
        ),
        [cancel],
      ),
      AiBarPhase.reply => (Text(plan?.reply ?? '', style: type.row), [close]),
      AiBarPhase.problem => (
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._problemTexts(loc, labels, controller.problem).indexed.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  entry.$2,
                  style: entry.$1 == 0 ? type.row : type.meta,
                ),
              ),
            ),
          ],
        ),
        [if (controller.canUndo) undo, close],
      ),
      AiBarPhase.done => (
        Row(
          children: [
            Expanded(
              child: Text(
                _doneText(loc, controller.done),
                key: const ValueKey('ai-done'),
                style: type.row,
              ),
            ),
            if (controller.canUndo) undo,
          ],
        ),
        const <Widget>[],
      ),
      _ => (const SizedBox.shrink(), const <Widget>[]),
    };

    return Container(
      key: const ValueKey('ai-panel'),
      decoration: BoxDecoration(
        color: n.ground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: n.line),
        boxShadow: AppShadows.floating(brightness),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  12,
                  buttons.isEmpty ? 10 : 0,
                ),
                child: content,
              ),
            ),
            if (buttons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: buttons,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _doneText(AppLocalizations loc, AiDone? done) {
  if (done == null) {
    return '';
  }
  final String lists = done.listNames.join(', ');
  return switch (done.kind) {
    AiDoneKind.added => loc.aiDoneAdded(lists),
    AiDoneKind.changed => loc.aiDoneChanged(lists),
    AiDoneKind.created => loc.aiDoneCreated(lists),
    AiDoneKind.undone => loc.aiUndone,
  };
}

// The problem's message, then its details (one per ListError).
List<String> _problemTexts(
  AppLocalizations loc,
  ListLabels labels,
  AiProblem? problem,
) {
  if (problem == null) {
    return const [];
  }
  final String? decline = problem.decline;
  if (decline != null) {
    return [
      switch (decline) {
        'notSupported' => loc.aiDeclinedNotSupported,
        'noValidTool' => loc.aiRefusedNoValidTool,
        _ => loc.aiDeclinedOffTopic,
      },
    ];
  }
  final String? refusal = problem.refusal;
  if (refusal != null) {
    return [aiRefusalText(loc, refusal)];
  }
  final List<ListError> errors = problem.errors;
  // A refused undo is the one store error with its own sentence.
  if (errors.isNotEmpty &&
      errors.every((error) => error.code == ListErrorCode.listChanged)) {
    return [labels.error(errors.first)];
  }
  return [
    loc.aiInvalidAnswer,
    for (final ListError error in errors.take(5)) labels.error(error),
  ];
}

// The function's refusal reasons (functions/src/errors.ts) as messages.
String aiRefusalText(AppLocalizations loc, String reason) {
  return switch (reason) {
    'aiNotAllowed' => loc.aiRefusedAiNotAllowed,
    'outputTooLong' => loc.aiRefusedOutputTooLong,
    'noValidTool' => loc.aiRefusedNoValidTool,
    'dailyCount' => loc.aiRefusedDailyCount,
    'globalBudget' => loc.aiRefusedBudget,
    'promptTooLong' => loc.aiRefusedPromptTooLong,
    'contextTooLarge' => loc.aiRefusedContextTooLarge,
    'signIn' || 'appCheck' || 'notAllowed' => loc.aiRefusedAccess,
    'badRequest' => loc.aiRefusedBadRequest,
    _ => loc.aiRefusedUnavailable,
  };
}

// A list as an answer to "which list?": its colour dot and name.
class _ListChip extends StatelessWidget {
  const _ListChip({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppNeutrals n = AppColors.neutrals(Theme.of(context).brightness);
    final AppTypography type = AppTypography.of(context);
    return Material(
      type: MaterialType.transparency,
      shape: StadiumBorder(side: BorderSide(color: n.text)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(label, style: type.row),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
