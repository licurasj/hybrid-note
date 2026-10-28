import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../app/app_theme.dart';
import '../app_colors.dart';
import '../l10n/generated/app_localizations.dart';
import 'builtin_templates.dart';
import 'generic_item_dialog.dart';
import 'list_definition.dart';
import 'list_editor_screen.dart';
import 'list_icons.dart';
import 'list_labels.dart';

// "New list" (Q-22 D): Blank or one of the templates. Returns a fresh
// definition for the editor, or null when the picker is dismissed. It opens as
// a sheet in direction A "Eclipse" (docs/AESTHETICS.md): a serif title, then
// hairline rows, each template with its icon in its colour disc.
Future<ListDefinition?> showListTemplatePicker(BuildContext context) {
  return showSlideUpSheet<ListDefinition>(
    context: context,
    builder: (_) => const _TemplatePicker(),
  );
}

class _TemplatePicker extends StatelessWidget {
  const _TemplatePicker();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final ListLabels labels = ListLabels(loc);
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals n = AppColors.neutrals(brightness);
    final AppTypography type = AppTypography.of(context);

    Widget row({
      required Key key,
      required Widget disc,
      required String title,
      String? meta,
      required ListDefinition Function() pick,
    }) {
      return InkWell(
        key: key,
        onTap: () => Navigator.of(context).pop(pick()),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(
            horizontal: AppShapes.sideMargin,
            vertical: 10,
          ),
          child: Row(
            children: [
              disc,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: type.row),
                    if (meta != null) Text(meta, style: type.meta),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget hairline() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppShapes.sideMargin),
      child: Divider(color: n.line, height: 1),
    );

    const double disc = 40;
    final List<ListDefinition> templates = BuiltinTemplates.all();

    return Semantics(
      label: loc.newList,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: n.ground,
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
                        color: n.line,
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
                    child: Text(loc.newList, style: type.screenTitle),
                  ),
                  hairline(),
                  row(
                    key: const ValueKey('template-blank'),
                    disc: Container(
                      width: disc,
                      height: disc,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: n.text, width: 1.5),
                      ),
                      child: Icon(Icons.add, size: 22, color: n.text),
                    ),
                    title: loc.blankList,
                    pick: () => blankListDefinition(loc),
                  ),
                  for (final ListDefinition template in templates) ...[
                    hairline(),
                    row(
                      key: ValueKey('template-${template.id}'),
                      disc: _ColorDisc(
                        size: disc,
                        color: listColor(
                          template.color,
                          brightness: brightness,
                        ),
                        icon: listIcon(template.icon),
                      ),
                      title: labels.listName(template),
                      meta: labels.viewKind(template.view.kind),
                      pick: () => templateCopy(template),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// A list's only image: its icon inside its colour disc.
class _ColorDisc extends StatelessWidget {
  const _ColorDisc({
    required this.size,
    required this.color,
    required this.icon,
  });

  final double size;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: 20, color: AppColors.onColor(color)),
    );
  }
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
