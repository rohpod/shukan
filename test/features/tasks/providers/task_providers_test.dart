import 'package:cloud_firestore/cloud_firestore.dart';
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
    container.listen<AsyncValue<String?>>(defaultListIdProvider, (_, next) {
      if (next.hasValue) values.add(next.value);
    }, fireImmediately: true);

    await pumpEventQueue();

    expect(values, contains(defaultListId));
  });

  test(
    'tasksForListProvider streams tasks for current user and list',
    () async {
      const uid = 'test-uid';
      const listId = 'inbox-123';

      final container = createContainer(
        user: MockUser(uid: uid, email: 'user@example.com'),
      );

      final emittedTasks = <List<Task>>[];
      container.listen<AsyncValue<List<Task>>>(tasksForListProvider(listId), (
        _,
        next,
      ) {
        if (next.hasValue) emittedTasks.add(next.value!);
      }, fireImmediately: true);

      await pumpEventQueue();
      expect(emittedTasks.last, isEmpty);

      // Create a task
      final repo = container.read(taskRepositoryProvider);
      await fakeFirestore.collection('lists').doc(listId).set({
        'listId': listId,
        'uid': uid,
        'name': 'Inbox',
        'isDefault': true,
      });
      await repo.createTask(uid: uid, listId: listId, title: 'Provider task');

      await pumpEventQueue();

      expect(emittedTasks.last.length, equals(1));
      expect(emittedTasks.last.first.title, equals('Provider task'));
    },
  );

  test(
    'recentlyDeletedTasksProvider streams soft-deleted tasks for current user',
    () async {
      const uid = 'test-uid';

      final container = createContainer(
        user: MockUser(uid: uid, email: 'user@example.com'),
      );

      final emittedTasks = <List<Task>>[];
      container.listen<AsyncValue<List<Task>>>(recentlyDeletedTasksProvider, (
        _,
        next,
      ) {
        if (next.hasValue) emittedTasks.add(next.value!);
      }, fireImmediately: true);

      await pumpEventQueue();
      expect(emittedTasks.last, isEmpty);

      // Create a soft-deleted task
      await fakeFirestore.collection('tasks').doc('del-1').set({
        'taskId': 'del-1',
        'uid': uid,
        'listId': 'list-1',
        'title': 'Deleted in Provider',
        'deletedAt': Timestamp.now(),
      });

      await pumpEventQueue();

      expect(emittedTasks.last.length, equals(1));
      expect(emittedTasks.last.first.title, equals('Deleted in Provider'));
    },
  );

  test(
    'recentlyDeletedCountProvider returns count of soft-deleted tasks',
    () async {
      const uid = 'test-uid';

      final container = createContainer(
        user: MockUser(uid: uid, email: 'user@example.com'),
      );

      final counts = <int>[];
      container.listen<int>(recentlyDeletedCountProvider, (_, next) {
        counts.add(next);
      }, fireImmediately: true);

      await pumpEventQueue();
      expect(counts.last, equals(0));

      // 1. Add a soft-deleted task
      await fakeFirestore.collection('tasks').doc('del-count-1').set({
        'taskId': 'del-count-1',
        'uid': uid,
        'listId': 'list-1',
        'title': 'Deleted 1',
        'deletedAt': Timestamp.now(),
      });

      await pumpEventQueue();
      expect(counts.last, equals(1));

      // 2. Add an active task (should not change count)
      await fakeFirestore.collection('tasks').doc('active-count').set({
        'taskId': 'active-count',
        'uid': uid,
        'listId': 'list-1',
        'title': 'Active Task',
        'deletedAt': null,
      });

      await pumpEventQueue();
      expect(counts.last, equals(1));

      // 3. Add a second soft-deleted task
      await fakeFirestore.collection('tasks').doc('del-count-2').set({
        'taskId': 'del-count-2',
        'uid': uid,
        'listId': 'list-1',
        'title': 'Deleted 2',
        'deletedAt': Timestamp.now(),
      });

      await pumpEventQueue();
      expect(counts.last, equals(2));
    },
  );
}
