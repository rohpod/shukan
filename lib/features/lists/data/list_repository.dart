import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/settled_write.dart';
import 'list.dart';

class ListRepository {
  final FirebaseFirestore _firestore;
  final void Function(Object error)? _onLateWriteFailure;

  ListRepository(this._firestore, [this._onLateWriteFailure]);

  Future<void> _write(Future<void> write) =>
      settleWrite(write, onLateFailure: _onLateWriteFailure);

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

    await _write(
      docRef.set({
        'listId': docRef.id,
        'uid': uid,
        'name': trimmedName,
        'createdAt': FieldValue.serverTimestamp(),
        'isDefault': false,
      }),
    );

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
    await _write(_listsCollection.doc(listId).update({'name': newName.trim()}));
  }

  /// Updates a list's icon.
  Future<void> updateListIcon(String listId, String iconKey) async {
    await _write(_listsCollection.doc(listId).update({'icon': iconKey}));
  }

  /// Deletes a list and soft-deletes all its active tasks.
  ///
  /// Tasks are written in chunks of [batchChunkSize], and the list goes last,
  /// so a failure partway leaves the list in place to delete again.
  ///
  /// Defence-in-depth:
  /// - Throws [StateError] if the list does not exist.
  /// - Throws [StateError] immediately if `isDefault == true`, with no writes attempted.
  Future<void> deleteList(
    String listId,
    String uid, {
    int batchChunkSize = 450,
  }) async {
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

    final now = Timestamp.now();
    final taskDocs = tasksSnapshot.docs;
    for (var i = 0; i < taskDocs.length; i += batchChunkSize) {
      final end = (i + batchChunkSize < taskDocs.length)
          ? i + batchChunkSize
          : taskDocs.length;
      final batch = _firestore.batch();
      for (final taskDoc in taskDocs.sublist(i, end)) {
        batch.update(taskDoc.reference, {'deletedAt': now});
      }
      await _write(batch.commit());
    }

    await _write(_listsCollection.doc(listId).delete());
  }
}
