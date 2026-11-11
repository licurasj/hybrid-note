// T-13 unit 2: the planner, row by row of the Rules table in
// tasks/T-13-reminders.md (Q-90 to Q-92, limits, missed rings, Q-117).
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_catalog.dart';
import 'package:hybrid_note/lists/list_definition.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/lists/list_patch.dart';
import 'package:hybrid_note/lists/list_vocabulary.dart';
import 'package:hybrid_note/reminders/reminder_planner.dart';
import 'package:hybrid_note/reminders/reminder_settings.dart';

final ListDefinition _tasks = BuiltinTemplates.tasks();
// Local times throughout, so the tests hold in any time zone.
final DateTime _now = DateTime(2026, 3, 10, 12);

ListItem _task(
  String id,
  Object? date, {
  bool done = false,
  String? repeat,
  int? customDays,
  ListDefinition? list,
}) => ListItem(
  id: id,
  listId: (list ?? _tasks).id,
  values: {
    'title': 'Task $id',
    'done': done,
    'reminderAt': ?date,
    if (repeat != null)
      'repeat': {'frequency': repeat, 'customDays': ?customDays},
  },
  createdAt: _now.toUtc(),
  updatedAt: _now.toUtc(),
);

String _at(DateTime local) => local.toUtc().toIso8601String();

List<PlannedRing> _plan(
  List<ListItem> items, {
  Set<ReminderLead> leads = ReminderLead.defaults,
  int morning = 9 * 60,
  bool listsOwn = true,
  List<ListDefinition>? lists,
  DateTime? now,
  int limit = ReminderPlanner.limit,
}) => ReminderPlanner.plan(
  catalog: ListCatalog(definitions: lists ?? [_tasks], items: items),
  settings: ReminderSettings(
    leads: leads,
    morningMinutes: morning,
    listsOwnLeads: listsOwn,
  ),
  now: now ?? _now,
  listName: (list) => list.name ?? list.id,
  limit: limit,
);

List<DateTime> _times(List<PlannedRing> rings) => [
  for (final PlannedRing ring in rings) ring.at.toLocal(),
];

void main() {
  test('rings at the time by default, once', () {
    final List<PlannedRing> rings = _plan([
      _task('a', _at(DateTime(2026, 3, 10, 15))),
    ]);
    expect(_times(rings), [DateTime(2026, 3, 10, 15)]);
    expect(rings.single.itemId, 'a');
    expect(rings.single.title, 'Task a');
    expect(rings.single.hasTime, isTrue);
    expect(rings.single.itemDate, _at(DateTime(2026, 3, 10, 15)));
    expect(rings.single.listColor, _tasks.color);
  });

  test('each picked lead is its own ring; none picked rings nothing', () {
    final ListItem item = _task('a', _at(DateTime(2026, 3, 12, 15)));
    expect(_times(_plan([item], leads: ReminderLead.values.toSet())), [
      DateTime(2026, 3, 11, 15),
      DateTime(2026, 3, 12, 14),
      DateTime(2026, 3, 12, 14, 30),
      DateTime(2026, 3, 12, 14, 50),
      DateTime(2026, 3, 12, 14, 55),
      DateTime(2026, 3, 12, 15),
    ]);
    expect(_plan([item], leads: {}), isEmpty);
    final Set<String> keys = {
      for (final PlannedRing ring in _plan([
        item,
      ], leads: ReminderLead.values.toSet()))
        ring.key,
    };
    expect(keys, hasLength(6));
  });

  test('a day with no time rings at the morning time, and the morning before '
      'with 1 day; minute and hour leads do not apply', () {
    final ListItem day = _task('a', '2026-03-12');
    expect(_times(_plan([day])), [DateTime(2026, 3, 12, 9)]);
    expect(
      _times(
        _plan(
          [day],
          leads: {ReminderLead.minutes5, ReminderLead.hour1},
          morning: 7 * 60 + 30,
        ),
      ),
      [DateTime(2026, 3, 12, 7, 30)],
    );
    expect(_times(_plan([day], leads: {ReminderLead.day1})), [
      DateTime(2026, 3, 11, 9),
      DateTime(2026, 3, 12, 9),
    ]);
    expect(_plan([day]).single.hasTime, isFalse);
  });

  test('a date field rings in the morning', () {
    final ListDefinition list = ListPatch.apply(_tasks, const [], [
      const ListPatchOp(PatchOpKind.addField, {
        'field': {'key': 'day', 'type': 'date', 'label': 'Day'},
      }),
      const ListPatchOp(PatchOpKind.setFieldProps, {
        'key': 'reminderAt',
        'role': null,
      }),
      const ListPatchOp(PatchOpKind.setFieldProps, {
        'key': 'day',
        'role': 'reminder',
      }),
    ], DateTime.utc(2026, 3, 1)).definition;
    expect(list.fieldWithRole(FieldRole.reminder)?.key, 'day');
    final ListItem item = ListItem(
      id: 'a',
      listId: list.id,
      values: {'title': 'Pay rent', 'day': '2026-03-11'},
      createdAt: _now.toUtc(),
      updatedAt: _now.toUtc(),
    );
    expect(_times(_plan([item], lists: [list])), [DateTime(2026, 3, 11, 9)]);

    // F7: a value saved before T-13 unit 10 (the picked day's midnight as a
    // UTC moment) rings on its UTC date, in any zone.
    for (final String legacy in [
      '2026-03-11T08:00:00.000Z',
      '2026-03-11T00:00:00.000Z',
    ]) {
      final ListItem old = ListItem(
        id: 'b',
        listId: list.id,
        values: {'title': 'Pay rent', 'day': legacy},
        createdAt: _now.toUtc(),
        updatedAt: _now.toUtc(),
      );
      expect(_times(_plan([old], lists: [list])), [DateTime(2026, 3, 11, 9)]);
    }
  });

  test('a ring offers Done only on a list with a tick (F9)', () {
    expect(_plan([_task('a', _at(DateTime(2026, 3, 10, 15)))]).single.canDone, isTrue);
    final Map<String, dynamic> json = _tasks.toJson();
    (json['fields'] as List).removeWhere((field) => (field as Map)['key'] == 'done');
    (json['behaviors'] as List).clear();
    final ListDefinition untickable = ListDefinition.fromJson(json);
    final ListItem item = ListItem(
      id: 'b',
      listId: untickable.id,
      values: {'title': 'Read', 'reminderAt': _at(DateTime(2026, 3, 10, 15))},
      createdAt: _now.toUtc(),
      updatedAt: _now.toUtc(),
    );
    expect(_plan([item], lists: [untickable]).single.canDone, isFalse);
  });

  test('lists without a marked date ring nothing', () {
    final ListDefinition grocery = BuiltinTemplates.grocery();
    final ListDefinition unmarked = ListPatch.apply(_tasks, const [], [
      const ListPatchOp(PatchOpKind.setFieldProps, {
        'key': 'reminderAt',
        'role': null,
      }),
    ], DateTime.utc(2026, 3, 1)).definition;
    expect(
      _plan(
        [_task('a', _at(DateTime(2026, 3, 10, 15)), list: unmarked)],
        lists: [unmarked, grocery],
      ),
      isEmpty,
    );
  });

  test('ticked without a repeat: no ring; no date: no ring', () {
    expect(_plan([_task('a', _at(DateTime(2026, 3, 10, 15)), done: true)]), isEmpty);
    expect(_plan([_task('b', null)]), isEmpty);
    expect(_plan([_task('c', 'not a date')]), isEmpty);
  });

  test('a repeat rings at every occurrence ahead, ticked, unticked or missed',
      () {
    final List<DateTime> expected = [
      DateTime(2026, 3, 10, 18),
      DateTime(2026, 3, 11, 18),
      DateTime(2026, 3, 12, 18),
    ];
    for (final ListItem item in [
      _task('open', _at(DateTime(2026, 3, 10, 18)), repeat: 'daily'),
      // Missed: its own time passed days ago and it was never ticked.
      _task('missed', _at(DateTime(2026, 3, 1, 18)), repeat: 'daily'),
    ]) {
      expect(
        _times(_plan([item])).take(3),
        expected,
        reason: item.id,
      );
    }
    // Ticked: its own time does not ring, the later ones do.
    expect(
      _times(
        _plan([
          _task(
            'ticked',
            _at(DateTime(2026, 3, 10, 18)),
            done: true,
            repeat: 'daily',
          ),
        ]),
      ).take(2),
      [DateTime(2026, 3, 11, 18), DateTime(2026, 3, 12, 18)],
    );
    // Repeat off: as no repeat.
    expect(
      _times(_plan([_task('off', _at(DateTime(2026, 3, 10, 18)), repeat: 'none')])),
      [DateTime(2026, 3, 10, 18)],
    );
  });

  test('a daily repeat books up to 30 days ahead', () {
    final List<PlannedRing> rings = _plan([
      _task('a', _at(DateTime(2026, 3, 10, 18)), repeat: 'daily'),
    ]);
    expect(rings, hasLength(30));
    expect(rings.last.at.toLocal(), DateTime(2026, 4, 8, 18));
  });

  test('weekly, custom and a month-end monthly repeat', () {
    expect(
      _times(_plan([_task('w', _at(DateTime(2026, 3, 9, 8)), repeat: 'weekly')])),
      [DateTime(2026, 3, 16, 8), DateTime(2026, 3, 23, 8), DateTime(2026, 3, 30, 8), DateTime(2026, 4, 6, 8)],
    );
    expect(
      _times(_plan([_task('c', _at(DateTime(2026, 3, 10, 8)), repeat: 'custom', customDays: 10)])),
      [DateTime(2026, 3, 20, 8), DateTime(2026, 3, 30, 8), DateTime(2026, 4, 9, 8)],
    );
    // The 31st: April has none, so the 30th; May has one again.
    expect(
      _times(
        _plan(
          [_task('m', _at(DateTime(2026, 1, 31, 8)), repeat: 'monthly')],
          now: DateTime(2026, 3, 10),
        ),
      ),
      [DateTime(2026, 3, 31, 8)],
    );
    expect(
      _times(
        _plan([
          _task('m', _at(DateTime(2026, 1, 31, 8)), repeat: 'monthly'),
        ], now: DateTime(2026, 4, 1)),
      ),
      [DateTime(2026, 4, 30, 8)],
    );
  });

  test('a repeating day with no time stays a morning ring', () {
    expect(
      _times(_plan([_task('d', '2026-03-09', repeat: 'weekly')])),
      [DateTime(2026, 3, 16, 9), DateTime(2026, 3, 23, 9), DateTime(2026, 3, 30, 9), DateTime(2026, 4, 6, 9)],
    );
  });

  test('a daily ring keeps its wall-clock time over a clock change', () {
    // Wherever the tests run, each local occurrence is 08:00.
    final List<PlannedRing> rings = _plan([
      _task('a', _at(DateTime(2026, 3, 10, 8)), repeat: 'daily'),
    ], now: DateTime(2026, 3, 10, 9));
    expect(rings.every((ring) => ring.at.toLocal().hour == 8), isTrue);
    expect(rings.every((ring) => ring.at.toLocal().minute == 0), isTrue);
  });

  test('missed rings never come: only times after now', () {
    expect(_plan([_task('a', _at(DateTime(2026, 3, 10, 11, 59)))]), isEmpty);
    // The time itself is ahead, its 1 hour before has passed.
    expect(
      _times(
        _plan(
          [_task('b', _at(DateTime(2026, 3, 10, 12, 30)))],
          leads: {ReminderLead.atTime, ReminderLead.hour1},
        ),
      ),
      [DateTime(2026, 3, 10, 12, 30)],
    );
    // A day with no time today, after its morning: nothing.
    expect(_plan([_task('c', '2026-03-10')]), isEmpty);
  });

  test('with a late window, rings just passed stay planned (F5)', () {
    final List<ListItem> items = [
      _task('a', _at(DateTime(2026, 3, 10, 11, 30))),
      _task('b', _at(DateTime(2026, 3, 10, 9, 30))),
      _task('c', _at(DateTime(2026, 3, 10, 13))),
    ];
    final List<PlannedRing> rings = ReminderPlanner.plan(
      catalog: ListCatalog(definitions: [_tasks], items: items),
      settings: const ReminderSettings(),
      now: _now,
      listName: (list) => list.id,
      late: const Duration(hours: 2),
    );
    expect(rings.map((ring) => ring.itemId), ['a', 'c']);
    // The horizon still counts from now, not from the late window.
    expect(
      ReminderPlanner.plan(
        catalog: ListCatalog(
          definitions: [_tasks],
          items: [_task('far', _at(DateTime(2026, 4, 9, 11, 30)))],
        ),
        settings: const ReminderSettings(),
        now: _now,
        listName: (list) => list.id,
        late: const Duration(hours: 2),
      ),
      hasLength(1),
    );
  });

  test('at most the 200 soonest, and nothing past 30 days', () {
    final List<ListItem> items = [
      for (int i = 0; i < 300; i++)
        _task('i$i', _at(DateTime(2026, 3, 11).add(Duration(minutes: i)))),
      _task('far', _at(DateTime(2026, 4, 10, 13))),
    ];
    final List<PlannedRing> rings = _plan(items);
    expect(rings, hasLength(200));
    expect(rings.first.itemId, 'i0');
    expect(rings.last.itemId, 'i199');
    expect(_plan([items.last]), isEmpty);
    expect(_plan(items, limit: 5), hasLength(5));
  });

  test('a list with its own how early, while lists may have their own', () {
    final ListDefinition own = ListPatch.apply(_tasks, const [], [
      const ListPatchOp(PatchOpKind.setListInfo, {
        ListDefinition.ownReminderLeadsKey: ['10m'],
      }),
    ], DateTime.utc(2026, 3, 1)).definition;
    expect(own.ownReminderLeads, ['10m']);
    final ListItem item = _task('a', _at(DateTime(2026, 3, 10, 15)), list: own);
    expect(_times(_plan([item], lists: [own])), [DateTime(2026, 3, 10, 14, 50)]);
    expect(
      _times(_plan([item], lists: [own], listsOwn: false)),
      [DateTime(2026, 3, 10, 15)],
    );
    final ListDefinition quiet = ListPatch.apply(_tasks, const [], [
      const ListPatchOp(PatchOpKind.setListInfo, {
        ListDefinition.ownReminderLeadsKey: <String>[],
      }),
    ], DateTime.utc(2026, 3, 1)).definition;
    expect(_plan([_task('a', _at(DateTime(2026, 3, 10, 15)), list: quiet)], lists: [quiet]), isEmpty);
  });

  test('setListInfo refuses unknown leads and clears with null', () {
    final result = ListPatch.apply(_tasks, const [], [
      const ListPatchOp(PatchOpKind.setListInfo, {
        ListDefinition.ownReminderLeadsKey: ['2h'],
      }),
    ], DateTime.utc(2026, 3, 1));
    expect(result.isValid, isFalse);
    final ListDefinition own = ListPatch.apply(_tasks, const [], [
      const ListPatchOp(PatchOpKind.setListInfo, {
        ListDefinition.ownReminderLeadsKey: ['1h'],
      }),
    ], DateTime.utc(2026, 3, 1)).definition;
    final ListDefinition back = ListPatch.apply(own, const [], [
      const ListPatchOp(PatchOpKind.setListInfo, {
        ListDefinition.ownReminderLeadsKey: null,
      }),
    ], DateTime.utc(2026, 3, 1)).definition;
    expect(back.ownReminderLeads, isNull);
    expect(ListDefinition.fromJson(own.toJson()).ownReminderLeads, ['1h']);
  });

  test('the preferences keep how early and the morning time', () {
    const AccountPreferences defaults = AccountPreferences();
    expect(defaults.reminderLeads, {ReminderLead.atTime});
    expect(defaults.reminderMorning, 9 * 60);
    expect(defaults.listsOwnReminderLeads, isTrue);
    final AccountPreferences picked = AccountPreferences.fromJson({
      AccountPreferences.reminderLeadsKey: ['1d', '5m', 'later'],
      AccountPreferences.reminderMorningKey: '07:30',
      AccountPreferences.listsOwnReminderLeadsKey: false,
    });
    expect(picked.reminderLeads, {ReminderLead.minutes5, ReminderLead.day1});
    expect(picked.reminderMorning, 7 * 60 + 30);
    expect(picked.toJson()[AccountPreferences.reminderLeadsKey], ['5m', '1d']);
    expect(picked.toJson()[AccountPreferences.reminderMorningKey], '07:30');
    expect(AccountPreferences.fromJson(picked.toJson()), picked);
    expect(
      AccountPreferences.fromJson({AccountPreferences.reminderLeadsKey: []})
          .reminderLeads,
      isEmpty,
    );
    expect(
      AccountPreferences.fromJson({AccountPreferences.reminderMorningKey: '25:00'})
          .reminderMorning,
      9 * 60,
    );
  });
}
