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

/// Timeout duration for the initial data emission of smart view streams.
final smartViewTimeoutProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 10);
});

/// Extension providing a first-event-only timeout mechanism for streams.
extension FirstEventTimeoutExtension<T> on Stream<T> {
  /// Emits a [TimeoutException] if the first event is not received within [duration].
  ///
  /// Once the first event or error is received, the timeout timer is cancelled
  /// and will not fire on subsequent idle periods.
  Stream<T> timeoutFirstEvent(Duration duration, {String? message}) {
    final controller = isBroadcast
        ? StreamController<T>.broadcast(sync: true)
        : StreamController<T>(sync: true);

    StreamSubscription<T>? subscription;
    Timer? timer;
    bool hasEmitted = false;

    controller.onListen = () {
      timer = Timer(duration, () {
        if (!hasEmitted) {
          controller.addError(
            TimeoutException(
              message ?? 'This is taking longer than expected — check your connection or try again',
              duration,
            ),
          );
        }
      });

      subscription = listen(
        (data) {
          hasEmitted = true;
          timer?.cancel();
          timer = null;
          controller.add(data);
        },
        onError: (Object error, StackTrace stackTrace) {
          hasEmitted = true;
          timer?.cancel();
          timer = null;
          controller.addError(error, stackTrace);
        },
        onDone: () {
          timer?.cancel();
          timer = null;
          controller.close();
        },
        cancelOnError: false,
      );
    };

    controller.onCancel = () {
      timer?.cancel();
      timer = null;
      return subscription?.cancel();
    };

    if (!isBroadcast) {
      controller.onPause = () => subscription?.pause();
      controller.onResume = () => subscription?.resume();
    }

    return controller.stream;
  }
}

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
    final timeoutDuration = ref.watch(smartViewTimeoutProvider);

    final DateTime? startDueDate;
    final DateTime? endDueDate;

    switch (viewType) {
      case SmartViewType.today:
        startDueDate = null;
        endDueDate = SmartViewDateUtils.endOfDay(currentDate);
        break;
      case SmartViewType.thisWeek:
        startDueDate = SmartViewDateUtils.startOfWeek(currentDate);
        endDueDate = SmartViewDateUtils.endOfWeek(currentDate);
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

    final mappedStream = baseStream.map((tasks) {
      final startOfToday = SmartViewDateUtils.startOfDay(currentDate);
      return tasks.where((t) {
        // In Today view, overdue tasks (dueDate < startOfToday) must only ever be incomplete.
        // Completed past tasks are never overdue and must not appear in Today view under any filter.
        if (viewType == SmartViewType.today &&
            t.dueDate != null &&
            t.dueDate!.isBefore(startOfToday)) {
          if (t.isCompleted) return false;
        }

        if (completionFilter == CompletionFilter.completed) {
          return t.isCompleted;
        }
        return true;
      }).toList();
    });

    return mappedStream.timeoutFirstEvent(
      timeoutDuration,
      message: 'This is taking longer than expected — check your connection or try again',
    );
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
