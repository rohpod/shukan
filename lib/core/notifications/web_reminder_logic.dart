import '../../features/tasks/data/task.dart';
import 'notification_date_utils.dart';

export 'notification_date_utils.dart' show resolveTaskDueDateTimeLocal;

/// The kind of reminder (early reminder before due time, or exactly at due time).
enum WebReminderKind { early, due }

/// A reminder to be displayed on web.
class WebReminder {
  final Task task;
  final WebReminderKind kind;
  final DateTime fireTime;
  final String key;

  WebReminder({required this.task, required this.kind, required this.fireTime})
    : key = '${task.taskId}:${kind.name}:${fireTime.millisecondsSinceEpoch}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebReminder &&
          runtimeType == other.runtimeType &&
          key == other.key;

  @override
  int get hashCode => key.hashCode;
}

/// Pure evaluator that returns reminders that should fire at [now].
///
/// Reminders are evaluated within a [grace] window (defaults to 2 minutes).
/// - Skips tasks that are completed, soft-deleted, or have no dueDate.
/// - Early reminder fires when `earlyReminderMinutes > 0`, at due moment minus that duration.
/// - Returns reminders where `fireTime <= now`, `now - fireTime <= grace`, and its key is not in [firedKeys].
/// - Reminders older than [grace] are omitted.
List<WebReminder> dueWebReminders(
  List<Task> tasks,
  DateTime now,
  Set<String> firedKeys, {
  Duration grace = const Duration(minutes: 2),
}) {
  final reminders = <WebReminder>[];

  for (final task in tasks) {
    if (task.isCompleted || task.isDeleted || task.dueDate == null) {
      continue;
    }

    final dueMoment = resolveTaskDueDateTimeLocal(
      dueDate: task.dueDate,
      dueTime: task.dueTime,
    );
    if (dueMoment == null) continue;

    // 1. Early reminder (if configured)
    if (task.earlyReminderMinutes > 0) {
      final earlyFireTime = dueMoment.subtract(
        Duration(minutes: task.earlyReminderMinutes),
      );
      final earlyReminder = WebReminder(
        task: task,
        kind: WebReminderKind.early,
        fireTime: earlyFireTime,
      );
      if (_isDue(earlyFireTime, now, grace) &&
          !firedKeys.contains(earlyReminder.key)) {
        reminders.add(earlyReminder);
      }
    }

    // 2. Due reminder
    final dueReminder = WebReminder(
      task: task,
      kind: WebReminderKind.due,
      fireTime: dueMoment,
    );
    if (_isDue(dueMoment, now, grace) && !firedKeys.contains(dueReminder.key)) {
      reminders.add(dueReminder);
    }
  }

  return reminders;
}

bool _isDue(DateTime fireTime, DateTime now, Duration grace) {
  if (fireTime.isAfter(now)) return false;
  return now.difference(fireTime) <= grace;
}
