import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../ai/ai_bar_controller.dart';
import '../ai/ai_service.dart';
import '../ai/prompt_bar.dart';
import '../home_screen.dart';
import '../l10n/generated/app_localizations.dart';
import '../launcher/dial_launcher.dart';
import '../launcher/launcher_hub_area.dart';
import '../launcher/radial_launcher.dart';
import '../lists/generic_list_host.dart';
import '../lists/generic_list_screen.dart' show ListEditAction;
import '../lists/list_catalog.dart';
import '../lists/list_catalog_builder.dart';
import '../lists/list_definition.dart';
import '../lists/list_editor_screen.dart';
import '../lists/list_error.dart';
import '../lists/list_icons.dart';
import '../lists/list_labels.dart';
import '../lists/list_patch.dart';
import '../lists/list_store.dart';
import '../lists/list_template_picker.dart';
import 'app_settings.dart';
import 'app_theme.dart' show AppMotion;

// The launcher is the dial (owner's choice, T-16 unit 6, 2026-11-03);
// --dart-define=FAN_LAUNCHER=true shows the earlier fan instead.
const bool _dialLauncher = !bool.fromEnvironment('FAN_LAUNCHER');

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() {
    return _MainShellState();
  }
}

// The home and the open list live in the shell's own navigator, with the
// launcher floating above it on both (T-16 unit 6). Opening a list from a
// list replaces it, so back always leads to the home. Sheets and dialogs on
// that navigator hide the hub; the list editor and the New list picker open
// on the app's navigator, above all of it.
//
// The AI prompt bar (T-19 unit 4, Q-36 A) sits between the screens and the
// launcher, so the open dial covers it. It hides with the hub under sheets
// and dialogs, and on a list with AI off. Back first closes the bar's panel
// (preview, question, answer, notice) or leaves "Describe a new list", then
// works as before: a list goes home, the home leaves the app. While the bar
// is focused and too wide to sit beside the hub, the hub rises to just above
// it (not saved); pressing the hub keeps it there until the dial closes.
class _MainShellState extends State<MainShell> {
  // Lists in the order they were last opened, newest first, so the common
  // case never needs scrolling (plan 5.3). Kept in memory for now.
  final List<String> _recent = [];

  final GlobalKey<NavigatorState> _content = GlobalKey<NavigatorState>();
  final _TopRoute _top = _TopRoute();

  // Null without an AiService (tests, other hosts): no bar.
  AiBarController? _ai;

  // The hub's raised spot (fractions) while the bar is focused, the last one
  // worked out, and whether a press on the raised hub keeps it there until
  // the dial closes.
  Offset? _lift;
  Offset? _lastLift;
  bool _keepLift = false;
  bool _dialOpen = false;

  static const String _listRoute = 'list:';

  // The list on top of the shell's navigator, if any.
  String? get _openListId {
    final String? name = _top.current?.settings.name;
    return name != null && name.startsWith(_listRoute)
        ? name.substring(_listRoute.length)
        : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AiService? service = context.read<AiService?>();
    if (_ai == null && service != null) {
      _ai = AiBarController(
        service: service,
        store: context.read<ListStore>(),
        preferences: context.read<AppSettingsCubit>().preferences,
        onOpenList: _openList,
        saveAutoApply: context.read<AppSettingsCubit>().setAiAutoApply,
      );
    }
  }

  @override
  void dispose() {
    _ai?.dispose();
    _top.dispose();
    super.dispose();
  }

  bool _isList(Route<dynamic>? route) =>
      route?.settings.name?.startsWith(_listRoute) ?? false;

  void _goHome() {
    _content.currentState?.popUntil((route) => route.isFirst);
  }

  void _openList(String listId) {
    setState(() {
      _recent
        ..remove(listId)
        ..insert(0, listId);
    });
    final NavigatorState? content = _content.currentState;
    final String? open = _openListId;
    if (content == null || open == listId) {
      return;
    }
    final Route<void> route = MaterialPageRoute<void>(
      settings: RouteSettings(name: '$_listRoute$listId'),
      builder: (_) => GenericListHost(listId: listId),
    );
    if (open == null) {
      content.push(route);
    } else {
      content.pushReplacement(route);
    }
  }

  List<LauncherNote> _notes(AppLocalizations loc, ListCatalog catalog) {
    final ListLabels labels = ListLabels(loc);
    final List<ListDefinition> ordered = [...catalog.definitions]
      ..sort((a, b) {
        int rank(ListDefinition definition) {
          final int index = _recent.indexOf(definition.id);
          return index < 0
              ? _recent.length + catalog.definitions.indexOf(definition)
              : index;
        }

        return rank(a).compareTo(rank(b));
      });

    return [
      for (final ListDefinition definition in ordered)
        LauncherNote(
          id: definition.id,
          label: labels.listName(definition),
          icon: listIcon(definition.icon),
          color: listColor(definition.color),
          semanticsLabel: loc.itemsCount(
            labels.listName(definition),
            catalog.itemsOf(definition.id).length,
          ),
        ),
    ];
  }

  // Blank or a template first, then the editor on that fresh copy, which can
  // be changed before saving (Q-22 D).
  Future<void> _newList() async {
    bool describe = false;
    final ListDefinition? draft = await showListTemplatePicker(
      context,
      onDescribe: _ai == null ? null : () => describe = true,
    );
    if (mounted && describe) {
      // After the picker's route has handed focus back.
      WidgetsBinding.instance.addPostFrameCallback((_) => _ai?.startNewList());
      return;
    }
    if (!mounted || draft == null) {
      return;
    }
    final ListEditorOutcome? outcome = await Navigator.of(context).push(
      MaterialPageRoute<ListEditorOutcome>(
        builder: (_) => ListEditorScreen(definition: draft, isNew: true),
      ),
    );
    final ListPatchResult? result = outcome?.result;
    if (!mounted || result == null || !result.isValid) {
      return;
    }

    final List<ListError> errors = await context.read<ListStore>().createList(
      result.definition,
    );
    if (mounted && errors.isEmpty) {
      _openList(result.definition.id);
    }
  }

  Future<void> _editList(String listId) async {
    final ListStore store = context.read<ListStore>();
    final ListCatalog catalog = store.current;
    final ListDefinition? definition = catalog.definition(listId);
    if (definition == null) {
      return;
    }

    final ListEditorOutcome? outcome = await Navigator.of(context).push(
      MaterialPageRoute<ListEditorOutcome>(
        builder: (_) => ListEditorScreen(
          definition: definition,
          items: catalog.itemsOf(listId),
        ),
      ),
    );
    if (!mounted || outcome == null) {
      return;
    }

    if (outcome.deleted) {
      await _deleteList(listId);
      return;
    }

    // The store re-applies the ops to its current items, in case they changed
    // meanwhile, and saves only a valid result. The editor has closed, so a
    // failure is reported here rather than lost (T-17 F1).
    final AppLocalizations loc = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await store.patchList(listId, outcome.ops);
    } on Object catch (error) {
      developer.log('patch $listId failed: $error', name: 'MainShell');
      messenger.showSnackBar(SnackBar(content: Text(loc.listChangeNotSaved)));
    }
  }

  // Deleting is immediate, with Undo in a snackbar and no trash bin (D-5).
  Future<void> _deleteList(String listId) async {
    final AppLocalizations loc = AppLocalizations.of(context);
    final ListStore store = context.read<ListStore>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final DeletedList? deleted = await store.deleteList(listId);
    if (deleted == null) {
      return;
    }

    setState(() => _recent.remove(listId));
    if (_openListId == listId) {
      _goHome();
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(loc.listDeleted),
        // A snackbar with an action stays until dismissed unless told
        // otherwise; Undo is only offered for a short while.
        persist: false,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: loc.undo,
          onPressed: () => store.restoreList(deleted),
        ),
      ),
    );
  }

  // The prompt bar for the screen on top: hidden with the hub, and on a
  // list with AI off. While its panel is open, Back is the bar's even on
  // the home (NavigatorPopHandler then hands it to handleBack above).
  ListDefinition? _openOf(Route<dynamic>? top, ListCatalog catalog) {
    final String? name = top?.settings.name;
    return name != null && name.startsWith(_listRoute)
        ? catalog.definition(name.substring(_listRoute.length))
        : null;
  }

  bool _barHidden(Route<dynamic>? top, ListCatalog catalog) {
    final ListDefinition? open = _openOf(top, catalog);
    return (top != null && top is! PageRoute) ||
        (open != null && !open.aiAllowed);
  }

  // Where the hub goes while the bar is focused (fractions of the size), or
  // null where it rests: just above the focused bar when the bar needs the
  // width beside it (PromptBarGeometry.hubLiftY).
  Offset? _hubLift(
    Size size,
    Offset? saved,
    double bottomInset,
    Route<dynamic>? top,
    ListCatalog catalog,
  ) {
    final AiBarController? ai = _ai;
    if (ai == null || _barHidden(top, catalog)) {
      return null;
    }
    if (ai.focused) {
      final LauncherHubArea rest = LauncherHubArea(
        hubPosition: saved,
        child: const SizedBox(),
      );
      final double? y = PromptBarGeometry.of(
        size,
        hub: rest,
        bottomInset: bottomInset,
        focused: true,
        fieldHeight: ai.fieldHeight.value,
        panelOpen: ai.isOpen,
        panelHeight: ai.panelHeight.value,
      ).hubLiftY;
      _lastLift = y == null
          ? null
          : Offset(rest.hubCenter(size).dx / size.width, y / size.height);
      return _lastLift;
    }
    return _keepLift ? _lastLift : null;
  }

  // The dial opened or closed. Opening it leaves the bar (the draft stays);
  // the hub comes down once the dial has closed.
  void _dialChanged(bool open) {
    _dialOpen = open;
    if (open) {
      _ai?.leave();
    } else if (_keepLift && mounted) {
      setState(() => _keepLift = false);
    }
  }

  // After a press that opened nothing the hub comes down. The dial reports
  // its state after the frame, so this looks one frame later.
  void _releaseLiftLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _keepLift && !_dialOpen) {
          setState(() => _keepLift = false);
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  Widget _bar(AiBarController ai, ListCatalog catalog, Offset? hubPosition) {
    return ValueListenableBuilder<Route<dynamic>?>(
      valueListenable: _top.route,
      builder: (context, top, _) {
        final ListDefinition? open = _openOf(top, catalog);
        return Offstage(
          offstage: _barHidden(top, catalog),
          child: ListenableBuilder(
            listenable: ai,
            builder: (context, child) => PopScope(
              canPop: !ai.focused && !ai.isOpen && !ai.newList,
              child: child!,
            ),
            child: LauncherHubArea(
              hubPosition: hubPosition,
              child: PromptBar(controller: ai, openList: open),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListCatalogBuilder(
        builder: (context, catalog) =>
            BlocBuilder<AppSettingsCubit, AppSettings>(
              builder: (context, settings) {
                final AppLocalizations loc = AppLocalizations.of(context);
                return ListenableBuilder(
                  listenable: Listenable.merge([
                    _top.route,
                    ?_ai,
                    ?_ai?.fieldHeight,
                    ?_ai?.panelHeight,
                  ]),
                  builder: (context, _) => LayoutBuilder(
                    builder: (context, constraints) {
                      final Size size = constraints.biggest;
                      final Offset? lift = _hubLift(
                        size,
                        settings.hubPosition,
                        MediaQuery.paddingOf(context).bottom,
                        _top.route.value,
                        catalog,
                      );
                      _lift = lift;
                      final Offset rest = LauncherHubArea(
                        hubPosition: settings.hubPosition,
                        child: const SizedBox(),
                      ).hubCenter(size);
                      final Offset restFraction = Offset(
                        rest.dx / size.width,
                        rest.dy / size.height,
                      );
                      return TweenAnimationBuilder<Offset>(
                        tween: Tween<Offset>(end: lift ?? restFraction),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : AppMotion.standard,
                        curve: AppMotion.curve,
                        builder: (context, value, _) => _stack(
                          context,
                          loc,
                          catalog,
                          settings,
                          // At rest the saved spot itself, so the default
                          // stays the default.
                          lift == null && value == restFraction
                              ? settings.hubPosition
                              : value,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      ),
    );
  }

  Widget _stack(
    BuildContext context,
    AppLocalizations loc,
    ListCatalog catalog,
    AppSettings settings,
    Offset? hubPosition,
  ) {
    return Stack(
      children: [
        // Back pops the shell's navigator first (the open list,
        // a sheet), then leaves the app as before.
        LauncherHubArea(
          // A list's add button rides above the raised hub too.
          hubPosition: hubPosition,
          // The open list's page offers Edit list too.
          child: ListEditAction(
            onEdit: _editList,
            child: NavigatorPopHandler(
              onPopWithResult: (_) {
                if (_ai?.handleBack() ?? false) {
                  return;
                }
                _content.currentState?.maybePop();
              },
              child: Navigator(
                key: _content,
                observers: [_top],
                onGenerateInitialRoutes: (_, _) => [
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: 'home'),
                    // Room below the dashboard so the hub never
                    // covers it.
                    builder: (_) => Padding(
                      padding: const EdgeInsets.only(bottom: 120),
                      child: HomeScreen(onOpenList: _openList),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_ai != null)
          Positioned.fill(child: _bar(_ai!, catalog, settings.hubPosition)),
        Positioned.fill(
          // A press on the raised hub keeps it up until the dial
          // closes; a press that opens nothing lets it down.
          child: Listener(
            behavior: HitTestBehavior.deferToChild,
            onPointerDown: (_) {
              if (_lift != null && !_keepLift) {
                setState(() => _keepLift = true);
              }
            },
            onPointerUp: (_) => _releaseLiftLater(),
            child: ValueListenableBuilder<Route<dynamic>?>(
              valueListenable: _top.route,
              builder: (context, top, _) => Offstage(
                offstage: top != null && top is! PageRoute,
                child: _dialLauncher
                    ? DialLauncher(
                        onHome: _isList(top) ? _goHome : null,
                        homeLabel: loc.home,
                        notes: _notes(loc, catalog),
                        onOpen: (note) => _openList(note.id),
                        onEdit: (note) => _editList(note.id),
                        onNew: _newList,
                        hubTooltip: loc.launcherHub,
                        editLabel: loc.edit,
                        moveLabel: loc.moveHub,
                        addLabel: loc.newList,
                        previousLabel: loc.previous,
                        nextLabel: loc.next,
                        noteHint: loc.launcherNoteHint,
                        hubPosition: hubPosition,
                        onHubMoved: context
                            .read<AppSettingsCubit>()
                            .setHubPosition,
                        onOpenChanged: _dialChanged,
                      )
                    : RadialLauncher(
                        // Inside a list the fan starts with Home.
                        onHome: _isList(top) ? _goHome : null,
                        homeLabel: loc.home,
                        notes: _notes(loc, catalog),
                        onOpen: (note) => _openList(note.id),
                        onEdit: (note) => _editList(note.id),
                        onNew: _newList,
                        hubTooltip: loc.launcherHub,
                        editLabel: loc.edit,
                        moveLabel: loc.moveHub,
                        addLabel: loc.newList,
                        previousLabel: loc.previous,
                        nextLabel: loc.next,
                        noteHint: loc.launcherNoteHint,
                        hubPosition: hubPosition,
                        onHubMoved: context
                            .read<AppSettingsCubit>()
                            .setHubPosition,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Follows the route on top of the shell's navigator. Navigator callbacks can
// come in the middle of a build, so the change is passed on after the frame.
class _TopRoute extends NavigatorObserver {
  final ValueNotifier<Route<dynamic>?> route = ValueNotifier(null);
  Route<dynamic>? _top;

  bool _disposed = false;

  Route<dynamic>? get current => _top;

  void dispose() {
    _disposed = true;
    route.dispose();
  }

  void _set(Route<dynamic>? top) {
    _top = top;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) {
        route.value = _top;
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // A sheet or dialog still covers the page while it slides away: the
    // shell knows at once what is on top, but the hub stays hidden until
    // the sheet has gone.
    if (route is TransitionRoute && route is! PageRoute) {
      _top = previousRoute;
      route.completed.whenComplete(() {
        if (!_disposed && identical(_top, previousRoute)) {
          _set(previousRoute);
        }
      });
      return;
    }
    _set(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route == _top) {
      _set(previousRoute);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == _top) {
      _set(newRoute);
    }
  }
}
