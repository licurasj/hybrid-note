import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
class _MainShellState extends State<MainShell> {
  // Lists in the order they were last opened, newest first, so the common
  // case never needs scrolling (plan 5.3). Kept in memory for now.
  final List<String> _recent = [];

  final GlobalKey<NavigatorState> _content = GlobalKey<NavigatorState>();
  final _TopRoute _top = _TopRoute();

  static const String _listRoute = 'list:';

  // The list on top of the shell's navigator, if any.
  String? get _openListId {
    final String? name = _top.current?.settings.name;
    return name != null && name.startsWith(_listRoute)
        ? name.substring(_listRoute.length)
        : null;
  }

  @override
  void dispose() {
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
    final ListDefinition? draft = await showListTemplatePicker(context);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListCatalogBuilder(
        builder: (context, catalog) =>
            BlocBuilder<AppSettingsCubit, AppSettings>(
              builder: (context, settings) {
                final AppLocalizations loc = AppLocalizations.of(context);
                return Stack(
                  children: [
                    // Back pops the shell's navigator first (the open list,
                    // a sheet), then leaves the app as before.
                    LauncherHubArea(
                      hubPosition: settings.hubPosition,
                      // The open list's page offers Edit list too.
                      child: ListEditAction(
                        onEdit: _editList,
                        child: NavigatorPopHandler(
                          onPopWithResult: (_) =>
                              _content.currentState?.maybePop(),
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
                    Positioned.fill(
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
                                  hubPosition: settings.hubPosition,
                                  onHubMoved: context
                                      .read<AppSettingsCubit>()
                                      .setHubPosition,
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
                            hubPosition: settings.hubPosition,
                            onHubMoved: context
                                .read<AppSettingsCubit>()
                                .setHubPosition,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
      ),
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
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(previousRoute);

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
