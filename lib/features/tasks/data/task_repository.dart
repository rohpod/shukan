import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

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

  static const Object _sentinel = Object();

  /// Performs a partial update on the task attributes.
  Future<void> updateTask(
    String taskId, {
    String? title,
    String? notes,
    String? url,
    String? priority,
    List<String>? tagIds,
    Object? dueDate = _sentinel,
    Object? dueTime = _sentinel,
    int? earlyReminderMinutes,
    String? repeatRule,
    bool clearDueDate = false,
    bool clearDueTime = false,
  }) async {
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title.trim();
    if (notes != null) updates['notes'] = notes.trim();
    if (url != null) updates['url'] = url.trim();
    if (priority != null) updates['priority'] = priority;
    if (tagIds != null) updates['tagIds'] = tagIds;
    if (earlyReminderMinutes != null) {
      updates['earlyReminderMinutes'] = earlyReminderMinutes;
    }
    if (repeatRule != null) updates['repeatRule'] = repeatRule;

    if (clearDueDate) {
      updates['dueDate'] = null;
      if (identical(dueTime, _sentinel)) {
        updates['dueTime'] = null;
      }
    } else if (!identical(dueDate, _sentinel)) {
      if (dueDate is DateTime) {
        updates['dueDate'] = Timestamp.fromDate(dueDate);
      } else if (dueDate == null) {
        updates['dueDate'] = null;
        if (identical(dueTime, _sentinel)) {
          updates['dueTime'] = null;
        }
      }
    }

    if (clearDueTime) {
      updates['dueTime'] = null;
    } else if (!identical(dueTime, _sentinel)) {
      if (dueTime is String) {
        updates['dueTime'] = dueTime.trim();
      } else if (dueTime == null) {
        updates['dueTime'] = null;
      }
    }

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

  /// Streams a single task by [taskId]. Emits null if the document does not exist.
  Stream<Task?> streamTask(String taskId) {
    return _tasksCollection.doc(taskId).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }
      return Task.fromFirestore(snapshot);
    });
  }

  Future<List<Map<String, dynamic>>> _getSubtasksForTask(String taskId) async {
    final doc = await _tasksCollection.doc(taskId).get();
    if (!doc.exists) {
      throw ArgumentError('Task not found: $taskId');
    }
    final data = doc.data();
    return (data?['subtasks'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        <Map<String, dynamic>>[];
  }

  /// Adds a subtask to [taskId] with a generated UUID.
  Future<void> addSubtask(String taskId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Subtask title cannot be empty');
    }
    final subtasks = await _getSubtasksForTask(taskId);
    final newSubtask = <String, dynamic>{
      'id': const Uuid().v4(),
      'title': trimmed,
      'completed': false,
    };
    await _tasksCollection.doc(taskId).update({
      'subtasks': [...subtasks, newSubtask],
    });
  }

  /// Toggles the completion status of subtask [subtaskId] within [taskId].
  Future<void> toggleSubtask(
    String taskId,
    String subtaskId, {
    required bool completed,
  }) async {
    final subtasks = await _getSubtasksForTask(taskId);
    final index = subtasks.indexWhere((s) => s['id'] == subtaskId);
    if (index == -1) {
      throw ArgumentError('Subtask not found: $subtaskId');
    }
    subtasks[index]['completed'] = completed;
    await _tasksCollection.doc(taskId).update({'subtasks': subtasks});
  }

  /// Removes subtask [subtaskId] from [taskId].
  Future<void> removeSubtask(String taskId, String subtaskId) async {
    final subtasks = await _getSubtasksForTask(taskId);
    final updated = subtasks.where((s) => s['id'] != subtaskId).toList();
    await _tasksCollection.doc(taskId).update({'subtasks': updated});
  }

  /// Reorders subtasks of [taskId] to match [orderedSubtaskIds].
  ///
  /// Throws [ArgumentError] if [orderedSubtaskIds] does not exactly match
  /// the set and count of current subtask IDs (e.g. duplicates, missing or extra IDs).
  Future<void> reorderSubtasks(
    String taskId,
    List<String> orderedSubtaskIds,
  ) async {
    final subtasks = await _getSubtasksForTask(taskId);
    final existingIds = subtasks.map((s) => s['id'] as String).toList();

    if (orderedSubtaskIds.length != existingIds.length) {
      throw ArgumentError(
        'Ordered subtask IDs count (${orderedSubtaskIds.length}) does not match existing subtask count (${existingIds.length})',
      );
    }

    final orderedSet = orderedSubtaskIds.toSet();
    if (orderedSet.length != orderedSubtaskIds.length) {
      throw ArgumentError('Ordered subtask IDs contains duplicate IDs');
    }

    final existingSet = existingIds.toSet();
    if (!orderedSet.containsAll(existingSet) ||
        !existingSet.containsAll(orderedSet)) {
      throw ArgumentError(
        'Ordered subtask IDs do not match existing subtask IDs',
      );
    }

    final subtaskMap = {for (final s in subtasks) s['id'] as String: s};
    final reordered = orderedSubtaskIds.map((id) => subtaskMap[id]!).toList();
    await _tasksCollection.doc(taskId).update({'subtasks': reordered});
  }
}
