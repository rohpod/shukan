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

  /// Schedules a notification for the given [task].
  ///
  /// - If [task.dueDate] is null or the fire time is in the past, any existing
  ///   notification for [task.taskId] is cancelled.
  /// - If [task.dueTime] is omitted, defaults to 9:00 AM local time.
  /// - Subtracts [task.earlyReminderMinutes] from the scheduled time.
  /// - Uses [AndroidScheduleMode.exactAllowWhileIdle] on Android.
  Future<void> scheduleForTask(Task task, {DateTime? now}) async {
    if (kIsWeb) return;

    if (task.dueDate == null) {
      await cancelForTask(task.taskId);
      return;
    }

    final fireTime = computeTaskFireTime(
      dueDate: task.dueDate,
      dueTime: task.dueTime,
      earlyReminderMinutes: task.earlyReminderMinutes,
      now: now,
    );

    if (fireTime == null) {
      // Fire time is either missing or in the past: cancel any pending reminder.
      await cancelForTask(task.taskId);
      return;
    }

    final id = taskNotificationId(task.taskId);

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

    await _plugin.zonedSchedule(
      id: id,
      title: task.title,
      body: task.notes.isNotEmpty ? task.notes : null,
      scheduledDate: fireTime,
      notificationDetails: notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: task.taskId,
    );
  }

  /// Cancels any scheduled notification for [taskId].
  Future<void> cancelForTask(String taskId) async {
    if (kIsWeb) return;
    final id = taskNotificationId(taskId);
    await _plugin.cancel(id: id);
  }
}

/// Provider exposing the [NotificationService] instance.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final plugin = ref.watch(flutterLocalNotificationsPluginProvider);
  return NotificationService(plugin);
});
