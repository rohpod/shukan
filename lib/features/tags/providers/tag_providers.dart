import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/tag.dart';
import '../data/tag_repository.dart';

final tagRepositoryProvider = Provider<TagRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return TagRepository(firestore);
});

/// Family stream provider returning tags for [uid] ordered by name.
final tagsForUserProvider = StreamProvider.family<List<Tag>, String>((
  ref,
  uid,
) {
  final repository = ref.watch(tagRepositoryProvider);
  return repository.streamTagsForUser(uid);
});

/// Stream provider returning tags for the currently authenticated user.
final tagsForCurrentUserProvider = StreamProvider<List<Tag>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Stream.value(const <Tag>[]);
  }
  final repository = ref.watch(tagRepositoryProvider);
  return repository.streamTagsForUser(uid);
});
