import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/notifications/notification_date_utils.dart';
import '../../data/task.dart';
import '../../domain/task_recurrence_utils.dart';
import '../../providers/missed_tasks_providers.dart';

/// `YYYY-MM-DD`, followed by [dueTime] when there is one.
String formatDueDate(DateTime? date, String? dueTime) {
  if (date == null) return '';
  final local = date.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  if (dueTime != null && dueTime.isNotEmpty) {
    return '$y-$m-$d $dueTime';
  }
  return '$y-$m-$d';
}

/// A task's due date, time and repeat summary, in red once it is overdue.
class TaskScheduleLine extends ConsumerWidget {
  const TaskScheduleLine({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dueDate = task.dueDate;
    if (dueDate == null) return const SizedBox.shrink();

    final now = ref.watch(currentMinuteProvider).value ?? DateTime.now();
    final isOverdue =
        !task.isCompleted &&
        isTaskOverdue(dueDate: dueDate, dueTime: task.dueTime, now: now);
    final color = isOverdue ? Colors.red.shade700 : Colors.blueGrey;
    final repeat = repeatSummary(task);

    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              formatDueDate(dueDate, task.dueTime),
              key: Key('taskDueDate_${task.taskId}'),
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: isOverdue ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
        if (repeat.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.repeat, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                repeat,
                key: Key('taskRepeat_${task.taskId}'),
                style: TextStyle(fontSize: 12, color: color),
              ),
            ],
          ),
      ],
    );
  }
}
