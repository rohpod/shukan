import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@immutable
class ListModel {
  final String listId;
  final String uid;
  final String name;
  final DateTime? createdAt;
  final bool isDefault;

  const ListModel({
    required this.listId,
    required this.uid,
    required this.name,
    this.createdAt,
    this.isDefault = false,
  });

  static DateTime? _parseDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    } else if (value is DateTime) {
      return value;
    }
    return null;
  }

  factory ListModel.fromMap(Map<String, dynamic> data, String listId) {
    return ListModel(
      listId: listId,
      uid: data['uid'] as String? ?? '',
      name: data['name'] as String? ?? '',
      createdAt: _parseDateTime(data['createdAt']),
      isDefault: data['isDefault'] as bool? ?? false,
    );
  }

  factory ListModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return ListModel.fromMap(snapshot.data() ?? {}, snapshot.id);
  }

  Map<String, dynamic> toFirestore() {
    return {
      'listId': listId,
      'uid': uid,
      'name': name,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      'isDefault': isDefault,
    };
  }

  Map<String, dynamic> toMap() => toFirestore();

  ListModel copyWith({
    String? listId,
    String? uid,
    String? name,
    DateTime? createdAt,
    bool? isDefault,
  }) {
    return ListModel(
      listId: listId ?? this.listId,
      uid: uid ?? this.uid,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListModel &&
          runtimeType == other.runtimeType &&
          listId == other.listId &&
          uid == other.uid &&
          name == other.name &&
          createdAt == other.createdAt &&
          isDefault == other.isDefault;

  @override
  int get hashCode =>
      listId.hashCode ^
      uid.hashCode ^
      name.hashCode ^
      createdAt.hashCode ^
      isDefault.hashCode;

  @override
  String toString() {
    return 'ListModel(listId: $listId, uid: $uid, name: $name, isDefault: $isDefault)';
  }
}
