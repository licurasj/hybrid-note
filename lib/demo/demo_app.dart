import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../ai/ai_service.dart';
import '../app/account_preferences.dart';
import '../app/app_banner.dart';
import '../app/app_settings.dart';
import '../app/app_theme.dart';
import '../app_colors.dart';
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
import 'page_probe.dart';
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
        topInset: demoTopInset(
          query: pageQuery(),
          coarsePointer: coarsePointer(),
        ),
        keyboardInset: frameKeyboardInset(),
      ),
    ),
  );
}

// Preferences that live in this page's memory only. Only the demo's start
// calls it; the real app keeps the platform's store. The demo starts light
// instead of following the system (T-18 unit 5, Q-146); the visitor can
// still switch in Preferences, until the next reload.
Future<SharedPreferences> demoPreferences() async {
  SharedPreferencesStorePlatform.instance =
      InMemorySharedPreferencesStore.empty();
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.setString(
    AppSettingsCubit.themeModeKey,
    ThemeMode.light.name,
  );
  return preferences;
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

// Room left at the top for the portfolio's close button (T-18 PX-3,
// Q-145): on a touch screen the portfolio shows the demo full screen with
// its close button (about 60 by 36, 12 from the top and right edges) over
// the frame's top-right corner.
const double embedTouchInset = 56;

// The band's colour: the app's dark ground, so it reads as part of the
// screen, not as a gap, behind the portfolio's close button.
final Color demoInsetBand = AppNeutrals.dark.ground;

// The demo's top inset: [embedTouchInset] when the page was opened by the
// portfolio (`embed=1` in [query]) on a touch screen ([coarsePointer]);
// none otherwise. With a fine pointer the portfolio's button sits outside
// the frame.
double demoTopInset({required String query, required bool coarsePointer}) {
  final String search = query.startsWith('?') ? query.substring(1) : query;
  final Map<String, String> params;
  try {
    params = Uri.splitQueryString(search);
  } on FormatException {
    return 0;
  } on ArgumentError {
    return 0;
  }
  return params['embed'] == '1' && coarsePointer ? embedTouchInset : 0;
}

// The demo's root, in place of HybridNoteApp: the shell on [store] with local
// preferences, a local account and no reminders. Expects an AppSettingsCubit
// above it. Without [aiService] there is no AI bar; startDemo gives the
// lazy one (T-18 unit 2b).
class DemoApp extends StatefulWidget {
  const DemoApp({
    super.key,
    required this.store,
    this.aiService,
    this.topInset = 0,
    this.keyboardInset,
  });

  final ListStore store;
  final AiService? aiService;

  // Space kept clear above every screen, sheet and dialog (demoTopInset).
  final double topInset;

  // How much of the frame the parent page's keyboard covers (Q-147), from
  // frameKeyboardInset; null outside a same-origin parent.
  final ValueListenable<double>? keyboardInset;

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
              builder: (context, child) {
                final Widget banners = AppBannerHost(
                  controller: _banners,
                  child: child!,
                );
                final ValueListenable<double>? keyboard = widget.keyboardInset;
                if (keyboard == null) {
                  return DemoFrame(topInset: widget.topInset, child: banners);
                }
                return ValueListenableBuilder<double>(
                  valueListenable: keyboard,
                  child: banners,
                  builder: (context, bottom, kept) => DemoFrame(
                    topInset: widget.topInset,
                    bottomInset: bottom,
                    child: kept!,
                  ),
                );
              },
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

// The phone layout, centred in a frame wider than [demoPhoneWidth] (Q-137),
// below a dark band [topInset] tall (Q-145). The screens below see the
// column's size as the screen's, so their own layout is the phone's; pages,
// sheets and dialogs open inside the column, under the band. A keyboard
// over the frame's bottom from outside it ([bottomInset], Q-147) counts as
// the screens' own keyboard (viewInsets), so the AI bar and sheets rise
// above it as they do outside a frame.
class DemoFrame extends StatelessWidget {
  const DemoFrame({
    super.key,
    required this.child,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  final Widget child;
  final double topInset;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData outer = MediaQuery.of(context);
    // Always wrapped, so the tree below keeps its state (and the field its
    // focus) when the keyboard comes or goes.
    final MediaQueryData media = outer.copyWith(
      viewInsets: outer.viewInsets.copyWith(
        bottom: math.max(outer.viewInsets.bottom, bottomInset),
      ),
    );
    return MediaQuery(data: media, child: _framed(media));
  }

  Widget _framed(MediaQueryData media) {
    if (topInset <= 0) {
      return _column(media);
    }
    final MediaQueryData below = media.copyWith(
      size: Size(media.size.width, math.max(0, media.size.height - topInset)),
      padding: media.padding.copyWith(
        top: math.max(0, media.padding.top - topInset),
      ),
      viewPadding: media.viewPadding.copyWith(
        top: math.max(0, media.viewPadding.top - topInset),
      ),
    );
    return ColoredBox(
      key: const ValueKey('demo-top-inset'),
      color: demoInsetBand,
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: MediaQuery(
          data: below,
          child: ClipRect(child: _column(below)),
        ),
      ),
    );
  }

  Widget _column(MediaQueryData media) {
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
