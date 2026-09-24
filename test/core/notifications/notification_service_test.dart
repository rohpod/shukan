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

    test('cancelForTask cancels using deterministic notification id', () async {
      const taskId = 'task-to-cancel-999';
      await service.cancelForTask(taskId);

      final expectedId = taskNotificationId(taskId);
      verify(() => mockPlugin.cancel(id: expectedId)).called(1);
    });
  });
}
