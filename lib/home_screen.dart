import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app/app_settings.dart';
import 'app/hybrid_note_app.dart';
import 'app/starter_note.dart';
import 'l10n/generated/app_localizations.dart';
import 'lists/list_catalog.dart';
import 'lists/list_catalog_builder.dart';
import 'lists/list_definition.dart';
import 'lists/list_icons.dart';
import 'lists/list_labels.dart';
import 'lists/list_vocabulary.dart';

// Minimal T-17 home: one card per list and the account row. T-16 unit 5
// replaces this screen (Q-20 A).
class HomeScreen extends StatelessWidget {
  final ValueChanged<String>? onOpenList;

  const HomeScreen({
    super.key,
    this.onOpenList,
  });

  Widget _summaryCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    final BorderRadius borderRadius = BorderRadius.circular(6);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, size: 34),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

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

  Future<void> _showLanguageDialog(
    BuildContext context,
    AppSettings settings,
  ) async {
    final AppLocalizations loc = AppLocalizations.of(context);

    final List<({String? code, String label, String subtitle})> options = [
      (code: null, label: loc.languageSystem, subtitle: loc.languageFollowsDevice),
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
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView.builder(
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                final bool selected = settings.localeCode == option.code;

                return ListTile(
                  selected: selected,
                  leading: Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  ),
                  title: Text(option.label),
                  subtitle: Text(option.subtitle),
                  onTap: () {
                    context.read<AppSettingsCubit>().setLocaleCode(option.code);
                    Navigator.of(dialogContext).pop();
                  },
                );
              },
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
    return BlocBuilder<AppSettingsCubit, AppSettings>(
      builder: (context, settings) {
        final AppLocalizations loc = AppLocalizations.of(context);
        final ListLabels labels = ListLabels(loc);
        final SignedInAccount account = context.read<SignedInAccount>();

        return Scaffold(
          appBar: AppBar(
            title: Text(loc.appTitle),
            actions: [
              IconButton(
                onPressed: () {
                  _showLanguageDialog(context, settings);
                },
                icon: const Icon(Icons.language),
                tooltip: '${loc.language}: ${_languageLabel(loc, settings.localeCode)}',
              ),
              IconButton(
                onPressed: () {
                  context.read<AppSettingsCubit>().toggleDarkMode();
                },
                icon: Icon(
                  settings.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                ),
                tooltip: settings.isDarkMode
                    ? loc.switchToLightMode
                    : loc.switchToDarkMode,
              ),
            ],
          ),
          body: ListCatalogBuilder(
            builder: (context, catalog) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (catalog.definitions.isEmpty) const StarterNote(),
                for (final ListDefinition definition in catalog.definitions)
                  _summaryCard(
                    context: context,
                    icon: listIcon(definition.icon),
                    title: labels.listName(definition),
                    value: '${_openCount(catalog, definition)}',
                    onTap: () {
                      onOpenList?.call(definition.id);
                    },
                  ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const Icon(Icons.account_circle),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            account.user.email ?? loc.account,
                            key: const ValueKey('account-email'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('sign-out'),
                          onPressed: account.signOut,
                          icon: const Icon(Icons.logout),
                          label: Text(loc.logOut),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Items not marked done (all items when the list has no completion field).
  static int _openCount(ListCatalog catalog, ListDefinition definition) {
    final String? done = definition.fieldWithRole(FieldRole.completion)?.key;
    return catalog
        .itemsOf(definition.id)
        .where((item) => done == null || item.values[done] != true)
        .length;
  }
}
