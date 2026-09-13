import 'package:cloud_firestore/cloud_firestore.dart';

import 'list.dart';

class ListRepository {
  final FirebaseFirestore _firestore;

  ListRepository(this._firestore);

  CollectionReference<Map<String, dynamic>> get _listsCollection =>
      _firestore.collection('lists');

  CollectionReference<Map<String, dynamic>> get _tasksCollection =>
      _firestore.collection('tasks');

  /// Creates a new user list.
  /// Always writes `isDefault: false` and uses `FieldValue.serverTimestamp()`.
  Future<ListModel> createList({
    required String uid,
    required String name,
  }) async {
    final docRef = _listsCollection.doc();
    final trimmedName = name.trim();

    await docRef.set({
      'listId': docRef.id,
      'uid': uid,
      'name': trimmedName,
      'createdAt': FieldValue.serverTimestamp(),
      'isDefault': false,
    });

    return ListModel(
      listId: docRef.id,
      uid: uid,
      name: trimmedName,
      createdAt: DateTime.now(),
      isDefault: false,
    );
  }

  /// Streams all lists belonging to [uid] ordered by `createdAt`.
  /// Sorts `isDefault: true` lists to the top client-side to avoid requiring
  /// a composite index in Firestore.
  Stream<List<ListModel>> streamListsForUser(String uid) {
    return _listsCollection
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) {
          final lists = snapshot.docs.map(ListModel.fromFirestore).toList();
          lists.sort((a, b) {
            if (a.isDefault != b.isDefault) {
              return a.isDefault ? -1 : 1;
            }
            if (a.createdAt != null && b.createdAt != null) {
              return a.createdAt!.compareTo(b.createdAt!);
            }
            return 0;
          });
          return lists;
        });
  }

  /// Renames a list. Renaming is allowed for any list, including the default list.
  Future<void> renameList(String listId, String newName) async {
    await _listsCollection.doc(listId).update({'name': newName.trim()});
  }

  /// Returns the number of active (non-soft-deleted) tasks belonging to [listId].
  Future<int> getActiveTaskCountForList({
    required String uid,
    required String listId,
  }) async {
    final snapshot = await _tasksCollection
        .where('uid', isEqualTo: uid)
        .where('listId', isEqualTo: listId)
        .where('deletedAt', isNull: true)
        .get();
    return snapshot.docs.length;
  }

  /// Deletes a list and soft-deletes all its active tasks in a single atomic batch.
  ///
  /// Defence-in-depth:
  /// - Throws [StateError] if the list does not exist.
  /// - Throws [StateError] immediately if `isDefault == true`, with no writes attempted.
  Future<void> deleteList(String listId, String uid) async {
    final listDoc = await _listsCollection.doc(listId).get();
    if (!listDoc.exists) {
      throw StateError('List not found: $listId');
    }

    final data = listDoc.data()!;
    if (data['isDefault'] == true) {
      throw StateError('Cannot delete the default list');
    }

    // Query active tasks belonging to this list
    final tasksSnapshot = await _tasksCollection
        .where('uid', isEqualTo: uid)
        .where('listId', isEqualTo: listId)
        .where('deletedAt', isNull: true)
        .get();

    final batch = _firestore.batch();

    // Soft delete all active tasks in this list
    for (final taskDoc in tasksSnapshot.docs) {
      batch.update(taskDoc.reference, {
        'deletedAt': FieldValue.serverTimestamp(),
      });
    }

    // Delete the list document itself
    batch.delete(_listsCollection.doc(listId));

    await batch.commit();
  }
}
