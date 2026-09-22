import 'package:flutter/material.dart';

import '../data/task.dart';

/// Available sort options for task list views and smart views.
enum TaskSortOption {
  manual('Manual', Icons.reorder),
  dueDate('Due date', Icons.calendar_today),
  priority('Priority', Icons.flag_outlined);

  final String label;
  final IconData icon;
  const TaskSortOption(this.label, this.icon);
}

/// Utility class providing sorting algorithms and midpoint calculation for tasks.
class TaskSortUtils {
  const TaskSortUtils._();

  /// Converts a priority string to its numeric rank for sorting.
  /// 'high' (3) > 'medium' (2) > 'low' (1) > 'none' (0).
  static int priorityWeight(String priority) {
    switch (priority.toLowerCase().trim()) {
      case 'high':
        return 3;
      case 'medium':
        return 2;
      case 'low':
        return 1;
      case 'none':
      default:
        return 0;
    }
  }

  /// Sorts a list of [tasks] according to [sortOption].
  ///
  /// Returns a new sorted list without mutating the original.
  static List<Task> sortTasks(List<Task> tasks, TaskSortOption sortOption) {
    final list = List<Task>.from(tasks);

    switch (sortOption) {
      case TaskSortOption.dueDate:
        list.sort(_compareByDueDate);
        break;
      case TaskSortOption.priority:
        list.sort(_compareByPriority);
        break;
      case TaskSortOption.manual:
        list.sort(_compareByManualOrder);
        break;
    }

    return list;
  }

  /// Due date: ascending, nulls last.
  /// Tie-break: dueTime ("HH:mm") -> priority -> order -> createdAt.
  static int _compareByDueDate(Task a, Task b) {
    if (a.dueDate == null && b.dueDate != null) return 1;
    if (a.dueDate != null && b.dueDate == null) return -1;

    if (a.dueDate != null && b.dueDate != null) {
      final dateCmp = a.dueDate!.compareTo(b.dueDate!);
      if (dateCmp != 0) return dateCmp;
    }

    // Tie-break 1: dueTime ("HH:mm")
    if (a.dueTime != null && b.dueTime != null) {
      final timeCmp = a.dueTime!.compareTo(b.dueTime!);
      if (timeCmp != 0) return timeCmp;
    } else if (a.dueTime != null && b.dueTime == null) {
      return -1;
    } else if (a.dueTime == null && b.dueTime != null) {
      return 1;
    }

    // Tie-break 2: priority (highest first)
    final priorityCmp = priorityWeight(b.priority)
        .compareTo(priorityWeight(a.priority));
    if (priorityCmp != 0) return priorityCmp;

    // Tie-break 3: order
    final orderCmp = a.order.compareTo(b.order);
    if (orderCmp != 0) return orderCmp;

    // Tie-break 4: createdAt
    if (a.createdAt != null && b.createdAt != null) {
      return a.createdAt!.compareTo(b.createdAt!);
    }
    return 0;
  }

  /// Priority: highest first (high > medium > low > none).
  /// Tie-break: dueDate (nulls last) -> dueTime -> order -> createdAt.
  static int _compareByPriority(Task a, Task b) {
    final weightA = priorityWeight(a.priority);
    final weightB = priorityWeight(b.priority);
    final priorityCmp = weightB.compareTo(weightA);
    if (priorityCmp != 0) return priorityCmp;

    // Tie-break 1: dueDate (nulls last)
    if (a.dueDate == null && b.dueDate != null) return 1;
    if (a.dueDate != null && b.dueDate == null) return -1;
    if (a.dueDate != null && b.dueDate != null) {
      final dateCmp = a.dueDate!.compareTo(b.dueDate!);
      if (dateCmp != 0) return dateCmp;
    }

    // Tie-break 2: dueTime
    if (a.dueTime != null && b.dueTime != null) {
      final timeCmp = a.dueTime!.compareTo(b.dueTime!);
      if (timeCmp != 0) return timeCmp;
    } else if (a.dueTime != null && b.dueTime == null) {
      return -1;
    } else if (a.dueTime == null && b.dueTime != null) {
      return 1;
    }

    // Tie-break 3: order
    final orderCmp = a.order.compareTo(b.order);
    if (orderCmp != 0) return orderCmp;

    // Tie-break 4: createdAt
    if (a.createdAt != null && b.createdAt != null) {
      return a.createdAt!.compareTo(b.createdAt!);
    }
    return 0;
  }

  /// Manual: ascending by order.
  /// Tie-break: createdAt ascending (oldest = lowest).
  static int _compareByManualOrder(Task a, Task b) {
    final orderCmp = a.order.compareTo(b.order);
    if (orderCmp != 0) return orderCmp;

    if (a.createdAt != null && b.createdAt != null) {
      return a.createdAt!.compareTo(b.createdAt!);
    }
    return 0;
  }

  /// Computes a new [order] value when placing a task between [before] and [after].
  ///
  /// - If [before] and [after] are both present, returns their midpoint `(before.order + after.order) / 2.0`.
  /// - If only [after] is present (placed at top), returns `after.order - 1000.0`.
  /// - If only [before] is present (placed at bottom), returns `before.order + 1000.0`.
  /// - If neither is present (only item), returns `1000.0`.
  static double computeMidpointOrder({Task? before, Task? after}) {
    if (before == null && after == null) {
      return 1000.0;
    }
    if (before == null && after != null) {
      return after.order - 1000.0;
    }
    if (before != null && after == null) {
      return before.order + 1000.0;
    }
    return (before!.order + after!.order) / 2.0;
  }

  /// Returns true if the order gap between [before] and [after] is so small that
  /// numerical precision issues could occur on further subdivisions.
  static bool needsRenumbering({required Task before, required Task after}) {
    return (after.order - before.order).abs() < 1e-6;
  }
}
