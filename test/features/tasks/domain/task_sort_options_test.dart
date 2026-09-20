import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/domain/task_sort_options.dart';

void main() {
  group('TaskSortOption enum', () {
    test('has expected values and labels', () {
      expect(TaskSortOption.manual.label, equals('Manual'));
      expect(TaskSortOption.dueDate.label, equals('Due date'));
      expect(TaskSortOption.priority.label, equals('Priority'));

      expect(TaskSortOption.manual.icon, equals(Icons.reorder));
      expect(TaskSortOption.dueDate.icon, equals(Icons.calendar_today));
      expect(TaskSortOption.priority.icon, equals(Icons.flag_outlined));
    });
  });

  group('TaskSortUtils.sortTasks', () {
    Task createTask({
      required String id,
      DateTime? dueDate,
      String? dueTime,
      String priority = 'none',
      double order = 0.0,
      DateTime? createdAt,
    }) {
      return Task(
        taskId: id,
        uid: 'u1',
        listId: 'l1',
        title: 'Task $id',
        notes: '',
        url: '',
        priority: priority,
        tagIds: const [],
        dueDate: dueDate,
        dueTime: dueTime,
        earlyReminderMinutes: 0,
        repeatRule: 'none',
        repeatCustomConfig: null,
        order: order,
        subtasks: const [],
        createdAt: createdAt ?? DateTime(2026, 1, 1),
        completedAt: null,
        deletedAt: null,
      );
    }

    test(
      'manual sort orders by order ascending, tie breaking by createdAt',
      () {
        final t1 = createTask(id: '1', order: 200.0);
        final t2 = createTask(id: '2', order: 100.0);
        final t3 = createTask(
          id: '3',
          order: 100.0,
          createdAt: DateTime(2025, 1, 1),
        );

        final sorted = TaskSortUtils.sortTasks([
          t1,
          t2,
          t3,
        ], TaskSortOption.manual);
        expect(sorted.map((t) => t.taskId).toList(), equals(['3', '2', '1']));
      },
    );

    test('dueDate sort orders by date ascending with nulls last', () {
      final t1 = createTask(id: '1', dueDate: DateTime(2026, 9, 20));
      final t2 = createTask(id: '2', dueDate: null);
      final t3 = createTask(id: '3', dueDate: DateTime(2026, 9, 15));

      final sorted = TaskSortUtils.sortTasks([
        t1,
        t2,
        t3,
      ], TaskSortOption.dueDate);
      expect(sorted.map((t) => t.taskId).toList(), equals(['3', '1', '2']));
    });

    test('dueDate sort tie breaks by dueTime, then priority, then order, then createdAt', () {
      final sameDate = DateTime(2026, 9, 20);
      final t1 = createTask(
        id: '1',
        dueDate: sameDate,
        dueTime: '15:00',
        priority: 'low',
      );
      final t2 = createTask(
        id: '2',
        dueDate: sameDate,
        dueTime: '09:00',
        priority: 'none',
      );
      final t3 = createTask(
        id: '3',
        dueDate: sameDate,
        dueTime: null,
        priority: 'high',
      );
      final t4 = createTask(
        id: '4',
        dueDate: sameDate,
        dueTime: '09:00',
        priority: 'high',
      );

      final sorted = TaskSortUtils.sortTasks([
        t1,
        t2,
        t3,
        t4,
      ], TaskSortOption.dueDate);
      // t4 has '09:00' & 'high', t2 has '09:00' & 'none', t1 has '15:00', t3 has null dueTime (nulls last)
      expect(
        sorted.map((t) => t.taskId).toList(),
        equals(['4', '2', '1', '3']),
      );
    });

    test('priority sort orders highest first (high > medium > low > none)', () {
      final tNone = createTask(id: 'none', priority: 'none');
      final tLow = createTask(id: 'low', priority: 'low');
      final tMed = createTask(id: 'med', priority: 'medium');
      final tHigh = createTask(id: 'high', priority: 'high');

      final sorted = TaskSortUtils.sortTasks([
        tNone,
        tLow,
        tMed,
        tHigh,
      ], TaskSortOption.priority);
      expect(
        sorted.map((t) => t.taskId).toList(),
        equals(['high', 'med', 'low', 'none']),
      );
    });

    test('priority sort tie breaks by dueDate (earliest first, nulls last), then order', () {
      final t1 = createTask(
        id: '1',
        priority: 'high',
        dueDate: DateTime(2026, 9, 25),
      );
      final t2 = createTask(
        id: '2',
        priority: 'high',
        dueDate: DateTime(2026, 9, 10),
      );
      final t3 = createTask(id: '3', priority: 'high', dueDate: null);

      final sorted = TaskSortUtils.sortTasks([
        t1,
        t2,
        t3,
      ], TaskSortOption.priority);
      expect(sorted.map((t) => t.taskId).toList(), equals(['2', '1', '3']));
    });
  });

  group('TaskSortUtils order midpoint and renumbering', () {
    Task dummyTask(double order) {
      return Task(
        taskId: 'test',
        uid: 'u',
        listId: 'l',
        title: 'Title',
        notes: '',
        url: '',
        priority: 'none',
        tagIds: const [],
        dueDate: null,
        dueTime: null,
        earlyReminderMinutes: 0,
        repeatRule: 'none',
        repeatCustomConfig: null,
        order: order,
        subtasks: const [],
        createdAt: DateTime.now(),
        completedAt: null,
        deletedAt: null,
      );
    }

    test('computeMidpointOrder calculates correct values', () {
      // Between two items
      expect(
        TaskSortUtils.computeMidpointOrder(
          before: dummyTask(1000.0),
          after: dummyTask(2000.0),
        ),
        equals(1500.0),
      );

      // Inserting before first item
      expect(
        TaskSortUtils.computeMidpointOrder(
          before: null,
          after: dummyTask(1000.0),
        ),
        equals(0.0),
      );

      // Inserting after last item
      expect(
        TaskSortUtils.computeMidpointOrder(
          before: dummyTask(2000.0),
          after: null,
        ),
        equals(3000.0),
      );

      // Both null (empty list)
      expect(
        TaskSortUtils.computeMidpointOrder(before: null, after: null),
        equals(1000.0),
      );
    });

    test('needsRenumbering detects close precision', () {
      expect(
        TaskSortUtils.needsRenumbering(
          before: dummyTask(1000.0),
          after: dummyTask(1000.00000001),
        ),
        isTrue,
      );

      expect(
        TaskSortUtils.needsRenumbering(
          before: dummyTask(1000.0),
          after: dummyTask(1001.0),
        ),
        isFalse,
      );
    });
  });
}
