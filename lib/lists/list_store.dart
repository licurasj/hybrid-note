import 'list_catalog.dart';
import 'list_definition.dart';
import 'list_error.dart';
import 'list_item.dart';
import 'list_patch.dart';
import 'list_rules.dart';

// Where the screens read and write lists. FirestoreListStore implements it
// for the signed-in user (T-17) and runs the shared contract tests
// (test/lists/list_store_contract_test.dart).
//
// Fit for Firestore (Q-5 A: lists/{listId} with an items subcollection, in
// the list engine JSON format):
// - Every write is async and may finish after the UI moved on; the read side
//   reports the result, so callers do not wait for it to redraw.
// - The read side is not one coherent snapshot per write (D-12): a store may
//   merge a listener on the lists with one per list's items, so after the
//   initial load a change may arrive in steps (a list before its items, a
//   deleted list's items after the list). Only the initial load is whole.
// - Ids are made by the client (list and item ids are UUID-based), so a
//   write never waits for the store to hand out an id.
// - patchList applies the ops on the store's current data, not on what the
//   caller saw (Q-12 A), so two devices do not overwrite each other. In
//   Firestore that needs a transaction; a transaction reads documents, not a
//   query, so how it also covers an item added meanwhile by another device
//   is FirestoreListStore's to settle and test (T-14).
// - deleteList is a subtree delete (the list document and all its items); it
//   returns what restoreList needs to bring both back (Undo, D-5).
// - restoreSnapshot undoes an AI change (Q-35 A): it puts back the list as
//   it was before, but only while the list is still as the change left it.
// - A store may refuse a write. patchList and createList return the reasons
//   and change nothing in that case.
abstract interface class ListStore {
  // The most item changes one AI answer may make (Q-60): what one Firestore
  // write holds.
  static const int maxAiWrites = 500;

  // Read side (Q-11 A): every list and item in one catalog. watch() emits
  // nothing until the initial load is complete (every list with its items,
  // D-12); then it emits the latest catalog to each new listener and a new
  // one after each change, possibly in several steps (see above). current is
  // the latest catalog, empty before the initial load. A caller that needs a
  // write's full result waits on watch() until all of it is there.
  ListCatalog get current;
  Stream<ListCatalog> watch();

  // Item writes.
  Future<void> apply(ListChanges changes);

  // Adds or removes a user option of a category or tags field (for example a
  // task category). Removing may be refused while items still use it.
  Future<void> addOption(String listId, String fieldKey, String value);
  Future<void> removeOption(String listId, String fieldKey, String value);

  Future<void> refresh();

  // List writes. createList validates the definition and items (including
  // unique item ids) and returns the errors (Q-14 A: codes the screens
  // translate, English in toString()); empty means the list was created,
  // otherwise nothing changed.
  Future<List<ListError>> createList(
    ListDefinition definition, {
    List<ListItem> items = const [],
  });

  // Applies ops to the list's current definition and items and saves the
  // result only when it is valid. Name, icon, colour and AI changes of the
  // built-in lists go through here too (setListInfo). Returns null when the
  // list does not exist. A change to more items than one write holds returns
  // once the definition is saved, with itemsPending set; its items follow
  // (Q-59).
  Future<ListPatchResult?> patchList(String listId, List<ListPatchOp> ops);

  // Returns null when the list does not exist or cannot be deleted.
  Future<DeletedList?> deleteList(String listId);
  Future<void> restoreList(DeletedList deleted);

  // Undo of an AI change (Q-35 A): writes back the definition and the
  // touched items as they were before the change (an item the change added
  // is deleted again), in one step, but only while the list's definition and
  // those items are still exactly as the change left them. Otherwise, or
  // when the list is gone, it changes nothing and returns listChanged.
  // Items the change did not touch are not compared. A restored definition
  // gets a new schemaRevision, so items saved for the changed one are fitted
  // to it like after any patch. A store that writes in one step of limited
  // size refuses a larger snapshot with undoTooLarge and changes nothing
  // (L13 of the T-19 unit 5 review). Empty means restored.
  Future<List<ListError>> restoreSnapshot(ListSnapshot snapshot);

  // An AI answer's item step, in one step against the stored data (Q-51, Q-53):
  // refused with aiNotAllowed when the list has AI off now, and with
  // previewChanged per AiItemWrite.over. A store that cannot read the stored
  // data refuses with needsConnection, except for a write that only adds items,
  // which overwrites nothing and may queue. More changes than one write holds
  // are refused with answerTooLarge (Q-60).
  //
  // needsConnection means nothing was or will be written. These writes, like
  // the two below, return outcomeUnknown instead when they reached the server
  // and it has not answered in time: the change may still land (Q-58).
  Future<AiWriteResult> applyAiItems(AiItemWrite write);

  // patchList for an AI answer: the same refusals (needsConnection with no
  // exception), as the result's errors; [previewed] is the definition the
  // preview showed. Returns null when the list does not exist.
  Future<ListPatchResult?> patchListAi(
    String listId,
    List<ListPatchOp> ops, {
    required ListDefinition previewed,
  });

  // Undo of a list an AI answer created (Q-52): deletes it only while it and
  // its items are still exactly as created; otherwise, or when the list is
  // gone, it changes nothing and returns listChanged. needsConnection and
  // undoTooLarge as above. Empty means deleted.
  Future<List<ListError>> deleteCreatedList(CreatedList created);
}

// A list as an AI answer created it.
class CreatedList {
  const CreatedList(this.definition, this.items);

  final ListDefinition definition;
  final List<ListItem> items;

  String get listId => definition.id;

  bool isCurrent(ListDefinition? stored, Iterable<ListItem> storedItems) {
    if (stored == null ||
        !ListSnapshot.sameJson(stored.toJson(), definition.toJson()) ||
        storedItems.length != items.length) {
      return false;
    }
    final Map<String, ListItem> byId = {for (final ListItem item in storedItems) item.id: item};
    return items.every(
      (item) =>
          byId[item.id] != null &&
          ListSnapshot.sameJson(byId[item.id]!.toJson(), item.toJson()),
    );
  }
}

// An AI answer's item step as its preview showed it (Q-51). [saved] holds whole
// items as they would be, [base] the existing ones among the touched items as
// the preview read them; only what differs between the two is the AI's change.
class AiItemWrite {
  const AiItemWrite({
    required this.definition,
    this.saved = const [],
    this.deletedIds = const [],
    this.base = const {},
  });

  final ListDefinition definition;
  final List<ListItem> saved;
  final List<String> deletedIds;
  final Map<String, ListItem> base;

  String get listId => definition.id;

  bool get addsOnly => base.isEmpty && deletedIds.isEmpty;

  // The documents this step writes.
  int get writes => saved.length + deletedIds.length;

  // The ids a store must read for [over].
  Set<String> get touchedIds => {
    ...base.keys,
    for (final ListItem item in saved) item.id,
  };

  // Works the step out over the list and items as stored ([items] by id, at
  // least the [touchedIds]). A new item already stored is this write's own
  // retry when it is unchanged, and refused otherwise: it must never replace an
  // edit made since (R2 of the Codex re-review). A changed item keeps what happened to its other
  // fields since the preview. Refused with previewChanged when the list is gone
  // or its fields changed, an item to change is gone, a field the AI changes
  // was meanwhile set to something else, or an item to delete has other values
  // by now (a delete would lose them).
  AiWriteResult over(ListDefinition? list, Map<String, ListItem> items) {
    if (list != null && !list.aiAllowed) {
      return AiWriteResult.refused(ListErrorCode.aiNotAllowed, listId);
    }
    if (list == null || !sameFields(list, definition)) {
      return AiWriteResult.refused(ListErrorCode.previewChanged, listId);
    }
    final List<ListItem> merged = [];
    final Map<String, ListItem?> before = {};
    for (final ListItem item in saved) {
      final ListItem? previewed = base[item.id];
      if (previewed == null) {
        final ListItem? stored = items[item.id];
        if (stored != null &&
            !ListSnapshot.sameJson(stored.toJson(), item.toJson())) {
          return AiWriteResult.refused(ListErrorCode.previewChanged, listId);
        }
        merged.add(item);
        before[item.id] = null;
        continue;
      }
      final ListItem? current = items[item.id];
      final ListItem? result = current == null ? null : _merge(previewed, item, current);
      if (result == null) {
        return AiWriteResult.refused(ListErrorCode.previewChanged, listId);
      }
      merged.add(result);
      before[item.id] = current;
    }
    final List<String> deleted = [];
    for (final String id in deletedIds) {
      final ListItem? current = items[id];
      if (current == null) {
        continue;
      }
      final ListItem? previewed = base[id];
      if (previewed == null ||
          !ListSnapshot.sameJson(current.values, previewed.values)) {
        return AiWriteResult.refused(ListErrorCode.previewChanged, listId);
      }
      deleted.add(id);
      before[id] = current;
    }
    final List<ListError> errors = [
      for (final ListItem item in merged)
        for (final ListError error in item.validateAgainst(list))
          error.forItem(item.id),
    ];
    if (errors.isNotEmpty) {
      return AiWriteResult(errors: errors);
    }
    return AiWriteResult(
      saved: merged,
      deletedIds: deleted,
      snapshot: ListSnapshot(
        before: list,
        after: list,
        itemsBefore: before,
        itemsAfter: {
          for (final ListItem item in merged) item.id: item,
          for (final String id in deleted) id: null,
        },
      ),
    );
  }

  // [proposed]'s differences from [previewed] over [current]; null when both
  // changed a field to different values.
  static ListItem? _merge(ListItem previewed, ListItem proposed, ListItem current) {
    final Map<String, dynamic> values = Map<String, dynamic>.from(current.values);
    for (final String key in {...previewed.values.keys, ...proposed.values.keys}) {
      final Object? wanted = proposed.values[key];
      final Object? was = previewed.values[key];
      if (ListSnapshot.sameJson(wanted, was)) {
        continue;
      }
      final Object? now = current.values[key];
      if (!ListSnapshot.sameJson(now, was) && !ListSnapshot.sameJson(now, wanted)) {
        return null;
      }
      if (wanted == null) {
        values.remove(key);
      } else {
        values[key] = wanted;
      }
    }
    return ListItem(
      id: current.id,
      listId: current.listId,
      values: values,
      createdAt: current.createdAt,
      updatedAt: proposed.updatedAt,
    );
  }

  // Whether a preview made for [previewed] still fits [stored] (Q-51).
  static bool sameFields(ListDefinition stored, ListDefinition previewed) {
    return ListSnapshot.sameJson(
      stored.toJson()['fields'],
      previewed.toJson()['fields'],
    );
  }
}

// What an AI item step did or why it was refused: [errors] empty means the
// store wrote [saved] and [deletedIds], and [snapshot] takes them back.
class AiWriteResult {
  const AiWriteResult({
    this.errors = const [],
    this.saved = const [],
    this.deletedIds = const [],
    this.snapshot,
  });

  factory AiWriteResult.refused(ListErrorCode code, String listId) {
    return AiWriteResult(errors: [ListError(code, {'list': listId})]);
  }

  final List<ListError> errors;
  final List<ListItem> saved;
  final List<String> deletedIds;
  final ListSnapshot? snapshot;

  bool get isValid => errors.isEmpty;
}

// A list before and after one change, for restoreSnapshot. Items are by id;
// null means the item did not exist on that side.
class ListSnapshot {
  const ListSnapshot({
    required this.before,
    required this.after,
    this.itemsBefore = const {},
    this.itemsAfter = const {},
  });

  // An item change (upsert_items, delete_items) to a list whose definition
  // and items were [definition] and [items] before it. [items] must be the
  // store's items read when the change is applied, not an older copy, or
  // undo would write back stale values (L11 of the T-19 unit 5 review).
  factory ListSnapshot.ofChanges(
    ListDefinition definition,
    List<ListItem> items,
    ListChanges changes,
  ) {
    final Map<String, ListItem> current = {for (final ListItem item in items) item.id: item};
    return ListSnapshot(
      before: definition,
      after: definition,
      itemsBefore: {
        for (final ListItem item in changes.saved) item.id: current[item.id],
        for (final String id in changes.deletedIds) id: current[id],
      },
      itemsAfter: {
        for (final ListItem item in changes.saved) item.id: item,
        for (final String id in changes.deletedIds) id: null,
      },
    );
  }

  // A patch (patch_list), with what its own write read as the before-images
  // (H6 of the Codex review).
  factory ListSnapshot.ofPatch(ListPatchResult result) {
    final Map<String, ListItem> current = {
      for (final ListItem item in result.itemsBefore) item.id: item,
    };
    return ListSnapshot(
      before: result.definitionBefore,
      after: result.definition,
      itemsBefore: {for (final String id in result.changedItemIds) id: current[id]},
      itemsAfter: {
        for (final ListItem item in result.items)
          if (result.changedItemIds.contains(item.id)) item.id: item,
      },
    );
  }

  final ListDefinition before;
  final ListDefinition after;
  final Map<String, ListItem?> itemsBefore;
  final Map<String, ListItem?> itemsAfter;

  String get listId => after.id;

  // This change and the [next] one on the same list as one change, so an Undo
  // does not trip over its own restored revision (M3 of the Codex review).
  // Null when something else happened between them: [next] did not start where
  // this one ended, and joining them would write over that.
  ListSnapshot? followedBy(ListSnapshot next) {
    if (next.listId != listId || !sameJson(after.toJson(), next.before.toJson())) {
      return null;
    }
    for (final MapEntry<String, ListItem?> entry in next.itemsBefore.entries) {
      if (itemsAfter.containsKey(entry.key) &&
          !sameJson(itemsAfter[entry.key]?.toJson(), entry.value?.toJson())) {
        return null;
      }
    }
    return ListSnapshot(
      before: before,
      after: next.after,
      itemsBefore: {...next.itemsBefore, ...itemsBefore},
      itemsAfter: {...itemsAfter, ...next.itemsAfter},
    );
  }

  // Every item id the change touched.
  Set<String> get itemIds => {...itemsBefore.keys, ...itemsAfter.keys};

  // Whether [definition] and [items] (the touched ones found in the store,
  // by id) are still as the change left them.
  bool isCurrent(ListDefinition? definition, Map<String, ListItem> items) {
    if (definition == null || !sameJson(definition.toJson(), after.toJson())) {
      return false;
    }
    for (final String id in itemIds) {
      final ListItem? expected = itemsAfter[id];
      final ListItem? found = items[id];
      if ((expected == null) != (found == null) ||
          (expected != null && !sameJson(found!.toJson(), expected.toJson()))) {
        return false;
      }
    }
    return true;
  }

  // The definition to write back, with a schemaRevision above [current]'s;
  // null when the change did not touch the definition.
  ListDefinition? restoredDefinition(ListDefinition current, DateTime now) {
    if (sameJson(before.toJson(), after.toJson())) {
      return null;
    }
    return ListDefinition.fromJson({
      ...before.toJson(),
      'schemaRevision': current.schemaRevision + 1,
      'updatedAt': now.toIso8601String(),
    });
  }

  // Deep equality of JSON values; numbers compare by value.
  static bool sameJson(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && sameJson(a[key], b[key]));
    }
    if (a is List && b is List) {
      if (a.length != b.length) {
        return false;
      }
      for (int i = 0; i < a.length; i++) {
        if (!sameJson(a[i], b[i])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }
}

// A deleted list with its items, kept in memory so Undo can bring it back
// (D-5).
class DeletedList {
  const DeletedList({required this.definition, required this.items});

  final ListDefinition definition;
  final List<ListItem> items;
}
