import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_settings.dart';
import '../lists/list_definition.dart';
import '../lists/list_error.dart';
import '../lists/list_item.dart';
import '../lists/list_labels.dart';
import '../lists/list_patch.dart';
import '../lists/list_store.dart';
import 'ai_match.dart';
import 'ai_plan.dart';
import 'ai_service.dart';

// What the prompt bar shows above its field.
enum AiBarPhase {
  // Just the field.
  idle,
  // The one-time AI notice, before the first request is sent.
  notice,
  // Waiting for the function.
  sending,
  // The changes, waiting for Apply.
  preview,
  // "Which list?" with list chips.
  question,
  // A text answer.
  reply,
  // Something went wrong or the AI declined; [AiBarController.problem].
  problem,
  // "Added to Grocery · Undo".
  done,
}

// Why there is nothing to apply. Exactly one of the four is set.
class AiProblem {
  const AiProblem.refusal(String this.refusal)
    : decline = null,
      listOff = null,
      errors = const [];
  const AiProblem.decline(String this.decline)
    : refusal = null,
      listOff = null,
      errors = const [];
  const AiProblem.invalid(this.errors)
    : refusal = null,
      decline = null,
      listOff = null;
  const AiProblem.listOff(String this.listOff)
    : refusal = null,
      decline = null,
      errors = const [];

  // functions/src/errors.ts reasons, a FirebaseFunctionsException code, or
  // `unavailable`.
  final String? refusal;
  // offTopic, notSupported, providerRefusal or noValidTool.
  final String? decline;
  // ListErrors that remained after the self-correction round, or a store
  // refusal while applying or undoing.
  final List<ListError> errors;
  // The name of a list with AI turned off that the request named, or that
  // a new list would copy (Q-41): nothing about it was sent.
  final String? listOff;
}

enum AiDoneKind { added, changed, created, undone }

class AiDone {
  const AiDone(this.kind, this.listNames);

  final AiDoneKind kind;
  final List<String> listNames;
}

// One applied step and how to take it back.
class _Undo {
  const _Undo.snapshot(ListSnapshot this.snapshot) : createdListId = null;
  const _Undo.created(String this.createdListId) : snapshot = null;

  final ListSnapshot? snapshot;
  final String? createdListId;
}

// The prompt bar's state (T-19 unit 4). The shell owns it, so Back can close
// the bar's panel before it pops a screen.
class AiBarController extends ChangeNotifier {
  AiBarController({
    required this.service,
    required this.store,
    required this.preferences,
    required this.onOpenList,
    this.saveAutoApply,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    focus.addListener(_focusChanged);
    focus.onKeyEvent = _key;
    text.addListener(_textChanged);
  }

  final AiService service;
  final ListStore store;
  final SharedPreferences preferences;
  // Opens a list the AI just created.
  final void Function(String listId) onOpenList;
  // Saves the auto-apply setting through the settings cubit, so the
  // Settings switch shows it; without it the preference is written here.
  final Future<void> Function(bool value)? saveAutoApply;
  final DateTime Function() _clock;

  static const String noticeKey = 'ai.noticeSeen';
  // Q-40 A: changes apply at once, with Undo, instead of waiting for Apply;
  // a device setting like the others (Q-24 A). Offered once, after the
  // first Apply.
  static const String autoApplyAskedKey = 'ai.autoApplyAsked';
  // How long "Added to ... · Undo" stays (as the list delete's Undo).
  static const Duration doneFor = Duration(seconds: 8);

  final TextEditingController text = TextEditingController();
  final FocusNode focus = FocusNode();
  // The field's height as laid out, so the shell can raise the hub just
  // above it while the bar is focused.
  final ValueNotifier<double> fieldHeight = ValueNotifier<double>(0);
  // The panel's height above the field, gap included (0 when closed): while
  // the bar is focused with a question up, the hub rises above it too.
  final ValueNotifier<double> panelHeight = ValueNotifier<double>(0);

  bool _focused = false;
  // The bar is being typed in: two to four lines, full width.
  bool get focused => _focused;

  void _focusChanged() {
    if (focus.hasFocus == _focused) {
      return;
    }
    _focused = focus.hasFocus;
    // The AI asked or answered: the bar's text answers it, so its message
    // stays up while that is typed (Q-42; owner, 2026-11-04). Its buttons
    // keep working, and Close or Cancel starts afresh.
    if (_focused &&
        (_phase == AiBarPhase.reply || _phase == AiBarPhase.question)) {
      final String? prompt = _lastPrompt;
      final String question =
          _plan?.question?.text ?? _plan?.itemQuestion?.text ?? '';
      if (_phase == AiBarPhase.question &&
          prompt != null &&
          question.isNotEmpty) {
        _followUp = AiFollowUp(prompt: prompt, reply: question);
      }
      notifyListeners();
      return;
    }
    // Otherwise a new request starts: an earlier preview or result goes.
    if (_focused && _phase != AiBarPhase.idle && _phase != AiBarPhase.sending) {
      dismiss();
      return;
    }
    notifyListeners();
  }

  // Leaving the bar (send, Back, keyboard closed, a tap outside, the dial):
  // it shrinks to one line and keeps what was typed as a draft.
  void leave() => focus.unfocus();

  AiBarPhase _phase = AiBarPhase.idle;
  AiBarPhase get phase => _phase;

  bool _newList = false;
  // "Describe a new list": the request asks for a new list.
  bool get newList => _newList;

  AiPlan? _plan;
  AiPlan? get plan => _plan;
  AiProblem? _problem;
  AiProblem? get problem => _problem;
  AiDone? _done;
  AiDone? get done => _done;
  bool _partial = false;
  // The function left part of the answer out (L3): the preview and the
  // done line say that not everything asked was done.
  bool get partial => _partial;
  bool get canUndo => _undo.isNotEmpty;

  AiRequest? _request;
  _Pending? _pending;
  // For the list names in "Added to ...".
  ListLabels? _labels;
  List<_Undo> _undo = const [];
  Timer? _doneTimer;
  // Bumped by cancel, so a late answer is dropped.
  int _generation = 0;

  bool get noticeSeen => preferences.getString(noticeKey) == aiNoticeId;

  bool get autoApply =>
      preferences.getBool(AppSettingsCubit.aiAutoApplyKey) ?? false;

  Future<void> setAutoApply(bool value) async {
    final Future<void> Function(bool value)? save = saveAutoApply;
    if (save != null) {
      await save(value);
    } else {
      await preferences.setBool(AppSettingsCubit.aiAutoApplyKey, value);
    }
    await preferences.setBool(autoApplyAskedKey, true);
    notifyListeners();
  }

  bool _offerAutoApply = false;
  // The done line asks once whether to apply without asking from now on.
  bool get offerAutoApply => _offerAutoApply;

  Future<void> answerAutoApply(bool yes) async {
    _offerAutoApply = false;
    await setAutoApply(yes);
    _doneTimer?.cancel();
    _doneTimer = Timer(doneFor, dismiss);
  }

  // The last request's words, put back in the bar after its Undo.
  String? _lastPrompt;
  // The list on screen when the request was sent, or the list the user
  // picked as the answer to "which list?" (Q-45 D).
  String? _homeListId;

  AiFollowUp? _followUp;
  // The AI's reply or question the next request answers (Q-42); it stays
  // up until the answer is sent or it is closed.
  AiFollowUp? get followUp => _followUp;

  Set<String> _picked = const {};
  // The items picked so far in "Which items?" (choose_items).
  Set<String> get picked => _picked;

  void togglePick(String itemId) {
    _picked = _picked.contains(itemId)
        ? ({..._picked}..remove(itemId))
        : {..._picked, itemId};
    notifyListeners();
  }

  // Applies the picked items as the delete or change the AI proposed.
  Future<void> applyPicked() async {
    final AiItemQuestion? question = _plan?.itemQuestion;
    if (question == null || _picked.isEmpty || _phase != AiBarPhase.question) {
      return;
    }
    final AiPlan plan = AiPlan.read(
      AiAnswer(requestId: '', toolCalls: [question.callFor(_picked.toList())]),
      store.current,
      openListId: question.definition.id,
    );
    if (!plan.isValid || plan.steps.isEmpty) {
      _problem = AiProblem.invalid(plan.errors);
      _set(AiBarPhase.problem);
      return;
    }
    _plan = plan;
    _followUp = null;
    await apply();
  }

  // Text put back by Undo and not touched since: one Backspace or Delete at
  // its end clears all of it.
  String? _refilled;

  void _textChanged() {
    final String? refilled = _refilled;
    if (refilled == null || text.text == refilled) {
      return;
    }
    _refilled = null;
    if (text.text == refilled.substring(0, refilled.length - 1) &&
        text.selection.isCollapsed &&
        text.selection.baseOffset == text.text.length) {
      text.clear();
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (_refilled != null &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.delete &&
        text.selection.isCollapsed &&
        text.selection.baseOffset == text.text.length) {
      _refilled = null;
      text.clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // The panel above the field is open.
  bool get isOpen => _phase != AiBarPhase.idle;

  void _set(AiBarPhase phase) {
    _doneTimer?.cancel();
    _phase = phase;
    notifyListeners();
  }

  // From "Describe a new list" in the New list picker.
  void startNewList() {
    _newList = true;
    _set(AiBarPhase.idle);
    focus.requestFocus();
  }

  // Sends the field's text. [openListId] is the list on screen (null on the
  // home): the request targets it, elsewhere the AI picks the list (Q-36).
  Future<void> submit({
    required String locale,
    required ListLabels labels,
    String? openListId,
  }) async {
    final String prompt = text.text.trim();
    if (prompt.isEmpty || _phase == AiBarPhase.sending) {
      return;
    }
    // Sending leaves the bar; the notice or the answer gets the room.
    leave();
    _pending = _Pending(prompt, locale, labels, openListId, _newList);
    if (!noticeSeen) {
      _set(AiBarPhase.notice);
      return;
    }
    await _sendPending();
  }

  Future<void> acceptNotice() async {
    await preferences.setString(noticeKey, aiNoticeId);
    await _sendPending();
  }

  Future<void> _sendPending() async {
    final _Pending? pending = _pending;
    if (pending == null) {
      return;
    }
    _pending = null;
    _labels = pending.labels;
    _lastPrompt = pending.prompt;
    _homeListId = pending.newList ? null : pending.openListId;
    // A request that names a list with AI off is answered here and sends
    // nothing (Q-41 A).
    final String? off = _aiOffNamed(pending.prompt, pending.labels);
    if (off != null) {
      _problem = AiProblem.listOff(off);
      _set(AiBarPhase.problem);
      return;
    }
    final AiRequest request = AiRequest.of(
      // A new list from a description: the AI designs it (Q-32).
      prompt: pending.newList
          ? 'Create a new list: ${pending.prompt}'
          : pending.prompt,
      locale: pending.locale,
      now: _clock(),
      catalog: store.current,
      labels: pending.labels,
      openListId: pending.newList ? null : pending.openListId,
      followUp: pending.newList ? null : _followUp,
      askLevel: AiAskLevel.of(
        preferences.getString(AppSettingsCubit.aiAskLevelKey),
      ).wire,
    );
    _followUp = null;
    await _run(request, correct: true);
  }

  // One request; when the device finds ListErrors in the answer, the same
  // request goes once more with them (Q-34 A), then the errors are shown.
  Future<void> _run(AiRequest request, {required bool correct}) async {
    final int generation = ++_generation;
    _request = request;
    _set(AiBarPhase.sending);
    final AiAnswer answer;
    try {
      answer = await service.send(request);
    } on AiRefusal catch (refusal) {
      if (generation == _generation) {
        _problem = AiProblem.refusal(refusal.reason);
        _set(AiBarPhase.problem);
      }
      return;
    } on Object catch (error) {
      developer.log('aiCommand failed: $error', name: 'AiBar');
      if (generation == _generation) {
        _problem = const AiProblem.refusal('unavailable');
        _set(AiBarPhase.problem);
      }
      return;
    }
    if (generation != _generation) {
      return;
    }
    if (answer.declined) {
      _problem = AiProblem.decline(answer.declineReason!);
      _set(AiBarPhase.problem);
      return;
    }

    final String? openListId = request.openList?.id;
    // Items named by their words (Q-39 D): the phone finds them; when it
    // cannot tell, the request goes again with that list's items.
    final AiMatchResult matched = AiMatch.resolve(
      answer,
      store.current,
      itemsSent: openListId,
    );
    final String? unclear = matched.unclearListId;
    if (unclear != null) {
      final AiRequest second = request.withOpenList(store.current, unclear);
      if (second.openList?.id == unclear) {
        await _run(second, correct: correct);
        return;
      }
    }
    final AiPlan plan = AiPlan.read(
      matched.answer,
      store.current,
      openListId: openListId,
    );
    final List<ListError> errors = [...matched.errors, ...plan.errors];
    if (errors.isNotEmpty) {
      if (correct) {
        await _run(
          request.withCorrection(
            AiCorrection(
              toolCalls: answer.toolCalls,
              errors: [for (final ListError error in errors) '$error'],
            ),
          ),
          correct: false,
        );
      } else {
        _problem = AiProblem.invalid(errors);
        _set(AiBarPhase.problem);
      }
      return;
    }
    // A new list named like a list with AI off (Q-41 A).
    for (final AiStep step in plan.steps) {
      if (step is AiCreateStep) {
        final String? off = _aiOffNamed(
          _labels?.listName(step.definition) ??
              step.definition.name ??
              step.definition.id,
          _labels,
          whole: true,
        );
        if (off != null) {
          _problem = AiProblem.listOff(off);
          _set(AiBarPhase.problem);
          return;
        }
      }
    }

    _plan = plan;
    _partial = answer.droppedTools > 0;
    text.clear();
    _newList = false;
    if (plan.steps.isEmpty) {
      if (plan.question != null || plan.itemQuestion != null) {
        _picked = const {};
        _set(AiBarPhase.question);
      } else if (plan.reply != null) {
        final String? prompt = _lastPrompt;
        if (prompt != null) {
          _followUp = AiFollowUp(prompt: prompt, reply: plan.reply!);
        }
        _set(AiBarPhase.reply);
      } else {
        _problem = const AiProblem.decline('noValidTool');
        _set(AiBarPhase.problem);
      }
      return;
    }
    // An add or change the AI moved away from the open list waits for
    // Apply even with auto-apply on, unless the request named that list
    // (Q-45 D).
    if ((plan.needsPreview(openListId) && !autoApply) ||
        _leavesHomeList(plan)) {
      _set(AiBarPhase.preview);
      return;
    }
    await apply();
  }

  // Whether an item step targets a list other than the one on screen that
  // the request did not name.
  bool _leavesHomeList(AiPlan plan) {
    final String? home = _homeListId;
    if (home == null) {
      return false;
    }
    final String said = ' ${AiMatch.words(_lastPrompt ?? '').join(' ')} ';
    for (final AiStep step in plan.steps) {
      if (step is! AiItemStep || step.listId == home) {
        continue;
      }
      final String name =
          _labels?.listName(step.definition) ??
          step.definition.name ??
          step.definition.id;
      final String words = AiMatch.words(name).join(' ');
      if (words.isEmpty || !said.contains(' $words ')) {
        return true;
      }
    }
    return false;
  }

  // The name of a list with AI off that [text] names (its words in a row),
  // or, with [whole], that [text] is.
  String? _aiOffNamed(String text, ListLabels? labels, {bool whole = false}) {
    final String said = ' ${AiMatch.words(text).join(' ')} ';
    for (final ListDefinition definition in store.current.definitions) {
      if (definition.aiAllowed) {
        continue;
      }
      final String name =
          labels?.listName(definition) ?? definition.name ?? definition.id;
      final String words = AiMatch.words(name).join(' ');
      if (words.isEmpty) {
        continue;
      }
      if (whole ? said.trim() == words : said.contains(' $words ')) {
        return name;
      }
    }
    return null;
  }

  // The answer to "which list?": the same request with that list open.
  Future<void> choose(String listId) async {
    final AiRequest? request = _request;
    if (request == null ||
        _phase != AiBarPhase.question ||
        _plan?.question == null) {
      return;
    }
    // A button answered the question, not the bar's text; the picked list
    // is the one the user meant (Q-45 D).
    _followUp = null;
    _homeListId = listId;
    await _run(
      request.withOpenList(store.current, listId, chosen: true),
      correct: true,
    );
  }

  // "New list" as the answer to "which list?" (Q-43).
  Future<void> chooseNewList() async {
    final AiRequest? request = _request;
    if (request == null || _phase != AiBarPhase.question) {
      return;
    }
    _followUp = null;
    await _run(request.withNewList(), correct: true);
  }

  // Saves the plan through the store's own paths only (D-7): apply,
  // patchList, createList. Each step keeps what Undo needs.
  Future<void> apply() async {
    final AiPlan? plan = _plan;
    if (plan == null || plan.steps.isEmpty) {
      return;
    }
    // The first Apply offers to skip it from now on (Q-40 A).
    final bool offer =
        (_phase == AiBarPhase.preview || _phase == AiBarPhase.question) &&
        !(preferences.getBool(autoApplyAskedKey) ?? false);
    final int generation = ++_generation;
    _set(AiBarPhase.sending);
    final List<_Undo> undo = [];
    final List<String> names = [];
    AiDoneKind kind = AiDoneKind.added;
    String? created;
    try {
      for (final AiStep step in plan.steps) {
        // The before-images are read now, at apply time (L11).
        final ListDefinition? before = store.current.definition(step.listId);
        final List<ListItem> items = store.current.itemsOf(step.listId);
        switch (step) {
          case AiItemStep():
            if (before == null) {
              throw const _StepFailed([]);
            }
            await store.apply(step.changes);
            undo.add(
              _Undo.snapshot(
                ListSnapshot.ofChanges(before, items, step.changes),
              ),
            );
            if (step.edited.isNotEmpty || step.deleted.isNotEmpty) {
              kind = AiDoneKind.changed;
            }
          case AiPatchStep():
            if (before == null) {
              throw const _StepFailed([]);
            }
            final ListPatchResult? result = await store.patchList(
              step.listId,
              step.ops,
            );
            if (result == null || !result.isValid) {
              throw _StepFailed(result?.errors ?? const []);
            }
            undo.add(
              _Undo.snapshot(ListSnapshot.ofPatch(before, items, result)),
            );
            kind = AiDoneKind.changed;
          case AiCreateStep():
            final List<ListError> errors = await store.createList(
              step.definition,
              items: step.items,
            );
            if (errors.isNotEmpty) {
              throw _StepFailed(errors);
            }
            undo.add(_Undo.created(step.listId));
            kind = AiDoneKind.created;
            created = step.listId;
        }
        final ListDefinition? definition =
            store.current.definition(step.listId) ??
            (step is AiCreateStep ? step.definition : before);
        if (definition != null) {
          final String name = _labels?.listName(definition) ?? step.listId;
          if (!names.contains(name)) {
            names.add(name);
          }
        }
      }
    } on _StepFailed catch (failed) {
      _undo = undo;
      if (generation == _generation) {
        _problem = AiProblem.invalid(failed.errors);
        _set(AiBarPhase.problem);
      }
      return;
    } on Object catch (error) {
      developer.log('AI apply failed: $error', name: 'AiBar');
      _undo = undo;
      if (generation == _generation) {
        _problem = const AiProblem.refusal('unavailable');
        _set(AiBarPhase.problem);
      }
      return;
    }
    _undo = undo;
    _done = AiDone(kind, names);
    _offerAutoApply = offer;
    if (offer) {
      await preferences.setBool(autoApplyAskedKey, true);
    }
    _set(AiBarPhase.done);
    // The offer stays until it is answered.
    if (!offer) {
      _doneTimer = Timer(doneFor, dismiss);
    }
    if (created != null) {
      onOpenList(created);
    }
  }

  // Undo of the whole answer, newest step first (Q-35 A). A list changed
  // since is refused by the store and left as it is.
  Future<void> undo() async {
    final List<_Undo> steps = _undo;
    if (steps.isEmpty) {
      return;
    }
    _undo = const [];
    ++_generation;
    _set(AiBarPhase.sending);
    final List<ListError> errors = [];
    for (final _Undo step in steps.reversed) {
      try {
        if (step.snapshot != null) {
          errors.addAll(await store.restoreSnapshot(step.snapshot!));
        } else {
          await store.deleteList(step.createdListId!);
        }
      } on Object catch (error) {
        developer.log('AI undo failed: $error', name: 'AiBar');
        errors.add(
          ListError(ListErrorCode.listChanged, {
            'list': step.snapshot?.listId ?? step.createdListId ?? '',
          }),
        );
      }
    }
    if (errors.isNotEmpty) {
      _problem = AiProblem.invalid(errors);
      _set(AiBarPhase.problem);
      return;
    }
    _done = const AiDone(AiDoneKind.undone, []);
    _offerAutoApply = false;
    // The request's words come back as a draft, not focused, to send again
    // or clear with one Backspace (owner, 2026-11-04).
    final String? prompt = _lastPrompt;
    if (prompt != null && prompt.isNotEmpty && text.text.isEmpty) {
      _refilled = prompt;
      text.value = TextEditingValue(
        text: prompt,
        selection: TextSelection.collapsed(offset: prompt.length),
      );
    }
    _set(AiBarPhase.done);
    _doneTimer = Timer(const Duration(seconds: 2), dismiss);
  }

  // Closes the panel; a request still waiting is dropped. Undo stays
  // possible only while its line shows. Closing a reply (Close, Back) also
  // ends the follow-up, so the next request starts fresh (Q-42).
  void dismiss() {
    ++_generation;
    _followUp = null;
    _plan = null;
    _problem = null;
    _done = null;
    _partial = false;
    _offerAutoApply = false;
    _pending = null;
    _undo = const [];
    _set(AiBarPhase.idle);
  }

  // Back leaves the bar first, then closes its panel, then leaves "Describe
  // a new list"; only then does the shell go back (main_shell.dart).
  bool handleBack() {
    if (focus.hasFocus) {
      leave();
      return true;
    }
    if (isOpen) {
      dismiss();
      return true;
    }
    if (_newList) {
      _newList = false;
      focus.unfocus();
      notifyListeners();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _doneTimer?.cancel();
    focus.removeListener(_focusChanged);
    text.removeListener(_textChanged);
    text.dispose();
    focus.dispose();
    fieldHeight.dispose();
    panelHeight.dispose();
    super.dispose();
  }
}

class _Pending {
  const _Pending(
    this.prompt,
    this.locale,
    this.labels,
    this.openListId,
    this.newList,
  );

  final String prompt;
  final String locale;
  final ListLabels labels;
  final String? openListId;
  final bool newList;
}

class _StepFailed implements Exception {
  const _StepFailed(this.errors);

  final List<ListError> errors;
}
