import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/notifications/notification_service.dart';
import 'package:shukan/core/notifications/web_reminder_scheduler.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/providers/task_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

class MockNotificationService extends Mock implements NotificationService {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      WebReminder(
        task: const Task(
          taskId: 'fallback',
          uid: 'u',
          listId: 'l',
          title: 'fallback',
        ),
        kind: WebReminderKind.due,
        fireTime: DateTime(2026, 1, 1),
      ),
    );
  });

  group('WebReminderScheduler Tests', () {
    late MockNotificationService mockNotifService;
    late StreamController<List<Task>> taskStreamController;
    late DateTime fakeCurrentTime;
    late int chimeCallCount;
    late bool chimePlayResult;

    setUp(() {
      mockNotifService = MockNotificationService();
      taskStreamController = StreamController<List<Task>>.broadcast();
      fakeCurrentTime = DateTime(2026, 10, 15, 9, 50);
      chimeCallCount = 0;
      chimePlayResult = true;

      SharedPreferences.setMockInitialValues({});

      when(() => mockNotifService.showWebReminder(any()))
          .thenAnswer((_) async => true);
      when(() => mockNotifService.webNotificationsGranted).thenReturn(true);
    });

    tearDown(() {
      taskStreamController.close();
    });

    Widget createTestWidget({required SharedPreferences prefs, Widget? child}) {
      return ProviderScope(
        overrides: [
          isWebPlatformProvider.overrideWithValue(true),
          reminderClockProvider.overrideWithValue(() => fakeCurrentTime),
          notificationServiceProvider.overrideWithValue(mockNotifService),
          sharedPreferencesProvider.overrideWithValue(prefs),
          chimePlayerProvider.overrideWithValue(() {
            chimeCallCount++;
            return chimePlayResult;
          }),
          allTasksForCurrentUserProvider.overrideWith(
            (ref) => taskStreamController.stream,
          ),
        ],
        child: MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          home: Scaffold(
            body: WebReminderHost(child: child ?? const Text('App Content')),
          ),
        ),
      );
    }

    testWidgets(
      'a due reminder fires once (notification and chime) after a tick',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(createTestWidget(prefs: prefs));

        final task = Task(
          taskId: 't-due-1',
          uid: 'u1',
          listId: 'l1',
          title: 'Meeting at 10',
          dueDate: DateTime(2026, 10, 15),
          dueTime: '10:00',
        );

        // Start at 9:59:50
        fakeCurrentTime = DateTime(2026, 10, 15, 9, 59, 50);
        taskStreamController.add([task]);
        await tester.pump();

        verifyNever(() => mockNotifService.showWebReminder(any()));
        expect(chimeCallCount, 0);

        // Advance clock to 10:00:00 and advance timer by 20s
        fakeCurrentTime = DateTime(2026, 10, 15, 10, 0, 0);
        await tester.pump(const Duration(seconds: 20));

        verify(() => mockNotifService.showWebReminder(any())).called(1);
        expect(chimeCallCount, 1);

        // Advance another 20s: should NOT refire
        fakeCurrentTime = DateTime(2026, 10, 15, 10, 0, 20);
        await tester.pump(const Duration(seconds: 20));

        verifyNever(() => mockNotifService.showWebReminder(any()));
        expect(chimeCallCount, 1);
      },
    );

    testWidgets('the early reminder fires at its own time', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(createTestWidget(prefs: prefs));

      final task = Task(
        taskId: 't-early-1',
        uid: 'u1',
        listId: 'l1',
        title: 'Standup',
        dueDate: DateTime(2026, 10, 15),
        dueTime: '10:00',
        earlyReminderMinutes: 15, // early at 9:45
      );

      fakeCurrentTime = DateTime(2026, 10, 15, 9, 44, 50);
      taskStreamController.add([task]);
      await tester.pump();

      // Tick to 9:45:00
      fakeCurrentTime = DateTime(2026, 10, 15, 9, 45, 0);
      await tester.pump(const Duration(seconds: 20));

      // Early reminder fired
      final earlyCaptured = verify(
        () => mockNotifService.showWebReminder(captureAny()),
      ).captured;
      expect(earlyCaptured.length, 1);
      final earlyReminder = earlyCaptured.first as WebReminder;
      expect(earlyReminder.kind, WebReminderKind.early);
      expect(chimeCallCount, 1);

      // Advance between early and due: neither fires
      fakeCurrentTime = DateTime(2026, 10, 15, 9, 55, 0);
      await tester.pump(const Duration(seconds: 20));
      expect(chimeCallCount, 1);

      // Advance to 10:00:00: due reminder fires!
      fakeCurrentTime = DateTime(2026, 10, 15, 10, 0, 0);
      await tester.pump(const Duration(seconds: 20));

      final dueCaptured = verify(
        () => mockNotifService.showWebReminder(captureAny()),
      ).captured;
      expect(dueCaptured.length, 1);
      final dueReminder = dueCaptured.first as WebReminder;
      expect(dueReminder.kind, WebReminderKind.due);
      expect(chimeCallCount, 2);
    });

    testWidgets('a re-emitted stream does not refire', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(createTestWidget(prefs: prefs));

      final task = Task(
        taskId: 't-reemit',
        uid: 'u1',
        listId: 'l1',
        title: 'Re-emit test',
        dueDate: DateTime(2026, 10, 15),
        dueTime: '10:00',
      );

      fakeCurrentTime = DateTime(2026, 10, 15, 10, 0, 0);
      taskStreamController.add([task]);
      await tester.pump();

      verify(() => mockNotifService.showWebReminder(any())).called(1);
      expect(chimeCallCount, 1);

      // Re-emit identical task stream
      taskStreamController.add([task]);
      await tester.pump();

      verifyNever(() => mockNotifService.showWebReminder(any()));
      expect(chimeCallCount, 1);
    });

    testWidgets('completing a task before fireTime prevents it', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(createTestWidget(prefs: prefs));

      final activeTask = Task(
        taskId: 't-complete',
        uid: 'u1',
        listId: 'l1',
        title: 'Complete before fire',
        dueDate: DateTime(2026, 10, 15),
        dueTime: '10:00',
      );

      fakeCurrentTime = DateTime(2026, 10, 15, 9, 50, 0);
      taskStreamController.add([activeTask]);
      await tester.pump();

      // Complete the task before 10:00
      final completedTask = activeTask.copyWith(
        completedAt: DateTime(2026, 10, 15, 9, 55),
      );
      taskStreamController.add([completedTask]);
      await tester.pump();

      // Advance to 10:00:00
      fakeCurrentTime = DateTime(2026, 10, 15, 10, 0, 0);
      await tester.pump(const Duration(seconds: 20));

      verifyNever(() => mockNotifService.showWebReminder(any()));
      expect(chimeCallCount, 0);
    });

    testWidgets('an edited time fires at the new time', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(createTestWidget(prefs: prefs));

      final task = Task(
        taskId: 't-edit',
        uid: 'u1',
        listId: 'l1',
        title: 'Rescheduled meeting',
        dueDate: DateTime(2026, 10, 15),
        dueTime: '10:00',
      );

      // Fires at 10:00
      fakeCurrentTime = DateTime(2026, 10, 15, 10, 0, 0);
      taskStreamController.add([task]);
      await tester.pump();

      verify(() => mockNotifService.showWebReminder(any())).called(1);
      expect(chimeCallCount, 1);

      // User changes dueTime to 11:00
      final editedTask = task.copyWith(dueTime: '11:00');
      taskStreamController.add([editedTask]);
      await tester.pump();

      // At 10:30: does not fire
      fakeCurrentTime = DateTime(2026, 10, 15, 10, 30, 0);
      await tester.pump(const Duration(seconds: 20));
      verifyNever(() => mockNotifService.showWebReminder(any()));

      // At 11:00: fires at new time
      fakeCurrentTime = DateTime(2026, 10, 15, 11, 0, 0);
      await tester.pump(const Duration(seconds: 20));

      verify(() => mockNotifService.showWebReminder(any())).called(1);
      expect(chimeCallCount, 2);
    });

    testWidgets(
      'keys persist so a rebuilt scheduler within the grace window does not repeat',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        final task = Task(
          taskId: 't-persist',
          uid: 'u1',
          listId: 'l1',
          title: 'Persistent reminder',
          dueDate: DateTime(2026, 10, 15),
          dueTime: '10:00',
        );

        // Mount first scheduler
        await tester.pumpWidget(createTestWidget(prefs: prefs));
        fakeCurrentTime = DateTime(2026, 10, 15, 10, 0, 0);
        taskStreamController.add([task]);
        await tester.pump();

        verify(() => mockNotifService.showWebReminder(any())).called(1);
        expect(chimeCallCount, 1);

        // Verify keys are in SharedPreferences
        final savedKeys = prefs.getStringList('web_fired_reminders');
        expect(savedKeys, isNotNull);
        expect(savedKeys!.isNotEmpty, isTrue);

        // Dismount first scheduler
        await tester.pumpWidget(const SizedBox.shrink());

        // Create new stream controller for new widget tree
        final newStreamController = StreamController<List<Task>>.broadcast();

        // Rebuild scheduler at 10:00:30 (still within 2-minute grace window)
        fakeCurrentTime = DateTime(2026, 10, 15, 10, 0, 30);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              isWebPlatformProvider.overrideWithValue(true),
              reminderClockProvider.overrideWithValue(() => fakeCurrentTime),
              notificationServiceProvider.overrideWithValue(mockNotifService),
              sharedPreferencesProvider.overrideWithValue(prefs),
              chimePlayerProvider.overrideWithValue(() {
                chimeCallCount++;
                return chimePlayResult;
              }),
              allTasksForCurrentUserProvider.overrideWith(
                (ref) => newStreamController.stream,
              ),
            ],
            child: MaterialApp(
              scaffoldMessengerKey: rootScaffoldMessengerKey,
              home: const Scaffold(
                body: WebReminderHost(child: Text('Rebuilt App')),
              ),
            ),
          ),
        );

        newStreamController.add([task]);
        await tester.pump();
        await tester.pump(const Duration(seconds: 20));

        // Should NOT have fired again!
        verifyNever(() => mockNotifService.showWebReminder(any()));
        expect(chimeCallCount, 1);

        newStreamController.close();
      },
    );

    testWidgets('a reminder past the grace window does not fire', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(createTestWidget(prefs: prefs));

      final task = Task(
        taskId: 't-past-grace',
        uid: 'u1',
        listId: 'l1',
        title: 'Missed task',
        dueDate: DateTime(2026, 10, 15),
        dueTime: '10:00',
      );

      // Clock is at 10:05 (5 minutes after due time > 2 minutes grace)
      fakeCurrentTime = DateTime(2026, 10, 15, 10, 5, 0);
      taskStreamController.add([task]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 20));

      verifyNever(() => mockNotifService.showWebReminder(any()));
      expect(chimeCallCount, 0);
    });

    testWidgets('denied permission triggers the SnackBar fallback', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      when(() => mockNotifService.webNotificationsGranted).thenReturn(false);

      await tester.pumpWidget(createTestWidget(prefs: prefs));

      final task = Task(
        taskId: 't-snack-perm',
        uid: 'u1',
        listId: 'l1',
        title: 'Blocked Permission Task',
        dueDate: DateTime(2026, 10, 15),
        dueTime: '10:00',
      );

      fakeCurrentTime = DateTime(2026, 10, 15, 10, 0, 0);
      taskStreamController.add([task]);
      await tester.pump();

      // Check SnackBar appeared
      expect(find.text('Reminder: Blocked Permission Task'), findsOneWidget);
    });

    testWidgets(
      'a blocked chime triggers the SnackBar fallback when tab is visible',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        when(() => mockNotifService.webNotificationsGranted).thenReturn(true);
        chimePlayResult = false; // Chime returns false

        await tester.pumpWidget(createTestWidget(prefs: prefs));

        final task = Task(
          taskId: 't-snack-chime',
          uid: 'u1',
          listId: 'l1',
          title: 'Muted Chime Task',
          dueDate: DateTime(2026, 10, 15),
          dueTime: '10:00',
        );

        fakeCurrentTime = DateTime(2026, 10, 15, 10, 0, 0);
        taskStreamController.add([task]);
        await tester.pump();

        // SnackBar fallback triggered because chime failed while tab is visible
        expect(find.text('Reminder: Muted Chime Task'), findsOneWidget);
      },
    );

    testWidgets('sign-out clears the timer and state', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      late WebReminderScheduler capturedScheduler;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isWebPlatformProvider.overrideWithValue(true),
            reminderClockProvider.overrideWithValue(() => fakeCurrentTime),
            notificationServiceProvider.overrideWithValue(mockNotifService),
            sharedPreferencesProvider.overrideWithValue(prefs),
            chimePlayerProvider.overrideWithValue(() => true),
            allTasksForCurrentUserProvider.overrideWith(
              (ref) => taskStreamController.stream,
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              capturedScheduler = ref.watch(webReminderSchedulerProvider);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final task = Task(
        taskId: 't-signout',
        uid: 'u1',
        listId: 'l1',
        title: 'Task before signout',
        dueDate: DateTime(2026, 10, 15),
        dueTime: '10:00',
      );

      taskStreamController.add([task]);
      await tester.pump();

      // Timer should be active
      expect(capturedScheduler.activeTimer, isNotNull);
      expect(capturedScheduler.latestTasks.isNotEmpty, isTrue);

      // Sign-out: tasks stream emits empty list []
      taskStreamController.add([]);
      await tester.pump();

      // Timer and state are cleared
      expect(capturedScheduler.activeTimer, isNull);
      expect(capturedScheduler.latestTasks, isEmpty);
      expect(capturedScheduler.firedKeys, isEmpty);
    });
  });
}
