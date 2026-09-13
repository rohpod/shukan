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

/// Notifier managing the currently selected list ID in local UI state.
/// When `null`, the UI falls back to the user's default list.
class SelectedListIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? listId) {
    state = listId;
  }

  @override
  set state(String? value) => super.state = value;
}

final selectedListIdProvider =
    NotifierProvider<SelectedListIdNotifier, String?>(SelectedListIdNotifier.new);
