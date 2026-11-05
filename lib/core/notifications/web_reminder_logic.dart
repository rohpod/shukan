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
  return [
    for (final task in tasks)
      for (final reminder in _remindersFor(task))
        if (_isDue(reminder.fireTime, now, grace) &&
            !firedKeys.contains(reminder.key))
          reminder,
  ];
}

/// Returns reminders that came due after [since] but are now too old to fire.
///
/// These are the ones dropped by [dueWebReminders] because no tab was running
/// when they came due.
List<WebReminder> missedWebReminders(
  List<Task> tasks,
  DateTime since,
  DateTime now,
  Set<String> firedKeys, {
  Duration grace = const Duration(minutes: 2),
}) {
  return [
    for (final task in tasks)
      for (final reminder in _remindersFor(task))
        if (reminder.fireTime.isAfter(since) &&
            now.difference(reminder.fireTime) > grace &&
            !firedKeys.contains(reminder.key))
          reminder,
  ];
}

/// The early and due reminders [task] has, whatever their fire times.
Iterable<WebReminder> _remindersFor(Task task) sync* {
  if (task.isCompleted || task.isDeleted) return;

  final dueMoment = resolveTaskDueDateTimeLocal(
    dueDate: task.dueDate,
    dueTime: task.dueTime,
  );
  if (dueMoment == null) return;

  if (task.earlyReminderMinutes > 0) {
    yield WebReminder(
      task: task,
      kind: WebReminderKind.early,
      fireTime: dueMoment.subtract(
        Duration(minutes: task.earlyReminderMinutes),
      ),
    );
  }
  yield WebReminder(task: task, kind: WebReminderKind.due, fireTime: dueMoment);
}

bool _isDue(DateTime fireTime, DateTime now, Duration grace) {
  if (fireTime.isAfter(now)) return false;
  return now.difference(fireTime) <= grace;
}
