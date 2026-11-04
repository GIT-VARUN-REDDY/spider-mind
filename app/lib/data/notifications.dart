import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../logic/notification_plan.dart';

/// On-device reminders: the primary, offline-capable delivery layer.
/// The set of notifications is always recomputed from [planNotifications]
/// and swapped in atomically (cancel all, schedule all).
/// Represents a notification action or tap response.
class NotificationEvent {
  const NotificationEvent({this.actionId, this.payload});
  final String? actionId;
  final String? payload;
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final StreamController<String> _taps = StreamController.broadcast();
  final StreamController<NotificationEvent> _events = StreamController.broadcast();
  bool _ready = false;
  bool permissionGranted = false;
  bool exactAllowed = true;
  String? launchPayload;

  Stream<String> get taps => _taps.stream;
  Stream<NotificationEvent> get events => _events.stream;
  bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static const _channel = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Reminders and due dates for your threads',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    actions: [
      AndroidNotificationAction('action_done', 'Done', showsUserInterface: true),
      AndroidNotificationAction('action_snooze', 'Snooze 1h', showsUserInterface: false),
    ],
  );
  static const _details = NotificationDetails(
    android: _channel,
    iOS: DarwinNotificationDetails(categoryIdentifier: 'reminders'),
  );

  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    await _plugin.initialize(
      InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              'reminders',
              actions: [
                DarwinNotificationAction.plain('action_done', 'Done'),
                DarwinNotificationAction.plain('action_snooze', 'Snooze 1h'),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null && p.isNotEmpty) _taps.add(p);
        _events.add(NotificationEvent(actionId: r.actionId, payload: r.payload));
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) launchPayload = launch?.notificationResponse?.payload;
    _ready = true;
    await refreshHealth();
  }

  Future<void> refreshHealth() async {
    if (!_ready) return;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      permissionGranted = await android.areNotificationsEnabled() ?? false;
      exactAllowed = await android.canScheduleExactNotifications() ?? false;
      return;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final p = await ios.checkPermissions();
      permissionGranted = p?.isEnabled ?? false;
    }
  }

  Future<void> requestPermission() async {
    if (!_ready) return;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
    await refreshHealth();
  }

  Future<void> openExactAlarmSettings() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
    await refreshHealth();
  }

  Future<void> apply(List<PlannedNotification> plan) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final mode = exactAllowed ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
      for (final n in plan) {
        await _plugin.zonedSchedule(
          n.id,
          n.title,
          n.body,
          tz.TZDateTime.from(n.at, tz.local),
          _details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: n.daily ? DateTimeComponents.time : null,
          payload: n.payload,
        );
      }
    } catch (e) {
      debugPrint('notification scheduling failed: $e');
    }
  }

  Future<void> showNow(String title, String body, {String payload = ''}) async {
    if (!_ready) return;
    await _plugin.show(notificationIdFor('now:${DateTime.now().microsecondsSinceEpoch}'), title, body, _details, payload: payload);
  }

  Future<void> cancelAll() async {
    if (_ready) await _plugin.cancelAll();
  }
}
