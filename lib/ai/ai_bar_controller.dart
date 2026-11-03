import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lists/list_definition.dart';
import '../lists/list_error.dart';
import '../lists/list_item.dart';
import '../lists/list_labels.dart';
import '../lists/list_patch.dart';
import '../lists/list_store.dart';
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

// Why there is nothing to apply. Exactly one of the three is set.
class AiProblem {
  const AiProblem.refusal(String this.refusal)
    : decline = null,
      errors = const [];
  const AiProblem.decline(String this.decline)
    : refusal = null,
      errors = const [];
  const AiProblem.invalid(this.errors) : refusal = null, decline = null;

  // functions/src/errors.ts reasons, a FirebaseFunctionsException code, or
  // `unavailable`.
  final String? refusal;
  // offTopic, notSupported, providerRefusal or noValidTool.
  final String? decline;
  // ListErrors that remained after the self-correction round, or a store
  // refusal while applying or undoing.
  final List<ListError> errors;
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
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    focus.addListener(_focusChanged);
  }

  final AiService service;
  final ListStore store;
  final SharedPreferences preferences;
  // Opens a list the AI just created.
  final void Function(String listId) onOpenList;
  final DateTime Function() _clock;

  static const String noticeKey = 'ai.noticeSeen';
  // How long "Added to ... · Undo" stays (as the list delete's Undo).
  static const Duration doneFor = Duration(seconds: 8);

  final TextEditingController text = TextEditingController();
  final FocusNode focus = FocusNode();
  // The field's height as laid out, so the shell can raise the hub just
  // above it while the bar is focused.
  final ValueNotifier<double> fieldHeight = ValueNotifier<double>(0);

  bool _focused = false;
  // The bar is being typed in: two to four lines, full width.
  bool get focused => _focused;

  void _focusChanged() {
    if (focus.hasFocus == _focused) {
      return;
    }
    _focused = focus.hasFocus;
    // A new request starts: an earlier answer, preview or question goes.
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
    );
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
    final AiPlan plan = AiPlan.read(
      answer,
      store.current,
      openListId: openListId,
    );
    if (!plan.isValid) {
      if (correct) {
        await _run(
          request.withCorrection(
            AiCorrection(
              toolCalls: answer.toolCalls,
              errors: [for (final ListError error in plan.errors) '$error'],
            ),
          ),
          correct: false,
        );
      } else {
        _problem = AiProblem.invalid(plan.errors);
        _set(AiBarPhase.problem);
      }
      return;
    }

    _plan = plan;
    _partial = answer.droppedTools > 0;
    text.clear();
    _newList = false;
    if (plan.steps.isEmpty) {
      if (plan.question != null) {
        _set(AiBarPhase.question);
      } else if (plan.reply != null) {
        _set(AiBarPhase.reply);
      } else {
        _problem = const AiProblem.decline('noValidTool');
        _set(AiBarPhase.problem);
      }
      return;
    }
    if (plan.needsPreview(openListId)) {
      _set(AiBarPhase.preview);
      return;
    }
    await apply();
  }

  // The answer to "which list?": the same request with that list open.
  Future<void> choose(String listId) async {
    final AiRequest? request = _request;
    if (request == null || _phase != AiBarPhase.question) {
      return;
    }
    await _run(request.withOpenList(store.current, listId), correct: true);
  }

  // Saves the plan through the store's own paths only (D-7): apply,
  // patchList, createList. Each step keeps what Undo needs.
  Future<void> apply() async {
    final AiPlan? plan = _plan;
    if (plan == null || plan.steps.isEmpty) {
      return;
    }
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
    _set(AiBarPhase.done);
    _doneTimer = Timer(doneFor, dismiss);
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
    _set(AiBarPhase.done);
    _doneTimer = Timer(const Duration(seconds: 2), dismiss);
  }

  // Closes the panel; a request still waiting is dropped. Undo stays
  // possible only while its line shows.
  void dismiss() {
    ++_generation;
    _plan = null;
    _problem = null;
    _done = null;
    _partial = false;
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
    text.dispose();
    focus.dispose();
    fieldHeight.dispose();
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
