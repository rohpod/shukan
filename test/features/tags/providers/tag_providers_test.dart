import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tags/data/tag.dart';
import 'package:shukan/features/tags/providers/tag_providers.dart';

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

  test('tagRepositoryProvider instantiates TagRepository', () {
    final container = createContainer();
    final repo = container.read(tagRepositoryProvider);
    expect(repo, isNotNull);
  });

  test('tagsForUserProvider streams tags for given uid', () async {
    const uid = 'test-uid';

    final container = createContainer(
      user: MockUser(uid: uid, email: 'user@example.com'),
    );

    final emittedTags = <List<Tag>>[];
    container.listen<AsyncValue<List<Tag>>>(tagsForUserProvider(uid), (
      _,
      next,
    ) {
      if (next.hasValue) emittedTags.add(next.value!);
    }, fireImmediately: true);

    await pumpEventQueue();
    expect(emittedTags.last, isEmpty);

    final repo = container.read(tagRepositoryProvider);
    await repo.createTag(uid: uid, name: 'Personal');

    await pumpEventQueue();

    expect(emittedTags.last.length, equals(1));
    expect(emittedTags.last.first.name, equals('Personal'));
  });

  test(
    'tagsForCurrentUserProvider streams tags for authenticated user',
    () async {
      const uid = 'test-uid';

      final container = createContainer(
        user: MockUser(uid: uid, email: 'user@example.com'),
      );

      final emittedTags = <List<Tag>>[];
      container.listen<AsyncValue<List<Tag>>>(tagsForCurrentUserProvider, (
        _,
        next,
      ) {
        if (next.hasValue) emittedTags.add(next.value!);
      }, fireImmediately: true);

      await pumpEventQueue();
      expect(emittedTags.last, isEmpty);

      final repo = container.read(tagRepositoryProvider);
      await repo.createTag(uid: uid, name: 'Work');

      await pumpEventQueue();

      expect(emittedTags.last.length, equals(1));
      expect(emittedTags.last.first.name, equals('Work'));
    },
  );
}
