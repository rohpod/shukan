import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tasks/data/task.dart';
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

  test('taskRepositoryProvider instantiates TaskRepository', () {
    final container = createContainer();
    final repo = container.read(taskRepositoryProvider);
    expect(repo, isNotNull);
  });

  test('defaultListIdProvider streams defaultListId from user doc', () async {
    const uid = 'test-uid';
    const defaultListId = 'inbox-123';

    await fakeFirestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': 'user@example.com',
      'defaultListId': defaultListId,
    });

    final container = createContainer(
      user: MockUser(uid: uid, email: 'user@example.com'),
    );

    final values = <String?>[];
    container.listen<AsyncValue<String?>>(
      defaultListIdProvider,
      (_, next) {
        if (next.hasValue) values.add(next.value);
      },
      fireImmediately: true,
    );

    await pumpEventQueue();

    expect(values, contains(defaultListId));
  });

  test('tasksForListProvider streams tasks for current user and list', () async {
    const uid = 'test-uid';
    const listId = 'inbox-123';

    final container = createContainer(
      user: MockUser(uid: uid, email: 'user@example.com'),
    );

    final emittedTasks = <List<Task>>[];
    container.listen<AsyncValue<List<Task>>>(
      tasksForListProvider(listId),
      (_, next) {
        if (next.hasValue) emittedTasks.add(next.value!);
      },
      fireImmediately: true,
    );

    await pumpEventQueue();
    expect(emittedTasks.last, isEmpty);

    // Create a task
    final repo = container.read(taskRepositoryProvider);
    await repo.createTask(
      uid: uid,
      listId: listId,
      title: 'Provider task',
    );

    await pumpEventQueue();

    expect(emittedTasks.last.length, equals(1));
    expect(emittedTasks.last.first.title, equals('Provider task'));
  });
}
