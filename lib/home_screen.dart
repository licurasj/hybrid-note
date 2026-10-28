import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app_cubit.dart';
import 'app_state.dart';
import 'l10n/generated/app_localizations.dart';

class HomeScreen extends StatelessWidget {
  final ValueChanged<int>? onNavigate;

  const HomeScreen({
    super.key,
    this.onNavigate,
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


  void _openPage(int index) {
    onNavigate?.call(index);
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
    AppState state,
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
                final bool selected = state.selectedLocaleCode == option.code;

                return ListTile(
                  selected: selected,
                  leading: Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  ),
                  title: Text(option.label),
                  subtitle: Text(option.subtitle),
                  onTap: () {
                    context.read<AppCubit>().setPreferredLocaleCode(option.code);
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
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, state) {
        final AppLocalizations loc = AppLocalizations.of(context);

        if (state.isLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(loc.appTitle),
            actions: [
              IconButton(
                onPressed: () {
                  _showLanguageDialog(context, state);
                },
                icon: const Icon(Icons.language),
                tooltip: '${loc.language}: ${_languageLabel(loc, state.selectedLocaleCode)}',
              ),
              IconButton(
                onPressed: () {
                  context.read<AppCubit>().toggleDarkMode();
                },
                icon: Icon(
                  state.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                ),
                tooltip: state.isDarkMode
                    ? loc.switchToLightMode
                    : loc.switchToDarkMode,
              ),
              IconButton(
                onPressed: state.isSyncing
                    ? null
                    : () {
                        context.read<AppCubit>().syncWithDrive();
                      },
                icon: state.isSyncing
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () {
              return context.read<AppCubit>().syncWithDrive();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _summaryCard(
                  context: context,
                  icon: Icons.pending_actions,
                  title: loc.pendingTasks,
                  value: '${state.pendingTaskCount}',
                  onTap: () {
                    _openPage(1);
                  },
                ),
                _summaryCard(
                  context: context,
                  icon: Icons.done_all,
                  title: loc.completedTasks,
                  value: '${state.completedTaskCount}',
                  onTap: () {
                    _openPage(1);
                  },
                ),
                _summaryCard(
                  context: context,
                  icon: Icons.book,
                  title: loc.journalEntries,
                  value: '${state.data.journalEntries.length}',
                  onTap: () {
                    _openPage(3);
                  },
                ),
                _summaryCard(
                  context: context,
                  icon: Icons.movie,
                  title: loc.watchReadItems,
                  value: '${state.data.watchItems.length}',
                  onTap: () {
                    _openPage(4);
                  },
                ),
                _summaryCard(
                  context: context,
                  icon: Icons.shopping_cart,
                  title: loc.groceryItems,
                  value: '${state.data.groceryItems.length}',
                  onTap: () {
                    _openPage(2);
                  },
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.googleDriveSync,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          state.isSyncing
                              ? loc.syncing
                              : state.lastSyncedAt == null
                                  ? loc.notSyncedYet
                                  : loc.lastSynced(state.lastSyncedAt!.toLocal().toString()),
                        ),
                        if (!state.isSyncing && state.syncMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(state.syncMessage!),
                        ],
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: state.isSyncing
                              ? null
                              : () {
                                  if (state.isGoogleSignedIn) {
                                    context.read<AppCubit>().signOutOfGoogle();
                                  } else {
                                    context.read<AppCubit>().signInToGoogle();
                                  }
                                },
                          icon: Icon(
                            state.isGoogleSignedIn ? Icons.logout : Icons.login,
                          ),
                          label: Text(
                            state.isGoogleSignedIn ? loc.logOut : loc.signInWithGoogle,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: state.isSyncing
                              ? null
                              : () {
                                  context.read<AppCubit>().syncWithDrive();
                                },
                          icon: state.isSyncing
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.cloud_sync),
                          label: Text(loc.syncToGoogleDrive),
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
}
