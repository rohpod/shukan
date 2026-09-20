import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
      order: 0.0,
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
    double? order,
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
    if (order != null) updates['order'] = order;

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

  /// Updates the manual [order] attribute of a single task.
  Future<void> updateTaskOrder(String taskId, double newOrder) async {
    await _tasksCollection.doc(taskId).update({'order': newOrder});
  }

  /// Updates manual [order] attributes for multiple tasks in a single batch.
  Future<void> batchUpdateTaskOrders(Map<String, double> taskIdToOrder) async {
    final batch = _firestore.batch();
    for (final entry in taskIdToOrder.entries) {
      batch.update(_tasksCollection.doc(entry.key), {'order': entry.value});
    }
    await batch.commit();
  }

  /// Backfills `order` for tasks owned by [uid] where order is 0.0 or unassigned.
  /// Orders tasks chronologically by [createdAt] (oldest = lowest).
  Future<void> backfillTaskOrders(String uid) async {
    final snapshot = await _tasksCollection
        .where('uid', isEqualTo: uid)
        .where('deletedAt', isNull: true)
        .get();

    final tasks = snapshot.docs.map(Task.fromFirestore).toList();
    final unbackfilled = tasks.where((t) => t.order == 0.0).toList();
    if (unbackfilled.isEmpty) return;

    tasks.sort((a, b) {
      if (a.createdAt != null && b.createdAt != null) {
        return a.createdAt!.compareTo(b.createdAt!);
      }
      return 0;
    });

    final batch = _firestore.batch();
    for (int i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final newOrder = (i + 1) * 1000.0;
      batch.update(_tasksCollection.doc(task.taskId), {'order': newOrder});
    }
    await batch.commit();
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

  /// Soft-deletes a task by setting its [deletedAt] field to the current timestamp.
  Future<void> softDeleteTask(String taskId) async {
    await _tasksCollection.doc(taskId).update({'deletedAt': Timestamp.now()});
  }

  /// Streams soft-deleted tasks belonging to [uid], ordered descending by [deletedAt].
  ///
  /// Filters by [uid] in Firestore and performs [deletedAt] filtering and sorting in-memory.
  /// This ensures immediate client-cache visibility upon deletion, avoids Firestore composite
  /// index propagation lag, and supports instantaneous offline/local snapshot updates.
  Stream<List<Task>> streamRecentlyDeletedTasks(String uid) {
    return _tasksCollection
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          final tasks = <Task>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            if (data['deletedAt'] == null) {
              continue;
            }
            try {
              var task = Task.fromFirestore(doc);
              if (task.deletedAt == null) {
                task = task.copyWith(deletedAt: DateTime.now());
              }
              tasks.add(task);
            } catch (e, st) {
              debugPrint('Error parsing deleted task ${doc.id}: $e\n$st');
            }
          }
          tasks.sort((a, b) {
            if (a.deletedAt == null && b.deletedAt == null) return 0;
            if (a.deletedAt == null) return 1;
            if (b.deletedAt == null) return -1;
            return b.deletedAt!.compareTo(a.deletedAt!);
          });
          return tasks;
        })
        .distinct((prev, next) => listEquals(prev, next));
  }

  /// Streams active (non-soft-deleted) tasks for [uid] that have a `dueDate`.
  ///
  /// - If [startDueDate] and [endDueDate] are specified, applies server-side range query on [dueDate].
  /// - If only [endDueDate] is specified, applies server-side query `dueDate <= endDueDate` (used by Today view).
  /// - If omitted, queries all tasks where `dueDate != null` (used by Scheduled view).
  /// - If [onlyIncomplete] is true, applies `completedAt == null` equality check in Firestore.
  /// - Tasks are sorted chronologically ascending by [dueDate], tie-broken by [dueTime],
  ///   then [order], then [createdAt].
  Stream<List<Task>> streamTasksWithDueDate({
    required String uid,
    DateTime? startDueDate,
    DateTime? endDueDate,
    bool onlyIncomplete = false,
  }) {
    Query<Map<String, dynamic>> query = _tasksCollection
        .where('uid', isEqualTo: uid)
        .where('deletedAt', isNull: true);

    if (onlyIncomplete) {
      query = query.where('completedAt', isNull: true);
    }

    if (startDueDate != null && endDueDate != null) {
      query = query
          .where(
            'dueDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDueDate),
          )
          .where('dueDate', isLessThanOrEqualTo: Timestamp.fromDate(endDueDate))
          .orderBy('dueDate');
    } else if (endDueDate != null) {
      query = query
          .where('dueDate', isLessThanOrEqualTo: Timestamp.fromDate(endDueDate))
          .orderBy('dueDate');
    } else {
      query = query.where('dueDate', isNull: false).orderBy('dueDate');
    }

    return query
        .snapshots()
        .map((snapshot) {
          final tasks = snapshot.docs.map(Task.fromFirestore).toList();
          tasks.sort((a, b) {
            if (a.dueDate == null && b.dueDate == null) return 0;
            if (a.dueDate == null) return 1;
            if (b.dueDate == null) return -1;
            final dateCmp = a.dueDate!.compareTo(b.dueDate!);
            if (dateCmp != 0) return dateCmp;

            // Tie-break 1: dueTime ("HH:mm")
            if (a.dueTime != null && b.dueTime != null) {
              final timeCmp = a.dueTime!.compareTo(b.dueTime!);
              if (timeCmp != 0) return timeCmp;
            } else if (a.dueTime != null && b.dueTime == null) {
              return -1;
            } else if (a.dueTime == null && b.dueTime != null) {
              return 1;
            }

            // Tie-break 2: order
            final orderCmp = a.order.compareTo(b.order);
            if (orderCmp != 0) return orderCmp;

            // Tie-break 3: createdAt
            if (a.createdAt != null && b.createdAt != null) {
              return a.createdAt!.compareTo(b.createdAt!);
            }
            return 0;
          });
          return tasks;
        })
        .distinct((prev, next) => listEquals(prev, next));
  }

  /// Restores a soft-deleted task by clearing its [deletedAt] timestamp.
  ///
  /// Defense-in-depth:
  /// - Throws [ArgumentError] if the task does not exist or does not belong to [uid].
  /// - No-ops if the task is already active (deletedAt is already null).
  ///
  /// List assignment safeguard:
  /// - If [task.listId] is empty or the referenced list no longer exists in `lists`,
  ///   the task is reassigned to [defaultListId] (or resolved from `users/{uid}`).
  Future<void> restoreTask({
    required String uid,
    required String taskId,
    String? defaultListId,
  }) async {
    final taskDoc = await _tasksCollection.doc(taskId).get();
    if (!taskDoc.exists) {
      throw ArgumentError('Task not found: $taskId');
    }
    final taskData = taskDoc.data()!;
    if (taskData['uid'] != uid) {
      throw ArgumentError('Task does not belong to user: $taskId');
    }

    // Already active / restored
    if (taskData['deletedAt'] == null) {
      return;
    }

    final currentListId = taskData['listId'] as String?;
    String? targetListId = currentListId;

    bool listExists = false;
    if (currentListId != null && currentListId.isNotEmpty) {
      final listDoc = await _firestore
          .collection('lists')
          .doc(currentListId)
          .get();
      listExists = listDoc.exists && listDoc.data()?['uid'] == uid;
    }

    if (!listExists) {
      if (defaultListId != null && defaultListId.isNotEmpty) {
        targetListId = defaultListId;
      } else {
        final userDoc = await _firestore.collection('users').doc(uid).get();
        targetListId = userDoc.data()?['defaultListId'] as String?;
      }
    }

    final updates = <String, dynamic>{'deletedAt': null};
    if (targetListId != null && targetListId != currentListId) {
      updates['listId'] = targetListId;
    }

    await _tasksCollection.doc(taskId).update(updates);
  }

  /// Permanently hard-deletes a task document from Firestore.
  ///
  /// Defense-in-depth:
  /// - Throws [ArgumentError] if the task does not exist or does not belong to [uid].
  Future<void> permanentlyDeleteTask({
    required String uid,
    required String taskId,
  }) async {
    final taskDoc = await _tasksCollection.doc(taskId).get();
    if (!taskDoc.exists) {
      throw ArgumentError('Task not found: $taskId');
    }
    if (taskDoc.data()?['uid'] != uid) {
      throw ArgumentError('Task does not belong to user: $taskId');
    }

    await _tasksCollection.doc(taskId).delete();
  }

  /// Permanently deletes all soft-deleted tasks belonging to [uid].
  ///
  /// Chunks deletions into batches of max 500 operations to respect Firestore's WriteBatch limit.
  Future<void> emptyRecentlyDeleted(String uid) async {
    final snapshot = await _tasksCollection.where('uid', isEqualTo: uid).get();

    final docs = snapshot.docs
        .where((doc) => doc.data()['deletedAt'] != null)
        .toList();

    if (docs.isEmpty) return;

    const batchSize = 500;
    for (var i = 0; i < docs.length; i += batchSize) {
      final end = (i + batchSize < docs.length) ? i + batchSize : docs.length;
      final chunk = docs.sublist(i, end);
      final batch = _firestore.batch();
      for (final doc in chunk) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  /// Automatically purges soft-deleted tasks belonging to [uid] that were deleted
  /// longer ago than [retention] (defaults to 30 days).
  ///
  /// Returns the number of permanently purged tasks.
  Future<int> purgeExpiredDeletedTasks(
    String uid, {
    Duration retention = const Duration(days: 30),
  }) async {
    final snapshot = await _tasksCollection.where('uid', isEqualTo: uid).get();
    final now = DateTime.now();
    final expiredDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final deletedAtRaw = data['deletedAt'];
      if (deletedAtRaw == null) continue;

      DateTime? deletedAt;
      if (deletedAtRaw is Timestamp) {
        deletedAt = deletedAtRaw.toDate();
      } else if (deletedAtRaw is DateTime) {
        deletedAt = deletedAtRaw;
      } else if (deletedAtRaw is String) {
        deletedAt = DateTime.tryParse(deletedAtRaw);
      }

      if (deletedAt != null && now.difference(deletedAt) >= retention) {
        expiredDocs.add(doc);
      }
    }

    if (expiredDocs.isEmpty) return 0;

    const batchSize = 500;
    for (var i = 0; i < expiredDocs.length; i += batchSize) {
      final end = (i + batchSize < expiredDocs.length)
          ? i + batchSize
          : expiredDocs.length;
      final chunk = expiredDocs.sublist(i, end);
      final batch = _firestore.batch();
      for (final doc in chunk) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    return expiredDocs.length;
  }

  /// Moves an existing task to [newListId], updating only its [listId] field.
  ///
  /// Verifies that the target list exists and belongs to the same user as the task.
  /// Throws [ArgumentError] if the task or target list doesn't exist, or if the
  /// target list belongs to a different user.
  Future<void> moveTaskToList(String taskId, String newListId) async {
    final taskDoc = await _tasksCollection.doc(taskId).get();
    if (!taskDoc.exists) {
      throw ArgumentError('Task not found: $taskId');
    }
    final uid = taskDoc.data()?['uid'];

    final listDoc = await _firestore.collection('lists').doc(newListId).get();
    if (!listDoc.exists) {
      throw ArgumentError('List not found: $newListId');
    }
    if (listDoc.data()?['uid'] != uid) {
      throw ArgumentError('List does not belong to user: $newListId');
    }

    await _tasksCollection.doc(taskId).update({'listId': newListId});
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
