import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/task.dart';
import '../data/task_repository.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return TaskRepository(firestore);
});

/// Streams the defaultListId from users/{uid}.
final defaultListIdProvider = StreamProvider<String?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Stream.value(null);
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.data()?['defaultListId'] as String?);
});

/// Family stream provider returning tasks for [listId] scoped to current user.
final tasksForListProvider = StreamProvider.family<List<Task>, String>((
  ref,
  listId,
) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Stream.value(const <Task>[]);
  }
  final repository = ref.watch(taskRepositoryProvider);
  return repository.streamTasksForList(uid, listId);
});

/// Family stream provider returning a single task by [taskId].
final taskStreamProvider = StreamProvider.family<Task?, String>((ref, taskId) {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.streamTask(taskId);
});

/// Streams all soft-deleted tasks belonging to the current user, ordered descending by deletedAt.
final recentlyDeletedTasksProvider = StreamProvider.autoDispose<List<Task>>((
  ref,
) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Stream.value(const <Task>[]);
  }
  final repository = ref.watch(taskRepositoryProvider);
  return repository.streamRecentlyDeletedTasks(uid);
});

/// Provider exposing the count of recently deleted tasks for badge displays.
/// Rebuilds listeners only when the integer count changes.
final recentlyDeletedCountProvider = Provider.autoDispose<int>((ref) {
  final tasksAsync = ref.watch(recentlyDeletedTasksProvider);
  return tasksAsync.value?.length ?? 0;
});

/// Stream provider returning all tasks for the current user across all lists.
final allTasksForCurrentUserProvider = StreamProvider<List<Task>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Stream.value(const <Task>[]);
  }
  final repository = ref.watch(taskRepositoryProvider);
  return repository.streamAllTasksForUser(uid);
});

/// Provider mapping list IDs to the count of active (non-completed, non-soft-deleted) tasks.
/// Derives counts from [allTasksForCurrentUserProvider] using a single Firestore listener.
final activeTaskCountsByListProvider = Provider<Map<String, int>>((ref) {
  final tasksAsync = ref.watch(allTasksForCurrentUserProvider);
  final tasks = tasksAsync.value ?? const <Task>[];
  final counts = <String, int>{};
  for (final task in tasks) {
    if (!task.isCompleted) {
      counts[task.listId] = (counts[task.listId] ?? 0) + 1;
    }
  }
  return counts;
});

/// Family provider returning the active (non-completed, non-soft-deleted) task count
/// for a specific [listId].
final activeTaskCountForListProvider = Provider.family<int, String>((
  ref,
  listId,
) {
  final counts = ref.watch(activeTaskCountsByListProvider);
  return counts[listId] ?? 0;
});
