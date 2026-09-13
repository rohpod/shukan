import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/list.dart';
import '../data/list_repository.dart';

final listRepositoryProvider = Provider<ListRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return ListRepository(firestore);
});

/// Streams all lists belonging to the currently authenticated user.
final listsForUserProvider = StreamProvider<List<ListModel>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Stream.value(const <ListModel>[]);
  }
  final repository = ref.watch(listRepositoryProvider);
  return repository.streamListsForUser(uid);
});
