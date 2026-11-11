import '../app/account_preferences.dart';
import '../lists/list_definition.dart';
import '../lists/list_item.dart';
import '../lists/list_rules.dart';
import '../lists/list_vocabulary.dart';

// What Done on a ring changes (T-13 unit 4, Q-97): the same as a tick on the
// list, worked out from a fresh copy of the item. A list that clears ticked
// items at once (Q-119) clears it, so a repeat comes again; elsewhere it is
// ticked. There is no Undo on a notification.
class ReminderDone {
  ReminderDone._();

  // Nothing when the item is ticked already or its date is no longer the one
  // the ring was booked for (it moved, or a repeat came round since). With
  // [mayClear] false (offline, F1) it only ticks, even on a list that clears
  // at once: a clear deletes and creates items, which needs the server.
  static ListChanges changes({
    required ListDefinition definition,
    required ListItem item,
    required String itemDate,
    required AccountPreferences preferences,
    required DateTime now,
    bool mayClear = true,
  }) {
    final FieldDefinition? date = definition.fieldWithRole(FieldRole.reminder);
    final FieldDefinition? completion = definition.fieldWithRole(
      FieldRole.completion,
    );
    if (date == null ||
        completion == null ||
        item[date.key] != itemDate ||
        item[completion.key] == true) {
      return const ListChanges();
    }
    final bool clearsAtOnce =
        mayClear &&
        definition.behaviors.any(
          (behavior) => behavior.kind == BehaviorKind.clearCompleted,
        ) &&
        preferences.tickedItemsFor(definition) == TickedItems.clearAtOnce;
    final ListChanges ticked = ListRules.setCompleted(
      definition,
      item,
      true,
      now,
    );
    if (!clearsAtOnce || ticked.saved.isEmpty) {
      return ticked;
    }
    final ListItem tickedItem = ticked.saved.first;
    return ListRules.clearCompleted(
      definition,
      [tickedItem],
      now,
      inScope: (candidate) => candidate.id == tickedItem.id,
    );
  }
}
