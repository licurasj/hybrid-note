import 'package:flutter/material.dart';

import '../app/account_preferences.dart';
import '../app/app_theme.dart';
import '../app_colors.dart';
import '../l10n/generated/app_localizations.dart';
import 'generic_item_dialog.dart';
import 'list_definition.dart';

// Whether to go on with deleting [name] (an item of [list], or [list] itself):
// at once, unless the user asked to be asked (Q-50 c), in Preferences or on
// that list (Q-117), then a slide-up sheet with Cancel and Delete.
Future<bool> confirmDelete(
  BuildContext context,
  String name, {
  ListDefinition? list,
}) async {
  if (!context.accountPreferences.confirmDeleteFor(list)) {
    return true;
  }
  final bool? confirmed = await showSlideUpSheet<bool>(
    context: context,
    builder: (_) => _ConfirmDeleteSheet(name: name),
  );
  return confirmed ?? false;
}

class _ConfirmDeleteSheet extends StatelessWidget {
  const _ConfirmDeleteSheet({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    final Brightness brightness = Theme.of(context).brightness;
    final AppNeutrals neutrals = AppColors.neutrals(brightness);
    final AppTypography type = AppTypography.of(context);

    return Semantics(
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppShapes.sideMargin,
                0,
                AppShapes.sideMargin,
                16,
              ),
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
                  Text(
                    loc.confirmDeleteTitle(name),
                    style: type.row.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        key: const ValueKey('confirm-delete-cancel'),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(loc.cancel),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        key: const ValueKey('confirm-delete-yes'),
                        style: AppInk.pressless(
                          TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(loc.delete),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
