import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@immutable
class Tag {
  final String tagId;
  final String uid;
  final String name;
  final DateTime? createdAt;

  const Tag({
    required this.tagId,
    required this.uid,
    required this.name,
    this.createdAt,
  });

  static DateTime? _parseDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    } else if (value is DateTime) {
      return value;
    }
    return null;
  }

  factory Tag.fromMap(Map<String, dynamic> data, String tagId) {
    return Tag(
      tagId: tagId,
      uid: data['uid'] as String? ?? '',
      name: data['name'] as String? ?? '',
      createdAt: _parseDateTime(data['createdAt']),
    );
  }

  factory Tag.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    return Tag.fromMap(snapshot.data() ?? {}, snapshot.id);
  }

  Map<String, dynamic> toFirestore() {
    return {
      'tagId': tagId,
      'uid': uid,
      'name': name,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
    };
  }

  Map<String, dynamic> toMap() => toFirestore();

  Tag copyWith({
    String? tagId,
    String? uid,
    String? name,
    DateTime? createdAt,
  }) {
    return Tag(
      tagId: tagId ?? this.tagId,
      uid: uid ?? this.uid,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tag &&
          runtimeType == other.runtimeType &&
          tagId == other.tagId &&
          uid == other.uid &&
          name == other.name &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      tagId.hashCode ^ uid.hashCode ^ name.hashCode ^ createdAt.hashCode;

  @override
  String toString() {
    return 'Tag(tagId: $tagId, uid: $uid, name: $name, createdAt: $createdAt)';
  }
}
