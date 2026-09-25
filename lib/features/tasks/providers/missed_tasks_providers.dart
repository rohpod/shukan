import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_date_utils.dart';
import '../data/task.dart';
import 'task_providers.dart';

/// Notifier tracking whether the missed tasks banner has been dismissed during
/// the current app session.
class MissedTasksBannerDismissedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;

  @override
  set state(bool value) => super.state = value;
}

/// Provider tracking whether the missed tasks banner has been dismissed during
/// the current app session.
///
/// Non-autoDispose, so it persists for the app session and resets only on cold restart.
final missedTasksBannerDismissedProvider =
    NotifierProvider<MissedTasksBannerDismissedNotifier, bool>(
      MissedTasksBannerDismissedNotifier.new,
    );

/// Derives the count of overdue tasks from [allTasksForCurrentUserProvider].
final overdueTaskCountProvider = Provider<int>((ref) {
  final tasksAsync = ref.watch(allTasksForCurrentUserProvider);
  final tasks = tasksAsync.value ?? const <Task>[];
  return tasks.where((task) {
    if (task.isCompleted || task.isDeleted) return false;
    try {
      final dueDateTime = resolveTaskDueDateTime(
        dueDate: task.dueDate,
        dueTime: task.dueTime,
      );
      return dueDateTime != null && dueDateTime.isBefore(DateTime.now());
    } catch (_) {
      // Fallback for tests/environments where timezone database is not initialized
      if (task.dueDate == null) return false;
      int hour = 9;
      int minute = 0;
      if (task.dueTime != null && task.dueTime!.trim().isNotEmpty) {
        final parts = task.dueTime!.trim().split(':');
        if (parts.length == 2) {
          final h = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          if (h != null &&
              m != null &&
              h >= 0 &&
              h <= 23 &&
              m >= 0 &&
              m <= 59) {
            hour = h;
            minute = m;
          }
        }
      }
      final localDate = task.dueDate!.toLocal();
      final dt = DateTime(
        localDate.year,
        localDate.month,
        localDate.day,
        hour,
        minute,
      );
      return dt.isBefore(DateTime.now());
    }
  }).length;
});
