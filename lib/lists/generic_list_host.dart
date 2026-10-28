import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/generated/app_localizations.dart';
import 'builtin_templates.dart';
import 'generic_list_screen.dart';
import 'list_catalog_builder.dart';
import 'list_definition.dart';
import 'list_labels.dart';
import 'list_store.dart';

// One list on the generic screen. A list made from a template gets that
// template's texts; any other list gets plain ones.
class GenericListHost extends StatelessWidget {
  const GenericListHost({super.key, required this.listId});

  final String listId;

  static GenericListTexts textsFor(
    AppLocalizations loc,
    ListDefinition definition,
  ) {
    final String name = ListLabels(loc).listName(definition);
    switch (definition.templateId) {
      case BuiltinTemplates.tasksId:
        return GenericListTexts(
          title: name,
          emptyText: loc.noTasksHereYet,
          addTooltip: loc.addTaskTooltip,
          addDialogTitle: loc.addTask,
          editDialogTitle: loc.editTask,
        );
      case BuiltinTemplates.groceryId:
        return GenericListTexts(
          title: definition.name ?? loc.groceryList,
          emptyText: loc.noGroceriesCurrent,
          addTooltip: loc.addGroceryItemTooltip,
          addDialogTitle: loc.addGroceryItem,
          editDialogTitle: loc.editGroceryItem,
        );
      case BuiltinTemplates.journalId:
        return GenericListTexts(
          title: name,
          emptyText: loc.noJournalEntriesYet,
          addTooltip: loc.addJournalEntryTooltip,
          addDialogTitle: loc.addJournalEntry,
          editDialogTitle: loc.editJournalEntry,
        );
      case BuiltinTemplates.watchReadId:
        return GenericListTexts(
          title: definition.name ?? loc.watchReadList,
          emptyText: loc.noWatchReadItemsYet,
          addTooltip: loc.addWatchReadItemTooltip,
          addDialogTitle: loc.addWatchReadItem,
          editDialogTitle: loc.editWatchReadItem,
        );
    }

    return GenericListTexts(
      title: name,
      emptyText: '—',
      addTooltip: loc.add,
      addDialogTitle: loc.add,
      editDialogTitle: loc.edit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final ListStore store = context.read<ListStore>();

    return ListCatalogBuilder(
      builder: (context, catalog) {
        final ListDefinition? definition = catalog.definition(listId);
        if (definition == null) {
          // The list was deleted while open.
          return Scaffold(appBar: AppBar());
        }

        return GenericListScreen(
          definition: definition,
          items: catalog.itemsOf(listId),
          store: store,
          texts: textsFor(loc, definition),
        );
      },
    );
  }
}
