// A list's own Ticked items and Confirm before deleting (T-24 unit 3, Q-117,
// Q-118): stored on the list, absent meaning Follow Preferences.
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_error.dart';
import 'package:hybrid_note/lists/list_patch.dart';

final DateTime _t0 = DateTime.utc(2026, 3, 1, 9);

ListDefinition _patched(ListDefinition list, Map<String, dynamic> info) {
  final ListPatchResult result = ListPatch.apply(
    list,
    const [],
    [ListPatchOp(PatchOpKind.setListInfo, info)],
    _t0,
  );
  expect(result.errors, isEmpty);
  return result.definition;
}

void main() {
  final ListDefinition grocery = BuiltinTemplates.grocery();

  test('an old list document follows Preferences', () {
    expect(grocery.ownTickedItems, isNull);
    expect(grocery.ownConfirmDelete, isNull);
    expect(grocery.toJson().containsKey('tickedItems'), isFalse);
  });

  test('setListInfo sets, keeps through JSON, and clears with null', () {
    final ListDefinition own = _patched(grocery, {
      'tickedItems': 'hide',
      'confirmDelete': true,
    });
    expect(own.ownTickedItems, 'hide');
    expect(own.ownConfirmDelete, isTrue);
    final ListDefinition stored = ListDefinition.fromJson(own.toJson());
    expect(stored.ownTickedItems, 'hide');
    expect(stored.ownConfirmDelete, isTrue);
    expect(stored.validate(), isEmpty);

    // Another change keeps them (the AI's edits too: they go through apply).
    final ListDefinition renamed = _patched(stored, {'name': 'Food'});
    expect(renamed.ownTickedItems, 'hide');

    final ListDefinition follows = _patched(stored, {'tickedItems': null});
    expect(follows.ownTickedItems, isNull);
    expect(follows.ownConfirmDelete, isTrue);
    expect(follows.toJson().containsKey('tickedItems'), isFalse);
  });

  test('a wrong type is refused', () {
    final ListPatchResult result = ListPatch.apply(
      grocery,
      const [],
      [ListPatchOp(PatchOpKind.setListInfo, {'confirmDelete': 'yes'})],
      _t0,
    );
    expect(result.errors.map((error) => error.code), contains(ListErrorCode.badOp));
  });

  test('Ticked items must be one of its wire values', () {
    final ListPatchResult junk = ListPatch.apply(
      grocery,
      const [],
      [ListPatchOp(PatchOpKind.setListInfo, {'tickedItems': 'sometimes'})],
      _t0,
    );
    expect(junk.errors.map((error) => error.code), contains(ListErrorCode.badOp));
    expect(
      ListDefinition.tickedItemsWires,
      TickedItems.values.map((ticked) => ticked.wire).toSet(),
    );
    for (final String wire in ListDefinition.tickedItemsWires) {
      expect(_patched(grocery, {'tickedItems': wire}).ownTickedItems, wire);
    }
  });

  group('the value a list uses', () {
    late final ListDefinition own;
    setUpAll(() {
      own = _patched(grocery, {
        'tickedItems': 'clearAtOnce',
        'confirmDelete': true,
      });
    });

    test('its own while lists can have their own; a change in Preferences moves only the others', () {
      const AccountPreferences preferences = AccountPreferences(
        tickedItems: TickedItems.stayInPlace,
      );
      expect(preferences.tickedItemsFor(own), TickedItems.clearAtOnce);
      expect(preferences.tickedItemsFor(grocery), TickedItems.stayInPlace);
      expect(preferences.confirmDeleteFor(own), isTrue);
      expect(preferences.confirmDeleteFor(grocery), isFalse);
      expect(preferences.tickedItemsFor(null), TickedItems.stayInPlace);
    });

    test('Lists can have their own off: every list follows, and on again restores', () {
      const AccountPreferences off = AccountPreferences(
        listsOwnTickedItems: false,
        listsOwnConfirmDelete: false,
      );
      expect(off.tickedItemsFor(own), TickedItems.moveToDone);
      expect(off.confirmDeleteFor(own), isFalse);
      const AccountPreferences on = AccountPreferences();
      expect(on.tickedItemsFor(own), TickedItems.clearAtOnce);
    });

    test('the switches sync, on by default', () {
      expect(AccountPreferences.fromJson(const {}).listsOwnTickedItems, isTrue);
      final AccountPreferences read = AccountPreferences.fromJson(
        const AccountPreferences(listsOwnConfirmDelete: false).toJson(),
      );
      expect(read.listsOwnConfirmDelete, isFalse);
      expect(read.listsOwnTickedItems, isTrue);
    });
  });
}
