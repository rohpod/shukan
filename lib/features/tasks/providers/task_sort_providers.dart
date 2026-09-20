import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/task.dart';
import '../domain/smart_view_models.dart';
import '../domain/task_priority_filter.dart';
import '../domain/task_sort_options.dart';
import 'smart_view_providers.dart';
import 'task_providers.dart';

/// Provider for SharedPreferences instance. Overridden in ProviderScope at app startup and in tests.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) {
  return null;
});

/// Per-view sort mode notifier, keyed by `listId` (for list views) or `viewType.name` (for smart views).
///
/// Persists the selected [TaskSortOption] to SharedPreferences under `task_sort_mode_<viewKey>`.
/// Defaults to [TaskSortOption.manual].
class TaskSortModeNotifier extends Notifier<TaskSortOption> {
  TaskSortModeNotifier(this.viewKey);

  final String viewKey;

  @override
  TaskSortOption build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final saved = prefs?.getString('task_sort_mode_$viewKey');
    if (saved != null) {
      for (final option in TaskSortOption.values) {
        if (option.name == saved) {
          return option;
        }
      }
    }
    return TaskSortOption.manual;
  }

  Future<void> setSortMode(TaskSortOption option) async {
    state = option;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.setString('task_sort_mode_$viewKey', option.name);
  }
}

/// Provider exposing the independent [TaskSortOption] for each view.
final taskSortModeProvider =
    NotifierProvider.family<TaskSortModeNotifier, TaskSortOption, String>(
      (arg) => TaskSortModeNotifier(arg),
    );

/// Per-view toggle for displaying completed tasks, keyed by `listId` (for list views)
/// or `viewType.name` (for smart views).
///
/// Persists a boolean to SharedPreferences under `task_show_completed_<viewKey>`.
/// Defaults to `false` (hide completed tasks).
class ShowCompletedTasksNotifier extends Notifier<bool> {
  ShowCompletedTasksNotifier(this.viewKey);

  final String viewKey;

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs?.getBool('task_show_completed_$viewKey') ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.setBool('task_show_completed_$viewKey', state);
  }

  Future<void> setShowCompleted(bool show) async {
    state = show;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.setBool('task_show_completed_$viewKey', state);
  }
}

/// Provider exposing whether completed tasks should be shown for a given view.
final showCompletedTasksProvider =
    NotifierProvider.family<ShowCompletedTasksNotifier, bool, String>(
      (arg) => ShowCompletedTasksNotifier(arg),
    );

/// Per-view priority filter notifier, keyed by `listId` (for list views) or `viewType.name` (for smart views).
///
/// Persists the selected [TaskPriorityFilter] to SharedPreferences under `task_priority_filter_<viewKey>`.
/// Defaults to [TaskPriorityFilter.all].
class TaskPriorityFilterNotifier extends Notifier<TaskPriorityFilter> {
  TaskPriorityFilterNotifier(this.viewKey);

  final String viewKey;

  @override
  TaskPriorityFilter build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final saved = prefs?.getString('task_priority_filter_$viewKey');
    if (saved != null) {
      for (final option in TaskPriorityFilter.values) {
        if (option.name == saved) {
          return option;
        }
      }
    }
    return TaskPriorityFilter.all;
  }

  Future<void> setFilter(TaskPriorityFilter filter) async {
    state = filter;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.setString('task_priority_filter_$viewKey', filter.name);
  }
}

/// Provider exposing the active priority filter for a given view.
final taskPriorityFilterProvider =
    NotifierProvider.family<
      TaskPriorityFilterNotifier,
      TaskPriorityFilter,
      String
    >((arg) => TaskPriorityFilterNotifier(arg));

/// Helper to map and sort tasks within an AsyncValue while preserving errors and loading states.
AsyncValue<List<Task>> _mapSortedTasks(
  AsyncValue<List<Task>> tasksAsync,
  TaskSortOption sortOption,
) {
  if (tasksAsync.hasError && !tasksAsync.hasValue) {
    return AsyncError(
      tasksAsync.error!,
      tasksAsync.stackTrace ?? StackTrace.current,
    );
  }

  if (tasksAsync.hasValue) {
    return AsyncData(TaskSortUtils.sortTasks(tasksAsync.value!, sortOption));
  }

  if (tasksAsync.hasError) {
    return AsyncError(
      tasksAsync.error!,
      tasksAsync.stackTrace ?? StackTrace.current,
    );
  }

  return const AsyncLoading();
}

/// Streams tasks for [listId] sorted by that list's independent [TaskSortOption]
/// and filtered by its independent [showCompletedTasksProvider] and [taskPriorityFilterProvider].
final sortedTasksForListProvider =
    Provider.family<AsyncValue<List<Task>>, String>((ref, listId) {
      final tasksAsync = ref.watch(tasksForListProvider(listId));
      final sortOption = ref.watch(taskSortModeProvider(listId));
      final showCompleted = ref.watch(showCompletedTasksProvider(listId));
      final priorityFilter = ref.watch(taskPriorityFilterProvider(listId));

      final filteredTasksAsync = tasksAsync.whenData((tasks) {
        var filtered = tasks;
        if (!showCompleted) {
          filtered = filtered.where((t) => !t.isCompleted).toList();
        }
        if (priorityFilter != TaskPriorityFilter.all) {
          final target = priorityFilter.firestoreValue;
          filtered = filtered.where((t) => t.priority == target).toList();
        }
        return filtered;
      });

      return _mapSortedTasks(filteredTasksAsync, sortOption);
    });

/// Streams tasks for [viewType] sorted by that smart view's independent [TaskSortOption].
final sortedSmartViewTasksProvider =
    Provider.family<AsyncValue<List<Task>>, SmartViewType>((ref, viewType) {
      final tasksAsync = ref.watch(smartViewTasksProvider(viewType));
      final sortOption = ref.watch(taskSortModeProvider(viewType.name));

      return _mapSortedTasks(tasksAsync, sortOption);
    });

/// One-time backfill provider that ensures existing tasks for the user have an initial `order`.
final taskOrderBackfillProvider = FutureProvider<void>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return;
  final prefs = ref.watch(sharedPreferencesProvider);
  final key = 'tasks_order_backfilled_$uid';
  if (prefs?.getBool(key) == true) return;

  final repository = ref.read(taskRepositoryProvider);
  await repository.backfillTaskOrders(uid);
  await prefs?.setBool(key, true);
});
