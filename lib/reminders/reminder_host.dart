import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app/account_preferences.dart';
import '../app/app_settings.dart';
import '../l10n/generated/app_localizations.dart';
import '../lists/list_catalog.dart';
import '../lists/list_labels.dart';
import '../lists/list_store.dart';
import 'reminder_planner.dart';
import 'reminder_text.dart';
import 'ring_booker.dart';

// Keeps this phone's booked rings in step with the lists while the app is
// open (T-13 unit 3, Q-93): it plans again and books the difference when a
// list changes (here or on another phone), when a reminder setting, Ring on
// this phone or the language changes, and when the app comes back to the
// front. Without a RingBooker (off Android, tests) it does nothing.
//
// The first time it has a ring to book it asks for the permissions, once per
// phone (Q-94): the system's notifications popup, then a short sheet that
// opens the Alarms & reminders switch. Refusing either blocks nothing.
class ReminderHost extends StatefulWidget {
  const ReminderHost({super.key, required this.account, required this.child});

  // The signed-in account's uid; each ring carries it (F2).
  final String account;
  final Widget child;

  // How long changes settle before booking; a burst of snapshots books once.
  static const Duration settle = Duration(milliseconds: 400);

  @override
  State<ReminderHost> createState() => _ReminderHostState();
}

class _ReminderHostState extends State<ReminderHost>
    with WidgetsBindingObserver {
  RingBooker? _booker;
  StreamSubscription<ListCatalog>? _lists;
  StreamSubscription<AccountPreferences>? _preferences;
  StreamSubscription<AppSettings>? _settings;
  ListCatalog? _catalog;
  Timer? _settle;
  Locale? _locale;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _booker = context.read<RingBooker?>();
    if (_booker == null) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    unawaited(_booker!.platform.startBackgroundCheck());
    final ListStore store = context.read<ListStore>();
    _catalog = store.current;
    _lists = store.watch().listen((catalog) {
      _catalog = catalog;
      _schedule();
    });
    _preferences = context.read<AccountPreferencesCubit>().stream.listen(
      (_) => _schedule(),
    );
    _settings = context.read<AppSettingsCubit>().stream.listen(
      (_) => _schedule(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Locale locale = Localizations.localeOf(context);
    if (_booker != null && locale != _locale) {
      _locale = locale;
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedule();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settle?.cancel();
    _lists?.cancel();
    _preferences?.cancel();
    _settings?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _schedule() {
    _settle?.cancel();
    _settle = Timer(ReminderHost.settle, () => unawaited(_sync()));
  }

  Future<void> _sync() async {
    final RingBooker? booker = _booker;
    final ListCatalog? catalog = _catalog;
    if (!mounted || booker == null || catalog == null) {
      return;
    }
    final AppSettingsCubit settings = context.read<AppSettingsCubit>();
    final AccountPreferences preferences = context
        .read<AccountPreferencesCubit>()
        .state;
    final AppLocalizations loc = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final ListLabels labels = ListLabels(loc);
    final List<PlannedRing> rings = settings.state.ringOnThisPhone
        ? ReminderPlanner.plan(
            catalog: catalog,
            settings: preferences.reminders,
            now: DateTime.now(),
            listName: labels.listName,
          )
        : const [];
    try {
      await booker.sync(
        rings,
        (ring) => reminderText(
          ring,
          loc: loc,
          locale: locale,
          format: preferences.timeFormat,
        ),
        account: widget.account,
      );
    } on Object catch (error) {
      debugPrint('Reminders not booked: $error');
      return;
    }
    if (rings.isNotEmpty && !settings.remindersAsked && mounted) {
      await _ask(booker, settings);
    }
  }

  // Q-94: the notifications popup, then the Alarms & reminders sheet, once.
  Future<void> _ask(RingBooker booker, AppSettingsCubit settings) async {
    if (_asking) {
      return;
    }
    _asking = true;
    try {
      await settings.setRemindersAsked();
      final bool allowed = await booker.platform.requestNotifications();
      final RingPermissions permissions = await booker.platform.permissions();
      if (allowed && !permissions.exact && mounted) {
        await showExactAlarmSheet(context, booker.platform);
      }
      // What was allowed decides how rings are booked.
      _schedule();
    } finally {
      _asking = false;
    }
  }
}

// The short sheet before the system's Alarms & reminders switch (Q-94). Also
// opened from Preferences > Reminders.
Future<void> showExactAlarmSheet(
  BuildContext context,
  RingPlatform platform,
) async {
  final AppLocalizations loc = AppLocalizations.of(context);
  final bool? open = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    builder: (sheetContext) {
      final ThemeData theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          key: const ValueKey('reminder-exact-sheet'),
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.reminderExactTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(loc.reminderExactText, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('reminder-exact-later'),
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: Text(loc.reminderExactLater),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('reminder-exact-open'),
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: Text(loc.reminderExactOpen),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  if (open == true) {
    await platform.openExactAlarmSettings();
  }
}
