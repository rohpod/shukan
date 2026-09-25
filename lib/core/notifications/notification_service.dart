import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tasks/data/task.dart';
import '../../features/tasks/domain/notification_id.dart';
import 'notification_date_utils.dart';

export '../../features/tasks/domain/notification_id.dart';
export 'notification_date_utils.dart';

/// Provider for the [FlutterLocalNotificationsPlugin] instance.
final flutterLocalNotificationsPluginProvider =
    Provider<FlutterLocalNotificationsPlugin>((ref) {
      return FlutterLocalNotificationsPlugin();
    });

/// Service responsible for initializing local notification channels,
/// requesting device permissions, and scheduling/cancelling task reminders.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;

  NotificationService(this._plugin);

  /// Initializes plugin settings for Android and iOS/macOS.
  ///
  /// On Web, this safely no-ops as background scheduled alarms are not supported.
  Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint(
        'NotificationService: Web platform detected. Scheduled notifications are disabled.',
      );
      return;
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings darwinSettings =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Reserved for handling notification click navigation if needed.
      },
    );
  }

  /// Requests notification and exact alarm permissions across supported platforms.
  ///
  /// - Android 13+ (API 33+): Requests POST_NOTIFICATIONS runtime permission.
  /// - Android 12+ (API 31+): Requests exact alarm permission if needed.
  /// - iOS: Requests alert, badge, and sound permissions.
  Future<void> requestPermissions() async {
    if (kIsWeb) return;

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImpl != null) {
      await androidImpl.requestNotificationsPermission();
      await androidImpl.requestExactAlarmsPermission();
    }

    final iosImpl = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosImpl != null) {
      await iosImpl.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  /// Schedules up to two notifications for the given [task]:
  /// 1. Main notification firing exactly at [task.dueDate] + [task.dueTime]
  ///    (or 9:00 AM local time if [task.dueTime] is omitted).
  /// 2. Early reminder notification firing at the due time minus [task.earlyReminderMinutes]
  ///    when [task.earlyReminderMinutes] > 0.
  ///
  /// - If [task.dueDate] is null, both notifications are cancelled.
  /// - If a fire time is strictly in the past, its corresponding notification is cancelled.
  /// - If [task.earlyReminderMinutes] <= 0, any early reminder notification is cancelled.
  /// - Uses [AndroidScheduleMode.exactAllowWhileIdle] on Android.
  Future<void> scheduleForTask(Task task, {DateTime? now}) async {
    if (kIsWeb) return;

    if (task.dueDate == null) {
      await cancelForTask(task.taskId);
      return;
    }

    final mainId = taskNotificationId(task.taskId);
    final earlyId = taskEarlyReminderNotificationId(task.taskId);

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'task_reminders_channel',
          'Task Reminders',
          channelDescription:
              'Notifications for scheduled task due dates and reminders',
          importance: Importance.high,
          priority: Priority.high,
        );

    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    // 1. Schedule or cancel main notification (due date + time)
    final mainFireTime = computeTaskFireTime(
      dueDate: task.dueDate,
      dueTime: task.dueTime,
      now: now,
    );

    if (mainFireTime != null) {
      await _plugin.zonedSchedule(
        id: mainId,
        title: task.title,
        body: task.notes.isNotEmpty ? task.notes : null,
        scheduledDate: mainFireTime,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: task.taskId,
      );
    } else {
      await _plugin.cancel(id: mainId);
    }

    // 2. Schedule or cancel early reminder notification
    if (task.earlyReminderMinutes > 0) {
      final earlyFireTime = computeEarlyReminderFireTime(
        dueDate: task.dueDate,
        dueTime: task.dueTime,
        earlyReminderMinutes: task.earlyReminderMinutes,
        now: now,
      );

      if (earlyFireTime != null) {
        await _plugin.zonedSchedule(
          id: earlyId,
          title: 'Upcoming: ${task.title}',
          body: task.notes.isNotEmpty ? task.notes : null,
          scheduledDate: earlyFireTime,
          notificationDetails: notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: task.taskId,
        );
      } else {
        await _plugin.cancel(id: earlyId);
      }
    } else {
      await _plugin.cancel(id: earlyId);
    }
  }

  /// Cancels both the main and early-reminder scheduled notifications for [taskId].
  Future<void> cancelForTask(String taskId) async {
    if (kIsWeb) return;
    await _plugin.cancel(id: taskNotificationId(taskId));
    await _plugin.cancel(id: taskEarlyReminderNotificationId(taskId));
  }
}

/// Provider exposing the [NotificationService] instance.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final plugin = ref.watch(flutterLocalNotificationsPluginProvider);
  return NotificationService(plugin);
});
