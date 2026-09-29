import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/providers/task_selection_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const listId = 'test-list-1';

  Task createTask(String id, {String title = 'Task'}) {
    return Task(taskId: id, uid: 'user-1', listId: listId, title: title);
  }

  group('TaskSelectionNotifier', () {
    test('initial state is empty set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(taskSelectionProvider(listId));
      expect(state, isEmpty);
    });

    test('toggle adds and removes task IDs', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(taskSelectionProvider(listId).notifier);

      notifier.toggle('task-1');
      expect(container.read(taskSelectionProvider(listId)), equals({'task-1'}));

      notifier.toggle('task-2');
      expect(
        container.read(taskSelectionProvider(listId)),
        equals({'task-1', 'task-2'}),
      );

      notifier.toggle('task-1');
      expect(container.read(taskSelectionProvider(listId)), equals({'task-2'}));

      notifier.toggle('task-2');
      expect(container.read(taskSelectionProvider(listId)), isEmpty);
    });

    test('retainOnly prunes unmentioned task IDs', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(taskSelectionProvider(listId).notifier);
      notifier.toggle('task-1');
      notifier.toggle('task-2');
      notifier.toggle('task-3');

      notifier.retainOnly({'task-2', 'task-4'});
      expect(container.read(taskSelectionProvider(listId)), equals({'task-2'}));

      // retainOnly with all present does not alter state
      notifier.retainOnly({'task-2'});
      expect(container.read(taskSelectionProvider(listId)), equals({'task-2'}));
    });

    test('clear empties selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(taskSelectionProvider(listId).notifier);
      notifier.toggle('task-1');
      notifier.toggle('task-2');
      expect(container.read(taskSelectionProvider(listId)), isNotEmpty);

      notifier.clear();
      expect(container.read(taskSelectionProvider(listId)), isEmpty);

      // Calling clear on already empty set does not error
      notifier.clear();
      expect(container.read(taskSelectionProvider(listId)), isEmpty);
    });

    test('maintains independent selection per listId', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(taskSelectionProvider('list-a').notifier).toggle('task-1');
      container.read(taskSelectionProvider('list-b').notifier).toggle('task-2');

      expect(
        container.read(taskSelectionProvider('list-a')),
        equals({'task-1'}),
      );
      expect(
        container.read(taskSelectionProvider('list-b')),
        equals({'task-2'}),
      );
    });

    test('state resets after autoDispose disposal', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Listen to keep provider alive
      final sub = container.listen(
        taskSelectionProvider(listId),
        (previous, next) {},
      );
      container.read(taskSelectionProvider(listId).notifier).toggle('task-1');
      expect(container.read(taskSelectionProvider(listId)), equals({'task-1'}));

      // Close subscription to trigger autoDispose
      sub.close();
      await Future<void>.delayed(Duration.zero);

      // Reading again reinitializes to empty
      expect(container.read(taskSelectionProvider(listId)), isEmpty);
    });
  });

  group('selectedTasksProvider', () {
    test('returns empty list when selection is empty', () {
      final task1 = createTask('t1', title: 'Task 1');
      final container = ProviderContainer(
        overrides: [
          sortedTasksForListProvider(listId)
              .overrideWithValue(AsyncData([task1])),
        ],
      );
      addTearDown(container.dispose);

      final selectedTasks = container.read(selectedTasksProvider(listId));
      expect(selectedTasks, isEmpty);
    });

    test('returns empty list while sortedTasksForListProvider is loading', () {
      final container = ProviderContainer(
        overrides: [
          sortedTasksForListProvider(listId)
              .overrideWithValue(const AsyncLoading()),
        ],
      );
      addTearDown(container.dispose);

      container.read(taskSelectionProvider(listId).notifier).toggle('t1');

      final selectedTasks = container.read(selectedTasksProvider(listId));
      expect(selectedTasks, isEmpty);
    });

    test('returns empty list when sortedTasksForListProvider has error', () {
      final container = ProviderContainer(
        overrides: [
          sortedTasksForListProvider(listId).overrideWithValue(
            AsyncError(Exception('Failed to load'), StackTrace.empty),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(taskSelectionProvider(listId).notifier).toggle('t1');

      final selectedTasks = container.read(selectedTasksProvider(listId));
      expect(selectedTasks, isEmpty);
    });

    test('returns selected tasks in displayed order', () {
      final task1 = createTask('t1', title: 'Task 1');
      final task2 = createTask('t2', title: 'Task 2');
      final task3 = createTask('t3', title: 'Task 3');
      final task4 = createTask('t4', title: 'Task 4');

      final container = ProviderContainer(
        overrides: [
          sortedTasksForListProvider(listId)
              .overrideWithValue(AsyncData([task1, task2, task3, task4])),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(taskSelectionProvider(listId).notifier);
      // Select out of display order: t3 first, then t1
      notifier.toggle('t3');
      notifier.toggle('t1');

      final selectedTasks = container.read(selectedTasksProvider(listId));
      // Display order must be preserved: t1 before t3
      expect(selectedTasks, equals([task1, task3]));
    });

    test('returns empty list when none of the selected tasks are visible', () {
      final task1 = createTask('t1', title: 'Task 1');
      final container = ProviderContainer(
        overrides: [
          sortedTasksForListProvider(listId)
              .overrideWithValue(AsyncData([task1])),
        ],
      );
      addTearDown(container.dispose);

      container.read(taskSelectionProvider(listId).notifier).toggle('t-hidden');

      final selectedTasks = container.read(selectedTasksProvider(listId));
      expect(selectedTasks, isEmpty);
    });
  });
}
