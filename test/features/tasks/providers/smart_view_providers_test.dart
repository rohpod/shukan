import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/providers/auth_providers.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/domain/smart_view_models.dart';
import 'package:shukan/features/tasks/domain/task_priority_filter.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  const uid = 'smart-user-123';
  const listId = 'inbox-1';

  setUp(() {
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'test@example.com'),
      signedIn: true,
    );
    fakeFirestore = FakeFirebaseFirestore();
  });

  ProviderContainer createContainer({DateTime? overrideDate}) {
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        if (overrideDate != null)
          currentDateProvider.overrideWithValue(overrideDate),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('SmartViewProviders', () {
    test('today view returns only tasks due on today local date', () async {
      final today = DateTime(2026, 10, 14, 10, 0); // Wednesday
      final container = createContainer(overrideDate: today);

      // Task 1: due today (active)
      await fakeFirestore.collection('tasks').doc('t-today').set({
        'taskId': 't-today',
        'uid': uid,
        'listId': listId,
        'title': 'Due Today',
        'dueDate': Timestamp.fromDate(DateTime(2026, 10, 14, 15, 0)),
        'deletedAt': null,
        'completedAt': null,
      });

      // Task 2: due tomorrow
      await fakeFirestore.collection('tasks').doc('t-tomorrow').set({
        'taskId': 't-tomorrow',
        'uid': uid,
        'listId': listId,
        'title': 'Due Tomorrow',
        'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15, 9, 0)),
        'deletedAt': null,
        'completedAt': null,
      });

      final emitted = <List<Task>>[];
      container.listen<AsyncValue<List<Task>>>(
        smartViewTasksProvider(SmartViewType.today),
        (_, next) {
          if (next.hasValue) emitted.add(next.value!);
        },
        fireImmediately: true,
      );

      await pumpEventQueue();

      expect(emitted.isNotEmpty, isTrue);
      expect(emitted.last.length, equals(1));
      expect(emitted.last.first.taskId, equals('t-today'));
    });

    test('thisWeek view returns all tasks from Monday to Sunday', () async {
      final wednesday = DateTime(2026, 10, 14, 10, 0);
      final container = createContainer(overrideDate: wednesday);

      // Task on Thursday (in week)
      await fakeFirestore.collection('tasks').doc('t-thurs').set({
        'taskId': 't-thurs',
        'uid': uid,
        'listId': listId,
        'title': 'Thursday Task',
        'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15, 11, 0)),
        'deletedAt': null,
        'completedAt': null,
      });

      // Task on Saturday (in week)
      await fakeFirestore.collection('tasks').doc('t-sat').set({
        'taskId': 't-sat',
        'uid': uid,
        'listId': listId,
        'title': 'Saturday Task',
        'dueDate': Timestamp.fromDate(DateTime(2026, 10, 17, 14, 0)),
        'deletedAt': null,
        'completedAt': null,
      });

      // Task next Tuesday (out of week completely)
      await fakeFirestore.collection('tasks').doc('t-next-week').set({
        'taskId': 't-next-week',
        'uid': uid,
        'listId': listId,
        'title': 'Next Week Task',
        'dueDate': Timestamp.fromDate(DateTime(2026, 10, 20, 9, 0)),
        'deletedAt': null,
        'completedAt': null,
      });

      final emitted = <List<Task>>[];
      container.listen<AsyncValue<List<Task>>>(
        smartViewTasksProvider(SmartViewType.thisWeek),
        (_, next) {
          if (next.hasValue) emitted.add(next.value!);
        },
        fireImmediately: true,
      );

      await pumpEventQueue();

      expect(
        emitted.last.map((t) => t.taskId).toSet(),
        equals({'t-thurs', 't-sat'}),
      );
    });

    test(
      'today view includes overdue incomplete tasks ordered chronologically',
      () async {
        final today = DateTime(2026, 10, 14, 10, 0);
        final container = createContainer(overrideDate: today);

        // Overdue task 1 (yesterday)
        await fakeFirestore.collection('tasks').doc('t-overdue-1').set({
          'taskId': 't-overdue-1',
          'uid': uid,
          'listId': listId,
          'title': 'Overdue Yesterday',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 13, 15, 0)),
          'deletedAt': null,
          'completedAt': null,
        });

        // Overdue task 2 (2 days ago)
        await fakeFirestore.collection('tasks').doc('t-overdue-2').set({
          'taskId': 't-overdue-2',
          'uid': uid,
          'listId': listId,
          'title': 'Overdue 2 Days Ago',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 12, 10, 0)),
          'deletedAt': null,
          'completedAt': null,
        });

        // Task due today
        await fakeFirestore.collection('tasks').doc('t-today').set({
          'taskId': 't-today',
          'uid': uid,
          'listId': listId,
          'title': 'Due Today',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 14, 11, 0)),
          'deletedAt': null,
          'completedAt': null,
        });

        final emitted = <List<Task>>[];
        container.listen<AsyncValue<List<Task>>>(
          smartViewTasksProvider(SmartViewType.today),
          (_, next) {
            if (next.hasValue) emitted.add(next.value!);
          },
          fireImmediately: true,
        );

        await pumpEventQueue();

        // Sorted chronologically: oldest overdue first, then today's tasks
        expect(
          emitted.last.map((t) => t.taskId).toList(),
          equals(['t-overdue-2', 't-overdue-1', 't-today']),
        );
      },
    );

    test(
      'today view drops completed overdue tasks across all filters',
      () async {
        final today = DateTime(2026, 10, 14, 10, 0);
        final container = createContainer(overrideDate: today);

        // Incomplete overdue task
        await fakeFirestore.collection('tasks').doc('t-overdue-inc').set({
          'taskId': 't-overdue-inc',
          'uid': uid,
          'listId': listId,
          'title': 'Overdue Incomplete',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 12, 10, 0)),
          'deletedAt': null,
          'completedAt': null,
        });

        // Completed overdue task (must NEVER be included in Today view)
        await fakeFirestore.collection('tasks').doc('t-overdue-comp').set({
          'taskId': 't-overdue-comp',
          'uid': uid,
          'listId': listId,
          'title': 'Overdue Completed',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 12, 12, 0)),
          'deletedAt': null,
          'completedAt': Timestamp.now(),
        });

        // Today completed task
        await fakeFirestore.collection('tasks').doc('t-today-comp').set({
          'taskId': 't-today-comp',
          'uid': uid,
          'listId': listId,
          'title': 'Today Completed',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 14, 14, 0)),
          'deletedAt': null,
          'completedAt': Timestamp.now(),
        });

        final emitted = <List<Task>>[];
        container.listen<AsyncValue<List<Task>>>(
          smartViewTasksProvider(SmartViewType.today),
          (_, next) {
            if (next.hasValue) emitted.add(next.value!);
          },
          fireImmediately: true,
        );

        await pumpEventQueue();

        // 1. Incomplete mode (default, showCompleted == false): only t-overdue-inc
        expect(
          emitted.last.map((t) => t.taskId).toList(),
          equals(['t-overdue-inc']),
        );

        // 2. Show completed == true: t-overdue-inc and t-today-comp (overdue completed is excluded)
        await container
            .read(showCompletedTasksProvider(SmartViewType.today.name).notifier)
            .setShowCompleted(true);
        await pumpEventQueue();

        expect(
          emitted.last.map((t) => t.taskId).toSet(),
          equals({'t-overdue-inc', 't-today-comp'}),
        );
      },
    );

    test('show completed toggle hides and shows completed tasks', () async {
      final today = DateTime(2026, 10, 14, 10, 0);
      final container = createContainer(overrideDate: today);

      // Incomplete task due today
      await fakeFirestore.collection('tasks').doc('t-inc').set({
        'taskId': 't-inc',
        'uid': uid,
        'listId': listId,
        'title': 'Incomplete',
        'dueDate': Timestamp.fromDate(DateTime(2026, 10, 14, 12, 0)),
        'deletedAt': null,
        'completedAt': null,
      });

      // Completed task due today
      await fakeFirestore.collection('tasks').doc('t-comp').set({
        'taskId': 't-comp',
        'uid': uid,
        'listId': listId,
        'title': 'Completed',
        'dueDate': Timestamp.fromDate(DateTime(2026, 10, 14, 14, 0)),
        'deletedAt': null,
        'completedAt': Timestamp.now(),
      });

      final emitted = <List<Task>>[];
      container.listen<AsyncValue<List<Task>>>(
        smartViewTasksProvider(SmartViewType.today),
        (_, next) {
          if (next.hasValue) emitted.add(next.value!);
        },
        fireImmediately: true,
      );

      await pumpEventQueue();

      // 1. Default (showCompleted == false) is incomplete only
      expect(emitted.last.map((t) => t.taskId).toList(), equals(['t-inc']));

      // 2. Toggle to Show completed
      await container
          .read(showCompletedTasksProvider(SmartViewType.today.name).notifier)
          .setShowCompleted(true);

      await pumpEventQueue();

      expect(
        emitted.last.map((t) => t.taskId).toSet(),
        equals({'t-inc', 't-comp'}),
      );

      // 3. Toggle back to hide completed
      await container
          .read(showCompletedTasksProvider(SmartViewType.today.name).notifier)
          .setShowCompleted(false);

      await pumpEventQueue();

      expect(emitted.last.map((t) => t.taskId).toList(), equals(['t-inc']));
    });

    test(
      'scheduled view returns all tasks with dueDate sorted chronologically',
      () async {
        final container = createContainer();

        await fakeFirestore.collection('tasks').doc('s1').set({
          'taskId': 's1',
          'uid': uid,
          'listId': listId,
          'title': 'Later in month',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 25)),
          'dueTime': '10:00',
          'deletedAt': null,
          'completedAt': null,
        });

        await fakeFirestore.collection('tasks').doc('s2').set({
          'taskId': 's2',
          'uid': uid,
          'listId': listId,
          'title': 'Tomorrow',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
          'dueTime': '15:00',
          'deletedAt': null,
          'completedAt': null,
        });

        await fakeFirestore.collection('tasks').doc('s3').set({
          'taskId': 's3',
          'uid': uid,
          'listId': listId,
          'title': 'Tomorrow earlier',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
          'dueTime': '08:30',
          'deletedAt': null,
          'completedAt': null,
        });

        final emitted = <List<Task>>[];
        container.listen<AsyncValue<List<Task>>>(
          smartViewTasksProvider(SmartViewType.scheduled),
          (_, next) {
            if (next.hasValue) emitted.add(next.value!);
          },
          fireImmediately: true,
        );

        await pumpEventQueue();

        expect(emitted.last.map((t) => t.taskId).toList(), ['s3', 's2', 's1']);
      },
    );

    test('smartViewCountProvider returns accurate count', () async {
      final today = DateTime(2026, 10, 14, 10, 0);
      final container = createContainer(overrideDate: today);

      final counts = <int>[];
      container.listen<int>(
        smartViewCountProvider(SmartViewType.today),
        (_, next) => counts.add(next),
        fireImmediately: true,
      );

      await pumpEventQueue();
      expect(counts.last, equals(0));

      await fakeFirestore.collection('tasks').doc('cnt-1').set({
        'taskId': 'cnt-1',
        'uid': uid,
        'listId': listId,
        'title': 'Count 1',
        'dueDate': Timestamp.fromDate(DateTime(2026, 10, 14, 12, 0)),
        'deletedAt': null,
        'completedAt': null,
      });

      await pumpEventQueue();
      expect(counts.last, equals(1));
    });

    test(
      'smartViewTasksProvider transitions to AsyncError on first event timeout',
      () async {
        final controller = StreamController<List<Task>>();
        addTearDown(controller.close);

        final container = ProviderContainer(
          overrides: [
            currentUidProvider.overrideWithValue(uid),
            smartViewTimeoutProvider.overrideWithValue(
              const Duration(milliseconds: 50),
            ),
            smartViewTasksProvider(SmartViewType.today).overrideWith(
              (ref) => controller.stream.timeoutFirstEvent(
                ref.watch(smartViewTimeoutProvider),
                message: 'This is taking longer than expected — check your connection or try again',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        AsyncValue<List<Task>>? state;
        container.listen<AsyncValue<List<Task>>>(
          smartViewTasksProvider(SmartViewType.today),
          (_, next) => state = next,
          fireImmediately: true,
        );

        expect(state?.isLoading, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(state?.hasError, isTrue);
        expect(state?.error, isA<TimeoutException>());
        expect(
          (state?.error as TimeoutException).message,
          equals(
            'This is taking longer than expected — check your connection or try again',
          ),
        );
      },
    );

    test(
      'smartViewTasksProvider does not timeout after first event is received',
      () async {
        final controller = StreamController<List<Task>>();
        addTearDown(controller.close);

        final container = ProviderContainer(
          overrides: [
            currentUidProvider.overrideWithValue(uid),
            smartViewTimeoutProvider.overrideWithValue(
              const Duration(milliseconds: 50),
            ),
            smartViewTasksProvider(SmartViewType.today).overrideWith(
              (ref) => controller.stream.timeoutFirstEvent(
                ref.watch(smartViewTimeoutProvider),
                message: 'This is taking longer than expected — check your connection or try again',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final states = <AsyncValue<List<Task>>>[];
        container.listen<AsyncValue<List<Task>>>(
          smartViewTasksProvider(SmartViewType.today),
          (_, next) => states.add(next),
          fireImmediately: true,
        );

        controller.add(<Task>[]);
        await pumpEventQueue();

        expect(states.last.hasValue, isTrue);
        expect(states.last.value, isEmpty);

        // Wait past the timeout duration (100ms > 50ms)
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Provider should remain in data state without timing out
        expect(states.last.hasValue, isTrue);
        expect(states.last.hasError, isFalse);
      },
    );

    test('smartViewTasksProvider filters by priority when set', () async {
      final today = DateTime(2026, 10, 14, 10, 0);
      final container = createContainer(overrideDate: today);

      await fakeFirestore.collection('tasks').doc('t-high').set({
        'taskId': 't-high',
        'uid': uid,
        'listId': listId,
        'title': 'High Task',
        'priority': 'high',
        'dueDate': Timestamp.fromDate(DateTime(2026, 10, 14, 12, 0)),
        'deletedAt': null,
        'completedAt': null,
      });

      await fakeFirestore.collection('tasks').doc('t-low').set({
        'taskId': 't-low',
        'uid': uid,
        'listId': listId,
        'title': 'Low Task',
        'priority': 'low',
        'dueDate': Timestamp.fromDate(DateTime(2026, 10, 14, 13, 0)),
        'deletedAt': null,
        'completedAt': null,
      });

      final emitted = <List<Task>>[];
      container.listen<AsyncValue<List<Task>>>(
        smartViewTasksProvider(SmartViewType.today),
        (_, next) {
          if (next.hasValue) emitted.add(next.value!);
        },
        fireImmediately: true,
      );

      await pumpEventQueue();

      // Default (All): both high and low emitted
      expect(
        emitted.last.map((t) => t.taskId).toSet(),
        equals({'t-high', 't-low'}),
      );

      // Set priority filter to high
      await container
          .read(taskPriorityFilterProvider(SmartViewType.today.name).notifier)
          .setFilter(TaskPriorityFilter.high);

      await pumpEventQueue();

      expect(emitted.last.map((t) => t.taskId).toList(), equals(['t-high']));
    });
  });
}
