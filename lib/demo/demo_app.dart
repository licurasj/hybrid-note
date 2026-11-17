import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../ai/ai_service.dart';
import '../app/account_preferences.dart';
import '../app/app_banner.dart';
import '../app/app_settings.dart';
import '../app/app_theme.dart';
import '../app/hybrid_note_app.dart' show SignedInAccount;
import '../app/main_shell.dart';
import '../backend/auth_service.dart';
import '../backend/firestore_setup.dart' show StarterSeeding;
import '../backend/starter_lists.dart';
import '../l10n/generated/app_localizations.dart';
import '../lists/builtin_templates.dart';
import '../lists/list_store.dart';
import 'demo_ai.dart';
import 'demo_build.dart';
import 'memory_list_store.dart';
import 'sample_items.dart';

// The demo's start (T-18): no Firebase, no sign-in. Preferences are kept in
// memory too (Q-135), so nothing is written to the browser's storage, which
// the demo shares with the portfolio page around it. Firebase starts only
// at the first AI request, after the AI notice (LazyAiService).
Future<void> startDemo() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences preferences = await demoPreferences();
  runApp(
    BlocProvider(
      create: (_) => AppSettingsCubit(preferences),
      child: DemoApp(
        store: demoStore(DateTime.now()),
        aiService: LazyAiService(FirebaseDemoAiBackend()),
      ),
    ),
  );
}

// Preferences that live in this page's memory only. Only the demo's start
// calls it; the real app keeps the platform's store.
Future<SharedPreferences> demoPreferences() {
  SharedPreferencesStorePlatform.instance =
      InMemorySharedPreferencesStore.empty();
  return SharedPreferences.getInstance();
}

// The starter lists with the sample items (Q-87), fresh on every start.
MemoryListStore demoStore(DateTime now) {
  final List<StarterCopy> copies = StarterLists.copies(
    BuiltinTemplates.all(),
    sampleItems: demoSampleItems(now),
    now: now.toUtc(),
  );
  return MemoryListStore(
    lists: [for (final StarterCopy copy in copies) copy.definition],
    items: [for (final StarterCopy copy in copies) ...copy.items],
  );
}

// The account the demo's screens see: on this page only, with no sign-out.
const AuthUser demoUser = AuthUser(uid: 'demo');

// The widest the phone layout grows in the demo; a wider frame shows it
// centred (Q-137) until the real wide layout (T-30).
const double demoPhoneWidth = 430;

// Outside the centred phone layout: the portfolio's background, so the
// column reads as the phone in the frame.
const Color demoBackdrop = Color(0xFF05070A);

// The demo's root, in place of HybridNoteApp: the shell on [store] with local
// preferences, a local account and no reminders. Expects an AppSettingsCubit
// above it. Without [aiService] there is no AI bar; startDemo gives the
// lazy one (T-18 unit 2b).
class DemoApp extends StatefulWidget {
  const DemoApp({super.key, required this.store, this.aiService});

  final ListStore store;
  final AiService? aiService;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  final AppBannerController _banners = AppBannerController();
  late final AccountPreferencesCubit _preferences = AccountPreferencesCubit(
    context.read<AppSettingsCubit>().preferences,
    demoUser.uid,
  );
  final StarterSeeding _starter = StarterSeeding.done();

  @override
  void dispose() {
    unawaited(_preferences.close());
    final ListStore store = widget.store;
    if (store is MemoryListStore) {
      unawaited(store.close());
    }
    _banners.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<DemoMode>.value(value: const DemoMode()),
        RepositoryProvider<AppBannerController>.value(value: _banners),
        RepositoryProvider<ListStore>.value(value: widget.store),
        RepositoryProvider<StarterSeeding>.value(value: _starter),
        if (widget.aiService != null)
          RepositoryProvider<AiService>.value(value: widget.aiService!),
        RepositoryProvider<SignedInAccount>.value(
          value: SignedInAccount(user: demoUser, signOut: () async {}),
        ),
      ],
      child: BlocProvider.value(
        value: _preferences,
        child: BlocBuilder<AppSettingsCubit, AppSettings>(
          builder: (context, settings) {
            return MaterialApp(
              onGenerateTitle: (context) =>
                  AppLocalizations.of(context).appTitle,
              debugShowCheckedModeBanner: false,
              builder: (context, child) => DemoFrame(
                child: AppBannerHost(controller: _banners, child: child!),
              ),
              locale: settings.localeCode == null
                  ? null
                  : Locale(settings.localeCode!),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(languageCode: settings.localeCode),
              darkTheme: AppTheme.dark(languageCode: settings.localeCode),
              themeMode: settings.themeMode,
              home: const MainShell(),
            );
          },
        ),
      ),
    );
  }
}

// The phone layout, centred in a frame wider than [demoPhoneWidth] (Q-137).
// The screens below see the column's size as the screen's, so their own
// layout is the phone's; pages, sheets and dialogs open inside the column.
class DemoFrame extends StatelessWidget {
  const DemoFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    if (media.size.width <= demoPhoneWidth) {
      return child;
    }
    return ColoredBox(
      color: demoBackdrop,
      child: Center(
        child: SizedBox(
          key: const ValueKey('demo-phone-column'),
          width: demoPhoneWidth,
          child: MediaQuery(
            data: media.copyWith(
              size: Size(demoPhoneWidth, media.size.height),
              padding: media.padding.copyWith(left: 0, right: 0),
              viewPadding: media.viewPadding.copyWith(left: 0, right: 0),
              viewInsets: media.viewInsets.copyWith(left: 0, right: 0),
            ),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}
