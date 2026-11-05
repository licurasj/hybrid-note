import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/auth_service.dart';
import '../backend/firestore_list_store.dart';
import '../backend/firestore_setup.dart';
import '../l10n/generated/app_localizations.dart';
import '../lists/list_store.dart';
import 'account_preferences.dart';
import 'app_banner.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'main_shell.dart';
import 'sign_in_screen.dart';

// Opens the list store of a signed-in user and writes their starter lists
// (FirestoreSetup.openStore in the app, a fake_cloud_firestore store in
// tests).
typedef OpenedStore = ({FirestoreListStore store, StarterSeeding starter});
typedef StoreOpener = OpenedStore Function(AuthUser user);

// The signed-in account as the shell sees it: who is signed in, and how to
// sign out (the gate closes the store first).
class SignedInAccount {
  const SignedInAccount({required this.user, required this.signOut});

  final AuthUser user;
  final Future<void> Function() signOut;
}

// Signed out: the sign-in screen and nothing else (Q-21 A). Signed in: the
// shell on a store for that user's uid, whatever the sign-in method (D-13).
// The providers sit above MaterialApp so pushed pages see them, and the app
// is keyed by uid: a new user (or none) gets a fresh page stack and store,
// so no list of the previous user stays on screen.
class HybridNoteApp extends StatefulWidget {
  const HybridNoteApp({
    super.key,
    required this.auth,
    required this.openStore,
    this.openPreferences,
    this.afterSignOut,
  });

  final AuthService auth;
  final StoreOpener openStore;
  // Where a signed-in user's preferences sync; without it they stay on this
  // device (tests).
  final AccountPreferencesSync Function(AuthUser user)? openPreferences;
  // Runs once sign-out has finished and the cache is cleared; on web it
  // reloads the page, since the cleared Firestore instance cannot be used
  // again (FirestoreSetup). It does not run while the cache is still there.
  // When it is set, the gate opens no store after a sign-out: the restarted
  // app does.
  final VoidCallback? afterSignOut;

  @override
  State<HybridNoteApp> createState() => _HybridNoteAppState();
}

class _HybridNoteAppState extends State<HybridNoteApp> {
  final GlobalKey<ScaffoldMessengerState> _messenger =
      GlobalKey<ScaffoldMessengerState>();
  final AppBannerController _banners = AppBannerController();
  late final StreamSubscription<AuthUser?> _subscription;
  // False until Firebase has said whether a user is signed in, so a
  // restored session does not flash the sign-in screen.
  bool _known = false;
  // The user on screen and their store.
  AuthUser? _user;
  FirestoreListStore? _store;
  StarterSeeding? _starter;
  AccountPreferencesCubit? _preferences;
  StreamSubscription<Object>? _writeFailures;
  // The user Firebase last reported; shown once no sign-out is running.
  AuthUser? _latest;
  // A sign-out (with its cache clear) is running. Auth transitions run one
  // at a time: meanwhile sign-in is disabled and a new user waits, so no
  // store opens on a cache that is about to be deleted (T-17 R2).
  bool _signingOut = false;
  // Signed out, but the previous account's cache could not be cleared: the
  // sign-in screen says so and offers to try again (T-17 R1, Q-25 A).
  bool _cleanupFailed = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.auth.userChanges.listen(_onUser);
  }

  @override
  void dispose() {
    _subscription.cancel();
    _writeFailures?.cancel();
    unawaited(_store?.close());
    unawaited(_preferences?.close());
    _banners.dispose();
    super.dispose();
  }

  void _onUser(AuthUser? user) {
    _latest = user;
    if (_signingOut || _cleanupFailed) {
      setState(() => _known = true);
      return;
    }
    _show(user);
  }

  void _show(AuthUser? user) {
    final FirestoreListStore? old = _store;
    final AccountPreferencesCubit? oldPreferences = _preferences;
    final bool sameUser = user?.uid == _user?.uid;
    setState(() {
      _known = true;
      _user = user;
      if (!sameUser) {
        final OpenedStore? opened = user == null
            ? null
            : widget.openStore(user);
        _store = opened?.store;
        _starter = opened?.starter;
        _preferences = user == null ? null : _openPreferences(user);
      }
    });
    if (!sameUser) {
      _watchWriteFailures();
      unawaited(old?.close());
      unawaited(oldPreferences?.close());
    }
  }

  AccountPreferencesCubit _openPreferences(AuthUser user) {
    return AccountPreferencesCubit(
      context.read<AppSettingsCubit>().preferences,
      user.uid,
      sync: widget.openPreferences?.call(user),
    );
  }

  // A list create, delete or Undo completes on the device at once; if the
  // server rejects it later, Firestore undoes it and this says so (T-17 R3).
  void _watchWriteFailures() {
    _writeFailures?.cancel();
    _writeFailures = _store?.writeFailures.listen((failure) {
      final BuildContext? context = _messenger.currentContext;
      if (context != null && context.mounted) {
        final AppLocalizations loc = AppLocalizations.of(context);
        _banners.show(
          failure is ItemsNotUpdated
              ? loc.itemsNotUpdated
              : loc.listChangeNotSaved,
        );
      }
    });
  }

  // Takes the lists off the screen at once, closes the store, then signs
  // out (which clears the cache, Q-25 A).
  Future<void> _signOut() async {
    if (_signingOut) {
      return;
    }
    final FirestoreListStore? store = _store;
    final AccountPreferencesCubit? preferences = _preferences;
    final String? uid = _user?.uid;
    final SharedPreferences stored = context
        .read<AppSettingsCubit>()
        .preferences;
    final AppSettingsCubit settings = context.read<AppSettingsCubit>();
    _banners.dismiss();
    setState(() {
      _signingOut = true;
      _user = null;
      _store = null;
      _preferences = null;
    });
    _watchWriteFailures();
    final bool cleared;
    try {
      await store?.close();
      await preferences?.close();
      cleared = await widget.auth.signOut();
      if (uid != null) {
        await AccountPreferencesCubit.forget(stored, uid);
        await settings.forgetRecentLists(uid);
      }
    } on Object catch (error) {
      debugPrint('Sign-out failed: $error');
      final BuildContext? context = _messenger.currentContext;
      if (context != null && context.mounted) {
        _banners.show(AppLocalizations.of(context).signOutFailed);
      }
      // Still signed in: back to that user's lists.
      if (mounted) {
        _signingOut = false;
        _show(widget.auth.currentUser);
      }
      return;
    }
    _afterCleanup(cleared);
  }

  Future<void> _retryCleanup() async {
    setState(() => _signingOut = true);
    _afterCleanup(await widget.auth.clearLocalData());
  }

  // Signed out either way; only a cleared cache ends the sign-out. Then
  // [HybridNoteApp.afterSignOut] restarts the app (web), or the user
  // Firebase reports by now is shown (null, or one who signed in since).
  void _afterCleanup(bool cleared) {
    if (!mounted) {
      return;
    }
    setState(() {
      _signingOut = false;
      _cleanupFailed = !cleared;
    });
    if (!cleared) {
      return;
    }
    if (widget.afterSignOut != null) {
      widget.afterSignOut!();
      return;
    }
    _show(_latest);
  }

  @override
  Widget build(BuildContext context) {
    final AuthUser? user = _user;
    final FirestoreListStore? store = _store;
    final AccountPreferencesCubit? preferences = _preferences;
    final Widget home;
    if (!_known) {
      home = const Scaffold();
    } else if (user == null || store == null) {
      home = SignInScreen(
        auth: widget.auth,
        waiting: _signingOut,
        onRetryCleanup: _cleanupFailed ? _retryCleanup : null,
      );
    } else {
      home = const MainShell();
    }

    final Widget app = BlocBuilder<AppSettingsCubit, AppSettings>(
      builder: (context, settings) {
        return MaterialApp(
          key: ValueKey(user?.uid),
          scaffoldMessengerKey: _messenger,
          onGenerateTitle: (context) {
            return AppLocalizations.of(context).appTitle;
          },
          debugShowCheckedModeBanner: false,
          builder: (context, child) =>
              AppBannerHost(controller: _banners, child: child!),
          locale: settings.localeCode == null
              ? null
              : Locale(settings.localeCode!),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(languageCode: settings.localeCode),
          darkTheme: AppTheme.dark(languageCode: settings.localeCode),
          themeMode: settings.themeMode,
          home: home,
        );
      },
    );

    if (user == null || store == null || preferences == null) {
      return RepositoryProvider<AppBannerController>.value(
        value: _banners,
        child: app,
      );
    }
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppBannerController>.value(value: _banners),
        RepositoryProvider<ListStore>.value(value: store),
        RepositoryProvider<StarterSeeding>.value(
          value: _starter ?? StarterSeeding.done(),
        ),
        RepositoryProvider<SignedInAccount>.value(
          value: SignedInAccount(user: user, signOut: _signOut),
        ),
      ],
      child: BlocProvider.value(value: preferences, child: app),
    );
  }
}
