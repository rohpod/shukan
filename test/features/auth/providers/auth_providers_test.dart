import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/providers/auth_providers.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    fakeFirestore = FakeFirebaseFirestore();
  });

  test('currentUidProvider returns null when unauthenticated and uid when signed in', () async {
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
      ],
    );
    addTearDown(container.dispose);

    final uids = <String?>[];
    container.listen<String?>(
      currentUidProvider,
      (previous, next) => uids.add(next),
      fireImmediately: true,
    );

    // Initial state: not signed in
    expect(uids.last, isNull);
    expect(container.read(currentUserProvider), isNull);

    // Sign up
    final repo = container.read(authRepositoryProvider);
    final cred = await repo.createUserWithEmailAndPassword(
      email: 'stream@example.com',
      password: 'password123',
    );

    await pumpEventQueue();

    // Provider now reflects authenticated user
    expect(uids.last, equals(cred.user!.uid));
    expect(
      container.read(currentUserProvider)?.email,
      equals('stream@example.com'),
    );

    // Sign out
    await repo.signOut();
    await pumpEventQueue();

    // Provider now reflects unauthenticated state
    expect(uids.last, isNull);
    expect(container.read(currentUserProvider), isNull);
  });
}
