import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/task.dart';
import 'task_sort_providers.dart';

/// Per-list task selection notifier holding the set of selected task IDs.
class TaskSelectionNotifier extends Notifier<Set<String>> {
  TaskSelectionNotifier(this.listId);

  final String listId;

  @override
  Set<String> build() {
    return const <String>{};
  }

  /// Toggles selection of [taskId].
  void toggle(String taskId) {
    final next = Set<String>.from(state);
    if (next.contains(taskId)) {
      next.remove(taskId);
    } else {
      next.add(taskId);
    }
    state = next;
  }

  /// Prunes any selected IDs that are not present in [ids].
  void retainOnly(Set<String> ids) {
    final next = state.where(ids.contains).toSet();
    if (next.length != state.length) {
      state = next;
    }
  }

  /// Clears all selected tasks.
  void clear() {
    if (state.isNotEmpty) {
      state = const <String>{};
    }
  }
}

/// Provider exposing the set of selected task IDs for a given [listId].
final taskSelectionProvider = NotifierProvider.autoDispose
    .family<TaskSelectionNotifier, Set<String>, String>(
      (arg) => TaskSelectionNotifier(arg),
    );

/// Provider exposing the selected [Task] models from displayed tasks
/// ([sortedTasksForListProvider] and [completedTasksForListProvider]) in their displayed order.
/// Returns an empty list while loading or on error.
final selectedTasksProvider = Provider.autoDispose.family<List<Task>, String>((
  ref,
  listId,
) {
  final selection = ref.watch(taskSelectionProvider(listId));
  if (selection.isEmpty) {
    return const <Task>[];
  }

  final activeTasks =
      ref.watch(sortedTasksForListProvider(listId)).value ?? const <Task>[];
  final completedTasks =
      ref.watch(completedTasksForListProvider(listId)).value ?? const <Task>[];
  final tasks = [...activeTasks, ...completedTasks];

  return tasks.where((task) => selection.contains(task.taskId)).toList();
});

/// Per-list selection mode active state (can be active even when 0 tasks are selected, e.g. via Edit button).
class TaskSelectionModeNotifier extends Notifier<bool> {
  TaskSelectionModeNotifier(this.listId);

  final String listId;

  @override
  bool build() {
    return false;
  }

  void enter() {
    state = true;
  }

  void exit() {
    state = false;
  }
}

/// Provider exposing whether selection mode was explicitly entered via the Edit button.
final isTaskSelectionModeActiveProvider = NotifierProvider.autoDispose
    .family<TaskSelectionModeNotifier, bool, String>(
      (arg) => TaskSelectionModeNotifier(arg),
    );

/// Provider exposing whether selection mode is currently active for [listId].
/// True if explicitly entered via edit mode, or if any tasks are currently selected.
final isSelectionModeActiveProvider = Provider.autoDispose.family<bool, String>(
  (ref, listId) {
    final isExplicit = ref.watch(isTaskSelectionModeActiveProvider(listId));
    final selectedTasks = ref.watch(selectedTasksProvider(listId));
    return isExplicit || selectedTasks.isNotEmpty;
  },
);
