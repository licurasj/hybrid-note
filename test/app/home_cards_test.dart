import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/app/home_cards.dart';
import 'package:hybrid_note/app/list_order.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';

// Home's cards and how home and the dial share an order (T-22, Q-70, Q-75,
// Q-78, Q-79). The table in tasks/T-22-home-cards.md is what these check.

final DateTime _now = DateTime(2026, 11, 5, 12);

ListDefinition _list(String id) => ListDefinition.fromJson({
  ...BuiltinTemplates.tasks().toJson(),
  'id': id,
  'name': id,
});

ListItem _item(
  String listId, {
  bool done = false,
  DateTime? due,
  DateTime? changed,
}) {
  final DateTime at = changed ?? _now.subtract(const Duration(days: 30));
  return ListItem(
    id: '$listId-${due?.toIso8601String()}-$done-$at',
    listId: listId,
    values: {
      'title': 'An item',
      'done': done,
      if (due != null) 'reminderAt': due.toIso8601String(),
    },
    createdAt: at,
    updatedAt: at,
  );
}

({List<String> pinned, List<String> suggested}) _cards(
  ListCatalog catalog, {
  List<String> pins = const [],
  List<String> removed = const [],
  bool showSuggestions = true,
}) {
  final result = chooseHomeCards(
    catalog,
    pinnedOrder: homePinnedOrder(
      pins: pins,
      dialOrder: [for (final list in catalog.definitions) list.id],
      homeOrder: const [],
      homeArranged: false,
    ),
    removed: removed,
    showSuggestions: showSuggestions,
    now: _now,
  );
  return (
    pinned: [for (final list in result.pinned) list.id],
    suggested: [for (final list in result.suggested) list.id],
  );
}

ListCatalog _manyLists(int count) {
  final List<String> ids = [for (int i = 0; i < count; i++) 'l$i'];
  return ListCatalog(
    definitions: [for (final String id in ids) _list(id)],
    items: [for (final String id in ids) _item(id)],
  );
}

Future<AccountPreferencesCubit> _cubit([
  AccountPreferences start = const AccountPreferences(),
]) async {
  SharedPreferences.setMockInitialValues({
    AccountPreferencesCubit.mirrorKey('u'): jsonEncode(start.toJson()),
  });
  final AccountPreferencesCubit cubit = AccountPreferencesCubit(
    await SharedPreferences.getInstance(),
    'u',
  );
  addTearDown(cubit.close);
  return cubit;
}

void main() {
  group('how many cards', () {
    for (final (int pins, int suggestions) in [
      (0, 3),
      (1, 3),
      (2, 3),
      (3, 2),
      (4, 1),
      (5, 0),
      (6, 0),
      (9, 0),
    ]) {
      test('$pins pinned get $suggestions suggested', () {
        final result = _cards(
          _manyLists(12),
          pins: [for (int i = 0; i < pins; i++) 'l$i'],
        );
        expect(result.pinned, hasLength(pins));
        expect(result.suggested, hasLength(suggestions));
        expect(homeSuggestionCount(pins), suggestions);
      });
    }

    test('a suggestion is never also pinned', () {
      final result = _cards(_manyLists(6), pins: ['l0', 'l1']);
      expect(result.suggested, isNot(contains('l0')));
      expect(result.suggested, isNot(contains('l1')));
    });

    test('Show suggestions off leaves only pinned cards', () {
      final result = _cards(
        _manyLists(6),
        pins: ['l1'],
        showSuggestions: false,
      );
      expect(result.pinned, ['l1']);
      expect(result.suggested, isEmpty);
      expect(_cards(_manyLists(6), showSuggestions: false).pinned, isEmpty);
    });

    test('fewer lists than places leave the rest empty', () {
      expect(_cards(_manyLists(1)).suggested, ['l0']);
      expect(
        _cards(const ListCatalog(definitions: [], items: [])).suggested,
        isEmpty,
      );
    });
  });

  group('which lists are suggested', () {
    test('a list with no open items is not, but stays when pinned', () {
      final ListCatalog catalog = ListCatalog(
        definitions: [_list('ticked'), _list('empty'), _list('open')],
        items: [_item('ticked', done: true), _item('open')],
      );
      expect(_cards(catalog).suggested, ['open']);
      expect(_cards(catalog, pins: ['empty', 'ticked']).pinned, [
        'ticked',
        'empty',
      ]);
    });

    test('a removed list is not, and pinned it shows', () {
      final ListCatalog catalog = _manyLists(5);
      expect(_cards(catalog, removed: ['l0']).suggested, ['l1', 'l2', 'l3']);
      expect(_cards(catalog, removed: ['l0'], pins: ['l0']).pinned, ['l0']);
    });

    test('soonest due first, then the most recently changed', () {
      final ListCatalog catalog = ListCatalog(
        definitions: [
          _list('old'),
          _list('new'),
          _list('later'),
          _list('soon'),
        ],
        items: [
          _item('old', changed: _now.subtract(const Duration(days: 9))),
          _item('new', changed: _now.subtract(const Duration(days: 1))),
          _item('later', due: _now.add(const Duration(days: 6))),
          _item('soon', due: _now.add(const Duration(days: 1))),
        ],
      );
      expect(_cards(catalog).suggested, ['soon', 'later', 'new']);
    });

    test('overdue ranks first, and past seven days does not count as due', () {
      final ListCatalog catalog = ListCatalog(
        definitions: [_list('far'), _list('late'), _list('fresh')],
        items: [
          _item(
            'far',
            due: _now.add(const Duration(days: 8)),
            changed: _now.subtract(const Duration(days: 20)),
          ),
          _item('late', due: _now.subtract(const Duration(days: 2))),
          _item('fresh', changed: _now.subtract(const Duration(days: 1))),
        ],
      );
      expect(_cards(catalog).suggested, ['late', 'fresh', 'far']);
    });

    test('a done item does not rank its list as due', () {
      final ListCatalog catalog = ListCatalog(
        definitions: [_list('done'), _list('fresh')],
        items: [
          _item('done', done: true, due: _now),
          _item('done', changed: _now.subtract(const Duration(days: 9))),
          _item('fresh', changed: _now.subtract(const Duration(days: 1))),
        ],
      );
      expect(_cards(catalog).suggested, ['fresh', 'done']);
    });

    test('equal lists keep the catalog order', () {
      expect(_cards(_manyLists(5)).suggested, ['l0', 'l1', 'l2']);
    });
  });

  group('deleted lists', () {
    test('a pin or an order id with no list is skipped', () {
      expect(_cards(_manyLists(2), pins: ['gone', 'l1']).pinned, ['l1']);
      expect(
        homePinnedOrder(
          pins: ['l1', 'gone', 'l0'],
          dialOrder: ['l0', 'l1'],
          homeOrder: ['gone', 'l1', 'l0'],
          homeArranged: true,
        ),
        ['l1', 'l0'],
      );
    });

    test('a deleted pinned list does not take a place from suggestions', () {
      final result = _cards(
        _manyLists(9),
        pins: ['gone1', 'gone2', 'gone3', 'gone4', 'gone5', 'l0'],
      );
      expect(result.pinned, ['l0']);
      expect(result.suggested, hasLength(3));
    });

    test('writing drops ids with no list, keeping the order', () {
      expect(keepExistingIds(['b', 'gone', 'a', 'b'], ['a', 'b']), ['b', 'a']);
    });

    test('pinning and removing clean up what they write', () async {
      final AccountPreferencesCubit cubit = await _cubit(
        const AccountPreferences(
          homePins: ['gone', 'a'],
          homeRemoved: ['gone', 'c'],
        ),
      );
      await cubit.pinToHome('b', existing: ['a', 'b', 'c']);
      expect(cubit.state.homePins, ['a', 'b']);
      await cubit.removeFromHome('a', existing: ['a', 'b', 'c']);
      expect(cubit.state.homeRemoved, ['c', 'a']);
    });
  });

  group('home order', () {
    test('until arranged, pinned lists follow the dial', () {
      expect(
        homePinnedOrder(
          pins: ['a', 'c'],
          dialOrder: ['c', 'b', 'a'],
          homeOrder: ['a', 'c'],
          homeArranged: false,
        ),
        ['c', 'a'],
      );
    });

    test('once arranged, the dragged order holds and a new pin joins last', () {
      expect(
        homePinnedOrder(
          pins: ['d', 'a', 'c'],
          dialOrder: ['c', 'b', 'a', 'd'],
          homeOrder: ['a', 'b', 'c'],
          homeArranged: true,
        ),
        ['a', 'c', 'd'],
      );
    });

    test('merging keeps every other list in its place', () {
      expect(
        mergeHomeOrderIntoDial(['a', 'x', 'b', 'y', 'c', 'z'], ['c', 'a', 'b']),
        ['c', 'x', 'a', 'y', 'b', 'z'],
      );
    });

    test('merging skips ids with no list and repeats nothing', () {
      expect(mergeHomeOrderIntoDial(['a', 'x', 'b'], ['gone', 'b', 'a', 'b']), [
        'b',
        'x',
        'a',
      ]);
    });

    test('merging only some of the lists leaves the rest alone', () {
      expect(mergeHomeOrderIntoDial(['a', 'b', 'c'], ['c']), ['a', 'b', 'c']);
    });
  });

  // Home and the dial as the app reads them: the dial from orderLists, home
  // from homePinnedOrder.
  List<String> dialOf(AccountPreferencesCubit cubit, List<String> lists) => [
    for (final ListDefinition list in orderLists(
      [for (final String id in lists) _list(id)],
      order: cubit.state.listOrder,
      myOrder: cubit.state.myListOrder,
      recent: const [],
      nameOf: (definition) => definition.name!,
    ))
      list.id,
  ];

  List<String> homeOf(AccountPreferencesCubit cubit, List<String> lists) =>
      homePinnedOrder(
        pins: cubit.state.homePins,
        dialOrder: dialOf(cubit, lists),
        homeOrder: cubit.state.homeOrder,
        homeArranged: cubit.state.homeArranged,
      );

  group('home and the dial together (Q-75)', () {
    const List<String> lists = ['a', 'x', 'b', 'y', 'c'];
    const AccountPreferences pinned = AccountPreferences(
      homePins: ['a', 'b', 'c'],
    );

    test('nothing arranged: both follow the setting', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.setListOrder(ListOrder.alphabetical);
      expect(dialOf(cubit, ['c', 'a', 'x', 'b']), ['a', 'b', 'c', 'x']);
      expect(homeOf(cubit, ['c', 'a', 'x', 'b']), ['a', 'b', 'c']);
      expect(cubit.state.homeArranged, isFalse);
      expect(cubit.state.dialArranged, isFalse);
    });

    test('only the dial arranged: home follows it', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnDial(['c', 'y', 'b', 'x', 'a']);
      expect(cubit.state.listOrder, ListOrder.myOrder);
      expect(dialOf(cubit, lists), ['c', 'y', 'b', 'x', 'a']);
      expect(homeOf(cubit, lists), ['c', 'b', 'a']);
      expect(cubit.state.homeHasOwnOrder, isFalse);
    });

    test('only a home drag: the dial follows, as My order', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnHome(['c', 'a', 'b'], dialOrder: lists);
      expect(cubit.state.listOrder, ListOrder.myOrder);
      expect(homeOf(cubit, lists), ['c', 'a', 'b']);
      expect(dialOf(cubit, lists), ['c', 'x', 'a', 'y', 'b']);
      expect(cubit.state.homeHasOwnOrder, isFalse);
    });

    test('a second home drag moves the dial again', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnHome(['c', 'a', 'b'], dialOrder: lists);
      await cubit.arrangedOnHome([
        'b',
        'c',
        'a',
      ], dialOrder: dialOf(cubit, lists));
      expect(dialOf(cubit, lists), ['b', 'x', 'c', 'y', 'a']);
      expect(cubit.state.dialArranged, isFalse);
    });

    test('both arranged, dial first: a home drag leaves the dial', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnDial(['y', 'x', 'c', 'b', 'a']);
      await cubit.arrangedOnHome([
        'a',
        'c',
        'b',
      ], dialOrder: dialOf(cubit, lists));
      expect(homeOf(cubit, lists), ['a', 'c', 'b']);
      expect(dialOf(cubit, lists), ['y', 'x', 'c', 'b', 'a']);
      expect(cubit.state.homeHasOwnOrder, isTrue);
    });

    test('both arranged, home first: a dial drag leaves home', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnHome(['c', 'a', 'b'], dialOrder: lists);
      await cubit.arrangedOnDial(['y', 'b', 'x', 'a', 'c']);
      expect(homeOf(cubit, lists), ['c', 'a', 'b']);
      expect(dialOf(cubit, lists), ['y', 'b', 'x', 'a', 'c']);
      expect(cubit.state.homeHasOwnOrder, isTrue);
    });

    for (final ListOrder order in [
      ListOrder.lastUsed,
      ListOrder.alphabetical,
    ]) {
      test('${order.wire} after a home drag splits them', () async {
        final AccountPreferencesCubit cubit = await _cubit(pinned);
        await cubit.arrangedOnHome(['c', 'a', 'b'], dialOrder: lists);
        await cubit.setListOrder(order);
        expect(cubit.state.homeHasOwnOrder, isTrue);
        expect(homeOf(cubit, lists), ['c', 'a', 'b']);
      });

      test('${order.wire} with no home drag does not', () async {
        final AccountPreferencesCubit cubit = await _cubit(pinned);
        await cubit.setListOrder(order);
        expect(cubit.state.dialArranged, isFalse);
        expect(cubit.state.homeHasOwnOrder, isFalse);
      });
    }

    test('My order after a home drag does not split them', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnHome(['c', 'a', 'b'], dialOrder: lists);
      await cubit.setListOrder(ListOrder.myOrder);
      expect(cubit.state.homeHasOwnOrder, isFalse);
    });

    test('Match dial order leaves only the dial arranged', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnDial(['y', 'x', 'c', 'b', 'a']);
      await cubit.arrangedOnHome([
        'a',
        'c',
        'b',
      ], dialOrder: dialOf(cubit, lists));
      await cubit.matchDialOrder();
      expect(cubit.state.homeHasOwnOrder, isFalse);
      expect(cubit.state.homeArranged, isFalse);
      expect(cubit.state.dialArranged, isTrue);
      expect(cubit.state.homeOrder, isEmpty);
      expect(homeOf(cubit, lists), ['c', 'b', 'a']);
    });

    test(
      'a list pinned after a home drag joins the end of home only',
      () async {
        final AccountPreferencesCubit cubit = await _cubit(pinned);
        await cubit.arrangedOnHome(['c', 'a', 'b'], dialOrder: lists);
        final List<String> dialBefore = dialOf(cubit, lists);
        await cubit.pinToHome('x', existing: lists);
        expect(homeOf(cubit, lists), ['c', 'a', 'b', 'x']);
        expect(dialOf(cubit, lists), dialBefore);
      },
    );
  });

  group('pins and removals', () {
    const List<String> lists = ['a', 'b', 'c'];

    test('pinning a removed list brings it back for good', () async {
      final AccountPreferencesCubit cubit = await _cubit(
        const AccountPreferences(homeRemoved: ['a', 'b']),
      );
      await cubit.pinToHome('a', existing: lists);
      await cubit.unpinFromHome('a');
      expect(cubit.state.homeRemoved, ['b']);
    });

    test('pinning twice keeps one pin', () async {
      final AccountPreferencesCubit cubit = await _cubit();
      await cubit.pinToHome('a', existing: lists);
      await cubit.pinToHome('a', existing: lists);
      expect(cubit.state.homePins, ['a']);
    });

    test('tapping an unfilled pin again keeps the arranged place', () async {
      final AccountPreferencesCubit cubit = await _cubit(
        const AccountPreferences(
          homePins: ['b', 'a', 'c'],
          homeOrder: ['b', 'a', 'c'],
          homeArranged: true,
        ),
      );
      await cubit.unpinFromHome('a');
      await cubit.pinToHome('a', existing: lists, keepPlace: true);
      expect(homeOf(cubit, lists), ['b', 'a', 'c']);
    });

    test('pinning again later goes to the end', () async {
      final AccountPreferencesCubit cubit = await _cubit(
        const AccountPreferences(
          homePins: ['b', 'a', 'c'],
          homeOrder: ['b', 'a', 'c'],
          homeArranged: true,
        ),
      );
      await cubit.unpinFromHome('a');
      await cubit.pinToHome('a', existing: lists);
      expect(homeOf(cubit, lists), ['b', 'c', 'a']);
    });

    test('Undo takes a removal back', () async {
      final AccountPreferencesCubit cubit = await _cubit();
      await cubit.removeFromHome('a', existing: lists);
      expect(cubit.state.homeRemoved, ['a']);
      await cubit.undoRemoveFromHome('a');
      expect(cubit.state.homeRemoved, isEmpty);
    });

    test('the switches change only themselves', () async {
      final AccountPreferencesCubit cubit = await _cubit(
        const AccountPreferences(homePins: ['a'], homeRemoved: ['b']),
      );
      await cubit.setHomeSuggestions(false);
      await cubit.setHomeCards(false);
      expect(
        cubit.state,
        const AccountPreferences(
          homePins: ['a'],
          homeRemoved: ['b'],
          homeSuggestions: false,
          homeCards: false,
        ),
      );
    });
  });
}
