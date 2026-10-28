import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../home_screen.dart';
import '../l10n/generated/app_localizations.dart';
import '../launcher/radial_launcher.dart';
import '../lists/generic_list_host.dart';
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

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() {
    return _MainShellState();
  }
}

class _MainShellState extends State<MainShell> {
  // Lists in the order they were last opened, newest first, so the common
  // case never needs scrolling (plan 5.3). Kept in memory for now.
  final List<String> _recent = [];

  void _openList(String listId) {
    setState(() {
      _recent
        ..remove(listId)
        ..insert(0, listId);
    });
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GenericListHost(listId: listId),
      ),
    );
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
                    // Room below the dashboard so the hub never covers it.
                    Padding(
                      padding: const EdgeInsets.only(bottom: 88),
                      child: HomeScreen(onOpenList: _openList),
                    ),
                    Positioned.fill(
                      child: RadialLauncher(
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
                  ],
                );
              },
            ),
      ),
    );
  }
}
