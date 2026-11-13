import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app/settings_controls.dart';
import '../l10n/generated/app_localizations.dart';
import '../lists/list_editor_style.dart';
import 'reminder_host.dart';
import 'ring_booker.dart';

// Preferences > Reminders: whether this phone may ring, and on time, with a
// button that fixes what is off (Q-94). Read again whenever the app comes
// back to the front, so a switch turned off in the phone's settings shows.
// Nothing without a RingBooker (off Android).
class ReminderPermissionRow extends StatefulWidget {
  const ReminderPermissionRow({super.key});

  @override
  State<ReminderPermissionRow> createState() => _ReminderPermissionRowState();
}

class _ReminderPermissionRowState extends State<ReminderPermissionRow>
    with WidgetsBindingObserver {
  RingPlatform? _platform;
  RingPermissions? _permissions;

  @override
  void initState() {
    super.initState();
    _platform = context.read<RingBooker?>()?.platform;
    if (_platform != null) {
      WidgetsBinding.instance.addObserver(this);
      _read();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _read();
    }
  }

  Future<void> _read() async {
    final RingPermissions permissions = await _platform!.permissions();
    if (mounted) {
      setState(() => _permissions = permissions);
    }
  }

  Future<void> _fix() async {
    final RingPlatform platform = _platform!;
    final RingPermissions? permissions = _permissions;
    if (permissions == null) {
      return;
    }
    if (!permissions.notifications) {
      // Asked once already, Android shows no popup: its settings then.
      if (!await platform.requestNotifications()) {
        await platform.openNotificationSettings();
      }
    } else if (!permissions.exact && mounted) {
      await showExactAlarmSheet(context, platform);
    }
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final RingPermissions? permissions = _permissions;
    if (_platform == null || permissions == null) {
      return const SizedBox.shrink();
    }
    final AppLocalizations loc = AppLocalizations.of(context);
    final EditorLook look = EditorLook.of(context);
    final bool ok = permissions.notifications && permissions.exact;
    return look.hairline(
      key: const ValueKey('preferences-reminder-permission'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    loc.preferencesReminderPermission,
                    style: look.type.row,
                  ),
                ),
                if (!ok)
                  FilledButton(
                    key: const ValueKey('preferences-reminder-permission-fix'),
                    onPressed: _fix,
                    child: Text(
                      permissions.notifications
                          ? loc.reminderExactOpen
                          : loc.preferencesReminderAllow,
                    ),
                  ),
              ],
            ),
          ),
          SettingLine(
            ok
                ? loc.preferencesReminderPermissionOk
                : !permissions.notifications
                ? loc.preferencesReminderNotificationsOff
                : loc.preferencesReminderExactOff,
          ),
        ],
      ),
    );
  }
}
