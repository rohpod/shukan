import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// Streams tags owned by [uid], ordered alphabetically by [name].
  Stream<List<Tag>> streamTagsForUser(String uid) {
    return _tagsCollection
        .where('uid', isEqualTo: uid)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Tag.fromFirestore).toList());
  }
}
