import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../l10n/generated/app_localizations.dart';
import 'builtin_templates.dart';
import 'list_definition.dart';
import 'list_editor_screen.dart';
import 'list_icons.dart';
import 'list_labels.dart';

// "New list" (Q-22 D): Blank or one of the templates. Returns a fresh
// definition for the editor, or null when the picker is dismissed. Plain
// look; the UI stream restyles it (T-16).
Future<ListDefinition?> showListTemplatePicker(BuildContext context) {
  final AppLocalizations loc = AppLocalizations.of(context);
  final ListLabels labels = ListLabels(loc);
  return showDialog<ListDefinition>(
    context: context,
    builder: (dialogContext) {
      return SimpleDialog(
        title: Text(loc.newList),
        children: [
          ListTile(
            key: const ValueKey('template-blank'),
            leading: const Icon(Icons.add),
            title: Text(loc.blankList),
            onTap: () =>
                Navigator.of(dialogContext).pop(blankListDefinition(loc)),
          ),
          for (final ListDefinition template in BuiltinTemplates.all())
            ListTile(
              key: ValueKey('template-${template.id}'),
              leading: Icon(
                listIcon(template.icon),
                color: listColor(template.color),
              ),
              title: Text(labels.listName(template)),
              onTap: () =>
                  Navigator.of(dialogContext).pop(templateCopy(template)),
            ),
        ],
      );
    },
  );
}

// A new list from [template]: its own id, the template named in
// `templateId` (so it gets the template's texts), everything else as in the
// template, as the starter copies are made (StarterLists).
ListDefinition templateCopy(ListDefinition template) {
  return template.copyWith(
    id: 'list-${const Uuid().v4()}',
    updatedAt: DateTime.now().toUtc(),
  );
}
