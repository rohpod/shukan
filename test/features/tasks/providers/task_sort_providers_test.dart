import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/features/auth/providers/auth_providers.dart';
import 'package:shukan/features/tasks/data/task_repository.dart';
import 'package:shukan/features/tasks/domain/task_sort_options.dart';
import 'package:shukan/features/tasks/providers/task_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late TaskRepository taskRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeFirestore = FakeFirebaseFirestore();
    taskRepo = TaskRepository(fakeFirestore);
  });

  group('TaskSortModeNotifier & persistence', () {
    test('defaults to TaskSortOption.manual when no pref saved', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final sortMode = container.read(taskSortModeProvider('list-1'));
      expect(sortMode, equals(TaskSortOption.manual));
    });

    test('persists selected sort mode to SharedPreferences under task_sort_mode_<viewKey>', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container
          .read(taskSortModeProvider('list-1').notifier)
          .setSortMode(TaskSortOption.dueDate);

      expect(
        container.read(taskSortModeProvider('list-1')),
        equals(TaskSortOption.dueDate),
      );
      expect(prefs.getString('task_sort_mode_list-1'), equals('dueDate'));
    });

    test('different viewKeys maintain independent sort modes', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container
          .read(taskSortModeProvider('list-A').notifier)
          .setSortMode(TaskSortOption.priority);

      await container
          .read(taskSortModeProvider('list-B').notifier)
          .setSortMode(TaskSortOption.dueDate);

      expect(
        container.read(taskSortModeProvider('list-A')),
        equals(TaskSortOption.priority),
      );
      expect(
        container.read(taskSortModeProvider('list-B')),
        equals(TaskSortOption.dueDate),
      );
      expect(
        container.read(taskSortModeProvider('today')),
        equals(TaskSortOption.manual),
      );
    });

    test(
      'loads saved sort mode from SharedPreferences on initialization',
      () async {
        SharedPreferences.setMockInitialValues({
          'task_sort_mode_today': 'priority',
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        final sortMode = container.read(taskSortModeProvider('today'));
        expect(sortMode, equals(TaskSortOption.priority));
      },
    );
  });

  group('sortedTasksForListProvider', () {
    test('sorts tasks based on list-specific sort mode', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUidProvider.overrideWithValue('u1'),
          taskRepositoryProvider.overrideWithValue(taskRepo),
        ],
      );
      addTearDown(container.dispose);

      // Create tasks
      await fakeFirestore.collection('lists').doc('l1').set({
        'listId': 'l1',
        'uid': 'u1',
        'name': 'List 1',
      });
      await fakeFirestore.collection('tasks').doc('t1').set({
        'taskId': 't1',
        'uid': 'u1',
        'listId': 'l1',
        'title': 'Task 1',
        'priority': 'low',
        'order': 100.0,
        'dueDate': null,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'completedAt': null,
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('t2').set({
        'taskId': 't2',
        'uid': 'u1',
        'listId': 'l1',
        'title': 'Task 2',
        'priority': 'high',
        'order': 200.0,
        'dueDate': null,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
        'completedAt': null,
        'deletedAt': null,
      });

      // Default: manual sort (t1 order 100 < t2 order 200)
      container.listen(sortedTasksForListProvider('l1'), (_, _) {});
      await pumpEventQueue();
      final initialTasks = container
          .read(sortedTasksForListProvider('l1'))
          .value!;
      expect(initialTasks.map((t) => t.taskId).toList(), equals(['t1', 't2']));

      // Change sort to priority (high > low -> t2, t1)
      await container
          .read(taskSortModeProvider('l1').notifier)
          .setSortMode(TaskSortOption.priority);
      await pumpEventQueue();

      final priorityTasks = container
          .read(sortedTasksForListProvider('l1'))
          .value!;
      expect(priorityTasks.map((t) => t.taskId).toList(), equals(['t2', 't1']));
    });
  });

  group('taskOrderBackfillProvider', () {
    test(
      'backfills order chronologically by createdAt and sets pref key',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            currentUidProvider.overrideWithValue('u1'),
            taskRepositoryProvider.overrideWithValue(taskRepo),
          ],
        );
        addTearDown(container.dispose);

        // Add two tasks with order 0.0 and different createdAt
        await fakeFirestore.collection('tasks').doc('t-old').set({
          'taskId': 't-old',
          'uid': 'u1',
          'listId': 'l1',
          'title': 'Old Task',
          'order': 0.0,
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('t-new').set({
          'taskId': 't-new',
          'uid': 'u1',
          'listId': 'l1',
          'title': 'New Task',
          'order': 0.0,
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'deletedAt': null,
        });

        await container.read(taskOrderBackfillProvider.future);

        expect(prefs.getBool('tasks_order_backfilled_u1'), isTrue);

        final docOld = await fakeFirestore
            .collection('tasks')
            .doc('t-old')
            .get();
        final docNew = await fakeFirestore
            .collection('tasks')
            .doc('t-new')
            .get();

        expect(docOld.data()!['order'], equals(1000.0));
        expect(docNew.data()!['order'], equals(2000.0));
      },
    );
  });
}
