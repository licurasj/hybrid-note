import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../app_colors.dart';
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

  Future<void> _init() => _ready ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(smallIcon),
        ),
      )
      .then((_) {});

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
