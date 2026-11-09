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
      existing: [for (final list in catalog.definitions) list.id],
      sortedOrder: [for (final list in catalog.definitions) list.id],
      homeOrder: const [],
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

  group('a card\'s top items', () {
    ListItem dated(
      String id, {
      DateTime? due,
      DateTime? made,
      bool done = false,
    }) {
      final DateTime at = made ?? _now;
      return ListItem(
        id: id,
        listId: 'l',
        values: {
          'title': id,
          'done': done,
          if (due != null) 'reminderAt': due.toIso8601String(),
        },
        createdAt: at,
        updatedAt: at,
      );
    }

    List<String> top(ListDefinition list, List<ListItem> items) => [
      for (final ListItem item in homeTopItems(list, items)) item.id,
    ];

    test('earliest due first, overdue leading, then newest', () {
      expect(
        top(_list('l'), [
          dated('old', made: _now.subtract(const Duration(days: 9))),
          dated('next-week', due: _now.add(const Duration(days: 8))),
          dated('tomorrow', due: _now.add(const Duration(days: 1))),
          dated('new', made: _now.subtract(const Duration(days: 1))),
          dated('late', due: _now.subtract(const Duration(days: 3))),
        ]),
        ['late', 'tomorrow', 'next-week', 'new', 'old'],
      );
    });

    test('done items do not count, however soon', () {
      expect(
        top(_list('l'), [dated('done', due: _now, done: true), dated('open')]),
        ['open'],
      );
    });

    test('a list with no reminders is newest first, whatever its dates', () {
      final ListDefinition journal = ListDefinition.fromJson({
        ...BuiltinTemplates.journal().toJson(),
        'id': 'l',
      });
      ListItem entry(String id, DateTime made) => ListItem(
        id: id,
        listId: 'l',
        values: {'title': id, 'date': made.toIso8601String()},
        createdAt: made,
        updatedAt: made,
      );
      expect(
        top(journal, [
          entry('older', _now.subtract(const Duration(days: 5))),
          entry('newer', _now.subtract(const Duration(days: 1))),
        ]),
        ['newer', 'older'],
      );
    });
  });

  group('what home shows', () {
    test('each choice, and an unknown one is both', () {
      expect(HomeContent.both.showsCards && HomeContent.both.showsDue, isTrue);
      expect(HomeContent.cards.showsCards, isTrue);
      expect(HomeContent.cards.showsDue, isFalse);
      expect(HomeContent.dueToday.showsCards, isFalse);
      expect(HomeContent.dueToday.showsDue, isTrue);
      expect(HomeContent.of('later'), HomeContent.both);
    });
  });

  group('deleted lists', () {
    test('a pin or an order id with no list is skipped', () {
      expect(_cards(_manyLists(2), pins: ['gone', 'l1']).pinned, ['l1']);
      expect(
        homePinnedOrder(
          pins: ['l1', 'gone', 'l0'],
          existing: ['l0', 'l1'],
          sortedOrder: null,
          homeOrder: ['gone', 'l1', 'l0'],
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
    test('sorted: the pinned lists in that order', () {
      expect(
        homePinnedOrder(
          pins: ['a', 'c'],
          existing: ['a', 'b', 'c'],
          sortedOrder: ['c', 'b', 'a'],
          homeOrder: ['a', 'c'],
        ),
        ['c', 'a'],
      );
    });

    test('My order: the dragged order holds and a new pin joins last', () {
      expect(
        homePinnedOrder(
          pins: ['d', 'a', 'c'],
          existing: ['c', 'b', 'a', 'd'],
          sortedOrder: null,
          homeOrder: ['a', 'b', 'c'],
        ),
        ['a', 'c', 'd'],
      );
    });
  });

  // Home and the dial as the app reads them: the dial from orderLists, home
  // from homePinnedOrder with Home list order (Q-108).
  List<String> idsIn(
    AccountPreferencesCubit cubit,
    List<String> lists,
    ListOrder order,
  ) => [
    for (final ListDefinition list in orderLists(
      [for (final String id in lists) _list(id)],
      order: order,
      myOrder: cubit.state.myListOrder,
      recent: const [],
      nameOf: (definition) => definition.name!,
    ))
      list.id,
  ];

  List<String> dialOf(AccountPreferencesCubit cubit, List<String> lists) =>
      idsIn(cubit, lists, cubit.state.listOrder);

  List<String> homeOf(AccountPreferencesCubit cubit, List<String> lists) =>
      homePinnedOrder(
        pins: cubit.state.homePins,
        existing: lists,
        sortedOrder: switch (cubit.state.homeSortedBy) {
          null => null,
          final ListOrder order => idsIn(cubit, lists, order),
        },
        homeOrder: cubit.state.homeOrder,
      );

  group('Dial list order and Home list order (Q-108)', () {
    const List<String> lists = ['a', 'x', 'b', 'y', 'c'];
    const AccountPreferences pinned = AccountPreferences(
      homePins: ['c', 'a', 'b'],
    );

    test(
      'Same as dial is the default, and home follows each dial order',
      () async {
        final AccountPreferencesCubit cubit = await _cubit(pinned);
        expect(cubit.state.homeListOrder, HomeListOrder.sameAsDial);
        await cubit.setListOrder(ListOrder.alphabetical);
        expect(homeOf(cubit, lists), ['a', 'b', 'c']);
        await cubit.arrangedOnDial(['c', 'y', 'b', 'x', 'a']);
        expect(homeOf(cubit, lists), ['c', 'b', 'a']);
        expect(cubit.state.homeListOrder, HomeListOrder.sameAsDial);
      },
    );

    test('home on its own sort while the dial is on My order', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnDial(['c', 'y', 'b', 'x', 'a']);
      await cubit.setHomeListOrder(HomeListOrder.alphabetical);
      expect(homeOf(cubit, lists), ['a', 'b', 'c']);
      expect(dialOf(cubit, lists), ['c', 'y', 'b', 'x', 'a']);
      await cubit.setHomeListOrder(HomeListOrder.lastUsed);
      // No list used yet: the order they were made in.
      expect(homeOf(cubit, lists), ['a', 'b', 'c']);
    });

    test(
      'a home drag on Same as dial makes it My order and leaves the dial (A)',
      () async {
        final AccountPreferencesCubit cubit = await _cubit(pinned);
        await cubit.setListOrder(ListOrder.alphabetical);
        await cubit.arrangedOnHome(['c', 'a', 'b']);
        expect(cubit.state.homeListOrder, HomeListOrder.myOrder);
        expect(homeOf(cubit, lists), ['c', 'a', 'b']);
        expect(cubit.state.listOrder, ListOrder.alphabetical);
        expect(cubit.state.myListOrder, isEmpty);
        expect(dialOf(cubit, lists), ['a', 'b', 'c', 'x', 'y']);
      },
    );

    test('a dial drag leaves home on My order alone', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnHome(['c', 'a', 'b']);
      await cubit.arrangedOnDial(['y', 'b', 'x', 'a', 'c']);
      expect(homeOf(cubit, lists), ['c', 'a', 'b']);
      expect(cubit.state.homeListOrder, HomeListOrder.myOrder);
    });

    test('Same as dial again follows the dial, and My order again brings '
        'back the dragged order', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnDial(['y', 'b', 'x', 'a', 'c']);
      await cubit.arrangedOnHome(['c', 'a', 'b']);
      await cubit.setHomeListOrder(HomeListOrder.sameAsDial);
      expect(homeOf(cubit, lists), ['b', 'a', 'c']);
      await cubit.setHomeListOrder(HomeListOrder.myOrder);
      expect(homeOf(cubit, lists), ['c', 'a', 'b']);
    });

    test('Same as dial off starts home from what it showed', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.setListOrder(ListOrder.alphabetical);
      await cubit.setHomeFollowsDial(false);
      expect(cubit.state.homeListOrder, HomeListOrder.alphabetical);
      await cubit.setHomeFollowsDial(true);
      expect(cubit.state.homeListOrder, HomeListOrder.sameAsDial);
      // On the dial's My order, home keeps a copy of it as its own.
      await cubit.arrangedOnDial(['c', 'y', 'b', 'x', 'a']);
      final List<String> shown = homeOf(cubit, lists);
      await cubit.setHomeFollowsDial(
        false,
        dialOrder: dialOf(cubit, lists),
      );
      expect(cubit.state.homeListOrder, HomeListOrder.myOrder);
      expect(homeOf(cubit, lists), shown);
      // A later dial drag leaves it.
      await cubit.arrangedOnDial(['a', 'b', 'c', 'x', 'y']);
      expect(homeOf(cubit, lists), ['c', 'b', 'a']);
    });

    test('Dial list order changes only the dial setting', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnHome(['c', 'a', 'b']);
      for (final ListOrder order in ListOrder.values) {
        await cubit.setListOrder(order);
        expect(cubit.state.homeListOrder, HomeListOrder.myOrder);
        expect(homeOf(cubit, lists), ['c', 'a', 'b']);
      }
    });
  });

  group('an account from before Q-108', () {
    HomeListOrder read(Map<String, Object?> json) =>
        AccountPreferences.fromJson(json).homeListOrder;

    test('home with its own order reads as My order, any other as Same as '
        'dial', () {
      expect(
        read(const {'homeArranged': true, 'dialArranged': true}),
        HomeListOrder.myOrder,
      );
      expect(read(const {'homeArranged': true}), HomeListOrder.sameAsDial);
      expect(read(const {'dialArranged': true}), HomeListOrder.sameAsDial);
      expect(read(const {}), HomeListOrder.sameAsDial);
    });

    test('a stored Home list order wins, and an unknown one falls back', () {
      expect(
        read(const {
          'homeListOrder': 'az',
          'homeArranged': true,
          'dialArranged': true,
        }),
        HomeListOrder.alphabetical,
      );
      expect(
        read(const {
          'homeListOrder': 'byColour',
          'homeArranged': true,
          'dialArranged': true,
        }),
        HomeListOrder.myOrder,
      );
      expect(read(const {'homeListOrder': 3}), HomeListOrder.sameAsDial);
    });

    test('the old flags are not written back', () {
      final Map<String, Object?> json = AccountPreferences.fromJson(const {
        'homeArranged': true,
        'dialArranged': true,
      }).toJson();
      expect(json['homeListOrder'], 'myOrder');
      expect(json.containsKey('homeArranged'), isFalse);
      expect(json.containsKey('dialArranged'), isFalse);
    });
  });

  // A new pin follows Home list order and changes no setting (Q-108).
  group('a new pin', () {
    const List<String> lists = ['a', 'x', 'b', 'y', 'c'];
    const AccountPreferences pinned = AccountPreferences(
      homePins: ['a', 'b', 'c'],
    );

    Future<void> pin(AccountPreferencesCubit cubit, String id) =>
        cubit.pinToHome(id, existing: lists);

    // Everything but the pins.
    AccountPreferences settings(AccountPreferencesCubit cubit) =>
        AccountPreferences.fromJson({
          ...cubit.state.toJson(),
          AccountPreferences.homePinsKey: const <String>[],
        });

    test('Same as dial, dial on A to Z: its sorted place', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.setListOrder(ListOrder.alphabetical);
      final AccountPreferences before = settings(cubit);
      await pin(cubit, 'x');
      expect(homeOf(cubit, lists), ['a', 'b', 'c', 'x']);
      await pin(cubit, 'y');
      expect(homeOf(cubit, lists), ['a', 'b', 'c', 'x', 'y']);
      expect(settings(cubit), before);
    });

    test('Same as dial, dial on My order: its place on the dial', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnDial(['c', 'y', 'b', 'x', 'a']);
      final AccountPreferences before = settings(cubit);
      await pin(cubit, 'x');
      expect(homeOf(cubit, lists), ['c', 'b', 'x', 'a']);
      expect(settings(cubit), before);
    });

    test('Home on A to Z: its sorted place', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnDial(['c', 'y', 'b', 'x', 'a']);
      await cubit.setHomeListOrder(HomeListOrder.alphabetical);
      await pin(cubit, 'x');
      expect(homeOf(cubit, lists), ['a', 'b', 'c', 'x']);
    });

    test('Home on My order: last, and the dial left alone', () async {
      final AccountPreferencesCubit cubit = await _cubit(pinned);
      await cubit.arrangedOnHome(['c', 'a', 'b']);
      final AccountPreferences before = settings(cubit);
      await pin(cubit, 'x');
      expect(homeOf(cubit, lists), ['c', 'a', 'b', 'x']);
      expect(settings(cubit), before);
    });
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
          homeListOrder: HomeListOrder.myOrder,
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
          homeListOrder: HomeListOrder.myOrder,
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
      await cubit.setHomeContent(HomeContent.dueToday);
      expect(
        cubit.state,
        const AccountPreferences(
          homePins: ['a'],
          homeRemoved: ['b'],
          homeSuggestions: false,
          homeContent: HomeContent.dueToday,
        ),
      );
    });
  });
}
