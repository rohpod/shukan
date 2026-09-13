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
