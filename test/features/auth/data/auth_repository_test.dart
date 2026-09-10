// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shukan/features/auth/data/auth_repository.dart';

class MockFirestore extends Mock implements FirebaseFirestore {}

class MockWriteBatch extends Mock implements WriteBatch {}

class MockCollectionReference<T extends Object?> extends Mock
    implements CollectionReference<T> {}

class MockDocumentReference<T extends Object?> extends Mock
    implements DocumentReference<T> {}

class FakeDocumentReference<T extends Object?> extends Fake
    implements DocumentReference<T> {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeDocumentReference<Object?>());
    registerFallbackValue(FakeDocumentReference<Map<String, dynamic>>());
    registerFallbackValue(<String, dynamic>{});
  });

  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  late AuthRepository repository;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    fakeFirestore = FakeFirebaseFirestore();
    repository = AuthRepository(mockAuth, fakeFirestore);
  });

  group('AuthRepository - Sign Up & Bootstrap', () {
    test('successful sign-up creates both users/{uid} and lists/{listId} documents correctly linked', () async {
      const email = 'user@example.com';
      const password = 'password123';

      final credential = await repository.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = credential.user!.uid;

      // 1. Verify user document
      final userSnapshot = await fakeFirestore
          .collection('users')
          .doc(uid)
          .get();
      expect(userSnapshot.exists, isTrue);

      final userData = userSnapshot.data()!;
      expect(userData['uid'], equals(uid));
      expect(userData['email'], equals(email));
      expect(userData['displayName'], equals(''));
      expect(userData['createdAt'], isNotNull);

      final defaultListId = userData['defaultListId'] as String;
      expect(defaultListId, isNotEmpty);

      // 2. Verify default list document
      final listSnapshot = await fakeFirestore
          .collection('lists')
          .doc(defaultListId)
          .get();
      expect(listSnapshot.exists, isTrue);

      final listData = listSnapshot.data()!;
      expect(listData['listId'], equals(defaultListId));
      expect(listData['uid'], equals(uid));
      expect(listData['name'], equals('Inbox'));
      expect(listData['isDefault'], isTrue);
      expect(listData['createdAt'], isNotNull);
    });

    test(
      'sign-in restores session and does not duplicate or overwrite lists',
      () async {
        const email = 'existing@example.com';
        const password = 'password123';

        // 1. Create user and bootstrap
        final credential = await repository.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        final uid = credential.user!.uid;

        final userSnapshotBefore = await fakeFirestore
            .collection('users')
            .doc(uid)
            .get();
        final initialDefaultListId = userSnapshotBefore
            .data()!['defaultListId'];

        final listsBefore = await fakeFirestore
            .collection('lists')
            .where('uid', isEqualTo: uid)
            .get();
        expect(listsBefore.docs.length, equals(1));

        // 2. Sign out
        await repository.signOut();
        expect(mockAuth.currentUser, isNull);

        // 3. Sign in
        final signInCredential = await repository.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        expect(signInCredential.user!.uid, equals(uid));

        // 4. Verify no new list created and user doc unchanged
        final listsAfter = await fakeFirestore
            .collection('lists')
            .where('uid', isEqualTo: uid)
            .get();
        expect(listsAfter.docs.length, equals(1));
        expect(listsAfter.docs.first.id, equals(initialDefaultListId));
      },
    );

    test(
      'batch failure does not leave a partial user doc and rethrows error',
      () async {
        final mockFirestore = MockFirestore();
        final mockBatch = MockWriteBatch();
        final mockUsersCollection =
            MockCollectionReference<Map<String, dynamic>>();
        final mockListsCollection =
            MockCollectionReference<Map<String, dynamic>>();
        final mockUserDoc = MockDocumentReference<Map<String, dynamic>>();
        final mockListDoc = MockDocumentReference<Map<String, dynamic>>();

        when(() => mockFirestore.collection('users'))
            .thenReturn(mockUsersCollection);
        when(() => mockFirestore.collection('lists'))
            .thenReturn(mockListsCollection);
        when(() => mockUsersCollection.doc(any())).thenReturn(mockUserDoc);
        when(() => mockListsCollection.doc()).thenReturn(mockListDoc);
        when(() => mockListDoc.id).thenReturn('pre-generated-list-id');

        when(() => mockFirestore.batch()).thenReturn(mockBatch);
        when(() => mockBatch.set(any(), any())).thenReturn(null);
        when(() => mockBatch.commit()).thenThrow(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
            message: 'Firestore temporarily unavailable',
          ),
        );

        final failingRepository = AuthRepository(mockAuth, mockFirestore);

        await expectLater(
          failingRepository.createUserWithEmailAndPassword(
            email: 'fail@example.com',
            password: 'password123',
          ),
          throwsA(isA<FirebaseException>()),
        );

        // Verify that atomic batch.commit was called and error propagated
        verify(() => mockBatch.commit()).called(1);
      },
    );

    test('signOut terminates the session', () async {
      await repository.createUserWithEmailAndPassword(
        email: 'signout@example.com',
        password: 'password123',
      );
      expect(repository.currentUser, isNotNull);

      await repository.signOut();
      expect(repository.currentUser, isNull);
    });
  });
}
