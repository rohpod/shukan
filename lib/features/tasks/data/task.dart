import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@immutable
class Task {
  final String taskId;
  final String uid;
  final String listId;
  final String title;
  final String notes;
  final String url;
  final String priority;
  final List<String> tagIds;
  final DateTime? dueDate;
  final String? dueTime;
  final int earlyReminderMinutes;
  final String repeatRule;
  final Map<String, dynamic>? repeatCustomConfig;
  final int order;
  final List<Map<String, dynamic>> subtasks;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final DateTime? deletedAt;

  const Task({
    required this.taskId,
    required this.uid,
    required this.listId,
    required this.title,
    this.notes = '',
    this.url = '',
    this.priority = 'none',
    this.tagIds = const [],
    this.dueDate,
    this.dueTime,
    this.earlyReminderMinutes = 0,
    this.repeatRule = 'none',
    this.repeatCustomConfig,
    this.order = 0,
    this.subtasks = const [],
    this.createdAt,
    this.completedAt,
    this.deletedAt,
  });

  bool get isCompleted => completedAt != null;
  bool get isDeleted => deletedAt != null;

  static DateTime? _parseDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    } else if (value is DateTime) {
      return value;
    }
    return null;
  }

  factory Task.fromMap(Map<String, dynamic> data, String taskId) {
    return Task(
      taskId: taskId,
      uid: data['uid'] as String? ?? '',
      listId: data['listId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      url: data['url'] as String? ?? '',
      priority: data['priority'] as String? ?? 'none',
      tagIds:
          (data['tagIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      dueDate: _parseDateTime(data['dueDate']),
      dueTime: data['dueTime'] as String?,
      earlyReminderMinutes: ((data['earlyReminderMinutes'] as num?) ?? 0)
          .toInt(),
      repeatRule: data['repeatRule'] as String? ?? 'none',
      repeatCustomConfig: data['repeatCustomConfig'] != null
          ? Map<String, dynamic>.from(data['repeatCustomConfig'] as Map)
          : null,
      order: ((data['order'] as num?) ?? 0).toInt(),
      subtasks:
          (data['subtasks'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      createdAt: _parseDateTime(data['createdAt']),
      completedAt: _parseDateTime(data['completedAt']),
      deletedAt: _parseDateTime(data['deletedAt']),
    );
  }

  factory Task.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    return Task.fromMap(snapshot.data() ?? {}, snapshot.id);
  }

  Map<String, dynamic> toFirestore() {
    return {
      'taskId': taskId,
      'uid': uid,
      'listId': listId,
      'title': title,
      'notes': notes,
      'url': url,
      'priority': priority,
      'tagIds': tagIds,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'dueTime': dueTime,
      'earlyReminderMinutes': earlyReminderMinutes,
      'repeatRule': repeatRule,
      'repeatCustomConfig': repeatCustomConfig,
      'order': order,
      'subtasks': subtasks,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      'completedAt': completedAt != null
          ? Timestamp.fromDate(completedAt!)
          : null,
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
    };
  }

  Map<String, dynamic> toMap() => toFirestore();

  Task copyWith({
    String? taskId,
    String? uid,
    String? listId,
    String? title,
    String? notes,
    String? url,
    String? priority,
    List<String>? tagIds,
    DateTime? dueDate,
    String? dueTime,
    int? earlyReminderMinutes,
    String? repeatRule,
    Map<String, dynamic>? repeatCustomConfig,
    int? order,
    List<Map<String, dynamic>>? subtasks,
    DateTime? createdAt,
    DateTime? completedAt,
    DateTime? deletedAt,
  }) {
    return Task(
      taskId: taskId ?? this.taskId,
      uid: uid ?? this.uid,
      listId: listId ?? this.listId,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      url: url ?? this.url,
      priority: priority ?? this.priority,
      tagIds: tagIds ?? this.tagIds,
      dueDate: dueDate ?? this.dueDate,
      dueTime: dueTime ?? this.dueTime,
      earlyReminderMinutes: earlyReminderMinutes ?? this.earlyReminderMinutes,
      repeatRule: repeatRule ?? this.repeatRule,
      repeatCustomConfig: repeatCustomConfig ?? this.repeatCustomConfig,
      order: order ?? this.order,
      subtasks: subtasks ?? this.subtasks,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  static bool _subtasksEquals(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!mapEquals(a[i], b[i])) return false;
    }
    return true;
  }

  static int _subtasksHash(List<Map<String, dynamic>> subtasks) {
    return Object.hashAll(
      subtasks.map((s) => Object.hash(s['id'], s['title'], s['completed'])),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task &&
          runtimeType == other.runtimeType &&
          taskId == other.taskId &&
          uid == other.uid &&
          listId == other.listId &&
          title == other.title &&
          notes == other.notes &&
          url == other.url &&
          priority == other.priority &&
          listEquals(tagIds, other.tagIds) &&
          dueDate == other.dueDate &&
          dueTime == other.dueTime &&
          earlyReminderMinutes == other.earlyReminderMinutes &&
          repeatRule == other.repeatRule &&
          _subtasksEquals(subtasks, other.subtasks) &&
          order == other.order &&
          createdAt == other.createdAt &&
          completedAt == other.completedAt &&
          deletedAt == other.deletedAt;

  @override
  int get hashCode =>
      taskId.hashCode ^
      uid.hashCode ^
      listId.hashCode ^
      title.hashCode ^
      notes.hashCode ^
      url.hashCode ^
      priority.hashCode ^
      dueDate.hashCode ^
      dueTime.hashCode ^
      earlyReminderMinutes.hashCode ^
      repeatRule.hashCode ^
      _subtasksHash(subtasks) ^
      order.hashCode ^
      createdAt.hashCode ^
      completedAt.hashCode ^
      deletedAt.hashCode;

  @override
  String toString() {
    return 'Task(taskId: $taskId, uid: $uid, listId: $listId, title: $title, '
        'isCompleted: $isCompleted, isDeleted: $isDeleted)';
  }
}
