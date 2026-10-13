import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tasks/data/task.dart';
import '../../features/tasks/domain/notification_id.dart';
import 'notification_date_utils.dart';
import 'web_reminder_logic.dart';

export '../../features/tasks/domain/notification_id.dart';
export 'notification_date_utils.dart';
export 'web_reminder_logic.dart';

/// The result of requesting web notification permission.
enum WebPermissionResult { granted, denied, dismissed, notWeb }

/// Provider for the [FlutterLocalNotificationsPlugin] instance.
final flutterLocalNotificationsPluginProvider =
    Provider<FlutterLocalNotificationsPlugin>((ref) {
      return FlutterLocalNotificationsPlugin();
    });

/// Service responsible for initializing local notification channels,
/// requesting device permissions, and scheduling/cancelling task reminders.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;
  final bool _isWeb;

  NotificationService(this._plugin, {bool? isWeb}) : _isWeb = isWeb ?? kIsWeb;

  /// Initializes plugin settings for Android and iOS/macOS, as well as Web.
  ///
  /// On Web, registers the service worker needed for displaying web notifications.
  Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings darwinSettings =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    final InitializationSettings initSettings = _isWeb
        ? const InitializationSettings(web: WebInitializationSettings())
        : const InitializationSettings(
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
    if (_isWeb) return;

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
    if (_isWeb) return;

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
    if (_isWeb) return;
    await _plugin.cancel(id: taskNotificationId(taskId));
    await _plugin.cancel(id: taskEarlyReminderNotificationId(taskId));
  }

  /// Shows a reminder notification in the browser on web.
  ///
  /// - id = taskNotificationId for due, taskEarlyReminderNotificationId for early.
  /// - title = task.title for due, 'Upcoming: ${task.title}' for early.
  /// - body = task.notes when non-empty.
  ///
  /// Returns `true` if shown, or `false` on non-web or if a StateError occurs.
  Future<bool> showWebReminder(WebReminder r) async {
    if (!_isWeb) return false;

    final id = r.kind == WebReminderKind.due
        ? taskNotificationId(r.task.taskId)
        : taskEarlyReminderNotificationId(r.task.taskId);
    final title = r.kind == WebReminderKind.due
        ? r.task.title
        : 'Upcoming: ${r.task.title}';
    final body = r.task.notes.isNotEmpty ? r.task.notes : null;

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: r.task.taskId,
      );
      return true;
    } on StateError catch (e) {
      debugPrint('NotificationService.showWebReminder StateError: $e');
      return false;
    } catch (e) {
      debugPrint('NotificationService.showWebReminder error: $e');
      return false;
    }
  }

  /// Returns true if web notification permission is currently granted.
  bool get webNotificationsGranted {
    if (!_isWeb) return false;
    final webPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          WebFlutterLocalNotificationsPlugin
        >();
    return webPlugin?.permissionStatus == WebNotificationPermission.granted;
  }

  /// Requests notification permission on web if undetermined/default.
  ///
  /// Returns [WebPermissionResult.notWeb] if not running on web.
  /// Returns [WebPermissionResult.granted] or [WebPermissionResult.denied] without
  /// prompting if the permission has already been determined.
  Future<WebPermissionResult> requestWebPermissionIfNeeded() async {
    if (!_isWeb) return WebPermissionResult.notWeb;

    final webPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          WebFlutterLocalNotificationsPlugin
        >();
    if (webPlugin == null) return WebPermissionResult.denied;

    if (webPlugin.permissionStatus == WebNotificationPermission.granted) {
      return WebPermissionResult.granted;
    }
    if (webPlugin.permissionStatus == WebNotificationPermission.denied) {
      return WebPermissionResult.denied;
    }

    final granted = await webPlugin.requestNotificationsPermission();
    if (granted == true ||
        webPlugin.permissionStatus == WebNotificationPermission.granted) {
      return WebPermissionResult.granted;
    }
    if (webPlugin.permissionStatus == WebNotificationPermission.denied) {
      return WebPermissionResult.denied;
    }
    return WebPermissionResult.dismissed;
  }
}

/// Provider exposing the [NotificationService] instance.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final plugin = ref.watch(flutterLocalNotificationsPluginProvider);
  return NotificationService(plugin);
});
