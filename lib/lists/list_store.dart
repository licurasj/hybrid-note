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
  // list does not exist.
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

  // A patch (patch_list) applied by patchList to [definition] and [items].
  factory ListSnapshot.ofPatch(
    ListDefinition definition,
    List<ListItem> items,
    ListPatchResult result,
  ) {
    final Map<String, ListItem> current = {for (final ListItem item in items) item.id: item};
    return ListSnapshot(
      before: definition,
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
