import 'dart:math' as math;

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

// Where the bar goes (owner, 2026-11-03; docs/INTERACTIONS.md "AI bar"):
// - At rest it is one line tall beside the collapsed hub: at most
//   [maxWidth], centred in the free space (between the hub and the far edge
//   when the hub is beside it, else on the screen).
// - Focused it is two to four lines tall and takes the full width (same
//   maximum, centred); the hub then rises to sit just above it
//   ([hubLiftY]). Where the free space beside the hub already holds the
//   widest bar, nothing moves.
// The open dial is drawn over the bar, so it never narrows for that. The hub
// can be dragged anywhere (LauncherHubArea), so this is worked out from its
// current spot.
class PromptBarGeometry {
  const PromptBarGeometry({
    required this.left,
    required this.right,
    required this.bottom,
    this.hubLiftY,
  });

  // The field's height at rest (one line).
  static const double height = 52;
  // The field's height when focused with two lines, until it is measured.
  static const double focusedHeight = 68;
  static const double margin = 12;
  static const double maxWidth = 600;
  // Room between the bar and the hub's blue disc.
  static const double hubGap = 8;
  // While the panel is open it may reach this share of the screen up.
  static const double panelShare = 0.6;

  final double left;
  final double right;
  final double bottom;
  // The hub centre's height while the bar is focused, or null when the hub
  // stays where it is.
  final double? hubLiftY;

  // [size] is the area the shell and the launcher fill; [hub] where the hub
  // rests; [bottomInset] the system's bottom padding; [fieldHeight] the
  // field's measured height. With [panelOpen] the panel above the field
  // counts too, so it never runs under the hub either.
  factory PromptBarGeometry.of(
    Size size, {
    LauncherHubArea? hub,
    double bottomInset = 0,
    bool panelOpen = false,
    bool focused = false,
    double? fieldHeight,
  }) {
    final double bottom = margin + bottomInset;
    final double barBottom = size.height - bottom;
    final double field = math.max(
      fieldHeight ?? 0,
      focused ? focusedHeight : height,
    );
    double start = margin;
    double end = size.width - margin;
    double? liftY;
    if (hub != null) {
      final Offset centre = hub.hubCenter(size);
      final double reach = hub.hubReach;
      final double barTop = panelOpen && !focused
          ? size.height * (1 - panelShare)
          : barBottom - field;
      final bool meets =
          centre.dy + reach > barTop && centre.dy - reach < barBottom;
      if (meets) {
        final bool hubRight = centre.dx >= size.width / 2;
        final double besideStart = hubRight
            ? margin
            : math.min(centre.dx + reach + hubGap, size.width / 2);
        final double besideEnd = hubRight
            ? math.max(centre.dx - reach - hubGap, size.width / 2)
            : size.width - margin;
        if (focused && besideEnd - besideStart < maxWidth) {
          liftY = barBottom - field - hubGap - reach;
        } else {
          start = besideStart;
          end = besideEnd;
        }
      }
    }
    final double width = math.min(maxWidth, math.max(0.0, end - start));
    final double left = start + (end - start - width) / 2;
    return PromptBarGeometry(
      left: left,
      right: size.width - left - width,
      bottom: bottom,
      hubLiftY: liftY,
    );
  }
}

// The AI prompt bar (T-19 unit 4, Q-36 A): one fixed place on every screen.
// On a list it targets that list; on the home the AI picks the list. It is
// built for the whole shell area; only the bar and its panel take touches.
// A touch anywhere else leaves the bar and still does its own job.
class PromptBar extends StatelessWidget {
  const PromptBar({super.key, required this.controller, this.openList});

  final AiBarController controller;
  // The list on screen, or null on the home.
  final ListDefinition? openList;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.fieldHeight]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final PromptBarGeometry geometry = PromptBarGeometry.of(
            constraints.biggest,
            hub: LauncherHubArea.maybeOf(context),
            bottomInset: MediaQuery.paddingOf(context).bottom,
            panelOpen: controller.isOpen,
            focused: controller.focused,
            fieldHeight: controller.fieldHeight.value,
          );
          return Stack(
            children: [
              AnimatedPositioned(
                duration: reduceMotion ? Duration.zero : AppMotion.standard,
                curve: AppMotion.curve,
                left: geometry.left,
                right: geometry.right,
                bottom: geometry.bottom,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        constraints.maxHeight * PromptBarGeometry.panelShare,
                  ),
                  // Touches on the bar or its panel do not leave the bar.
                  child: TapRegion(
                    groupId: controller,
                    child: _BarColumn(
                      controller: controller,
                      openList: openList,
                    ),
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

class _Field extends StatefulWidget {
  const _Field({required this.controller, required this.openList});

  final AiBarController controller;
  final ListDefinition? openList;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> with WidgetsBindingObserver {
  final GlobalKey _box = GlobalKey();
  double _keyboard = 0;

  AiBarController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.text.addListener(_textChanged);
  }

  @override
  void dispose() {
    controller.text.removeListener(_textChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Typing can add a line: build again, so the new height is measured and
  // the raised hub keeps clear of it.
  void _textChanged() => setState(() {});

  // Closing the keyboard (Android's Back while it is up, its hide key)
  // leaves the bar; the field would otherwise keep the focus.
  @override
  void didChangeMetrics() {
    final double keyboard = View.of(context).viewInsets.bottom;
    if (controller.focused && _keyboard > 0 && keyboard == 0) {
      controller.leave();
    }
    _keyboard = keyboard;
  }

  void _send() {
    final AppLocalizations loc = AppLocalizations.of(context);
    controller.submit(
      locale: Localizations.localeOf(context).toLanguageTag(),
      labels: ListLabels(loc),
      openListId: widget.openList?.id,
    );
  }

  // Tells the shell the field's height, for the raised hub.
  void _measure() {
    final double? height = _box.currentContext?.size?.height;
    if (height != null && (height - controller.fieldHeight.value).abs() > 0.5) {
      controller.fieldHeight.value = height;
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _measure();
      }
    });
    final AppLocalizations loc = AppLocalizations.of(context);
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals n = AppColors.neutrals(brightness);
    final AppTypography type = AppTypography.of(context);
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final bool sending = controller.phase == AiBarPhase.sending;
    final bool focused = controller.focused;
    final ListDefinition? openList = widget.openList;
    final String hint = controller.newList
        ? loc.aiBarHintNewList
        : openList == null
        ? loc.aiBarHint
        : loc.aiBarHintList(ListLabels(loc).listName(openList));
    // Typed text in the theme's field size (15), as other fields.
    final TextStyle textStyle = type.row.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w400,
    );
    // Left with text in it: the draft on one line, ending in "…"; a tap
    // brings the whole of it back.
    final bool draft = !focused && controller.text.text.isNotEmpty;

    final Widget field = TextField(
      key: const ValueKey('ai-bar-field'),
      controller: controller.text,
      focusNode: controller.focus,
      groupId: controller,
      onTapOutside: (_) => controller.leave(),
      enabled: !sending,
      // One line at rest; two when focused, growing to four, then it
      // scrolls inside.
      minLines: focused ? 2 : 1,
      maxLines: focused ? 4 : 1,
      maxLength: 1000,
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => null,
      // Enter sends, also on a hardware keyboard.
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _send(),
      style: textStyle,
      decoration: InputDecoration(
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        filled: false,
        hintText: hint,
        hintStyle: textStyle.copyWith(color: n.muted),
        hintMaxLines: 1,
        semanticCounterText: '',
      ),
    );

    return AnimatedSize(
      key: const ValueKey('ai-bar'),
      duration: reduceMotion ? Duration.zero : AppMotion.standard,
      curve: AppMotion.curve,
      alignment: Alignment.bottomCenter,
      child: Container(
        key: _box,
        constraints: const BoxConstraints(minHeight: PromptBarGeometry.height),
        decoration: ShapeDecoration(
          color: n.ground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PromptBarGeometry.height / 2),
            side: BorderSide(color: n.line),
          ),
          shadows: AppShadows.floating(brightness),
        ),
        padding: EdgeInsets.fromLTRB(18, focused ? 12 : 0, 4, focused ? 2 : 0),
        child: Row(
          crossAxisAlignment: focused
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: focused ? 12 : 0),
                // The field keeps its place whether or not the draft shows:
                // rebuilt elsewhere, it would drop the keyboard on a phone
                // and the bar would close again (T-19 unit 8).
                child: Stack(
                  children: [
                    Offstage(offstage: draft, child: field),
                    if (draft)
                      GestureDetector(
                        key: const ValueKey('ai-bar-draft'),
                        behavior: HitTestBehavior.opaque,
                        onTap: sending ? null : controller.focus.requestFocus,
                        child: Text(
                          controller.text.text.replaceAll('\n', ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle,
                        ),
                      ),
                  ],
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
                        onTap: empty || sending ? null : _send,
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
            if (controller.partial)
              Text(
                loc.aiPartlyNotDone,
                key: const ValueKey('ai-partial'),
                style: type.meta,
              ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _doneText(loc, controller.done),
                    key: const ValueKey('ai-done'),
                    style: type.row,
                  ),
                  if (controller.partial &&
                      controller.done?.kind != AiDoneKind.undone)
                    Text(
                      loc.aiPartlyNotDone,
                      key: const ValueKey('ai-partial'),
                      style: type.meta,
                    ),
                  if (controller.offerAutoApply)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        loc.aiAutoApplyOffer,
                        key: const ValueKey('ai-auto-apply-offer'),
                        style: type.meta,
                      ),
                    ),
                ],
              ),
            ),
            if (controller.canUndo) undo,
          ],
        ),
        [
          if (controller.offerAutoApply) ...[
            TextButton(
              key: const ValueKey('ai-auto-apply-no'),
              onPressed: () => controller.answerAutoApply(false),
              child: Text(loc.aiAutoApplyNo),
            ),
            FilledButton(
              key: const ValueKey('ai-auto-apply-yes'),
              onPressed: () => controller.answerAutoApply(true),
              child: Text(loc.aiAutoApplyYes),
            ),
          ],
        ],
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
  final String? listOff = problem.listOff;
  if (listOff != null) {
    return [loc.aiListOff(listOff)];
  }
  final List<ListError> errors = problem.errors;
  // A refused undo is the one store error with its own sentence.
  if (errors.isNotEmpty &&
      errors.every(
        (error) =>
            error.code == ListErrorCode.listChanged ||
            error.code == ListErrorCode.undoTooLarge,
      )) {
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
    'providerAccount' => loc.aiRefusedProviderAccount,
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
