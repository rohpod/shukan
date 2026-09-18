import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/task.dart';
import '../domain/smart_view_models.dart';
import 'task_providers.dart';

/// Stream that emits the current local time and automatically emits again
/// as soon as the clock crosses local midnight.
final currentDateStreamProvider = StreamProvider<DateTime>((ref) {
  final controller = StreamController<DateTime>();
  controller.add(DateTime.now());

  Timer? timer;
  void scheduleNextMidnight() {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final durationUntilMidnight =
        nextMidnight.difference(now) + const Duration(seconds: 1);
    timer = Timer(durationUntilMidnight, () {
      if (!controller.isClosed) {
        controller.add(DateTime.now());
        scheduleNextMidnight();
      }
    });
  }

  scheduleNextMidnight();

  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Current calendar date provider, updated automatically at local midnight.
final currentDateProvider = Provider<DateTime>((ref) {
  final asyncDate = ref.watch(currentDateStreamProvider);
  return asyncDate.value ?? DateTime.now();
});

/// User toggle for "This Week" view: Work week (Mon–Fri) vs Full week (Mon–Sun).
// TODO: Persist across app restarts when local storage or user preferences are implemented.
class ThisWeekFilterNotifier extends Notifier<WeekFilter> {
  @override
  WeekFilter build() => WeekFilter.fullWeek;

  void setFilter(WeekFilter filter) => state = filter;
}

final thisWeekFilterProvider =
    NotifierProvider<ThisWeekFilterNotifier, WeekFilter>(
      ThisWeekFilterNotifier.new,
    );

/// User toggle for task completion status in smart views.
// TODO: Persist across app restarts when local storage or user preferences are implemented.
class CompletionFilterNotifier extends Notifier<CompletionFilter> {
  @override
  CompletionFilter build() => CompletionFilter.incomplete;

  void setFilter(CompletionFilter filter) => state = filter;
}

final smartViewCompletionFilterProvider =
    NotifierProvider<CompletionFilterNotifier, CompletionFilter>(
      CompletionFilterNotifier.new,
    );

/// Family provider that streams tasks for a specific [SmartViewType].
///
/// Implements server-side filtering on `dueDate` range/inequality and `completedAt == null`
/// (for incomplete-only mode), with in-memory filtering fallback for complete-only mode.
final smartViewTasksProvider = StreamProvider.family<List<Task>, SmartViewType>(
  (ref, viewType) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) {
      return Stream.value(const <Task>[]);
    }

    final repository = ref.watch(taskRepositoryProvider);
    final currentDate = ref.watch(currentDateProvider);
    final completionFilter = ref.watch(smartViewCompletionFilterProvider);
    final weekFilter = ref.watch(thisWeekFilterProvider);

    final DateTime? startDueDate;
    final DateTime? endDueDate;

    switch (viewType) {
      case SmartViewType.today:
        startDueDate = SmartViewDateUtils.startOfDay(currentDate);
        endDueDate = SmartViewDateUtils.endOfDay(currentDate);
        break;
      case SmartViewType.thisWeek:
        startDueDate = SmartViewDateUtils.startOfWeek(currentDate);
        endDueDate = SmartViewDateUtils.endOfWeek(currentDate, weekFilter);
        break;
      case SmartViewType.scheduled:
        startDueDate = null;
        endDueDate = null;
        break;
    }

    final onlyIncomplete = completionFilter == CompletionFilter.incomplete;

    final baseStream = repository.streamTasksWithDueDate(
      uid: uid,
      startDueDate: startDueDate,
      endDueDate: endDueDate,
      onlyIncomplete: onlyIncomplete,
    );

    return baseStream.map((tasks) {
      if (completionFilter == CompletionFilter.completed) {
        return tasks.where((t) => t.isCompleted).toList();
      }
      return tasks;
    });
  },
);

/// Provider exposing the integer count of tasks for a given [SmartViewType].
final smartViewCountProvider = Provider.family<int, SmartViewType>((
  ref,
  viewType,
) {
  final tasksAsync = ref.watch(smartViewTasksProvider(viewType));
  return tasksAsync.value?.length ?? 0;
});
