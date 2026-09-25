import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/providers/task_providers.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('overdueTaskCountProvider', () {
    test(
      'computes overdue count correctly from allTasksForCurrentUserProvider',
      () async {
        final now = DateTime.now();
        final yesterday = now.subtract(const Duration(days: 1));
        final tomorrow = now.add(const Duration(days: 1));

        final tasks = [
          // 1. Overdue task (yesterday, not completed, not deleted) -> COUNTED
          Task(
            taskId: 't1',
            uid: 'u1',
            listId: 'l1',
            title: 'Overdue task',
            dueDate: yesterday,
          ),
          // 2. Overdue date-only task but completed -> NOT COUNTED
          Task(
            taskId: 't2',
            uid: 'u1',
            listId: 'l1',
            title: 'Completed past task',
            dueDate: yesterday,
            completedAt: yesterday,
          ),
          // 3. Overdue task but soft-deleted -> NOT COUNTED
          Task(
            taskId: 't3',
            uid: 'u1',
            listId: 'l1',
            title: 'Deleted past task',
            dueDate: yesterday,
            deletedAt: yesterday,
          ),
          // 4. Future task -> NOT COUNTED
          Task(
            taskId: 't4',
            uid: 'u1',
            listId: 'l1',
            title: 'Future task',
            dueDate: tomorrow,
          ),
          // 5. Task with no due date -> NOT COUNTED
          const Task(
            taskId: 't5',
            uid: 'u1',
            listId: 'l1',
            title: 'No date task',
          ),
        ];

        final container = ProviderContainer(
          overrides: [
            allTasksForCurrentUserProvider.overrideWith(
              (ref) => Stream.value(tasks),
            ),
          ],
        );
        addTearDown(container.dispose);

        final counts = <int>[];
        container.listen<int>(
          overdueTaskCountProvider,
          (_, next) => counts.add(next),
          fireImmediately: true,
        );

        await pumpEventQueue();

        expect(counts.last, equals(1));
      },
    );
  });
}
