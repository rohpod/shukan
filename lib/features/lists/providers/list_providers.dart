import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../tasks/providers/task_providers.dart';
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

/// Resolves the effective default list for the user.
///
/// Watches [defaultListIdProvider] and [listsForUserProvider].
/// If lists is non-empty, returns the list whose listId matches the default,
/// else falls back to [lists.first]. Returns null when lists is empty or still loading.
final effectiveDefaultListProvider = Provider<ListModel?>((ref) {
  final defaultListId = ref.watch(defaultListIdProvider).value;
  final lists = ref.watch(listsForUserProvider).value;
  if (lists == null || lists.isEmpty) {
    return null;
  }
  if (defaultListId != null) {
    for (final l in lists) {
      if (l.listId == defaultListId) {
        return l;
      }
    }
  }
  return lists.first;
});
