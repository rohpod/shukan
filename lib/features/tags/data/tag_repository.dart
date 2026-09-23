import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tag.dart';

class TagRepository {
  final FirebaseFirestore _firestore;

  TagRepository(this._firestore);

  CollectionReference<Map<String, dynamic>> get _tagsCollection =>
      _firestore.collection('tags');

  /// Creates a new tag or returns the existing tag ID if one with the same
  /// case-insensitive name already exists for [uid].
  Future<String> createTag({required String uid, required String name}) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Tag name cannot be empty');
    }

    final querySnapshot = await _tagsCollection
        .where('uid', isEqualTo: uid)
        .get();

    for (final doc in querySnapshot.docs) {
      final docName = doc.data()['name'] as String? ?? '';
      if (docName.toLowerCase() == trimmedName.toLowerCase()) {
        return doc.id;
      }
    }

    final docRef = _tagsCollection.doc();
    final data = <String, dynamic>{
      'tagId': docRef.id,
      'uid': uid,
      'name': trimmedName,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await docRef.set(data);
    return docRef.id;
  }

  /// Renames an existing tag for [uid].
  ///
  /// Reuses the same case-insensitive duplicate validation as [createTag].
  /// Throws [ArgumentError] if [newName] is empty or if another tag with the same
  /// case-insensitive name already exists for [uid].
  Future<void> renameTag({
    required String uid,
    required String tagId,
    required String newName,
  }) async {
    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Tag name cannot be empty');
    }

    final querySnapshot = await _tagsCollection
        .where('uid', isEqualTo: uid)
        .get();

    for (final doc in querySnapshot.docs) {
      if (doc.id != tagId) {
        final docName = doc.data()['name'] as String? ?? '';
        if (docName.toLowerCase() == trimmedName.toLowerCase()) {
          throw ArgumentError('A tag with this name already exists');
        }
      }
    }

    await _tagsCollection.doc(tagId).update({'name': trimmedName});
  }

  /// Deletes a tag and batch-removes its reference from all matching tasks
  /// (both active and soft-deleted) for [uid].
  ///
  /// Chunks task updates in batches of at most [batchChunkSize] (default 450)
  /// to stay well within Firestore's 500-operation batched write limit.
  /// If [preferences] is provided, strips [tagId] from all persisted
  /// `task_tag_filter_<viewKey>` entries.
  Future<void> deleteTag({
    required String uid,
    required String tagId,
    SharedPreferences? preferences,
    int batchChunkSize = 450,
  }) async {
    // 1. Query all tasks (active and soft-deleted) containing this tagId for this user.
    final querySnapshot = await _firestore
        .collection('tasks')
        .where('uid', isEqualTo: uid)
        .where('tagIds', arrayContains: tagId)
        .get();

    final docs = querySnapshot.docs;
    for (var i = 0; i < docs.length; i += batchChunkSize) {
      final end = (i + batchChunkSize < docs.length)
          ? i + batchChunkSize
          : docs.length;
      final chunk = docs.sublist(i, end);
      final batch = _firestore.batch();
      for (final doc in chunk) {
        batch.update(doc.reference, {
          'tagIds': FieldValue.arrayRemove([tagId]),
        });
      }
      await batch.commit();
    }

    // 2. Delete the tag document itself.
    await _tagsCollection.doc(tagId).delete();

    // 3. Clean up persisted SharedPreferences tag filters if provided.
    if (preferences != null) {
      await cleanupPersistedTagFilter(preferences, tagId);
    }
  }

  /// Strips [tagId] from all saved `task_tag_filter_<viewKey>` entries in [preferences].
  static Future<void> cleanupPersistedTagFilter(
    SharedPreferences preferences,
    String tagId,
  ) async {
    final keys = preferences.getKeys();
    for (final key in keys) {
      if (key.startsWith('task_tag_filter_')) {
        if (key == 'task_tag_filter_tag_$tagId') {
          await preferences.remove(key);
          continue;
        }
        final list = preferences.getStringList(key);
        if (list != null && list.contains(tagId)) {
          final updated = list.where((id) => id != tagId).toList();
          if (updated.isEmpty) {
            await preferences.remove(key);
          } else {
            await preferences.setStringList(key, updated);
          }
        }
      }
    }
  }

  /// Streams tags owned by [uid], ordered alphabetically by [name].
  Stream<List<Tag>> streamTagsForUser(String uid) {
    return _tagsCollection
        .where('uid', isEqualTo: uid)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Tag.fromFirestore).toList());
  }
}
