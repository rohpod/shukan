import 'dart:async';

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

/// Emits the current time once a minute, so time-based state such as the
/// overdue count updates while the app stays open.
final currentMinuteProvider = StreamProvider<DateTime>((ref) {
  final controller = StreamController<DateTime>();
  controller.add(DateTime.now());
  final timer = Timer.periodic(const Duration(minutes: 1), (_) {
    controller.add(DateTime.now());
  });
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

/// Derives the count of overdue tasks from [allTasksForCurrentUserProvider].
final overdueTaskCountProvider = Provider<int>((ref) {
  final tasksAsync = ref.watch(allTasksForCurrentUserProvider);
  final now = ref.watch(currentMinuteProvider).value ?? DateTime.now();
  final tasks = tasksAsync.value ?? const <Task>[];
  return tasks.where((task) {
    if (task.isCompleted || task.isDeleted) return false;
    return isTaskOverdue(
      dueDate: task.dueDate,
      dueTime: task.dueTime,
      now: now,
    );
  }).length;
});
