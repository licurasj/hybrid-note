import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import '../app_colors.dart';
import 'reminder_background.dart';
import 'ring_booker.dart';

// Rings on Android through flutter_local_notifications (T-13 unit 3). One
// channel, "Reminders"; the small icon is res/drawable/ic_stat_reminder. Times
// are booked as UTC instants: the planner already worked out the local
// wall-clock time, and it plans again when the phone's zone changes.
class LocalRingPlatform implements RingPlatform {
  LocalRingPlatform({required this.channelName});

  static const String channelId = 'reminders';
  static const String smallIcon = 'ic_stat_reminder';

  // The channel's name in the phone's settings, in the app's language when
  // the channel was first made.
  String channelName;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _ready;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  // Taps on a ring's body while the app runs (T-13 unit 4). Done goes to
  // onRingActionInBackground, in an isolate of its own, even with the app
  // open.
  static final StreamController<RingPayload> _taps =
      StreamController<RingPayload>.broadcast();

  Future<void> _init() => _ready ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(smallIcon),
        ),
        onDidReceiveNotificationResponse: _onResponse,
        onDidReceiveBackgroundNotificationResponse: onRingActionInBackground,
      )
      .then((_) {});

  static void _onResponse(NotificationResponse response) {
    if (response.actionId == reminderDoneAction) {
      unawaited(onRingActionInBackground(response));
      return;
    }
    final RingPayload? payload = RingPayload.decode(response.payload);
    if (payload != null) {
      _taps.add(payload);
    }
  }

  @override
  Stream<RingPayload> get taps {
    unawaited(_init());
    return _taps.stream;
  }

  @override
  Future<RingPayload?> launchTap() async {
    await _init();
    final NotificationAppLaunchDetails? details = await _plugin
        .getNotificationAppLaunchDetails();
    final NotificationResponse? response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp != true ||
        response == null ||
        response.actionId != null) {
      return null;
    }
    return RingPayload.decode(response.payload);
  }

  // Cancels the rings, booked or showing, of [payload]'s occurrence: the
  // same item and due time, any lead (Rules: Done details).
  Future<void> cancelOccurrence(RingPayload payload) async {
    await _init();
    bool same(String? raw) {
      final RingPayload? other = RingPayload.decode(raw);
      return other != null &&
          other.listId == payload.listId &&
          other.itemId == payload.itemId &&
          other.dueMs == payload.dueMs;
    }

    for (final PendingNotificationRequest request
        in await _plugin.pendingNotificationRequests()) {
      if (same(request.payload)) {
        await _plugin.cancel(id: request.id);
      }
    }
    for (final ActiveNotification active
        in await _android?.getActiveNotifications() ?? const []) {
      final int? id = active.id;
      if (id != null && same(active.payload)) {
        await _plugin.cancel(id: id);
      }
    }
  }

  // The background check about every 15 minutes (Q-93), while online;
  // Android may stretch it. Started again on each open, kept if running.
  @override
  Future<void> startBackgroundCheck() async {
    try {
      await Workmanager().initialize(reminderCheckDispatcher);
      await Workmanager().registerPeriodicTask(
        reminderCheckWork,
        reminderCheckWork,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } on Object catch (error) {
      debugPrint('Reminders: background check not started: $error');
    }
  }

  @override
  Future<void> stopBackgroundCheck() async {
    try {
      await Workmanager().cancelByUniqueName(reminderCheckWork);
    } on Object catch (error) {
      debugPrint('Reminders: background check not stopped: $error');
    }
  }

  @override
  Future<List<BookedRing>> booked() async {
    await _init();
    return [
      for (final PendingNotificationRequest request
          in await _plugin.pendingNotificationRequests())
        BookedRing(id: request.id, payload: RingPayload.decode(request.payload)),
    ];
  }

  @override
  Future<void> book(RingRequest request) async {
    await _init();
    await _plugin.zonedSchedule(
      id: request.id,
      title: request.text.title,
      body: request.text.body,
      scheduledDate: tz.TZDateTime.from(request.at.toUtc(), tz.UTC),
      payload: request.payload.encode(),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          color: AppColors.appBlue,
          // The body says the time; a day with no time has none to show.
          showWhen: false,
          actions: [
            AndroidNotificationAction(reminderDoneAction, request.text.done),
          ],
        ),
      ),
      androidScheduleMode: request.exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await _init();
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancelAll();
  }

  @override
  Future<RingPermissions> permissions() async {
    await _init();
    final AndroidFlutterLocalNotificationsPlugin? android = _android;
    return RingPermissions(
      notifications: await android?.areNotificationsEnabled() ?? false,
      exact: await android?.canScheduleExactNotifications() ?? false,
    );
  }

  @override
  Future<bool> requestNotifications() async {
    await _init();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> openExactAlarmSettings() async {
    await _init();
    await _android?.requestExactAlarmsPermission();
  }

  @override
  Future<void> openNotificationSettings() async {
    await _init();
    await _android?.openAppNotificationSettings();
  }
}
