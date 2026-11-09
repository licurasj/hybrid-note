import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'app/account_preferences.dart';
import 'app/app_banner.dart';
import 'app/app_settings.dart';
import 'app/app_theme.dart';
import 'app/date_preferences.dart';
import 'app/home_cards.dart';
import 'app/hybrid_note_app.dart';
import 'app/list_order.dart';
import 'app/preferences_screen.dart';
import 'app/starter_note.dart';
import 'app_colors.dart';
import 'home_cards_view.dart';
import 'l10n/generated/app_localizations.dart';
import 'launcher/arrange_sway.dart';
import 'launcher/launcher_geometry.dart';
import 'launcher/launcher_hub_area.dart';
import 'lists/generic_list_screen.dart' show ListEditAction;
import 'lists/generic_item_dialog.dart';
import 'lists/list_catalog.dart';
import 'lists/list_catalog_builder.dart';
import 'lists/list_definition.dart';
import 'lists/list_icons.dart';
import 'lists/list_item.dart';
import 'lists/list_labels.dart';
import 'lists/list_rules.dart';
import 'lists/list_store.dart';
import 'lists/list_vocabulary.dart';

// One item whose reminder date is today or earlier: open, or ticked and not
// yet cleared.
class HomeDueItem {
  const HomeDueItem({
    required this.definition,
    required this.item,
    required this.due,
    required this.hasTime,
    this.done = false,
  });

  final ListDefinition definition;
  final ListItem item;
  final DateTime due;
  // Date-and-time fields show their time; date fields only their day.
  final bool hasTime;
  final bool done;

  // Its list clears ticked items (a Clear ticked rule), so its row offers ×.
  bool get clearable => definition.behaviors.any(
    (behavior) => behavior.kind == BehaviorKind.clearCompleted,
  );
}

// What is due today or overdue across every list, earliest first: items whose
// reminder-role date falls before tomorrow. Open ones, and ticked ones too, so
// that a tick by accident can be taken back (owner, 2026-11-08): those stay
// until cleared, on home or on their list page. In a list with no Clear ticked
// rule a ticked item cannot be cleared, so it stays only while due today.
// Lists without a reminder field have nothing due.
List<HomeDueItem> homeDueItems(ListCatalog catalog, DateTime now) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime tomorrow = DateTime(now.year, now.month, now.day + 1);
  final List<HomeDueItem> due = [];
  for (final ListDefinition definition in catalog.definitions) {
    final FieldDefinition? field = definition.fieldWithRole(FieldRole.reminder);
    if (field == null) {
      continue;
    }
    for (final ListItem item in catalog.itemsOf(definition.id)) {
      final Object? raw = item[field.key];
      final DateTime? date = raw is String
          ? DateTime.tryParse(raw)?.toLocal()
          : null;
      if (date == null || !date.isBefore(tomorrow)) {
        continue;
      }
      final HomeDueItem entry = HomeDueItem(
        definition: definition,
        item: item,
        due: date,
        hasTime: field.type == FieldType.dateTime,
        done: ListRules.isCompleted(definition, item),
      );
      if (entry.done && !entry.clearable && date.isBefore(today)) {
        continue;
      }
      due.add(entry);
    }
  }
  due.sort((a, b) => a.due.compareTo(b.due));
  return due;
}

// The home behind the hub (Q-20 A, Q-65, docs/AESTHETICS.md Layout): a fixed
// header with the weekday very large, the date with "N things today" and the
// blue settings button, and scrolling behind it what is due today or overdue
// across lists, then the list cards. Lists come from the ListStore catalog;
// nothing keys on list ids.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.onOpenList,
    this.recentLists,
    this.returned,
    this.pressedElsewhere,
  });

  final ValueChanged<String>? onOpenList;
  // The phone's Last used order, newest first (Q-49).
  final List<String> Function()? recentLists;
  // Fires on coming back to home from a list.
  final Listenable? returned;
  // Fires on a press on the hub or the AI bar, which ends arranging.
  final Listenable? pressedElsewhere;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// The cards hold still once worked out, with only the items inside them
// updating, until coming back from a list, a new start or a pull down (Q-74).
// A change to the account's choices that this screen did not make also counts,
// as they arrive after the first frame on a new phone or from another phone.
//
// Holding a card lifts it, and its choices slide out as prompts (Q-76, interaction
// law). Rearrange opens arranging (Q-77): pinned cards sway on a soft surface, the
// held card is ready to drag, and any other is picked up by a short rest; a swipe
// still scrolls. Everything else dims, and Done, a tap outside or Back ends it.
class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // How much a lifted card grows, and how far cards lean while arranging: a
  // lifted one less than the rest. The owner tunes these on the phone.
  static const double _liftScale = 1.08;
  static const double _liftedSwayDegrees = 0.4;
  // What arranging looks like, to judge on screen with the owner: how far all but
  // the pinned cards dim, and each pinned card's surface, a soft shadow on the
  // ground colour or, with [_arrangeTint], a soft background with no shadow.
  static const double _arrangeDim = 0.35;
  static const bool _arrangeTint = false;
  static const double _arrangeRadius = 20;
  static const double _edgeScrollZone = 80;
  static const double _edgeScrollSpeed = 700;

  List<String>? _pinned;
  List<String> _suggested = const [];
  // Unpinned here, and showing an unfilled pin until the next refresh (Q-65).
  final Set<String> _unfilled = {};
  String? _workedOutFrom;
  // Changes from this screen on their way, some in several steps.
  int _ownChanges = 0;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _stack = GlobalKey();
  final Map<String, GlobalKey> _cardKeys = {};
  final ValueNotifier<Duration> _time = ValueNotifier(Duration.zero);
  late final Ticker _clock;
  Duration _lastTick = Duration.zero;
  // One clock for every Today row's small blob: each tick repaints them only.
  final ValueNotifier<int> _blobTick = ValueNotifier(0);
  late final Ticker _blobClock;
  late final AnimationController _lift;
  late final AnimationController _reveal;
  // A rest on a pinned card while arranging lifts it until it is picked up.
  late final AnimationController _rest;
  String? _restingId;

  // The card under a hold, and once its prompts are out what they offer.
  String? _heldId;
  List<HomeCardAction> _prompts = const [];
  List<String> _promptLabels = const [];
  List<Rect> _promptRects = const [];
  HomePromptFit? _promptFit;
  int? _promptSelected;
  Offset _holdStart = Offset.zero;
  Offset _finger = Offset.zero;
  Rect _heldRect = Rect.zero;

  bool _arranging = false;
  String? _selectedId;
  String? _dragId;
  // The pinned order when the drag began, to go back to if it is cancelled.
  List<String>? _dragStartOrder;
  double _dragGrab = 0;
  bool _dragMoved = false;
  // Picked up as the selected card, with no rest, which its recognizer keeps.
  bool _dragFromReady = false;
  // Cards that have changed place, by how far they still have to slide.
  final Map<String, double> _slides = {};
  Offset? _outsideTapFrom;

  bool get _moves =>
      !HomeBlob.isStill && !MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _clock = createTicker(_tick);
    _blobClock = createTicker((_) => _blobTick.value++);
    _lift = AnimationController(
      vsync: this,
      duration: const LauncherConfig().promptDelay,
    );
    _reveal = AnimationController(
      vsync: this,
      duration: const LauncherConfig().revealDuration,
    );
    _rest = AnimationController(
      vsync: this,
      duration: const LauncherConfig().dialPickUpDelay,
    );
    widget.returned?.addListener(_refresh);
    widget.pressedElsewhere?.addListener(_endArranging);
  }

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (old.returned != widget.returned) {
      old.returned?.removeListener(_refresh);
      widget.returned?.addListener(_refresh);
    }
    if (old.pressedElsewhere != widget.pressedElsewhere) {
      old.pressedElsewhere?.removeListener(_endArranging);
      widget.pressedElsewhere?.addListener(_endArranging);
    }
  }

  @override
  void dispose() {
    widget.returned?.removeListener(_refresh);
    widget.pressedElsewhere?.removeListener(_endArranging);
    _clock.dispose();
    _blobClock.dispose();
    _blobTick.dispose();
    _lift.dispose();
    _reveal.dispose();
    _rest.dispose();
    _time.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() => _pinned = null);
    }
  }

  Future<void> _pullDown() async {
    await context.read<ListStore>().refresh();
    _refresh();
  }

  static String _choices(AccountPreferences preferences) => jsonEncode([
    preferences.homeSuggestions,
    preferences.homePins,
    preferences.homeRemoved,
    preferences.homeOrder,
    preferences.homeArranged,
    preferences.listOrder.wire,
    preferences.myListOrder,
  ]);

  List<String> _dialOrder(
    ListCatalog catalog,
    AccountPreferences preferences,
    ListLabels labels,
  ) => [
    for (final ListDefinition list in orderLists(
      catalog.definitions,
      order: preferences.listOrder,
      myOrder: preferences.myListOrder,
      recent: widget.recentLists?.call() ?? const [],
      nameOf: labels.listName,
    ))
      list.id,
  ];

  void _workOutCards(
    ListCatalog catalog,
    AccountPreferences preferences,
    ListLabels labels,
    DateTime now,
  ) {
    if (_pinned != null && (_ownChanges > 0 || _arranging || _heldId != null)) {
      return;
    }
    final String choices = _choices(preferences);
    if (_pinned != null &&
        _workedOutFrom == choices &&
        (_pinned!.isNotEmpty || _suggested.isNotEmpty)) {
      return;
    }
    final List<String> pinned = homePinnedOrder(
      pins: preferences.homePins,
      dialOrder: _dialOrder(catalog, preferences, labels),
      homeOrder: preferences.homeOrder,
      homeArranged: preferences.homeArranged,
    );
    _pinned = pinned;
    _suggested = [
      for (final ListDefinition list in chooseHomeCards(
        catalog,
        pinnedOrder: pinned,
        removed: preferences.homeRemoved,
        showSuggestions: preferences.homeSuggestions,
        now: now,
      ).suggested)
        list.id,
    ];
    _unfilled.clear();
    _workedOutFrom = choices;
  }

  // A change made here: the cards do not treat it as news from elsewhere.
  Future<void> _own(
    Future<void> Function(AccountPreferencesCubit) change,
  ) async {
    final AccountPreferencesCubit cubit = context
        .read<AccountPreferencesCubit>();
    _ownChanges++;
    try {
      await change(cubit);
    } finally {
      _ownChanges--;
      if (mounted) {
        setState(() => _workedOutFrom = _choices(cubit.state));
      }
    }
  }

  // The pin on a card: the card stays, and a second tap puts it back in place.
  void _tapPin(String listId, ListCatalog catalog) {
    final bool filling = _unfilled.remove(listId);
    if (!filling) {
      _unfilled.add(listId);
    }
    setState(() {});
    _own(
      (cubit) => filling
          ? cubit.pinToHome(
              listId,
              existing: [for (final list in catalog.definitions) list.id],
              keepPlace: true,
            )
          : cubit.unpinFromHome(listId),
    );
  }

  void _act(HomeCardAction action, String listId, ListCatalog catalog) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final AppBannerController banners = context.read<AppBannerController>();
    final List<String> existing = [
      for (final list in catalog.definitions) list.id,
    ];
    switch (action) {
      case HomeCardAction.rearrange:
        _startArranging(listId);
      case HomeCardAction.edit:
        _edit?.onEdit(listId);
      case HomeCardAction.unpin:
        _tapPin(listId, catalog);
      case HomeCardAction.pin:
        if (_unfilled.contains(listId)) {
          _tapPin(listId, catalog);
        } else {
          // At once to the end of the pinned cards; the suggestions are worked
          // out again at the next refresh (Q-76).
          setState(() {
            _suggested = [..._suggested]..remove(listId);
            _pinned = [..._pinned!, listId];
          });
          _own((cubit) => cubit.pinToHome(listId, existing: existing));
        }
      case HomeCardAction.remove:
        setState(() => _suggested = [..._suggested]..remove(listId));
        _own((cubit) => cubit.removeFromHome(listId, existing: existing));
        banners.show(
          loc.homeRemovedBanner,
          actionLabel: loc.undo,
          onAction: () {
            context.read<AccountPreferencesCubit>().undoRemoveFromHome(listId);
            _refresh();
          },
        );
      case HomeCardAction.noSuggestions:
        // Like Remove: the suggestions go by hand and the rest stays as it is
        // until the next refresh (Q-65, Q-74); Undo brings them back with one.
        setState(() => _suggested = const []);
        _own((cubit) => cubit.setHomeSuggestions(false));
        banners.show(
          loc.homeSuggestionsOffBanner,
          actionLabel: loc.undo,
          onAction: () {
            context.read<AccountPreferencesCubit>().setHomeSuggestions(true);
            _refresh();
          },
        );
    }
  }

  ListEditAction? _edit;

  String _actionLabel(AppLocalizations loc, HomeCardAction action) =>
      switch (action) {
        HomeCardAction.rearrange => loc.homeRearrange,
        HomeCardAction.edit => loc.edit,
        HomeCardAction.unpin => loc.homeUnpinShort,
        HomeCardAction.pin => loc.homePinShort,
        HomeCardAction.remove => loc.homeRemove,
        HomeCardAction.noSuggestions => loc.homeNoSuggestions,
      };

  List<HomeCardAction> _actionsOf(String listId, {required bool suggested}) =>
      homeCardActions(
        pinned: suggested ? null : !_unfilled.contains(listId),
        pinnedLists: _filledPins.length,
      );

  List<String> get _filledPins => [
    for (final String id in _pinned ?? const <String>[])
      if (!_unfilled.contains(id)) id,
  ];

  void _buzz(bool strong) {
    if (context.accountPreferences.vibration) {
      strong ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
    }
  }

  // Each frame of a hold or of arranging: the sways, the cards sliding to their
  // places and scrolling at the screen's edges.
  void _tick(Duration elapsed) {
    final double seconds = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _time.value = elapsed;
    if (_slides.isNotEmpty) {
      final double step = seconds / (AppMotion.quick.inMicroseconds / 1e6);
      setState(() {
        _slides.updateAll((_, left) {
          final double done = left * (1 - step).clamp(0.0, 1.0);
          return done.abs() < 0.5 ? 0 : done;
        });
        _slides.removeWhere((_, left) => left == 0);
      });
    }
    if (_dragId != null) {
      _scrollAtEdge(seconds);
    }
    _syncClock();
  }

  // Ticks or unticks an item as its list page does (ListRules.setCompleted).
  // A ticked row stays, crossed out, so a tick by accident is one tap to undo.
  void _tickDue(HomeDueItem due) {
    if (_arranging) {
      return;
    }
    _buzz(false);
    final ListChanges changes = ListRules.setCompleted(
      due.definition,
      due.item,
      !due.done,
      DateTime.now().toUtc(),
    );
    if (!changes.isEmpty) {
      context.read<ListStore>().apply(changes);
    }
  }

  // Clears one ticked item as the list page's Clear on that item does, so a
  // Grocery item is kept for next time and a repeating task comes again.
  void _clearDue(HomeDueItem due, ListCatalog catalog) {
    if (_arranging) {
      return;
    }
    final ListChanges changes = ListRules.clearCompleted(
      due.definition,
      catalog.itemsOf(due.definition.id),
      DateTime.now().toUtc(),
      inScope: (other) => other.id == due.item.id,
    );
    if (!changes.isEmpty) {
      context.read<ListStore>().apply(changes);
    }
  }

  // The Today rows' blobs move only while there are rows to show.
  void _syncBlobClock(bool wanted) {
    if (wanted && !_blobClock.isActive) {
      _blobClock.start();
    } else if (!wanted && _blobClock.isActive) {
      _blobClock.stop();
    }
  }

  void _syncClock() {
    final bool wanted =
        _slides.isNotEmpty ||
        _dragId != null ||
        ((_arranging || _heldId != null) && _moves);
    if (wanted && !_clock.isActive) {
      _lastTick = Duration.zero;
      _clock.start();
    } else if (!wanted && _clock.isActive) {
      _clock.stop();
    }
  }

  RenderBox? get _stackBox =>
      _stack.currentContext?.findRenderObject() as RenderBox?;

  // Where a card lies in the stack, without its sway or slide.
  Rect? _rectOf(String listId) {
    final RenderBox? box =
        _cardKeys[listId]?.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? stack = _stackBox;
    if (box == null || stack == null || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
  }

  // --- The hold ---

  void _holdDown(String listId) {
    if (_arranging) {
      return;
    }
    setState(() => _heldId = listId);
    if (_moves) {
      _lift.forward(from: 0);
    }
    _syncClock();
  }

  // Before the prompts, the finger moved off. After them, the system took the
  // touch (a cancel, not an end): it ends as a release on none, doing nothing.
  void _holdCancelled() {
    if (_arranging) {
      return;
    }
    _lift.value = 0;
    _reveal.value = 0;
    setState(() {
      _heldId = null;
      _prompts = const [];
      _promptLabels = const [];
      _promptRects = const [];
      _promptSelected = null;
    });
    _syncClock();
  }

  void _holdReached(
    String listId,
    Offset global, {
    required bool suggested,
    required TextScaler scaler,
    required AppLocalizations loc,
  }) {
    final RenderBox? stack = _stackBox;
    final Rect? rect = _rectOf(listId);
    if (stack == null || rect == null) {
      return;
    }
    _buzz(true);
    _lift.value = 1;
    final Offset finger = stack.globalToLocal(global);
    final List<HomeCardAction> actions = _actionsOf(
      listId,
      suggested: suggested,
    );
    final List<String> labels = [
      for (final HomeCardAction action in actions) _actionLabel(loc, action),
    ];
    final measured = homePromptMeasure(
      labels,
      Directionality.of(context),
      scaler,
    );
    final Size screen = stack.size;
    final HomePromptFit fit = homePromptFit(
      oneLine: measured.oneLine,
      broken: measured.broken,
      room: screen.width - 2 * homePromptMargin,
    );
    final LauncherHubArea? hub = LauncherHubArea.maybeOf(context);
    final Offset? hubCentre = hub?.hubCenter(screen);
    setState(() {
      _heldRect = rect;
      _holdStart = finger;
      _finger = finger;
      _prompts = actions;
      _promptFit = fit;
      _promptLabels = [
        for (int i = 0; i < labels.length; i++)
          fit.wrapped.contains(i) ? measured.brokenLabels[i] : labels[i],
      ];
      _promptRects = homePromptRow(
        finger: finger,
        widths: fit.widths,
        height: fit.wrapped.isEmpty
            ? homePromptHeight
            : homePromptWrappedHeight,
        screen: screen,
        top: MediaQuery.paddingOf(context).top + 8,
        bottom: screen.height - homePromptBottomRoom,
        avoid: hubCentre == null
            ? null
            : Rect.fromCircle(center: hubCentre, radius: hub!.hubReach),
      );
      _promptSelected = null;
    });
    if (_moves) {
      _reveal.forward(from: 0);
    } else {
      _reveal.value = 1;
    }
  }

  // Filled by how far the finger has come, and full once it is there (rule 3).
  double _promptProgress(int index) =>
      homePromptProgress(_holdStart, _finger, _promptRects[index]);

  void _holdMoved(Offset global) {
    final RenderBox? stack = _stackBox;
    if (stack == null || _prompts.isEmpty) {
      return;
    }
    final Offset finger = stack.globalToLocal(global);
    const LauncherConfig config = LauncherConfig();
    setState(() {
      _finger = finger;
      int? best;
      double bestProgress = 0;
      for (int i = 0; i < _prompts.length; i++) {
        final double progress = _promptProgress(i);
        if (progress > bestProgress) {
          best = i;
          bestProgress = progress;
        }
      }
      final int? was = _promptSelected;
      if (was != null &&
          (_promptProgress(was) < config.promptUnselectAt || best != was)) {
        _promptSelected = null;
      }
      if (_promptSelected == null &&
          best != null &&
          bestProgress >= config.promptSelectAt) {
        _promptSelected = best;
        if (best != was) {
          _buzz(false);
        }
      }
    });
  }

  void _holdEnded(ListCatalog catalog) {
    final String? listId = _heldId;
    final int? chosen = _promptSelected;
    final HomeCardAction? action = chosen == null ? null : _prompts[chosen];
    setState(() {
      _heldId = null;
      _prompts = const [];
      _promptLabels = const [];
      _promptRects = const [];
      _promptSelected = null;
    });
    _reveal.value = 0;
    if (listId != null && action != null) {
      _act(action, listId, catalog);
    }
    // Rearrange carries the lift on; anything else settles at once.
    _lift.value = _arranging ? 1 : 0;
    _syncClock();
  }

  // --- Arranging ---

  void _startArranging(String listId) {
    setState(() {
      _arranging = true;
      _selectedId = listId;
    });
    _syncClock();
  }

  void _endArranging() {
    if (!_arranging || !mounted) {
      return;
    }
    setState(() {
      _arranging = false;
      _selectedId = null;
      _dragId = null;
      _outsideTapFrom = null;
      _restingId = null;
    });
    _rest.value = 0;
    _syncClock();
  }

  void _restDown(String listId) {
    if (_moves && _selectedId != listId) {
      setState(() => _restingId = listId);
      _rest.forward(from: 0);
    }
  }

  // A finger that moves off lets it ease back. A drag the system takes (a
  // cancel, not a drop) puts the cards back as they were and saves nothing.
  void _restCancelled(String listId) {
    if (_dragId == listId) {
      final List<String>? pinned = _pinned;
      setState(() {
        if (pinned != null && _dragStartOrder != null) {
          pinned
            ..clear()
            ..addAll(_dragStartOrder!);
        }
        _dragStartOrder = null;
        _dragId = null;
        _slides.clear();
      });
      _syncClock();
      return;
    }
    if (_restingId == listId) {
      _rest.animateBack(0, duration: AppMotion.quick);
    }
  }

  void _pickUp(String listId, Offset global) {
    final RenderBox? stack = _stackBox;
    final Rect? rect = _rectOf(listId);
    if (stack == null || rect == null) {
      return;
    }
    if (_selectedId != listId) {
      _buzz(true);
    }
    final Offset finger = stack.globalToLocal(global);
    setState(() {
      _dragFromReady = _selectedId == listId;
      _selectedId = listId;
      _restingId = null;
      _dragId = listId;
      _dragMoved = false;
      _finger = finger;
      _holdStart = finger;
      _heldRect = rect;
      _dragGrab = finger.dy - rect.top;
      _dragStartOrder = List.of(_pinned ?? const <String>[]);
      _slides.remove(listId);
    });
    _syncClock();
  }

  void _dragMovedTo(Offset global) {
    final RenderBox? stack = _stackBox;
    if (stack == null || _dragId == null) {
      return;
    }
    final Offset finger = stack.globalToLocal(global);
    setState(() {
      _finger = finger;
      if ((finger - _holdStart).distance > kTouchSlop) {
        _dragMoved = true;
      }
    });
    if (_dragMoved) {
      _changePlaces();
    }
  }

  // A place changes when the card's middle passes a neighbour's middle. The
  // neighbour slides from where it was (T-21's idea for the dial, in y).
  void _changePlaces() {
    final String? dragged = _dragId;
    final List<String>? pinned = _pinned;
    if (dragged == null || pinned == null) {
      return;
    }
    final double middle = _finger.dy - _dragGrab + _heldRect.height / 2;
    final List<String> filled = _filledPins;
    final int at = filled.indexOf(dragged);
    String? passed;
    bool down = false;
    if (at + 1 < filled.length) {
      final Rect? next = _rectOf(filled[at + 1]);
      if (next != null && middle > next.center.dy) {
        passed = filled[at + 1];
        down = true;
      }
    }
    if (passed == null && at > 0) {
      final Rect? previous = _rectOf(filled[at - 1]);
      if (previous != null && middle < previous.center.dy) {
        passed = filled[at - 1];
      }
    }
    if (passed == null) {
      return;
    }
    final String other = passed;
    _buzz(false);
    setState(() {
      final int from = pinned.indexOf(dragged);
      final int to = pinned.indexOf(other);
      pinned
        ..[from] = other
        ..[to] = dragged;
      if (_moves) {
        _slides[other] =
            (_slides[other] ?? 0) +
            (down ? _heldRect.height : -_heldRect.height);
      }
    });
    _syncClock();
  }

  void _scrollAtEdge(double seconds) {
    final RenderBox? stack = _stackBox;
    if (stack == null || !_scroll.hasClients) {
      return;
    }
    final double top = _finger.dy - _edgeScrollZone;
    final double bottom = stack.size.height - homePromptBottomRoom - _finger.dy;
    final double depth = top < 0
        ? top / _edgeScrollZone
        : bottom < 0
        ? -bottom / _edgeScrollZone
        : 0;
    if (depth == 0) {
      return;
    }
    final ScrollPosition position = _scroll.position;
    final double target = (position.pixels + depth * _edgeScrollSpeed * seconds)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) {
      _scroll.jumpTo(target);
      _changePlaces();
    }
  }

  void _dropped(ListCatalog catalog, ListLabels labels) {
    final String? dragged = _dragId;
    if (dragged == null) {
      return;
    }
    if (!_dragMoved) {
      // A press that lifts without moving leaves it ready to drag.
      setState(() => _dragId = null);
      _syncClock();
      return;
    }
    final double top = _finger.dy - _dragGrab;
    final Rect? place = _rectOf(dragged);
    setState(() {
      _dragId = null;
      _selectedId = null;
      if (place != null && _moves) {
        _slides[dragged] = top - place.top;
      }
    });
    _syncClock();
    _saveOrder(catalog, labels);
  }

  void _saveOrder(ListCatalog catalog, ListLabels labels) {
    final List<String> order = _filledPins;
    final AccountPreferences now = context.accountPreferences;
    final List<String> shown = homePinnedOrder(
      pins: now.homePins,
      dialOrder: _dialOrder(catalog, now, labels),
      homeOrder: now.homeOrder,
      homeArranged: now.homeArranged,
    );
    if (listEquals(order, shown)) {
      return;
    }
    final List<String> dial = _dialOrder(catalog, now, labels);
    _own((cubit) => cubit.arrangedOnHome(order, dialOrder: dial));
  }

  // For a screen reader, which has no hold or drag.
  void _moveByOne(
    String listId,
    int by,
    ListCatalog catalog,
    ListLabels labels,
  ) {
    final List<String> filled = _filledPins;
    final int at = filled.indexOf(listId);
    final int to = at + by;
    if (at < 0 || to < 0 || to >= filled.length) {
      return;
    }
    final List<String> pinned = _pinned!;
    final int a = pinned.indexOf(listId);
    final int b = pinned.indexOf(filled[to]);
    setState(() {
      pinned
        ..[a] = filled[to]
        ..[b] = listId;
    });
    _saveOrder(catalog, labels);
  }

  // A tap on anything but a pinned card ends arranging; a swipe does not.
  void _pointerDown(PointerDownEvent event) {
    if (!_arranging) {
      return;
    }
    final RenderBox? stack = _stackBox;
    final Offset? at = stack?.globalToLocal(event.position);
    final bool onCard =
        at != null &&
        _filledPins.any((id) => _rectOf(id)?.contains(at) ?? false);
    _outsideTapFrom = onCard ? null : event.position;
  }

  void _pointerMove(PointerMoveEvent event) {
    final Offset? from = _outsideTapFrom;
    if (from != null && (event.position - from).distance > kTouchSlop) {
      _outsideTapFrom = null;
    }
  }

  void _pointerUp(PointerUpEvent event) {
    if (_outsideTapFrom != null) {
      _outsideTapFrom = null;
      _endArranging();
    }
  }

  Widget _cardContent(
    ListCatalog catalog,
    ListDefinition definition, {
    required bool suggested,
    required bool lifted,
  }) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final String listId = definition.id;
    final Widget card = HomeListCard(
      definition: definition,
      openItems: homeTopItems(definition, catalog.itemsOf(listId)),
      pinned: suggested ? null : !_unfilled.contains(listId),
      lifted: lifted,
      onPin: suggested || _arranging ? null : () => _tapPin(listId, catalog),
      menu: _arranging
          ? const []
          : [
              for (final HomeCardAction action in _actionsOf(
                listId,
                suggested: suggested,
              ))
                (
                  key: action.name,
                  label: _actionLabel(loc, action),
                  icon: _actionIcon(action),
                  onSelected: () => _act(action, listId, catalog),
                ),
            ],
    );
    return _arranging && !suggested && !_unfilled.contains(listId)
        ? _arrangeSurface(listId, card)
        : card;
  }

  // Under a pinned card while arranging, wider than the card so its text is clear
  // of the edge, and with no change to the card's place. The normal home has none.
  Widget _arrangeSurface(String listId, Widget card) {
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    // A shadow does not show on a black ground.
    final bool tint = _arrangeTint || brightness == Brightness.dark;
    final bool selected = _selectedId == listId;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -6,
          right: -6,
          top: 0,
          bottom: 4,
          child: DecoratedBox(
            key: ValueKey('home-arrange-surface-$listId'),
            decoration: BoxDecoration(
              color: tint ? neutrals.line : neutrals.ground,
              borderRadius: BorderRadius.circular(_arrangeRadius),
              border: selected
                  ? Border.all(color: neutrals.text, width: 1.5)
                  : null,
              boxShadow: selected
                  ? AppShadows.floating(brightness)
                  : tint
                  ? null
                  : AppShadows.arranging,
            ),
          ),
        ),
        card,
      ],
    );
  }

  // All but the pinned cards while arranging. At once, as nothing fades (Motion).
  Widget _dim(Widget child) =>
      Opacity(opacity: _arranging ? _arrangeDim : 1, child: child);

  // Under the thumb, on the side away from the hub.
  Widget _doneButton(AppLocalizations loc, AppNeutrals neutrals) {
    final Size screen = MediaQuery.sizeOf(context);
    final Offset? hub = LauncherHubArea.maybeOf(context)?.hubCenter(screen);
    final bool atLeft = hub == null || hub.dx > screen.width / 2;
    return Positioned(
      left: atLeft ? AppShapes.sideMargin : null,
      right: atLeft ? null : AppShapes.sideMargin,
      bottom: homePromptBottomRoom + 4,
      child: TextButton(
        key: const ValueKey('home-arrange-done'),
        onPressed: _endArranging,
        style: TextButton.styleFrom(
          backgroundColor: neutrals.promptDark,
          foregroundColor: AppColors.onColor(neutrals.promptDark),
          minimumSize: const Size(72, 40),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: AppShapes.pill,
          textStyle: HomePrompt.labelStyle,
        ),
        child: Text(loc.homeArrangeDone),
      ),
    );
  }

  static IconData _actionIcon(HomeCardAction action) => switch (action) {
    HomeCardAction.rearrange => Icons.swap_vert,
    HomeCardAction.edit => Icons.edit_outlined,
    HomeCardAction.unpin => Icons.push_pin_outlined,
    HomeCardAction.pin => Icons.push_pin,
    HomeCardAction.remove => Icons.remove_circle_outline,
    HomeCardAction.noSuggestions => Icons.visibility_off_outlined,
  };

  Widget _card(
    ListCatalog catalog,
    String listId,
    int index,
    ListLabels labels, {
    required bool suggested,
  }) {
    final ListDefinition? definition = catalog.definition(listId);
    if (definition == null) {
      return const SizedBox.shrink();
    }
    final AppLocalizations loc = labels.loc;
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final bool draggable = !suggested && !_unfilled.contains(listId);
    final bool selected = _selectedId == listId;
    final bool inHand =
        _dragId == listId || (_heldId == listId && _prompts.isNotEmpty);
    final Map<Type, GestureRecognizerFactory> gestures = {};

    void holdHandlers(LongPressGestureRecognizer recognizer) {
      recognizer
        ..onLongPressDown = ((_) => _holdDown(listId))
        ..onLongPressCancel = _holdCancelled
        ..onLongPressStart = ((details) => _holdReached(
          listId,
          details.globalPosition,
          suggested: suggested,
          scaler: scaler,
          loc: loc,
        ))
        ..onLongPressMoveUpdate = ((details) =>
            _holdMoved(details.globalPosition))
        ..onLongPressEnd = ((_) => _holdEnded(catalog));
    }

    void dragHandlers(LongPressGestureRecognizer recognizer) {
      recognizer
        ..onLongPressDown = ((_) => _restDown(listId))
        ..onLongPressCancel = (() => _restCancelled(listId))
        ..onLongPressStart = ((details) =>
            _pickUp(listId, details.globalPosition))
        ..onLongPressMoveUpdate = ((details) =>
            _dragMovedTo(details.globalPosition))
        ..onLongPressEnd = ((_) => _dropped(catalog, labels));
    }

    if (!_arranging) {
      gestures[TapGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (recognizer) =>
                recognizer.onTap = () => widget.onOpenList?.call(listId),
          );
      gestures[_HoldRecognizer] =
          GestureRecognizerFactoryWithHandlers<_HoldRecognizer>(
            _HoldRecognizer.new,
            holdHandlers,
          );
    } else if (draggable && selected && (_dragId != listId || _dragFromReady)) {
      gestures[_ReadyRecognizer] =
          GestureRecognizerFactoryWithHandlers<_ReadyRecognizer>(
            _ReadyRecognizer.new,
            dragHandlers,
          );
    } else if (draggable) {
      gestures[_RestRecognizer] =
          GestureRecognizerFactoryWithHandlers<_RestRecognizer>(
            _RestRecognizer.new,
            dragHandlers,
          );
    }

    final List<String> filled = _filledPins;
    final int place = filled.indexOf(listId);
    return KeyedSubtree(
      key: _cardKeys.putIfAbsent(listId, GlobalKey.new),
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Semantics(
          container: true,
          button: !_arranging,
          onTap: _arranging ? null : () => widget.onOpenList?.call(listId),
          customSemanticsActions: draggable
              ? {
                  if (place > 0)
                    CustomSemanticsAction(label: loc.homeMoveEarlier): () =>
                        _moveByOne(listId, -1, catalog, labels),
                  if (place >= 0 && place + 1 < filled.length)
                    CustomSemanticsAction(label: loc.homeMoveLater): () =>
                        _moveByOne(listId, 1, catalog, labels),
                }
              : null,
          child: RawGestureDetector(
            key: ValueKey('home-card-$listId'),
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            gestures: gestures,
            child: Opacity(
              // In the hand it is drawn again above the rest, by _overlay.
              opacity: inHand
                  ? 0
                  : _arranging && !draggable
                  ? _arrangeDim
                  : 1,
              child: _moving(
                listId,
                index,
                draggable: draggable,
                child: _cardContent(
                  catalog,
                  definition,
                  suggested: suggested,
                  lifted: selected || _heldId == listId,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The card's slide, lift and sway.
  Widget _moving(
    String listId,
    int index, {
    required bool draggable,
    required Widget child,
  }) {
    final bool held = _heldId == listId;
    final bool selected = _selectedId == listId;
    final bool swaying = _arranging && draggable;
    const LauncherConfig config = LauncherConfig();
    return Transform.translate(
      offset: Offset(0, _slides[listId] ?? 0),
      child: AnimatedBuilder(
        animation: Listenable.merge([_lift, _time, _rest]),
        child: child,
        builder: (context, child) {
          final double lift = held
              ? config.holdBuild(config.promptDelay * _lift.value)
              : selected
              ? 1
              : _restingId == listId
              ? config.pickUpBuild(config.dialPickUpDelay * _rest.value)
              : 0;
          final double degrees = !_moves
              ? 0
              : lift > 0
              ? _liftedSwayDegrees * lift
              : swaying
              ? config.dialArrangeSwayDegrees
              : 0;
          return Transform.rotate(
            angle: arrangeSway(_time.value, index) * degrees * math.pi / 180,
            child: Transform.scale(
              scale: 1 + (_liftScale - 1) * lift,
              child: child,
            ),
          );
        },
      ),
    );
  }

  // The card in the hand, above everything. While holding, the prompts above it,
  // sliding out from under the finger (owner, 2026-11-08).
  List<Widget> _overlay(ListCatalog catalog, ListLabels labels) {
    final String? listId = _dragId ?? (_prompts.isNotEmpty ? _heldId : null);
    final ListDefinition? definition = listId == null
        ? null
        : catalog.definition(listId);
    if (listId == null || definition == null) {
      return const [];
    }
    final bool suggested = _suggested.contains(listId);
    final double top = _dragId != null ? _finger.dy - _dragGrab : _heldRect.top;
    final List<String> filled = _filledPins;

    Widget copy() {
      final Widget card = IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _moving(
            listId,
            math.max(filled.indexOf(listId), 0),
            draggable: !suggested,
            child: _cardContent(
              catalog,
              definition,
              suggested: suggested,
              lifted: true,
            ),
          ),
        ),
      );
      return Positioned(
        left: _heldRect.left,
        top: top,
        width: _heldRect.width,
        child: card,
      );
    }

    final HomePromptFit? fit = _promptFit;
    return [
      copy(),
      if (fit != null)
        for (int i = 0; i < _prompts.length; i++)
          AnimatedBuilder(
            animation: _reveal,
            builder: (context, _) => HomePrompt(
              key: ValueKey('home-prompt-${_prompts[i].name}'),
              label: _promptLabels[i],
              centre: Offset.lerp(
                _holdStart,
                _promptRects[i].center,
                _reveal.value,
              )!,
              width: _promptRects[i].width,
              height: _promptRects[i].height,
              padding: fit.padding,
              textScale: fit.textScale,
              reveal: _reveal.value,
              near: (_promptProgress(i) / const LauncherConfig().promptSelectAt)
                  .clamp(0.0, 1.0),
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final ListLabels labels = ListLabels(loc);
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final AppTypography type = AppTypography.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final AccountPreferences preferences = context.watchAccountPreferences;
    final double top = MediaQuery.paddingOf(context).top;
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    _edit = ListEditAction.maybeOf(context);
    // What the fixed header takes: its padding, the button, the weekday and the
    // date line, with room to spare under them.
    final double headerHeight =
        top + 8 + 40 + 20 + 76 + 10 + scaler.scale(15) * 1.5 + 8;

    // One line, starting at the left edge of the cards' blobs: a small blob in
    // the list's colour, moving in step with its card's, then the title in the
    // text colour and the time or date and list's name small and muted (owner,
    // 2026-11-08). The title gives way first.
    Widget row(HomeDueItem due, ListCatalog catalog) {
      final ListDefinition definition = due.definition;
      final Object? title =
          due.item[definition.fields
              .firstWhere(
                (field) => field.primary,
                orElse: () => definition.fields.first,
              )
              .key];
      final bool overdue = due.due.isBefore(today);
      final String when = overdue
          ? DateFormat.MMMd(locale).format(due.due)
          : due.hasTime
          ? timeFormat(locale, preferences.timeFormat).format(due.due)
          : '';
      final bool ticked = due.done;
      // The card's mark, small: the blob behind, the tick circle over its lower
      // right (a card's 60 circle at 25,25 on its 84 blob), with a 48 touch
      // target around the circle.
      const double blob = homeDueBlobSize;
      const double inset = blob * 25 / 84;
      const double circleCentre = inset + homeTickSize / 2;
      // The target reaches this far left of the blob's box, so the box starts
      // after it within the mark.
      const double reach = homeTickTarget / 2 - circleCentre;
      final Widget mark = SizedBox(
        width: homeTickTarget,
        height: homeTickTarget,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: reach,
              top: homeTickTarget / 2 - circleCentre,
              child: HomeSmallBlob(
                color: listColor(definition.color, brightness: brightness),
                seed: homeBlobSeed(definition.id),
                clock: _moves ? _blobTick : null,
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: Semantics(
                button: true,
                checked: ticked,
                label: loc.homeTick,
                child: GestureDetector(
                  key: ValueKey('home-tick-${due.item.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _tickDue(due),
                  child: SizedBox.square(
                    dimension: homeTickTarget,
                    child: Center(
                      child: Container(
                        width: homeTickSize,
                        height: homeTickSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ticked ? neutrals.text : neutrals.ground,
                          border: Border.all(color: neutrals.text, width: 1.75),
                        ),
                        child: ticked
                            ? Icon(
                                Icons.check,
                                size: 14,
                                color: neutrals.ground,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      return InkWell(
        key: ValueKey('home-due-${due.item.id}'),
        onTap: () {
          if (!_arranging) {
            widget.onOpenList?.call(definition.id);
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: homeDueRowHeight),
          child: Row(
            children: [
              // The blob's left edge on the cards' blob edge.
              const SizedBox(
                width:
                    homeDueLeft -
                    (homeTickTarget / 2 -
                        homeDueBlobSize * 25 / 84 -
                        homeTickSize / 2),
              ),
              mark,
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title is String ? title : '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.row.copyWith(
                          color: neutrals.text,
                          fontSize: 15,
                          decoration: ticked
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: neutrals.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                      ),
                      child: Text(
                        [
                          if (when.isNotEmpty) when,
                          labels.listName(definition),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.meta,
                      ),
                    ),
                  ],
                ),
              ),
              // A ticked row clears from here, where its list can clear.
              if (ticked && due.clearable)
                IconButton(
                  key: ValueKey('home-clear-${due.item.id}'),
                  tooltip: loc.clearTicked,
                  onPressed: () => _clearDue(due, catalog),
                  icon: Icon(Icons.close, size: 18, color: neutrals.muted),
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_arranging,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _endArranging();
        }
      },
      child: Scaffold(
        body: ListCatalogBuilder(
          builder: (context, catalog) {
            final List<HomeDueItem> due = homeDueItems(catalog, now);
            _syncBlobClock(
              _moves && preferences.homeContent.showsDue && due.isNotEmpty,
            );
            _workOutCards(catalog, preferences, labels, now);
            final List<String> pinned = _pinned!;
            final bool nothingDue =
                preferences.homeContent.showsDue &&
                due.isEmpty &&
                catalog.definitions.isNotEmpty;
            // The fixed header, with the nothing-due line when it shows.
            final double listTop =
                headerHeight +
                (nothingDue ? homeNothingDueGap + scaler.scale(15) * 1.5 : 0);
            return Listener(
              onPointerDown: _pointerDown,
              onPointerMove: _pointerMove,
              onPointerUp: _pointerUp,
              child: Stack(
                key: _stack,
                children: [
                  Positioned.fill(
                    child: RefreshIndicator(
                      onRefresh: _pullDown,
                      color: AppColors.appBlue,
                      edgeOffset: listTop,
                      child: ListView(
                        key: const ValueKey('home-scroll'),
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          AppShapes.sideMargin,
                          listTop,
                          AppShapes.sideMargin,
                          // Room so the hub, and while arranging Done, do not
                          // cover the last card.
                          _arranging ? 190 : 140,
                        ),
                        children: [
                          if (catalog.definitions.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 28),
                              child: StarterNote(),
                            ),
                          // The header's count says these are today's, so no
                          // label above them (owner, 2026-11-08).
                          if (preferences.homeContent.showsDue &&
                              due.isNotEmpty) ...[
                            const SizedBox(height: homeDueGap),
                            for (final HomeDueItem item in due)
                              _dim(row(item, catalog)),
                          ],
                          if (preferences.homeContent.showsCards &&
                              (pinned.isNotEmpty || _suggested.isNotEmpty)) ...[
                            const SizedBox(height: homeCardsGap),
                            for (int i = 0; i < pinned.length; i++)
                              _card(
                                catalog,
                                pinned[i],
                                i,
                                labels,
                                suggested: false,
                              ),
                            for (int i = 0; i < _suggested.length; i++)
                              _card(
                                catalog,
                                _suggested[i],
                                pinned.length + i,
                                labels,
                                suggested: true,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppShapes.sideMargin,
                        8 + top,
                        AppShapes.sideMargin,
                        0,
                      ),
                      child: _dim(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: IconButton(
                                key: const ValueKey('settings'),
                                tooltip: loc.settings,
                                onPressed: () {
                                  if (!_arranging) {
                                    showSettingsSheet(context);
                                  }
                                },
                                style: IconButton.styleFrom(
                                  backgroundColor: AppColors.appBlue,
                                  foregroundColor: AppColors.onAppBlue,
                                  fixedSize: const Size(40, 40),
                                  minimumSize: const Size(40, 40),
                                ),
                                icon: const Icon(
                                  Icons.settings_outlined,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // The weekday stays whole: long names shrink to the
                            // width.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                DateFormat.EEEE(locale).format(now),
                                key: const ValueKey('home-weekday'),
                                style: type.screenTitle.copyWith(
                                  fontSize: 76,
                                  height: 1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              // The count only when there are due rows to count.
                              [
                                DateFormat.MMMMd(locale).format(now),
                                if (preferences.homeContent.showsDue &&
                                    due.any((each) => !each.done))
                                  loc.homeThingsToday(
                                    due.where((each) => !each.done).length,
                                  ),
                              ].join(' · '),
                              key: const ValueKey('home-date'),
                              style: type.meta.copyWith(fontSize: 15),
                            ),
                            // Nothing due: said once, fixed under the date, not
                            // in the scroll (owner, 2026-11-09).
                            if (nothingDue) ...[
                              const SizedBox(height: homeNothingDueGap),
                              Text(
                                loc.homeNothingDue,
                                key: const ValueKey('home-nothing-due'),
                                style: type.meta.copyWith(fontSize: 15),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_arranging) _doneButton(loc, neutrals),
                  ..._overlay(catalog, labels),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// How long each press takes to count (Q-76, Q-77): a hold for the prompts, the
// dial's short rest for a card while arranging, and none for the one selected.
class _HoldRecognizer extends LongPressGestureRecognizer {
  _HoldRecognizer() : super(duration: const LauncherConfig().promptDelay);
}

class _RestRecognizer extends LongPressGestureRecognizer {
  _RestRecognizer() : super(duration: const LauncherConfig().dialPickUpDelay);
}

class _ReadyRecognizer extends LongPressGestureRecognizer {
  _ReadyRecognizer() : super(duration: Duration.zero);
}

// The settings sheet: theme and language (this phone), the two AI choices, the
// way to Preferences, and the account (email, Log out).
Future<void> showSettingsSheet(BuildContext context) {
  return showSlideUpSheet<void>(
    context: context,
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  String _languageLabel(AppLocalizations loc, String? code) {
    switch (code) {
      case 'en':
        return loc.languageEnglish;
      case 'zh':
        return loc.languageChinese;
      case 'ja':
        return loc.languageJapanese;
      case 'fr':
        return loc.languageFrench;
      case 'es':
        return loc.languageSpanish;
      case 'de':
        return loc.languageGerman;
      case null:
      default:
        return loc.languageSystem;
    }
  }

  Future<void> _chooseTheme(BuildContext context, AppSettings settings) async {
    final AppLocalizations loc = AppLocalizations.of(context);
    final AppSettingsCubit cubit = context.read<AppSettingsCubit>();
    final ThemeMode? mode = await showChoiceSheet<ThemeMode>(
      context,
      title: loc.theme,
      selected: settings.themeMode,
      choices: [
        (value: ThemeMode.system, label: loc.themeFollowPhone),
        (value: ThemeMode.light, label: loc.themeLight),
        (value: ThemeMode.dark, label: loc.themeDark),
      ],
    );
    if (mode != null) {
      await cubit.setThemeMode(mode);
    }
  }

  Future<void> _showLanguageDialog(
    BuildContext context,
    AppSettings settings,
  ) async {
    final AppLocalizations loc = AppLocalizations.of(context);
    final AppNeutrals neutrals = AppColors.neutrals(
      Theme.of(context).brightness,
    );

    final List<({String? code, String label, String subtitle})> options = [
      (
        code: null,
        label: loc.languageSystem,
        subtitle: loc.languageFollowsDevice,
      ),
      (code: 'en', label: loc.languageEnglish, subtitle: 'English'),
      (code: 'zh', label: loc.languageChinese, subtitle: 'Chinese'),
      (code: 'ja', label: loc.languageJapanese, subtitle: 'Japanese'),
      (code: 'fr', label: loc.languageFrench, subtitle: 'French'),
      (code: 'es', label: loc.languageSpanish, subtitle: 'Spanish'),
      (code: 'de', label: loc.languageGerman, subtitle: 'German'),
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(loc.chooseLanguage),
          // As tall as the languages need; the dialog limits it on a small
          // screen, and then the bar shows there are more.
          content: SizedBox(
            width: 420,
            child: ScrollbarTheme(
              data: ScrollbarThemeData(
                thumbColor: WidgetStatePropertyAll(neutrals.muted),
                thickness: const WidgetStatePropertyAll(4),
                radius: const Radius.circular(2),
              ),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  primary: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final option in options)
                        ListTile(
                          selected: settings.localeCode == option.code,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(
                            settings.localeCode == option.code
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          title: Text(option.label),
                          subtitle: Text(option.subtitle),
                          onTap: () {
                            context.read<AppSettingsCubit>().setLocaleCode(
                              option.code,
                            );
                            Navigator.of(dialogContext).pop();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text(loc.cancel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final AppTypography type = AppTypography.of(context);
    final SignedInAccount account = context.read<SignedInAccount>();

    String themeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => loc.themeFollowPhone,
      ThemeMode.light => loc.themeLight,
      ThemeMode.dark => loc.themeDark,
    };

    Widget hairline() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppShapes.sideMargin),
      child: Divider(color: neutrals.line, height: 1),
    );

    Widget row({
      required Key key,
      required IconData icon,
      required Widget label,
      Widget? trailing,
      VoidCallback? onTap,
    }) {
      return InkWell(
        key: key,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: AppShapes.sideMargin,
            vertical: 6,
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: neutrals.text),
              const SizedBox(width: 14),
              Expanded(child: label),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                // At the right edge; a long value wraps past half the width.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width / 2,
                  ),
                  child: trailing,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return BlocBuilder<AppSettingsCubit, AppSettings>(
      builder: (context, settings) {
        // The two AI choices stay here and sync with the account (Q-48).
        final AccountPreferences synced = context.watchAccountPreferences;
        final AccountPreferencesCubit preferences = context
            .read<AccountPreferencesCubit>();
        return Semantics(
          label: loc.settings,
          explicitChildNodes: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: neutrals.ground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppShapes.sheetRadius),
              ),
              boxShadow: AppShadows.floating(brightness),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(top: 10, bottom: 14),
                          decoration: BoxDecoration(
                            color: neutrals.line,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppShapes.sideMargin,
                          0,
                          AppShapes.sideMargin,
                          12,
                        ),
                        child: Text(loc.settings, style: type.screenTitle),
                      ),
                      hairline(),
                      row(
                        key: const ValueKey('settings-theme'),
                        icon: Icons.dark_mode_outlined,
                        label: Text(loc.theme, style: type.row),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                themeLabel(settings.themeMode),
                                style: type.meta.copyWith(fontSize: 15),
                              ),
                            ),
                            Icon(Icons.chevron_right, color: neutrals.muted),
                          ],
                        ),
                        onTap: () => _chooseTheme(context, settings),
                      ),
                      hairline(),
                      row(
                        key: const ValueKey('settings-language'),
                        icon: Icons.language,
                        label: Text(loc.language, style: type.row),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _languageLabel(loc, settings.localeCode),
                                style: type.meta.copyWith(fontSize: 15),
                              ),
                            ),
                            Icon(Icons.chevron_right, color: neutrals.muted),
                          ],
                        ),
                        onTap: () => _showLanguageDialog(context, settings),
                      ),
                      hairline(),
                      // One node for a screen reader: the switch with its name.
                      MergeSemantics(
                        child: row(
                          key: const ValueKey('settings-ai-auto-apply'),
                          icon: Icons.check_circle_outline,
                          label: Text(loc.settingsAiAutoApply, style: type.row),
                          trailing: Switch(
                            value: synced.aiAutoApply,
                            activeTrackColor: AppColors.appBlue,
                            onChanged: preferences.setAiAutoApply,
                          ),
                          onTap: () =>
                              preferences.setAiAutoApply(!synced.aiAutoApply),
                        ),
                      ),
                      hairline(),
                      Padding(
                        key: const ValueKey('settings-ai-ask'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppShapes.sideMargin,
                        ),
                        child: AiAskSlider(
                          level: synced.aiAskLevel,
                          onChanged: preferences.setAiAskLevel,
                        ),
                      ),
                      row(
                        key: const ValueKey('settings-preferences'),
                        icon: Icons.tune,
                        label: Text(loc.preferences, style: type.row),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: neutrals.muted,
                        ),
                        // Above the shell, like the list editor: no hub and
                        // no AI bar on it. Back comes back to this sheet.
                        onTap: () =>
                            Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const PreferencesScreen(),
                              ),
                            ),
                      ),
                      hairline(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppShapes.sideMargin,
                          26,
                          AppShapes.sideMargin,
                          8,
                        ),
                        child: Text(
                          loc.account.toUpperCase(),
                          style: type.sectionLabel,
                        ),
                      ),
                      hairline(),
                      row(
                        key: const ValueKey('settings-account'),
                        icon: Icons.account_circle_outlined,
                        label: Text(
                          account.user.email ?? loc.account,
                          key: const ValueKey('account-email'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.row,
                        ),
                        trailing: TextButton(
                          key: const ValueKey('sign-out'),
                          onPressed: () {
                            // Close the sheet first; signing out replaces the
                            // whole app with the sign-in screen.
                            Navigator.of(context).pop();
                            account.signOut();
                          },
                          child: Text(loc.logOut),
                        ),
                      ),
                      hairline(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
