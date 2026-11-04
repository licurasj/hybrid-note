import 'package:uuid/uuid.dart';

import '../l10n/generated/app_localizations.dart';
import '../lists/list_catalog.dart';
import '../lists/list_definition.dart';
import '../lists/list_error.dart';
import '../lists/list_input.dart';
import '../lists/list_item.dart';
import '../lists/list_labels.dart';
import '../lists/list_patch.dart';
import '../lists/list_rules.dart';
import '../lists/list_store.dart';
import '../lists/list_vocabulary.dart';
import 'ai_service.dart';

// What the AI's answer would do, read and checked on the device (Q-34 A)
// before anything is saved: ListInput reads each tool call, ListPatch.apply
// dry-runs a structure change and ListDefinition.validate checks a new list.
// Any ListError means nothing is applied; the errors go back to the AI once
// for self-correction.
sealed class AiStep {
  const AiStep();

  String get listId;
}

// upsert_items or delete_items on one list.
class AiItemStep extends AiStep {
  const AiItemStep({
    required this.definition,
    required this.changes,
    required this.added,
    required this.edited,
    required this.deleted,
    this.base = const {},
  });

  final ListDefinition definition;
  final ListChanges changes;
  final List<ListItem> added;
  final List<ListItem> edited;
  // The items as they are now, before the delete.
  final List<ListItem> deleted;
  // The existing items among those changed or deleted, as the preview read
  // them (Q-51).
  final Map<String, ListItem> base;

  @override
  String get listId => definition.id;

  AiItemWrite get write => AiItemWrite(
    definition: definition,
    saved: changes.saved,
    deletedIds: changes.deletedIds,
    base: base,
  );

  // This step and the [next] one on the same list as one step: one write, and
  // an item touched by both is changed once (M2 of the Codex review).
  AiItemStep? followedBy(AiItemStep next) {
    final Set<String> addedHere = {for (final ListItem item in added) item.id};
    final Map<String, ListItem> joinedBase = {
      for (final MapEntry<String, ListItem> entry in next.base.entries)
        if (!addedHere.contains(entry.key)) entry.key: entry.value,
      ...base,
    };
    final Map<String, ListItem> saved = {
      for (final ListItem item in changes.saved) item.id: item,
      for (final ListItem item in next.changes.saved) item.id: item,
    };
    next.changes.deletedIds.forEach(saved.remove);
    final List<String> deletedIds = [
      ...changes.deletedIds,
      for (final String id in next.changes.deletedIds)
        if (joinedBase.containsKey(id)) id,
    ];
    if (saved.isEmpty && deletedIds.isEmpty) {
      return null;
    }
    return AiItemStep(
      definition: next.definition,
      changes: ListChanges(saved: saved.values.toList(), deletedIds: deletedIds),
      added: [
        for (final ListItem item in saved.values)
          if (!joinedBase.containsKey(item.id)) item,
      ],
      edited: [
        for (final ListItem item in saved.values)
          if (joinedBase.containsKey(item.id)) item,
      ],
      deleted: [for (final String id in deletedIds) joinedBase[id]!],
      base: joinedBase,
    );
  }
}

// patch_list on the open list, with the dry run's result.
class AiPatchStep extends AiStep {
  const AiPatchStep({
    required this.definition,
    required this.ops,
    required this.dryRun,
  });

  final ListDefinition definition;
  final List<ListPatchOp> ops;
  final ListPatchResult dryRun;

  @override
  String get listId => definition.id;
}

// create_list: a new list and its first items.
class AiCreateStep extends AiStep {
  const AiCreateStep({required this.definition, required this.items});

  final ListDefinition definition;
  final List<ListItem> items;

  @override
  String get listId => definition.id;
}

// choose_list: the AI asks which list (Q-36), with 2-3 of the user's lists.
class AiQuestion {
  const AiQuestion({
    required this.text,
    required this.candidates,
    this.offerNewList = false,
  });

  final String text;
  final List<ListDefinition> candidates;
  // New list is one more choice (Q-43).
  final bool offerNewList;
}

// choose_items: the AI asks which items (Q-42), with 2-6 items of the open
// list; the picked ones are deleted, or get [values].
class AiItemQuestion {
  const AiItemQuestion({
    required this.text,
    required this.definition,
    required this.candidates,
    required this.values,
  });

  final String text;
  final ListDefinition definition;
  final List<ListItem> candidates;
  // Null: delete the picked items; otherwise upsert_items values entries.
  final List<Object?>? values;

  // The tool call the picked items make, read like any other answer.
  AiToolCall callFor(List<String> ids) => values == null
      ? AiToolCall('delete_items', {'listId': definition.id, 'ids': ids})
      : AiToolCall('upsert_items', {
          'listId': definition.id,
          'items': [
            for (final String id in ids) {'id': id, 'values': values},
          ],
        });
}

class AiPlan {
  const AiPlan({
    this.steps = const [],
    this.reply,
    this.question,
    this.itemQuestion,
    this.errors = const [],
  });

  // Reads [answer]'s tool calls against [catalog], each against what the ones
  // before it would leave, so a later call builds on an earlier one (M2 of the
  // Codex review). [openListId] is the list the request had open: structure
  // changes are allowed only there.
  factory AiPlan.read(
    AiAnswer answer,
    ListCatalog catalog, {
    String? openListId,
    String Function()? newId,
    DateTime? now,
  }) {
    final String Function() id = newId ?? () => const Uuid().v4();
    final DateTime time = now ?? DateTime.now().toUtc();
    final List<AiStep> steps = [];
    final List<ListError> errors = [];
    final List<String> replies = [];
    AiQuestion? question;
    AiItemQuestion? itemQuestion;
    ListCatalog working = catalog;

    // Adds an item step, joined to the step before it when that is one on the
    // same list, and moves the working catalog past it.
    void addItemStep(AiItemStep step) {
      final AiStep? last = steps.lastOrNull;
      if (last is AiItemStep && last.listId == step.listId) {
        steps.removeLast();
        final AiItemStep? joined = last.followedBy(step);
        if (joined != null) {
          steps.add(joined);
        }
      } else {
        steps.add(step);
      }
      final Set<String> gone = {
        ...step.changes.deletedIds,
        for (final ListItem item in step.changes.saved) item.id,
      };
      working = ListCatalog(
        definitions: working.definitions,
        items: [
          for (final ListItem item in working.items)
            if (!gone.contains(item.id)) item,
          ...step.changes.saved,
        ],
      );
    }

    for (final AiToolCall call in answer.toolCalls) {
      switch (call.name) {
        case 'upsert_items':
          final (ListChanges changes, List<ListError> found) =
              ListInput.upsertItems(call.args, working, newId: id, now: time);
          errors.addAll(found);
          final ListDefinition? definition = found.isEmpty
              ? working.definition('${(call.args as Map)['listId']}')
              : null;
          if (definition != null && !changes.isEmpty) {
            final Map<String, ListItem> existing = {
              for (final ListItem item in working.itemsOf(definition.id))
                item.id: item,
            };
            addItemStep(
              AiItemStep(
                definition: definition,
                changes: changes,
                added: [
                  for (final ListItem item in changes.saved)
                    if (!existing.containsKey(item.id)) item,
                ],
                edited: [
                  for (final ListItem item in changes.saved)
                    if (existing.containsKey(item.id)) item,
                ],
                deleted: const [],
                base: {
                  for (final ListItem item in changes.saved)
                    if (existing[item.id] case final ListItem old) item.id: old,
                },
              ),
            );
          }
        case 'delete_items':
          final (ListChanges changes, List<ListError> found) =
              ListInput.deleteItems(call.args, working);
          errors.addAll(found);
          final ListDefinition? definition = found.isEmpty
              ? working.definition('${(call.args as Map)['listId']}')
              : null;
          if (definition != null && !changes.isEmpty) {
            final Set<String> ids = changes.deletedIds.toSet();
            final List<ListItem> deleted = [
              for (final ListItem item in working.itemsOf(definition.id))
                if (ids.contains(item.id)) item,
            ];
            addItemStep(
              AiItemStep(
                definition: definition,
                changes: changes,
                added: const [],
                edited: const [],
                deleted: deleted,
                base: {for (final ListItem item in deleted) item.id: item},
              ),
            );
          }
        case 'patch_list':
          final (String? listId, List<ListPatchOp> ops, List<ListError> found) =
              ListInput.patchList(call.args, working);
          errors.addAll(found);
          if (listId == null || found.isNotEmpty) {
            break;
          }
          if (listId != openListId) {
            errors.add(
              ListError(ListErrorCode.badOp, {
                'op': 'patch_list',
                'detail': 'structure changes only on the open list',
              }),
            );
            break;
          }
          final ListDefinition definition = working.definition(listId)!;
          final ListPatchResult dryRun = ListPatch.apply(
            definition,
            working.itemsOf(listId),
            ops,
            time,
          );
          errors.addAll(dryRun.errors);
          if (dryRun.isValid && ops.isNotEmpty) {
            steps.add(
              AiPatchStep(definition: definition, ops: ops, dryRun: dryRun),
            );
            working = ListCatalog(
              definitions: [
                for (final ListDefinition d in working.definitions)
                  d.id == listId ? dryRun.definition : d,
              ],
              items: [
                for (final ListItem item in working.items)
                  if (item.listId != listId) item,
                ...dryRun.items,
              ],
            );
          }
        case 'create_list':
          final (
            ListDefinition? definition,
            List<ListItem> items,
            List<ListError> found,
          ) = ListInput.createList(
            call.args,
            listId: 'list-${id()}',
            newId: id,
            now: time,
          );
          errors.addAll(found);
          if (definition != null) {
            steps.add(AiCreateStep(definition: definition, items: items));
          }
        case 'choose_list':
          final Object? args = call.args;
          if (args is Map && args['candidates'] is List) {
            final List<ListDefinition> candidates = [
              for (final Object? candidate in args['candidates'] as List)
                if (catalog.definition('$candidate') case final ListDefinition d
                    when d.aiAllowed)
                  d,
            ];
            if (candidates.isNotEmpty) {
              question = AiQuestion(
                text: args['question'] is String
                    ? args['question'] as String
                    : '',
                candidates: candidates,
                offerNewList: args['newList'] == true,
              );
            }
          }
        case 'choose_items':
          final Object? args = call.args;
          if (args is! Map || args['candidates'] is! List) {
            break;
          }
          final ListDefinition? d = catalog.definition('${args['listId']}');
          if (d != null && d.aiAllowed) {
            final Set<String> ids = {
              for (final Object? id in args['candidates'] as List) '$id',
            };
            final List<ListItem> candidates = [
              for (final ListItem item in catalog.itemsOf(d.id))
                if (ids.contains(item.id)) item,
            ];
            if (candidates.isNotEmpty) {
              itemQuestion = AiItemQuestion(
                text: args['question'] is String
                    ? args['question'] as String
                    : '',
                definition: d,
                candidates: candidates,
                values: args['values'] is List
                    ? args['values'] as List<Object?>
                    : null,
              );
            }
          }
        case 'reply':
          final Object? args = call.args;
          if (args is Map && args['text'] is String) {
            replies.add(args['text'] as String);
          }
      }
    }

    return AiPlan(
      steps: steps,
      reply: replies.isEmpty ? null : replies.join('\n'),
      question: question,
      itemQuestion: itemQuestion,
      errors: errors,
    );
  }

  final List<AiStep> steps;
  final String? reply;
  final AiQuestion? question;
  final AiItemQuestion? itemQuestion;
  final List<ListError> errors;

  bool get isValid => errors.isEmpty;
  bool get isEmpty =>
      steps.isEmpty &&
      reply == null &&
      question == null &&
      itemQuestion == null;

  // Item adds apply at once with Undo; everything else waits for Apply:
  // structure changes, new lists, deletes and edits always preview (Q-32),
  // and so do adds to a list other than the open one (an injected item in
  // the open list could steer them elsewhere, L12).
  bool needsPreview(String? openListId) {
    for (final AiStep step in steps) {
      if (step is! AiItemStep ||
          step.edited.isNotEmpty ||
          step.deleted.isNotEmpty ||
          (openListId != null && step.listId != openListId)) {
        return true;
      }
    }
    return false;
  }
}

// The plain-language lines of a preview and the "Added to ..." summary.
class AiPlanText {
  AiPlanText(this.loc) : labels = ListLabels(loc);

  final AppLocalizations loc;
  final ListLabels labels;

  // At most this many item names in one line; the rest as "+N".
  static const int maxNames = 4;

  static String itemTitle(ListDefinition definition, ListItem item) {
    final Object? title = item['title'];
    if (title is String && title.isNotEmpty) {
      return title;
    }
    for (final FieldDefinition field in definition.fields) {
      final Object? value = item[field.key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return '—';
  }

  String names(ListDefinition definition, List<ListItem> items) {
    final List<String> titles = [
      for (final ListItem item in items.take(maxNames))
        itemTitle(definition, item),
    ];
    final int more = items.length - titles.length;
    return more > 0 ? '${titles.join(', ')} +$more' : titles.join(', ');
  }

  List<String> lines(AiPlan plan) {
    return [for (final AiStep step in plan.steps) ...stepLines(step)];
  }

  List<String> stepLines(AiStep step) {
    switch (step) {
      case AiItemStep():
        final String list = labels.listName(step.definition);
        return [
          if (step.added.isNotEmpty)
            loc.aiAddItems(list, names(step.definition, step.added)),
          if (step.edited.isNotEmpty)
            loc.aiEditItems(list, names(step.definition, step.edited)),
          if (step.deleted.isNotEmpty)
            loc.aiDeleteItems(list, names(step.definition, step.deleted)),
        ];
      case AiPatchStep():
        final String list = labels.listName(step.definition);
        return [
          for (final ListPatchOp op in step.ops) _opLine(list, step, op),
          if (step.dryRun.hiddenValues > 0)
            loc.aiHiddenValues(step.dryRun.hiddenValues),
        ];
      case AiCreateStep():
        final ListDefinition definition = step.definition;
        return [
          loc.aiNewList(
            labels.listName(definition),
            [
              for (final FieldDefinition field in definition.fields)
                labels.field(field),
            ].join(', '),
          ),
          if (step.items.isNotEmpty)
            loc.aiAddItems(
              labels.listName(definition),
              names(definition, step.items),
            ),
        ];
    }
  }

  String _fieldName(ListDefinition definition, Object? key) {
    for (final FieldDefinition field in definition.fields) {
      if (field.key == key) {
        return labels.field(field);
      }
    }
    return '$key';
  }

  String _opLine(String list, AiPatchStep step, ListPatchOp op) {
    final Map<String, dynamic> args = op.args;
    switch (op.kind) {
      case PatchOpKind.addField:
        final Object? field = args['field'];
        final Object? label = field is Map
            ? field['label'] ?? field['key']
            : null;
        return loc.aiOpAddField(list, '${label ?? ''}');
      case PatchOpKind.removeField:
        return loc.aiOpRemoveField(
          list,
          _fieldName(step.definition, args['key']),
        );
      case PatchOpKind.renameField:
        return loc.aiOpRenameField(
          list,
          _fieldName(step.definition, args['key']),
          '${args['label']}',
        );
      case PatchOpKind.changeFieldType:
      case PatchOpKind.setFieldProps:
      case PatchOpKind.setOptions:
      case PatchOpKind.moveField:
        return loc.aiOpChangeField(
          list,
          _fieldName(step.definition, args['key']),
        );
      case PatchOpKind.setView:
        final Object? view = args['view'];
        final ViewKind? kind = view is Map
            ? enumFromWire(ViewKind.values, view['kind'])
            : null;
        return loc.aiOpSetView(
          list,
          kind == null ? '${view ?? ''}' : labels.viewKind(kind),
        );
      case PatchOpKind.addBehavior:
      case PatchOpKind.removeBehavior:
        final Object? behavior = args['behavior'];
        final BehaviorKind? kind = enumFromWire(
          BehaviorKind.values,
          behavior is Map ? behavior['kind'] : args['kind'],
        );
        return loc.aiOpBehavior(
          list,
          kind == null ? '' : labels.behavior(kind),
        );
      case PatchOpKind.setListInfo:
        return loc.aiOpListInfo(list);
    }
  }
}
