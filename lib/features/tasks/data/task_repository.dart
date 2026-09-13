import 'package:cloud_firestore/cloud_firestore.dart';

import 'task.dart';

class TaskRepository {
  final FirebaseFirestore _firestore;

  TaskRepository(this._firestore);

  CollectionReference<Map<String, dynamic>> get _tasksCollection =>
      _firestore.collection('tasks');

  /// Creates a new task with the complete schema and placeholder defaults.
  Future<Task> createTask({
    required String uid,
    required String listId,
    required String title,
    String notes = '',
    String url = '',
  }) async {
    final listDoc = await _firestore.collection('lists').doc(listId).get();
    if (!listDoc.exists) {
      throw ArgumentError('List not found: $listId');
    }
    if (listDoc.data()?['uid'] != uid) {
      throw ArgumentError('List does not belong to user: $listId');
    }

    final docRef = _tasksCollection.doc();
    final data = <String, dynamic>{
      'taskId': docRef.id,
      'uid': uid,
      'listId': listId,
      'title': title.trim(),
      'notes': notes.trim(),
      'url': url.trim(),
      'priority': 'none',
      'tagIds': <String>[],
      'dueDate': null,
      'dueTime': null,
      'earlyReminderMinutes': 0,
      'repeatRule': 'none',
      'repeatCustomConfig': null,
      'order': 0,
      'subtasks': <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'completedAt': null,
      'deletedAt': null,
    };

    await docRef.set(data);

    return Task(
      taskId: docRef.id,
      uid: uid,
      listId: listId,
      title: title.trim(),
      notes: notes.trim(),
      url: url.trim(),
      priority: 'none',
      tagIds: const [],
      dueDate: null,
      dueTime: null,
      earlyReminderMinutes: 0,
      repeatRule: 'none',
      repeatCustomConfig: null,
      order: 0,
      subtasks: const [],
      createdAt: DateTime.now(),
      completedAt: null,
      deletedAt: null,
    );
  }

  /// Streams active (non-soft-deleted) tasks for a specific list belonging to [uid],
  /// ordered chronologically by [createdAt].
  Stream<List<Task>> streamTasksForList(String uid, String listId) {
    return _tasksCollection
        .where('uid', isEqualTo: uid)
        .where('listId', isEqualTo: listId)
        .where('deletedAt', isNull: true)
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Task.fromFirestore).toList());
  }

  /// Performs a partial update on the task, restricted to [title], [notes], and [url].
  Future<void> updateTask(
    String taskId, {
    String? title,
    String? notes,
    String? url,
  }) async {
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title.trim();
    if (notes != null) updates['notes'] = notes.trim();
    if (url != null) updates['url'] = url.trim();

    if (updates.isNotEmpty) {
      await _tasksCollection.doc(taskId).update(updates);
    }
  }

  /// Marks a task completed or clears its completion status.
  Future<void> toggleTaskCompleted(
    String taskId, {
    required bool isCompleted,
  }) async {
    await _tasksCollection.doc(taskId).update({
      'completedAt': isCompleted ? FieldValue.serverTimestamp() : null,
    });
  }

  /// Soft-deletes a task by setting its [deletedAt] field to the server timestamp.
  Future<void> softDeleteTask(String taskId) async {
    await _tasksCollection.doc(taskId).update({
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }
}
