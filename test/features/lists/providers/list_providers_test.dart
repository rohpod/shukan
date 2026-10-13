import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/lists/data/list.dart';
import 'package:shukan/features/lists/providers/list_providers.dart';
import 'package:shukan/features/tasks/providers/task_providers.dart';

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

  group('effectiveDefaultListProvider', () {
    test('returns matching list when default is found', () async {
      final list1 = ListModel(
        listId: 'list-1',
        uid: 'u1',
        name: 'Work',
        isDefault: false,
      );
      final list2 = ListModel(
        listId: 'list-2',
        uid: 'u1',
        name: 'Inbox',
        isDefault: true,
      );

      final container = ProviderContainer(
        overrides: [
          defaultListIdProvider.overrideWith((ref) => Stream.value('list-2')),
          listsForUserProvider.overrideWith(
            (ref) => Stream.value([list1, list2]),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(effectiveDefaultListProvider, (_, _) {});
      await pumpEventQueue();

      expect(container.read(effectiveDefaultListProvider), equals(list2));
    });

    test(
      'falls back to lists.first when default is missing or does not match',
      () async {
        final list1 = ListModel(
          listId: 'list-1',
          uid: 'u1',
          name: 'Work',
          isDefault: false,
        );
        final list2 = ListModel(
          listId: 'list-2',
          uid: 'u1',
          name: 'Personal',
          isDefault: false,
        );

        final container = ProviderContainer(
          overrides: [
            defaultListIdProvider.overrideWith(
              (ref) => Stream.value('non-existent'),
            ),
            listsForUserProvider.overrideWith(
              (ref) => Stream.value([list1, list2]),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.listen(effectiveDefaultListProvider, (_, _) {});
        await pumpEventQueue();

        expect(container.read(effectiveDefaultListProvider), equals(list1));
      },
    );

    test('returns null when lists is empty or still loading', () async {
      final containerEmpty = ProviderContainer(
        overrides: [
          defaultListIdProvider.overrideWith((ref) => Stream.value('list-1')),
          listsForUserProvider.overrideWith(
            (ref) => Stream.value(<ListModel>[]),
          ),
        ],
      );
      addTearDown(containerEmpty.dispose);

      containerEmpty.listen(effectiveDefaultListProvider, (_, _) {});
      await pumpEventQueue();

      expect(containerEmpty.read(effectiveDefaultListProvider), isNull);

      final containerLoading = ProviderContainer(
        overrides: [
          defaultListIdProvider.overrideWith(
            (ref) => const Stream<String?>.empty(),
          ),
          listsForUserProvider.overrideWith(
            (ref) => const Stream<List<ListModel>>.empty(),
          ),
        ],
      );
      addTearDown(containerLoading.dispose);

      expect(containerLoading.read(effectiveDefaultListProvider), isNull);
    });
  });
}
