import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/lists/data/list.dart';
import 'package:shukan/features/lists/providers/list_providers.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    fakeFirestore = FakeFirebaseFirestore();
  });

  ProviderContainer createContainer({MockUser? user}) {
    if (user != null) {
      mockAuth = MockFirebaseAuth(mockUser: user, signedIn: true);
    }
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('listRepositoryProvider instantiates ListRepository', () {
    final container = createContainer();
    final repo = container.read(listRepositoryProvider);
    expect(repo, isNotNull);
  });

  test('listsForUserProvider streams lists for authenticated user', () async {
    const uid = 'test-uid';
    const listId = 'list-123';

    await fakeFirestore.collection('lists').doc(listId).set({
      'listId': listId,
      'uid': uid,
      'name': 'Work',
      'isDefault': false,
    });

    final container = createContainer(
      user: MockUser(uid: uid, email: 'user@example.com'),
    );

    final emitted = <List<ListModel>>[];
    container.listen<AsyncValue<List<ListModel>>>(listsForUserProvider, (
      _,
      next,
    ) {
      if (next.hasValue) emitted.add(next.value!);
    }, fireImmediately: true);

    await pumpEventQueue();

    expect(emitted.isNotEmpty, isTrue);
    expect(emitted.last.length, equals(1));
    expect(emitted.last.first.name, equals('Work'));

    // Create a new list via repository
    final repo = container.read(listRepositoryProvider);
    await repo.createList(uid: uid, name: 'Personal');

    await pumpEventQueue();

    expect(emitted.last.length, equals(2));
  });

  test('listsForUserProvider emits empty list when unauthenticated', () async {
    final container = createContainer();

    final emitted = <List<ListModel>>[];
    container.listen<AsyncValue<List<ListModel>>>(listsForUserProvider, (
      _,
      next,
    ) {
      if (next.hasValue) emitted.add(next.value!);
    }, fireImmediately: true);

    await pumpEventQueue();

    expect(emitted.isNotEmpty, isTrue);
    expect(emitted.last, isEmpty);
  });
}
