import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';
import 'generic_item_dialog.dart';
import 'list_definition.dart';
import 'list_item.dart';
import 'list_labels.dart';
import 'list_rules.dart';
import 'list_store.dart';
import 'list_vocabulary.dart';

// The per-list words a screen needs that are not part of the definition.
class GenericListTexts {
  const GenericListTexts({
    required this.title,
    required this.emptyText,
    required this.addTooltip,
    required this.addDialogTitle,
    required this.editDialogTitle,
  });

  final String title;
  final String emptyText;
  final String addTooltip;
  final String addDialogTitle;
  final String editDialogTitle;
}

// Shows any list from its definition and writes every change through a
// ListStore. The look is deliberately plain until the design pass (D-3).
class GenericListScreen extends StatefulWidget {
  const GenericListScreen({
    super.key,
    required this.definition,
    required this.items,
    required this.store,
    required this.texts,
  });

  final ListDefinition definition;
  final List<ListItem> items;
  final ListStore store;
  final GenericListTexts texts;

  @override
  State<GenericListScreen> createState() {
    return _GenericListScreenState();
  }
}

class _GenericListScreenState extends State<GenericListScreen> {
  // Selected filter chip value; null shows everything.
  String? _filter;

  ListDefinition get _definition => widget.definition;

  FieldDefinition? get _completion =>
      _definition.fieldWithRole(FieldRole.completion);

  FieldDefinition? get _filterField {
    final String? key = _definition.view.filterChipsBy;
    return key == null ? null : _definition.field(key);
  }

  BehaviorDefinition? _behavior(BehaviorKind kind) {
    for (final BehaviorDefinition behavior in _definition.behaviors) {
      if (behavior.kind == kind) {
        return behavior;
      }
    }
    return null;
  }

  bool _matchesFilter(ListItem item) {
    final FieldDefinition? field = _filterField;
    if (_filter == null || field == null) {
      return true;
    }
    final Object? value = item[field.key];
    return value is List ? value.contains(_filter) : value == _filter;
  }

  Future<void> _apply(ListChanges changes) async {
    if (!changes.isEmpty) {
      await widget.store.apply(changes);
    }
  }

  Future<void> _showItemDialog({ListItem? item}) async {
    final FieldDefinition? filterField = _filterField;
    final ListItem? result = await showDialog<ListItem>(
      context: context,
      builder: (_) {
        return GenericItemDialog(
          definition: _definition,
          item: item,
          title: item == null
              ? widget.texts.addDialogTitle
              : widget.texts.editDialogTitle,
          initialValues: {
            if (filterField != null && _filter != null) filterField.key: _filter,
          },
        );
      },
    );

    if (result == null) {
      return;
    }

    // New user options (a category typed in the dialog) are added first so
    // the store knows them when the item arrives.
    for (final FieldDefinition field in _definition.fields) {
      final Object? value = result[field.key];
      if (field.type.hasUserOptions) {
        final List<Object?> values = value is List ? value : [value];
        for (final Object? entry in values) {
          if (entry is String && entry.isNotEmpty && !field.hasOption(entry)) {
            await widget.store.addOption(_definition.id, field.key, entry);
          }
        }
      }
    }

    await _apply(ListChanges(saved: [result]));
  }

  Future<void> _clearCompleted(bool Function(ListItem item) inScope) {
    return _apply(
      ListRules.clearCompleted(
        _definition,
        widget.items,
        DateTime.now().toUtc(),
        inScope: inScope,
      ),
    );
  }

  Future<void> _toggleSubItem(
    ListItem item,
    FieldDefinition field,
    String subId,
    bool done,
  ) {
    final String now = DateTime.now().toUtc().toIso8601String();
    final Object? raw = item[field.key];
    final List<Map<String, dynamic>> subItems = [
      if (raw is List)
        for (final Object? entry in raw)
          if (entry is Map)
            entry['id'] == subId
                ? {...Map<String, dynamic>.from(entry), 'done': done, 'updatedAt': now}
                : Map<String, dynamic>.from(entry),
    ];
    return _apply(
      ListChanges(
        saved: [
          ListRules.withValues(item, {field.key: subItems}, DateTime.now().toUtc()),
        ],
      ),
    );
  }

  Future<void> _manageOptions(FieldDefinition field, ListLabels labels) async {
    final AppLocalizations loc = labels.loc;
    final TextEditingController controller = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children: [
              Text(loc.categories, style: Theme.of(context).textTheme.titleMedium),
              for (final FieldOption option in field.options)
                ListTile(
                  title: Text(labels.option(option)),
                  trailing: IconButton(
                    tooltip: loc.deleteCategory,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await widget.store.removeOption(
                        _definition.id,
                        field.key,
                        option.value,
                      );
                    },
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(labelText: loc.categoryName),
                    ),
                  ),
                  IconButton(
                    tooltip: loc.createCategory,
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      final String name = controller.text.trim();
                      if (name.isEmpty) {
                        return;
                      }
                      Navigator.of(sheetContext).pop();
                      await widget.store.addOption(_definition.id, field.key, name);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(FieldType type, DateTime date) {
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final DateFormat format = type == FieldType.dateTime
        ? DateFormat.yMMMd(locale).add_jm()
        : DateFormat.yMMMd(locale);
    return format.format(date.toLocal());
  }

  // The recurrence field that repeats the given date field, if any.
  FieldDefinition? _recurrenceFor(String dateField) {
    for (final BehaviorDefinition behavior in _definition.behaviors) {
      if (behavior.kind == BehaviorKind.recurOnClear &&
          behavior.stringParam('dateField') == dateField) {
        return _definition.field(behavior.stringParam('recurrenceField') ?? '');
      }
    }
    return null;
  }

  String _summary(ListLabels labels, ListItem item) {
    final AppLocalizations loc = labels.loc;
    final List<String> parts = [];

    if (_definition.view.kind == ViewKind.timeline) {
      final DateTime? date = _timelineDate(item);
      if (date != null) {
        parts.add(DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag())
            .format(date.toLocal()));
      }
    }

    for (final FieldDefinition field in _definition.fields) {
      // The section or group header already names this value.
      if (field.primary ||
          field.role == FieldRole.completion ||
          field.key == _definition.view.sectionBy ||
          field.key == _definition.view.groupBy ||
          !field.isVisibleFor(item.values)) {
        continue;
      }

      final Object? value = item[field.key];
      switch (field.type) {
        case FieldType.choice:
          for (final FieldOption option in field.options) {
            if (option.value == value) {
              parts.add(labels.option(option));
            }
          }
        case FieldType.counter:
        case FieldType.number:
        case FieldType.rating:
          if (value is num && value != 0) {
            parts.add('${labels.field(field)} $value');
          }
        case FieldType.checkbox:
        case FieldType.toggle:
          if (value == true) {
            parts.add(labels.field(field));
          }
        case FieldType.text:
        case FieldType.longText:
        case FieldType.url:
        case FieldType.category:
          if (value is String && value.trim().isNotEmpty) {
            parts.add(value.trim());
          }
        case FieldType.tags:
          if (value is List && value.isNotEmpty) {
            parts.add(value.join(', '));
          }
        case FieldType.date:
        case FieldType.dateTime:
          final DateTime? date = value is String ? DateTime.tryParse(value) : null;
          if (date == null) {
            break;
          }
          final String text = _formatDate(field.type, date);
          final FieldDefinition? recurrenceField = _recurrenceFor(field.key);
          final Object? recurrence =
              recurrenceField == null ? null : item[recurrenceField.key];
          final RecurrenceFrequency frequency = enumFromWire(
                RecurrenceFrequency.values,
                recurrence is Map ? recurrence['frequency'] : null,
              ) ??
              RecurrenceFrequency.none;
          if (frequency == RecurrenceFrequency.none) {
            parts.add(loc.reminderText(text));
          } else if (frequency == RecurrenceFrequency.custom) {
            final Object? days = (recurrence as Map)['customDays'];
            parts.add(loc.repeatsEveryDays(text, days is int ? days : 1));
          } else {
            parts.add(loc.repeats(text, labels.recurrence(frequency).toLowerCase()));
          }
        case FieldType.checklist:
          if (value is List && value.isNotEmpty) {
            final int done = value.where((entry) => entry is Map && entry['done'] == true).length;
            parts.add(loc.subtaskProgress(done, value.length));
          }
        case FieldType.recurrence:
          break;
      }
    }

    return parts.join(' | ');
  }

  DateTime? _timelineDate(ListItem item) {
    final String? key = _definition.view.dateField;
    if (key == 'createdAt') {
      return item.createdAt;
    }
    if (key == 'updatedAt') {
      return item.updatedAt;
    }
    final Object? value = key == null ? null : item[key];
    return value is String ? DateTime.tryParse(value) : null;
  }

  Widget _header(String text, {List<Widget> actions = const []}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }

  Widget _itemCard(ListLabels labels, ListItem item) {
    final AppLocalizations loc = labels.loc;
    final FieldDefinition? completion = _completion;
    final bool done = completion != null && item[completion.key] == true;
    final String summary = _summary(labels, item);
    final Object? primary =
        item[_definition.fields.firstWhere((field) => field.primary).key];
    final FieldDefinition? sectionField = _definition.view.kind == ViewKind.sectioned
        ? _definition.field(_definition.view.sectionBy ?? '')
        : null;
    final FieldDefinition? checklistField = _definition.fields
        .where((field) => field.type == FieldType.checklist)
        .firstOrNull;
    final Object? subItems =
        checklistField == null ? null : item[checklistField.key];

    final Widget? leading = completion == null
        ? null
        : Checkbox(
            value: done,
            onChanged: (value) => _apply(
              ListRules.setCompleted(
                _definition,
                item,
                value ?? false,
                DateTime.now().toUtc(),
              ),
            ),
          );
    final Widget title = Text(
      primary is String ? primary : '',
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
    final Widget? subtitle = summary.isEmpty
        ? null
        : Text(summary, overflow: TextOverflow.ellipsis, maxLines: 3);

    final Widget menu = PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'edit') {
          _showItemDialog(item: item);
        } else if (value == 'delete') {
          _apply(ListChanges(deletedIds: [item.id]));
        } else if (value == 'clear') {
          _clearCompleted((other) => other.id == item.id);
        } else if (value.startsWith('move:') && sectionField != null) {
          _apply(
            ListRules.moveTo(
              _definition,
              item,
              sectionField.key,
              value.substring('move:'.length),
              DateTime.now().toUtc(),
            ),
          );
        }
      },
      itemBuilder: (context) {
        PopupMenuItem<String> entry(String value, IconData icon, String text) {
          return PopupMenuItem(
            value: value,
            child: ListTile(
              leading: Icon(icon),
              title: Text(text),
              contentPadding: EdgeInsets.zero,
            ),
          );
        }

        return [
          entry('edit', Icons.edit_outlined, loc.edit),
          if (sectionField != null)
            for (final FieldOption option in sectionField.options)
              if (item[sectionField.key] != option.value)
                entry('move:${option.value}', Icons.drive_file_move_outline,
                    labels.option(option)),
          if (done && _behavior(BehaviorKind.clearCompleted) != null)
            entry('clear', Icons.cleaning_services_outlined, loc.clear),
          entry('delete', Icons.delete_outline, loc.delete),
        ];
      },
    );

    final ShapeBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
    );

    if (checklistField != null && subItems is List && subItems.isNotEmpty) {
      return Card(
        shape: shape,
        child: ExpansionTile(
          key: PageStorageKey('item-${item.id}'),
          leading: leading,
          title: title,
          subtitle: subtitle,
          trailing: menu,
          shape: const Border(),
          children: [
            for (final Object? entry in subItems)
              if (entry is Map)
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: entry['done'] == true,
                  title: Text('${entry['title'] ?? ''}'),
                  onChanged: (value) => _toggleSubItem(
                    item,
                    checklistField,
                    '${entry['id']}',
                    value ?? false,
                  ),
                ),
          ],
        ),
      );
    }

    return Card(
      shape: shape,
      child: ListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: menu,
        onTap: () => _showItemDialog(item: item),
      ),
    );
  }

  List<Widget> _filterChips(ListLabels labels) {
    final FieldDefinition? field = _filterField;
    if (field == null) {
      return const [];
    }

    int count(String? value) {
      return widget.items.where((item) {
        if (value == null) {
          return true;
        }
        final Object? itemValue = item[field.key];
        return itemValue is List ? itemValue.contains(value) : itemValue == value;
      }).length;
    }

    return [
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${labels.loc.allMyTasks} (${count(null)})'),
                selected: _filter == null,
                onSelected: (_) => setState(() => _filter = null),
              ),
            ),
            for (final FieldOption option in field.options)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('${labels.option(option)} (${count(option.value)})'),
                  selected: _filter == option.value,
                  onSelected: (_) => setState(() => _filter = option.value),
                ),
              ),
            if (field.type.hasUserOptions)
              IconButton(
                tooltip: labels.loc.categories,
                icon: const Icon(Icons.tune),
                onPressed: () => _manageOptions(field, labels),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _grouped(ListLabels labels, List<ListItem> sorted) {
    final FieldDefinition? groupField =
        _definition.field(_definition.view.groupBy ?? '');
    if (groupField == null) {
      return [for (final ListItem item in sorted) _itemCard(labels, item)];
    }

    final List<Widget> children = [];
    final Set<String> placed = {};

    void addGroup(String header, bool Function(ListItem item) matches) {
      final List<ListItem> members = sorted
          .where((item) => !placed.contains(item.id) && matches(item))
          .toList();
      if (members.isEmpty) {
        return;
      }
      placed.addAll(members.map((item) => item.id));
      children.add(_header('$header (${members.length})'));
      children.addAll(members.map((item) => _itemCard(labels, item)));
    }

    for (final FieldOption option in groupField.options) {
      addGroup(labels.option(option), (item) => item[groupField.key] == option.value);
    }
    for (final ListItem item in sorted) {
      final Object? value = item[groupField.key];
      if (!placed.contains(item.id) && value is String && value.isNotEmpty) {
        addGroup(value, (other) => other[groupField.key] == value);
      }
    }
    // Items matching no group go last, so nothing is ever hidden.
    addGroup('—', (item) => true);
    return children;
  }

  List<Widget> _sectioned(ListLabels labels, List<ListItem> sorted) {
    final FieldDefinition? sectionField =
        _definition.field(_definition.view.sectionBy ?? '');
    if (sectionField == null) {
      return [for (final ListItem item in sorted) _itemCard(labels, item)];
    }

    final BehaviorDefinition? moveAll = _behavior(BehaviorKind.moveAll);
    final bool canClear = _behavior(BehaviorKind.clearCompleted) != null;
    final List<Widget> children = [];

    for (final FieldOption option in sectionField.options) {
      final List<ListItem> members =
          sorted.where((item) => item[sectionField.key] == option.value).toList();
      final int ticked =
          members.where((item) => ListRules.isCompleted(_definition, item)).length;
      final bool movesFromHere = moveAll != null &&
          moveAll.stringParam('field') == sectionField.key &&
          moveAll.stringParam('from') == option.value &&
          members.isNotEmpty;
      final FieldOption? target = movesFromHere
          ? sectionField.options
              .where((other) => other.value == moveAll.stringParam('to'))
              .firstOrNull
          : null;

      children.add(
        _header(
          '${labels.option(option)} (${members.length})',
          actions: [
            if (canClear && ticked > 0)
              TextButton(
                onPressed: () => _clearCompleted(
                  (item) => item[sectionField.key] == option.value,
                ),
                child: Text(
                  '${labels.loc.clearTicked} (${labels.loc.tickedCount(ticked)})',
                ),
              ),
            if (target != null)
              TextButton.icon(
                icon: const Icon(Icons.arrow_upward),
                label: Text(labels.option(target)),
                onPressed: () => _apply(
                  ListRules.moveAll(
                    _definition,
                    widget.items,
                    moveAll!,
                    DateTime.now().toUtc(),
                  ),
                ),
              ),
          ],
        ),
      );

      if (members.isEmpty) {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('—'),
          ),
        );
      }
      children.addAll(members.map((item) => _itemCard(labels, item)));
    }

    return children;
  }

  List<Widget> _timeline(ListLabels labels, List<ListItem> sorted) {
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final bool byMonth =
        _definition.view.timelineGrouping != TimelineGrouping.year;
    final Map<int, Map<int, List<ListItem>>> years = {};

    for (final ListItem item in sorted) {
      final DateTime date = (_timelineDate(item) ?? item.createdAt).toLocal();
      years
          .putIfAbsent(date.year, () => {})
          .putIfAbsent(byMonth ? date.month : 0, () => [])
          .add(item);
    }

    final List<int> yearKeys = years.keys.toList()..sort((a, b) => b - a);
    return [
      for (final int year in yearKeys)
        ExpansionTile(
          key: PageStorageKey('year-$year'),
          initiallyExpanded: year == yearKeys.first,
          title: Text('$year'),
          children: [
            for (final int month in years[year]!.keys.toList()..sort((a, b) => b - a))
              if (!byMonth)
                ...years[year]![month]!.map((item) => _itemCard(labels, item))
              else
                ExpansionTile(
                  key: PageStorageKey('month-$year-$month'),
                  initiallyExpanded: year == yearKeys.first,
                  title: Text(DateFormat.MMMM(locale).format(DateTime(year, month))),
                  children: [
                    for (final ListItem item in years[year]![month]!)
                      _itemCard(labels, item),
                  ],
                ),
          ],
        ),
    ];
  }

  List<Widget> _checklist(ListLabels labels, List<ListItem> sorted) {
    final FieldDefinition? bucketField =
        _definition.field(_definition.view.bucketBy ?? '');
    if (bucketField == null) {
      return [for (final ListItem item in sorted) _itemCard(labels, item)];
    }

    final DateTime now = DateTime.now();
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    int bucket(ListItem item) {
      final Object? raw = item[bucketField.key];
      final DateTime? date = raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
      if (date == null || sameDay(date, now)) {
        return 0;
      }
      return sameDay(date, now.add(const Duration(days: 1))) ? 1 : 2;
    }

    final List<String> names = [labels.loc.today, labels.loc.tomorrow, labels.loc.later];
    final List<Widget> children = [];
    for (int index = 0; index < names.length; index++) {
      final List<ListItem> members =
          sorted.where((item) => bucket(item) == index).toList();
      if (members.isEmpty) {
        continue;
      }
      children.add(_header('${names[index]} (${members.length})'));
      children.addAll(members.map((item) => _itemCard(labels, item)));
    }
    return children;
  }

  // Checklists show open items first, soonest date first; everything else
  // shows newest first.
  List<ListItem> _sorted(List<ListItem> items) {
    final List<ListItem> sorted = [...items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (_definition.view.kind != ViewKind.checklist) {
      return sorted;
    }

    final String? dateKey = _definition.view.bucketBy;
    DateTime? dateOf(ListItem item) {
      final Object? raw = dateKey == null ? null : item[dateKey];
      return raw is String ? DateTime.tryParse(raw) : null;
    }

    sorted.sort((a, b) {
      final int doneOrder = (ListRules.isCompleted(_definition, a) ? 1 : 0) -
          (ListRules.isCompleted(_definition, b) ? 1 : 0);
      if (doneOrder != 0) {
        return doneOrder;
      }
      final DateTime? dateA = dateOf(a);
      final DateTime? dateB = dateOf(b);
      if (dateA != null && dateB != null) {
        return dateA.compareTo(dateB);
      }
      if (dateA != null || dateB != null) {
        return dateA == null ? -1 : 1;
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final ListLabels labels = ListLabels(loc);
    final FieldDefinition? filterField = _filterField;
    if (filterField != null && _filter != null && !filterField.hasOption(_filter)) {
      _filter = null;
    }

    final List<ListItem> visible = _sorted(widget.items.where(_matchesFilter).toList());
    final bool canClearAll = _definition.view.kind == ViewKind.checklist &&
        _behavior(BehaviorKind.clearCompleted) != null &&
        visible.any((item) => ListRules.isCompleted(_definition, item));

    final List<Widget> content = switch (_definition.view.kind) {
      ViewKind.grouped => _grouped(labels, visible),
      ViewKind.sectioned => _sectioned(labels, visible),
      ViewKind.timeline => _timeline(labels, visible),
      ViewKind.checklist => _checklist(labels, visible),
      ViewKind.table || ViewKind.cards => [
          for (final ListItem item in visible) _itemCard(labels, item),
        ],
    };

    final bool showEmpty =
        visible.isEmpty && _definition.view.kind != ViewKind.sectioned;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.texts.title),
        actions: [
          if (canClearAll)
            IconButton(
              tooltip: loc.clear,
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: () => _clearCompleted(_matchesFilter),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showItemDialog();
        },
        tooltip: widget.texts.addTooltip,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: widget.store.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            ..._filterChips(labels),
            if (showEmpty) ...[
              const SizedBox(height: 200),
              Center(child: Text(widget.texts.emptyText)),
            ] else
              ...content,
          ],
        ),
      ),
    );
  }
}
