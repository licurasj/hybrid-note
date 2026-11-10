import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../app/account_preferences.dart';
import '../app/app_banner.dart';
import '../app/app_theme.dart';
import '../app/date_preferences.dart';
import '../app/grow_in.dart';
import '../app_colors.dart';
import '../home_cards_view.dart';
import '../l10n/generated/app_localizations.dart';
import '../launcher/launcher_hub_area.dart';
import 'clear_with_undo.dart';
import 'confirm_delete_sheet.dart';
import 'generic_item_dialog.dart';
import 'item_dates.dart';
import 'list_definition.dart';
import 'list_icons.dart';
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

// Lets the open list's page offer "Edit list" (top right): the shell puts it
// above its navigator with its own way of editing a list. Without it (tests,
// other hosts) the page has no such button.
class ListEditAction extends InheritedWidget {
  const ListEditAction({super.key, required this.onEdit, required super.child});

  final ValueChanged<String> onEdit;

  static ListEditAction? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ListEditAction>();
  }

  @override
  bool updateShouldNotify(ListEditAction oldWidget) =>
      onEdit != oldWidget.onEdit;
}

// Shows any list from its definition and writes every change through a
// ListStore. The look is direction A "Eclipse" (docs/AESTHETICS.md): a giant
// cropped title, text filters, hairline rows and the eclipse add button, in
// the list's own colour.
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

class _GenericListScreenState extends State<GenericListScreen>
    with SingleTickerProviderStateMixin {
  // Text and headers sit on the side margin. Rows sit 12 px outside it, so
  // their 48 px checkbox and menu targets line up with it visually.
  static const double _margin = AppShapes.sideMargin;
  static const double _edge = AppShapes.sideMargin - 12;

  // Selected filter value; null shows everything.
  String? _filter;

  final Set<String> _flipped = {};

  late _Look _look;

  // Under the floating launcher the add button grows in once the page has
  // arrived and shrinks away as soon as the page starts to leave (going
  // home, or another list replacing it), as it does when the hub moves: size
  // only, and at once with reduced motion (docs/AESTHETICS.md, Motion).
  bool _pageArrived = false;
  bool _pageLeaving = false;
  bool _reduceMotion = false;
  Animation<double>? _pageAnimation;
  Animation<double>? _coverAnimation;
  late final AnimationController _addIn = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
  );
  late final CurvedAnimation _addScale = CurvedAnimation(
    parent: _addIn,
    curve: AppMotion.curve,
    // Leaving starts at once, as the page starts to go.
    reverseCurve: AppMotion.curve.flipped,
  );

  ListDefinition get _definition => widget.definition;

  bool get _addShown => _pageArrived && !_pageLeaving;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    final Animation<double>? animation = route?.animation;
    if (animation != _pageAnimation) {
      _pageAnimation?.removeStatusListener(_onPageAnimation);
      _pageAnimation = animation;
      _pageArrived = animation == null || animation.isCompleted;
      animation?.addStatusListener(_onPageAnimation);
    }
    final Animation<double>? cover = route?.secondaryAnimation;
    if (cover != _coverAnimation) {
      _coverAnimation?.removeStatusListener(_onCoverAnimation);
      _coverAnimation = cover;
      cover?.addStatusListener(_onCoverAnimation);
    }
    // With reduced motion there is no page transition to wait for.
    if (_reduceMotion) {
      _pageArrived = true;
    }
    _showAddButton();
  }

  void _showAddButton() {
    if (_reduceMotion) {
      _addIn.value = _addShown ? 1 : 0;
    } else if (_addShown) {
      _addIn.forward();
    } else {
      _addIn.reverse();
    }
  }

  void _onPageAnimation(AnimationStatus status) {
    final bool arrived = _pageArrived || status.isCompleted;
    final bool leaving = status == AnimationStatus.reverse;
    if (arrived != _pageArrived || leaving != _pageLeaving) {
      setState(() {
        _pageArrived = arrived;
        _pageLeaving = leaving;
      });
      _showAddButton();
    }
  }

  // Another page coming over this one (a list replacing it).
  void _onCoverAnimation(AnimationStatus status) {
    final bool leaving = status.isForwardOrCompleted;
    if (leaving != _pageLeaving) {
      setState(() => _pageLeaving = leaving);
      _showAddButton();
    }
  }

  @override
  void dispose() {
    _pageAnimation?.removeStatusListener(_onPageAnimation);
    _coverAnimation?.removeStatusListener(_onCoverAnimation);
    _addScale.dispose();
    _addIn.dispose();
    super.dispose();
  }

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
    final ListItem? result = await showItemSheet(
      context: context,
      definition: _definition,
      item: item,
      title: item == null
          ? widget.texts.addDialogTitle
          : widget.texts.editDialogTitle,
      initialValues: {
        if (filterField != null && _filter != null) filterField.key: _filter,
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

  // Every clear on this page shows "Cleared · Undo" (Q-101).
  Future<void> _clearCompleted(bool Function(ListItem item) inScope) {
    return ClearWithUndo.run(
      store: widget.store,
      definition: _definition,
      items: widget.items,
      inScope: inScope,
      banners: context.read<AppBannerController?>(),
      loc: AppLocalizations.of(context),
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

  // A day with No time shows no time (Q-91).
  String _formatDate(bool hasTime, DateTime date) {
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final DateFormat format = hasTime
        ? dateTimeFormat(locale, context.watchAccountPreferences.timeFormat)
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
          final String text = _formatDate(
            ItemDates.hasTime(field.type, value),
            date,
          );
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

    return parts.join(' · ');
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

  // Collapsible parts (years, months, items with sub-items) whose state the
  // user flipped from its default.
  bool _isOpen(String key, bool byDefault) =>
      _flipped.contains(key) ? !byDefault : byDefault;

  void _flip(String key) {
    setState(() {
      if (!_flipped.remove(key)) {
        _flipped.add(key);
      }
    });
  }

  // Shows or hides children by growing them; never fades.
  Widget _collapsible(bool open, List<Widget> children) {
    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.standard,
      curve: AppMotion.curve,
      alignment: Alignment.topCenter,
      child: open
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
          : const SizedBox(width: double.infinity),
    );
  }

  // A round checkbox filled in the list colour.
  Widget _check(bool value, ValueChanged<bool> onChanged, {double scale = 1.3}) {
    final _Look look = _look;
    return Transform.scale(
      scale: scale,
      child: Checkbox(
        value: value,
        onChanged: (value) => onChanged(value ?? false),
        shape: const CircleBorder(),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? look.color
              : Colors.transparent,
        ),
        checkColor: look.onColor,
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? look.color
                : look.neutrals.text,
            width: 1.75 / scale,
          ),
        ),
      ),
    );
  }

  // An uppercase section label with its count, and any actions (clear ticked,
  // move all) as a bar under it. [trailing] sits on the label's own line at its
  // right, in a line always as tall as a button, so it comes and goes without
  // moving anything (Q-120 C).
  Widget _header(
    String text, {
    int? count,
    List<Widget> actions = const [],
    Widget? trailing,
  }) {
    final _Look look = _look;
    final Widget label = Semantics(
      header: true,
      child: Text(
        count == null ? text.toUpperCase() : '${text.toUpperCase()} · $count',
        style: look.type.sectionLabel,
        // Beside a button, one line, so the line keeps its height.
        maxLines: trailing == null ? null : 1,
        overflow: trailing == null ? null : TextOverflow.ellipsis,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(_margin, 22, _margin, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trailing == null)
            label
          else
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 8),
                  trailing,
                ],
              ),
            ),
          // Each action brings its own top gap (see _barGap), so a bar whose
          // buttons are all hidden takes no room.
          if (actions.isNotEmpty) Wrap(spacing: 8, children: actions),
        ],
      ),
    );
  }

  // A tappable section label that folds what is under it.
  Widget _foldHeader(String text, bool open, VoidCallback onTap, {bool strong = false}) {
    final _Look look = _look;
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_margin, 10, _margin, 0),
            child: Row(
              children: [
                Text(
                  text.toUpperCase(),
                  style: strong
                      ? look.type.sectionLabel.copyWith(
                          color: look.neutrals.text,
                          fontWeight: FontWeight.w600,
                        )
                      : look.type.sectionLabel,
                ),
                const SizedBox(width: 4),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: look.neutrals.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // The gap between a section label and its button bar, inside each button
  // so it grows and goes with it.
  Widget _barGap(Widget button) =>
      Padding(padding: const EdgeInsets.only(top: 4), child: button);

  ButtonStyle get _barButtonStyle {
    final _Look look = _look;
    return AppInk.pressless(TextButton.styleFrom(
      foregroundColor: look.neutrals.text,
      backgroundColor: look.neutrals.surface,
      textStyle: look.type.meta.copyWith(fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      minimumSize: const Size(0, 36),
      shape: AppShapes.pill,
    ));
  }

  Widget _itemRow(ListLabels labels, ListItem item) {
    final AppLocalizations loc = labels.loc;
    final _Look look = _look;
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
    final bool hasSubItems =
        checklistField != null && subItems is List && subItems.isNotEmpty;
    final String openKey = 'item-${item.id}';
    final bool open = hasSubItems && _isOpen(openKey, false);

    final Widget menu = PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, size: 20, color: look.neutrals.muted),
      onSelected: (value) {
        if (value == 'edit') {
          _showItemDialog(item: item);
        } else if (value == 'delete') {
          _deleteItem(item, primary is String ? primary : '');
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
          entry('delete', Icons.delete_outline, loc.delete),
        ];
      },
    );

    final Widget text = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppShapes.rowPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primary is String ? primary : '',
            style: done
                ? look.type.row.copyWith(
                    color: look.neutrals.muted,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: look.neutrals.muted,
                  )
                : look.type.row,
          ),
          if (summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                summary,
                style: look.type.meta,
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
              ),
            ),
        ],
      ),
    );

    return Padding(
      key: ValueKey(openKey),
      padding: const EdgeInsets.symmetric(horizontal: _edge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: hasSubItems
                ? () => _flip(openKey)
                : () => _showItemDialog(item: item),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (completion == null)
                  const SizedBox(width: _margin - _edge)
                else ...[
                  _check(done, (value) => _setTick(item, value)),
                  const SizedBox(width: 2),
                ],
                Expanded(child: text),
                if (hasSubItems)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: look.neutrals.muted,
                    ),
                  ),
                // The × on a ticked item clears just it (Q-101, Q-102). It
                // grows in left of the dots, which stay put (rule 7).
                if (completion != null &&
                    _behavior(BehaviorKind.clearCompleted) != null)
                  GrowIn(
                    key: ValueKey('clear-slot-${item.id}'),
                    shown: done,
                    alignment: AlignmentDirectional.centerEnd,
                    vertical: false,
                    child: IconButton(
                      key: ValueKey('clear-item-${item.id}'),
                      tooltip: loc.clear,
                      icon: Icon(Icons.close, size: 18, color: look.neutrals.muted),
                      onPressed: () =>
                          _clearCompleted((other) => other.id == item.id),
                    ),
                  ),
                menu,
              ],
            ),
          ),
          if (hasSubItems)
            _collapsible(open, [
              for (final Object? entry in subItems)
                if (entry is Map)
                  _subItemRow(item, checklistField, entry),
            ]),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _margin - _edge),
            child: Divider(),
          ),
        ],
      ),
    );
  }

  Widget _subItemRow(ListItem item, FieldDefinition field, Map entry) {
    final _Look look = _look;
    final bool done = entry['done'] == true;
    void toggle(bool value) =>
        _toggleSubItem(item, field, '${entry['id']}', value);

    return InkWell(
      key: ValueKey('sub-${entry['id']}'),
      onTap: () => toggle(!done),
      child: Padding(
        padding: const EdgeInsets.only(left: 50),
        child: Row(
          children: [
            _check(done, toggle, scale: 1.1),
            Expanded(
              child: Text(
                '${entry['title'] ?? ''}',
                style: look.type.row.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: done ? look.neutrals.muted : null,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: look.neutrals.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _filters(ListLabels labels) {
    final FieldDefinition? field = _filterField;
    if (field == null) {
      return const [];
    }
    final _Look look = _look;

    int count(String? value) {
      return widget.items.where((item) {
        if (value == null) {
          return true;
        }
        final Object? itemValue = item[field.key];
        return itemValue is List ? itemValue.contains(value) : itemValue == value;
      }).length;
    }

    // Plain text; the active one is bold with a dot in the list colour.
    Widget filter(String text, String? value) {
      final bool on = _filter == value;
      return Semantics(
        button: true,
        selected: on,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() => _filter = value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (on) ...[
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: look.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  text,
                  style: look.type.row.copyWith(
                    fontSize: 14,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    color: on ? look.neutrals.text : look.neutrals.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(_margin, 8, _edge, 0),
        child: Row(
          children: [
            filter('${labels.loc.listFilterAll} ${count(null)}', null),
            for (final FieldOption option in field.options) ...[
              const SizedBox(width: 18),
              filter('${labels.option(option)} ${count(option.value)}', option.value),
            ],
            if (field.type.hasUserOptions) ...[
              const SizedBox(width: 6),
              IconButton(
                tooltip: labels.loc.categories,
                icon: Icon(Icons.tune, size: 20, color: look.neutrals.muted),
                onPressed: () => _manageOptions(field, labels),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  Future<void> _deleteItem(ListItem item, String name) async {
    if (await confirmDelete(context, name, list: _definition) && mounted) {
      await _apply(ListChanges(deletedIds: [item.id]));
    }
  }

  // Open items in their groups, then ticked items in one Done group, unless
  // the user keeps them in place (Q-50 b).
  // Where ticked items go (Q-109): the same in every layout.
  TickedItems get _ticked =>
      context.watchAccountPreferences.tickedItemsFor(_definition);

  // Every item the filter lets through, ticked ones included, for counts that
  // must not depend on where ticked items are shown.
  List<ListItem> _allVisible = const [];

  // Ticking an item; with Clear straight away it is cleared at once, with
  // Undo, through the same clear as Clear ticked (Q-119), on a list with the
  // Clear ticked rule only: elsewhere it is a plain tick (Q-124).
  Future<void> _setTick(ListItem item, bool value) {
    if (value &&
        _behavior(BehaviorKind.clearCompleted) != null &&
        context.accountPreferences.tickedItemsFor(_definition) ==
            TickedItems.clearAtOnce) {
      return ClearWithUndo.run(
        store: widget.store,
        definition: _definition,
        items: widget.items,
        tick: item,
        banners: context.read<AppBannerController?>(),
        loc: AppLocalizations.of(context),
      );
    }
    return _apply(
      ListRules.setCompleted(_definition, item, value, DateTime.now().toUtc()),
    );
  }

  // Move to the bottom: ticked items go to an open Done group under the
  // layout's own groups, in every layout (Q-109).
  List<Widget> _withDone(
    ListLabels labels,
    List<ListItem> sorted,
    List<Widget> Function(List<ListItem> open) openPart,
  ) {
    if (_completion == null || _ticked != TickedItems.moveToDone) {
      return openPart(sorted);
    }
    final List<ListItem> done =
        sorted.where((item) => ListRules.isCompleted(_definition, item)).toList();
    return [
      ...openPart(
        sorted.where((item) => !ListRules.isCompleted(_definition, item)).toList(),
      ),
      if (done.isNotEmpty) ...[
        _header(labels.loc.listDoneGroup, count: done.length),
        for (final ListItem item in done) _itemRow(labels, item),
      ],
    ];
  }

  List<Widget> _grouped(ListLabels labels, List<ListItem> sorted) {
    final FieldDefinition? groupField =
        _definition.field(_definition.view.groupBy ?? '');
    if (groupField == null) {
      return [for (final ListItem item in sorted) _itemRow(labels, item)];
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
      children.add(_header(header, count: members.length));
      children.addAll(members.map((item) => _itemRow(labels, item)));
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
      return [for (final ListItem item in sorted) _itemRow(labels, item)];
    }

    final BehaviorDefinition? moveAll = _behavior(BehaviorKind.moveAll);
    final bool canClear = _behavior(BehaviorKind.clearCompleted) != null;
    final List<Widget> children = [];

    for (final FieldOption option in sectionField.options) {
      final List<ListItem> members =
          sorted.where((item) => item[sectionField.key] == option.value).toList();
      // Counted over every item of the section, wherever ticked ones show.
      final int ticked = _allVisible
          .where((item) =>
              item[sectionField.key] == option.value &&
              ListRules.isCompleted(_definition, item))
          .length;
      final bool movesFromHere = moveAll != null &&
          moveAll.stringParam('field') == sectionField.key &&
          moveAll.stringParam('from') == option.value &&
          _allVisible.any((item) => item[sectionField.key] == option.value);
      // The section has a Move button (shown or not).
      final bool hasMove = moveAll != null &&
          moveAll.stringParam('field') == sectionField.key &&
          moveAll.stringParam('from') == option.value;
      final Widget clearButton = TextButton(
        key: ValueKey('clear-ticked-button-${option.value}'),
        style: _barButtonStyle,
        onPressed: () => _clearCompleted(
          (item) => item[sectionField.key] == option.value,
        ),
        child: Text(
          '${labels.loc.clearTicked} (${labels.loc.tickedCount(ticked)})',
        ),
      );
      final FieldOption? target = movesFromHere
          ? sectionField.options
              .where((other) => other.value == moveAll.stringParam('to'))
              .firstOrNull
          : null;

      children.add(
        _header(
          labels.option(option),
          count: members.length,
          // Rule 7 (Q-105): Move keeps the first spot and Clear ticked grows
          // in on its right, so a tick never moves Move. Clear ticked is
          // shown only while Move is (it needs items), so Move growing in
          // never pushes it either. In a section with no Move, Clear ticked
          // grows in on the label's line instead, so no row opens (Q-120 C).
          trailing: canClear && !hasMove
              ? GrowIn(
                  key: ValueKey('clear-ticked-${option.value}'),
                  shown: ticked > 0,
                  vertical: false,
                  alignment: AlignmentDirectional.centerEnd,
                  child: clearButton,
                )
              : null,
          actions: [
            if (hasMove)
              GrowIn(
                key: ValueKey('move-all-${option.value}'),
                shown: target != null,
                child: _barGap(TextButton.icon(
                  key: ValueKey('move-all-button-${option.value}'),
                  style: _barButtonStyle,
                  icon: const Icon(Icons.arrow_upward, size: 16),
                  label: Text(target == null ? '' : labels.option(target)),
                  onPressed: () => _apply(
                    ListRules.moveAll(
                      _definition,
                      widget.items,
                      moveAll,
                      DateTime.now().toUtc(),
                    ),
                  ),
                )),
              ),
            if (canClear && hasMove)
              GrowIn(
                key: ValueKey('clear-ticked-${option.value}'),
                shown: ticked > 0,
                child: _barGap(clearButton),
              ),
          ],
        ),
      );

      if (members.isEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _margin,
              vertical: AppShapes.rowPadding,
            ),
            child: Text('—', style: _look.type.meta),
          ),
        );
      }
      children.addAll(members.map((item) => _itemRow(labels, item)));
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
    final List<Widget> children = [];
    for (final int year in yearKeys) {
      final String yearKey = 'year-$year';
      final bool yearOpen = _isOpen(yearKey, year == yearKeys.first);
      children.add(_foldHeader('$year', yearOpen, () => _flip(yearKey), strong: true));
      children.add(
        _collapsible(yearOpen, [
          for (final int month in years[year]!.keys.toList()..sort((a, b) => b - a))
            if (!byMonth)
              ...years[year]![month]!.map((item) => _itemRow(labels, item))
            else ...[
              _foldHeader(
                DateFormat.MMMM(locale).format(DateTime(year, month)),
                _isOpen('month-$year-$month', year == yearKeys.first),
                () => _flip('month-$year-$month'),
              ),
              _collapsible(
                _isOpen('month-$year-$month', year == yearKeys.first),
                [
                  for (final ListItem item in years[year]![month]!)
                    _itemRow(labels, item),
                ],
              ),
            ],
        ]),
      );
    }
    return children;
  }

  List<Widget> _checklist(ListLabels labels, List<ListItem> sorted) {
    final FieldDefinition? bucketField =
        _definition.field(_definition.view.bucketBy ?? '');
    if (bucketField == null) {
      return [for (final ListItem item in sorted) _itemRow(labels, item)];
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
      children.add(_header(names[index], count: members.length));
      children.addAll(members.map((item) => _itemRow(labels, item)));
    }
    return children;
  }

  // Checklists show open items first, soonest date first; everything else
  // shows newest first.
  // Hide: ticked items wait in a folded Done group at the end, in every view
  // (Q-50 b); tapping its label shows them.
  List<Widget> _hiddenDone(ListLabels labels, List<ListItem> done) {
    if (done.isEmpty) {
      return const [];
    }
    const String key = 'done-group';
    final bool open = _isOpen(key, false);
    return [
      _foldHeader(
        '${labels.loc.listDoneGroup} \u00b7 ${done.length}',
        open,
        () => _flip(key),
      ),
      if (open)
        for (final ListItem item in done) _itemRow(labels, item),
    ];
  }

  List<ListItem> _sorted(List<ListItem> items) {
    final List<ListItem> sorted = [...items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (_definition.view.kind != ViewKind.checklist) {
      return sorted;
    }

    final bool doneLast = _ticked != TickedItems.stayInPlace;
    final String? dateKey = _definition.view.bucketBy;
    DateTime? dateOf(ListItem item) {
      final Object? raw = dateKey == null ? null : item[dateKey];
      return raw is String ? DateTime.tryParse(raw) : null;
    }

    sorted.sort((a, b) {
      final int doneOrder = !doneLast
          ? 0
          : (ListRules.isCompleted(_definition, a) ? 1 : 0) -
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

  // The giant list name, cropped by the right edge, its description (Q-44)
  // and the count under it.
  Widget _title(AppLocalizations loc) {
    final _Look look = _look;
    final String? description = ListLabels(loc).listDescription(_definition);
    final int done = _completion == null
        ? 0
        : widget.items.where((item) => ListRules.isCompleted(_definition, item)).length;
    return Padding(
      padding: const EdgeInsets.only(left: 18, top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              widget.texts.title,
              style: look.type.listTitle,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
          ),
          // 20: when the title fits (tablets) it is not clipped, and its
          // descenders reach about 12 below its 0.9 line box.
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 20, right: 18),
              child: Text(
                description,
                key: const ValueKey('list-page-description'),
                style: look.type.meta.copyWith(fontSize: 14),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Padding(
            padding: EdgeInsets.only(left: 4, top: description == null ? 12 : 6),
            child: Text(
              _completion == null
                  ? loc.listItemCount(widget.items.length)
                  : loc.listOpenDoneCount(widget.items.length - done, done),
              style: look.type.meta.copyWith(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  static const double _addDisc = 62;
  static const double _addHeight = _addDisc + 6;

  // Room at the end of the list: enough for the last row to scroll clear of
  // the add button, which floats above the hub (and the AI bar) under the
  // launcher, and at least the old 120.
  double _bottomRoom(LauncherHubArea? hubArea) {
    const double least = 120;
    if (hubArea == null) return least;
    final double above = AboveHubButtonLocation.heightAboveBottom(
      hubArea,
      MediaQuery.sizeOf(context),
      _addHeight,
    );
    return above + 12 > least ? above + 12 : least;
  }

  // The eclipse: a list-colour disc over a black one, with the floating shadow.
  Widget _addButton() {
    final _Look look = _look;
    const double disc = _addDisc;
    return SizedBox(
      width: disc + 10,
      height: _addHeight,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            width: disc,
            height: disc,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: look.neutrals.text,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            width: disc,
            height: disc,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: look.shadow,
              ),
              child: FloatingActionButton(
                onPressed: () {
                  _showItemDialog();
                },
                tooltip: widget.texts.addTooltip,
                backgroundColor: look.color,
                foregroundColor: look.onColor,
                elevation: 0,
                focusElevation: 0,
                hoverElevation: 0,
                highlightElevation: 0,
                shape: const CircleBorder(),
                child: const Icon(Icons.add, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final ListLabels labels = ListLabels(loc);
    _look = _Look.of(context, _definition);
    final FieldDefinition? filterField = _filterField;
    if (filterField != null && _filter != null && !filterField.hasOption(_filter)) {
      _filter = null;
    }

    final List<ListItem> visible = _sorted(widget.items.where(_matchesFilter).toList());
    _allVisible = visible;
    final bool hideDone = _completion != null && _ticked == TickedItems.hide;
    final List<ListItem> shown = hideDone
        ? visible.where((item) => !ListRules.isCompleted(_definition, item)).toList()
        : visible;
    // The top bar's clear button belongs to checklist lists that clear; it
    // shows while any visible item is ticked.
    final bool hasClearAll = _definition.view.kind == ViewKind.checklist &&
        _behavior(BehaviorKind.clearCompleted) != null;
    final bool canClearAll = hasClearAll &&
        visible.any((item) => ListRules.isCompleted(_definition, item));

    final List<Widget> content = [
      ...switch (_definition.view.kind) {
        ViewKind.grouped =>
          _withDone(labels, shown, (open) => _grouped(labels, open)),
        ViewKind.sectioned =>
          _withDone(labels, shown, (open) => _sectioned(labels, open)),
        ViewKind.timeline =>
          _withDone(labels, shown, (open) => _timeline(labels, open)),
        ViewKind.checklist =>
          _withDone(labels, shown, (open) => _checklist(labels, open)),
        ViewKind.table || ViewKind.cards => _withDone(labels, shown, (open) => [
              for (final ListItem item in open) _itemRow(labels, item),
            ]),
      },
      if (hideDone)
        ..._hiddenDone(
          labels,
          visible.where((item) => ListRules.isCompleted(_definition, item)).toList(),
        ),
    ];

    final bool showEmpty =
        visible.isEmpty && _definition.view.kind != ViewKind.sectioned;
    // Under the floating launcher the add button sits just above its hub.
    final LauncherHubArea? hubArea = LauncherHubArea.maybeOf(context);
    final ListEditAction? editAction = ListEditAction.maybeOf(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          // Rule 7 (Q-105): the clear button grows in at the left end of the
          // right-aligned buttons, so the pin and Edit list never move.
          if (hasClearAll)
            GrowIn(
              key: const ValueKey('list-clear'),
              shown: canClearAll,
              alignment: AlignmentDirectional.centerEnd,
              vertical: false,
              child: IconButton(
                tooltip: loc.clearTicked,
                icon: const Icon(Icons.cleaning_services_outlined),
                onPressed: () => _clearCompleted(_matchesFilter),
              ),
            ),
          // Pins follow the account, so there is none without one.
          if (context.read<AccountPreferencesCubit?>()
              case final AccountPreferencesCubit preferences)
            HomePinButton(
              key: const ValueKey('list-pin'),
              pinned: context.watchAccountPreferences.homePins.contains(
                _definition.id,
              ),
              onPressed: () {
                if (preferences.state.homePins.contains(_definition.id)) {
                  preferences.unpinFromHome(_definition.id);
                } else {
                  preferences.pinToHome(
                    _definition.id,
                    existing: [
                      for (final ListDefinition list
                          in widget.store.current.definitions)
                        list.id,
                    ],
                  );
                }
              },
            ),
          if (editAction != null)
            IconButton(
              key: const ValueKey('edit-list'),
              tooltip: loc.editList,
              icon: const Icon(Icons.tune),
              onPressed: () => editAction.onEdit(_definition.id),
            ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: hubArea == null
          ? _addButton()
          : ScaleTransition(
              key: const ValueKey('add-button-scale'),
              scale: _addScale,
              child: IgnorePointer(ignoring: !_addShown, child: _addButton()),
            ),
      floatingActionButtonLocation:
          hubArea == null ? null : AboveHubButtonLocation(hubArea),
      floatingActionButtonAnimator: hubArea == null
          ? null
          : _reduceMotion
              ? FloatingActionButtonAnimator.noAnimation
              : const _SizeOnlyButtonAnimator(),
      // The title, description and count stay; the items scroll under them
      // (Q-65).
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(loc),
          Expanded(
            child: RefreshIndicator(
              onRefresh: widget.store.refresh,
              color: _look.color,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                // The last row, its × included, clears the add button when
                // scrolled to the end (T-24 unit 7 D1).
                padding: EdgeInsets.only(bottom: _bottomRoom(hubArea)),
                children: [
                  ..._filters(labels),
                  if (showEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(_margin, 32, _margin, 0),
                      child:
                          Text(widget.texts.emptyText, style: _look.type.meta),
                    )
                  else
                    ...content,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// The colours and styles this screen uses for the current theme: the
// neutrals and the open list's colour (docs/AESTHETICS.md).
class _Look {
  const _Look._({
    required this.neutrals,
    required this.type,
    required this.color,
    required this.onColor,
    required this.shadow,
  });

  factory _Look.of(BuildContext context, ListDefinition definition) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color color = listColor(definition.color, brightness: brightness);
    return _Look._(
      neutrals: AppColors.neutrals(brightness),
      type: AppTypography.of(context),
      color: color,
      onColor: AppColors.onColor(color),
      shadow: AppShadows.floating(brightness),
    );
  }

  final AppNeutrals neutrals;
  final AppTypography type;
  final Color color;
  final Color onColor;
  final List<BoxShadow> shadow;
}

// Moves the add button when the hub moves by shrinking it away and growing
// it back at its new place: size only, without the default turn
// (docs/AESTHETICS.md, Motion).
class _SizeOnlyButtonAnimator extends FloatingActionButtonAnimator {
  const _SizeOnlyButtonAnimator();

  @override
  Offset getOffset({
    required Offset begin,
    required Offset end,
    required double progress,
  }) =>
      progress < 0.5 ? begin : end;

  @override
  Animation<double> getScaleAnimation({required Animation<double> parent}) {
    return parent.drive(
      TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(begin: 1, end: 0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: 1)
              .chain(CurveTween(curve: AppMotion.curve)),
          weight: 1,
        ),
      ]),
    );
  }

  @override
  Animation<double> getRotationAnimation({required Animation<double> parent}) =>
      const AlwaysStoppedAnimation<double>(1);

  // Continues from where an interrupted move left off.
  @override
  double getAnimationRestart(double previousValue) =>
      previousValue < 0.5 ? previousValue : 1 - previousValue;
}
