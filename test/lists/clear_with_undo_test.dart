// Clearing with Undo (T-23 unit 2, Q-101).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/app_banner.dart';
import 'package:hybrid_note/backend/firestore_list_store.dart';
import 'package:hybrid_note/l10n/generated/app_localizations.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/clear_with_undo.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_rules.dart';

import '../support/firestore_store.dart';

final ListDefinition _grocery = BuiltinTemplates.grocery();
final ListDefinition _tasks = BuiltinTemplates.tasks();
final DateTime _t0 = DateTime.utc(2026, 3, 1, 9);
final AppLocalizations _loc = lookupAppLocalizations(const Locale('en'));

ListItem _item(ListDefinition list, String id, Map<String, dynamic> values) =>
    ListItem(id: id, listId: list.id, values: values, createdAt: _t0, updatedAt: _t0);

// Milk is kept for next time; Bread is not.
final ListItem _milk = _item(_grocery, 'milk', {
  'title': 'Milk',
  'done': true,
  'section': 'current',
  'autoAddToNext': true,
});
final ListItem _bread = _item(_grocery, 'bread', {
  'title': 'Bread',
  'done': true,
  'section': 'current',
});
final ListItem _eggs = _item(_grocery, 'eggs', {
  'title': 'Eggs',
  'done': false,
  'section': 'current',
});

Future<ListCatalog> _when(
  FirestoreListStore store,
  bool Function(List<ListItem> items) test,
) {
  return store
      .watch()
      .firstWhere((catalog) => test(catalog.itemsOf(_grocery.id)))
      .timeout(const Duration(seconds: 5));
}

void main() {
  group('ClearUndo', () {
    test('reverse puts the cleared items back with their ids and removes the copies', () {
      final List<ListItem> items = [_milk, _bread, _eggs];
      final ListChanges changes = ListRules.clearCompleted(
        _grocery,
        items,
        _t0,
        newId: () => 'copy',
      );
      final ClearUndo undo = ClearUndo.of(_grocery.id, items, changes);

      expect(undo.count, 2);
      expect(undo.created.single.id, 'copy');
      final ListChanges back = undo.reverse();
      expect(back.saved.map((item) => item.id), ['milk', 'bread']);
      expect(back.saved.first.values, _milk.values);
      expect(back.deletedIds, ['copy']);
    });

    test('a repeating task: Undo removes the next one', () {
      final ListItem call = _item(_tasks, 'call', {
        'title': 'Call',
        'done': true,
        'reminderAt': DateTime.utc(2026, 2, 26, 8).toIso8601String(),
        'repeat': {'frequency': 'daily'},
      });
      final ListChanges changes = ListRules.clearCompleted(_tasks, [call], _t0);
      final ClearUndo undo = ClearUndo.of(_tasks.id, [call], changes);

      expect(undo.reverse().saved.single.id, 'call');
      expect(undo.reverse().deletedIds, [changes.saved.single.id]);
    });

    test('is current only while things stay as the clear left them', () {
      final List<ListItem> items = [_milk, _eggs];
      final ListChanges changes = ListRules.clearCompleted(
        _grocery,
        items,
        _t0,
        newId: () => 'copy',
      );
      final ClearUndo undo = ClearUndo.of(_grocery.id, items, changes);
      final ListItem copy = changes.saved.single;

      expect(undo.isCurrent([_eggs, copy]), isTrue);
      // Eggs is not part of the clear: changing it does not count.
      expect(undo.isCurrent([ListRules.withValues(_eggs, {'title': 'Eggs!'}, _t0), copy]), isTrue);
      // The copy edited or deleted, or the cleared item back.
      expect(undo.isCurrent([_eggs, ListRules.withValues(copy, {'done': true}, _t0)]), isFalse);
      expect(undo.isCurrent([_eggs]), isFalse);
      expect(undo.isCurrent([_eggs, copy, _milk]), isFalse);
    });
  });

  group('ClearWithUndo', () {
    test('clears, shows "Cleared · Undo", and Undo restores', () async {
      final FirestoreListStore store = await fakeFirestoreStore(items: [_milk, _eggs]);
      final AppBannerController banners = AppBannerController();
      addTearDown(banners.dispose);

      await ClearWithUndo.run(
        store: store,
        definition: _grocery,
        items: store.current.itemsOf(_grocery.id),
        inScope: (item) => item.id == 'milk',
        banners: banners,
        loc: _loc,
      );
      final ListCatalog cleared = await _when(
        store,
        (items) => items.every((item) => item.id != 'milk') && items.length == 2,
      );
      final ListItem copy =
          cleared.itemsOf(_grocery.id).firstWhere((item) => item.id != 'eggs');
      expect(copy['section'], 'nextTime');
      expect(banners.text, 'Cleared');
      expect(banners.actionLabel, 'Undo');

      banners.act();
      final ListCatalog back = await _when(
        store,
        (items) => items.any((item) => item.id == 'milk') && items.length == 2,
      );
      final ListItem milk = back.itemsOf(_grocery.id).firstWhere((item) => item.id == 'milk');
      expect(milk.values, _milk.values);
      expect(back.itemsOf(_grocery.id).any((item) => item.id == copy.id), isFalse);
    });

    test('several at once say how many', () async {
      final FirestoreListStore store = await fakeFirestoreStore(items: [_milk, _bread]);
      final AppBannerController banners = AppBannerController();
      addTearDown(banners.dispose);

      await ClearWithUndo.run(
        store: store,
        definition: _grocery,
        items: store.current.itemsOf(_grocery.id),
        banners: banners,
        loc: _loc,
      );

      expect(banners.text, '2 cleared');
    });

    test('Undo goes away once the copy is changed', () async {
      final FirestoreListStore store = await fakeFirestoreStore(items: [_milk]);
      final AppBannerController banners = AppBannerController();
      addTearDown(banners.dispose);

      await ClearWithUndo.run(
        store: store,
        definition: _grocery,
        items: store.current.itemsOf(_grocery.id),
        banners: banners,
        loc: _loc,
      );
      final ListCatalog cleared = await _when(
        store,
        (items) => items.length == 1 && items.single.id != 'milk',
      );
      expect(banners.showing, isTrue);

      final ListItem copy = cleared.itemsOf(_grocery.id).single;
      await store.apply(ListChanges(saved: [ListRules.withValues(copy, {'title': 'Oat milk'}, _t0)]));
      await _when(store, (items) => items.single['title'] == 'Oat milk');
      await Future<void>.delayed(Duration.zero);

      expect(banners.showing, isFalse);
    });
  });
}
