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
}

// A deleted list with its items, kept in memory so Undo can bring it back
// (D-5).
class DeletedList {
  const DeletedList({required this.definition, required this.items});

  final ListDefinition definition;
  final List<ListItem> items;
}
