import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shukan/core/notifications/notification_service.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class MockFlutterLocalNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));

    registerFallbackValue(
      InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(tz.TZDateTime.now(tz.local));
    registerFallbackValue(AndroidScheduleMode.exactAllowWhileIdle);
  });

  late MockFlutterLocalNotificationsPlugin mockPlugin;
  late NotificationService service;

  setUp(() {
    mockPlugin = MockFlutterLocalNotificationsPlugin();
    service = NotificationService(mockPlugin);

    when(
      () => mockPlugin.initialize(
        settings: any(named: 'settings'),
        onDidReceiveNotificationResponse: any(
          named: 'onDidReceiveNotificationResponse',
        ),
      ),
    ).thenAnswer((_) async => true);

    when(
      () => mockPlugin.zonedSchedule(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        scheduledDate: any(named: 'scheduledDate'),
        notificationDetails: any(named: 'notificationDetails'),
        androidScheduleMode: any(named: 'androidScheduleMode'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async {});

    when(() => mockPlugin.cancel(id: any(named: 'id')))
        .thenAnswer((_) async {});
  });

  group('NotificationService', () {
    test('initialize configures plugin with platform settings', () async {
      await service.initialize();

      verify(
        () => mockPlugin.initialize(
          settings: any(named: 'settings'),
          onDidReceiveNotificationResponse: any(
            named: 'onDidReceiveNotificationResponse',
          ),
        ),
      ).called(1);
    });

    test('scheduleForTask with future dueDate schedules notification with correct id', () async {
      final task = Task(
        taskId: 'task-future-123',
        uid: 'user-1',
        listId: 'list-1',
        title: 'Submit Report',
        notes: 'Review numbers first',
        dueDate: DateTime.utc(2026, 12, 1),
        dueTime: '15:00',
      );

      final now = DateTime.utc(2026, 11, 30, 10, 0);
      await service.scheduleForTask(task, now: now);

      final expectedId = taskNotificationId(task.taskId);

      verify(
        () => mockPlugin.zonedSchedule(
          id: expectedId,
          title: 'Submit Report',
          body: 'Review numbers first',
          scheduledDate: any(named: 'scheduledDate'),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: 'task-future-123',
        ),
      ).called(1);
    });

    test(
      'scheduleForTask with null dueDate cancels any existing notification',
      () async {
        final task = Task(
          taskId: 'task-no-date',
          uid: 'user-1',
          listId: 'list-1',
          title: 'Task without due date',
          dueDate: null,
        );

        await service.scheduleForTask(task);

        final expectedId = taskNotificationId(task.taskId);
        verify(() => mockPlugin.cancel(id: expectedId)).called(1);
        verifyNever(
          () => mockPlugin.zonedSchedule(
            id: any(named: 'id'),
            scheduledDate: any(named: 'scheduledDate'),
            notificationDetails: any(named: 'notificationDetails'),
            androidScheduleMode: any(named: 'androidScheduleMode'),
          ),
        );
      },
    );

    test('scheduleForTask with past dueDate/dueTime cancels any existing notification', () async {
      final task = Task(
        taskId: 'task-past-123',
        uid: 'user-1',
        listId: 'list-1',
        title: 'Yesterday task',
        dueDate: DateTime.utc(2026, 5, 1),
        dueTime: '10:00',
      );

      final now = DateTime.utc(2026, 5, 2, 10, 0);
      await service.scheduleForTask(task, now: now);

      final expectedId = taskNotificationId(task.taskId);
      verify(() => mockPlugin.cancel(id: expectedId)).called(1);
      verifyNever(
        () => mockPlugin.zonedSchedule(
          id: any(named: 'id'),
          scheduledDate: any(named: 'scheduledDate'),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: any(named: 'androidScheduleMode'),
        ),
      );
    });

    test('cancelForTask cancels both main ID and early-reminder ID', () async {
      const taskId = 'task-to-cancel-999';
      await service.cancelForTask(taskId);

      final expectedMainId = taskNotificationId(taskId);
      final expectedEarlyId = taskEarlyReminderNotificationId(taskId);

      verify(() => mockPlugin.cancel(id: expectedMainId)).called(1);
      verify(() => mockPlugin.cancel(id: expectedEarlyId)).called(1);
    });

    test('scheduleForTask with earlyReminderMinutes > 0 schedules two notifications with distinct IDs and correct times', () async {
      final task = Task(
        taskId: 'task-dual-123',
        uid: 'user-1',
        listId: 'list-1',
        title: 'Team Standup',
        notes: 'Prepare notes',
        dueDate: DateTime.utc(2026, 12, 1),
        dueTime: '15:00',
        earlyReminderMinutes: 15,
      );

      final now = DateTime.utc(2026, 11, 30, 10, 0);
      await service.scheduleForTask(task, now: now);

      final expectedMainId = taskNotificationId(task.taskId);
      final expectedEarlyId = taskEarlyReminderNotificationId(task.taskId);

      // Verify main notification scheduled exactly at due time (15:00)
      verify(
        () => mockPlugin.zonedSchedule(
          id: expectedMainId,
          title: 'Team Standup',
          body: 'Prepare notes',
          scheduledDate: tz.TZDateTime(tz.local, 2026, 12, 1, 15, 0),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: 'task-dual-123',
        ),
      ).called(1);

      // Verify early reminder notification scheduled 15 minutes earlier (14:45)
      verify(
        () => mockPlugin.zonedSchedule(
          id: expectedEarlyId,
          title: 'Upcoming: Team Standup',
          body: 'Prepare notes',
          scheduledDate: tz.TZDateTime(tz.local, 2026, 12, 1, 14, 45),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: 'task-dual-123',
        ),
      ).called(1);
    });

    test('scheduleForTask with earlyReminderMinutes == 0 schedules only main notification and cancels early reminder ID', () async {
      final task = Task(
        taskId: 'task-single-123',
        uid: 'user-1',
        listId: 'list-1',
        title: 'Submit Expense',
        dueDate: DateTime.utc(2026, 12, 1),
        dueTime: '17:00',
        earlyReminderMinutes: 0,
      );

      final now = DateTime.utc(2026, 11, 30, 10, 0);
      await service.scheduleForTask(task, now: now);

      final expectedMainId = taskNotificationId(task.taskId);
      final expectedEarlyId = taskEarlyReminderNotificationId(task.taskId);

      verify(
        () => mockPlugin.zonedSchedule(
          id: expectedMainId,
          title: 'Submit Expense',
          body: null,
          scheduledDate: tz.TZDateTime(tz.local, 2026, 12, 1, 17, 0),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: 'task-single-123',
        ),
      ).called(1);

      verifyNever(
        () => mockPlugin.zonedSchedule(
          id: expectedEarlyId,
          title: any(named: 'title'),
          body: any(named: 'body'),
          scheduledDate: any(named: 'scheduledDate'),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: any(named: 'androidScheduleMode'),
          payload: any(named: 'payload'),
        ),
      );

      verify(() => mockPlugin.cancel(id: expectedEarlyId)).called(1);
    });

    test('earlyReminderMinutes changed from >0 to 0 on an update cancels the early-reminder ID', () async {
      final taskWithReminder = Task(
        taskId: 'task-update-reminder',
        uid: 'user-1',
        listId: 'list-1',
        title: 'Doctor Appointment',
        dueDate: DateTime.utc(2026, 12, 1),
        dueTime: '11:00',
        earlyReminderMinutes: 30,
      );
      final now = DateTime.utc(2026, 11, 30, 10, 0);
      await service.scheduleForTask(taskWithReminder, now: now);

      clearInteractions(mockPlugin);

      final taskWithoutReminder = taskWithReminder.copyWith(
        earlyReminderMinutes: 0,
      );
      await service.scheduleForTask(taskWithoutReminder, now: now);

      final expectedEarlyId = taskEarlyReminderNotificationId(
        taskWithReminder.taskId,
      );
      verify(() => mockPlugin.cancel(id: expectedEarlyId)).called(1);
    });

    test('regression guard: main notification fire time is unaffected by earlyReminderMinutes value', () async {
      final taskWithoutEarly = Task(
        taskId: 'task-regress-1',
        uid: 'user-1',
        listId: 'list-1',
        title: 'Pay Bill',
        dueDate: DateTime.utc(2026, 12, 1),
        dueTime: '17:00',
        earlyReminderMinutes: 0,
      );

      final taskWithEarly = Task(
        taskId: 'task-regress-2',
        uid: 'user-1',
        listId: 'list-1',
        title: 'Pay Bill',
        dueDate: DateTime.utc(2026, 12, 1),
        dueTime: '17:00',
        earlyReminderMinutes: 10,
      );

      final now = DateTime.utc(2026, 11, 30, 10, 0);

      await service.scheduleForTask(taskWithoutEarly, now: now);
      await service.scheduleForTask(taskWithEarly, now: now);

      final id1 = taskNotificationId(taskWithoutEarly.taskId);
      final id2 = taskNotificationId(taskWithEarly.taskId);

      final expectedFireTime = tz.TZDateTime(tz.local, 2026, 12, 1, 17, 0);

      verify(
        () => mockPlugin.zonedSchedule(
          id: id1,
          title: any(named: 'title'),
          body: any(named: 'body'),
          scheduledDate: expectedFireTime,
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: any(named: 'androidScheduleMode'),
          payload: any(named: 'payload'),
        ),
      ).called(1);

      verify(
        () => mockPlugin.zonedSchedule(
          id: id2,
          title: any(named: 'title'),
          body: any(named: 'body'),
          scheduledDate: expectedFireTime,
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: any(named: 'androidScheduleMode'),
          payload: any(named: 'payload'),
        ),
      ).called(1);
    });

    test('scheduleForTask when early reminder is in the past but main due time is in future', () async {
      final task = Task(
        taskId: 'task-partial-past',
        uid: 'user-1',
        listId: 'list-1',
        title: 'Late Reminder Task',
        dueDate: DateTime.utc(2026, 10, 15),
        dueTime: '10:00',
        earlyReminderMinutes: 30,
      );

      final now = DateTime.utc(2026, 10, 15, 9, 35);
      await service.scheduleForTask(task, now: now);

      final mainId = taskNotificationId(task.taskId);
      final earlyId = taskEarlyReminderNotificationId(task.taskId);

      verify(
        () => mockPlugin.zonedSchedule(
          id: mainId,
          title: 'Late Reminder Task',
          body: null,
          scheduledDate: tz.TZDateTime(tz.local, 2026, 10, 15, 10, 0),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: 'task-partial-past',
        ),
      ).called(1);

      verify(() => mockPlugin.cancel(id: earlyId)).called(1);
    });
  });
}
