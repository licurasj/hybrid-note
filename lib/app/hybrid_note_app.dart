import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app_cubit.dart';
import '../app_state.dart';
import '../l10n/generated/app_localizations.dart';
import 'app_theme.dart';
import 'main_shell.dart';

class HybridNoteApp extends StatelessWidget {
  const HybridNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, state) {
        return MaterialApp(
          onGenerateTitle: (context) {
            return AppLocalizations.of(context).appTitle;
          },
          debugShowCheckedModeBanner: false,
          locale: state.selectedLocaleCode == null
              ? null
              : Locale(state.selectedLocaleCode!),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(languageCode: state.selectedLocaleCode),
          darkTheme: AppTheme.dark(languageCode: state.selectedLocaleCode),
          themeMode: state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const MainShell(),
        );
      },
    );
  }
}
