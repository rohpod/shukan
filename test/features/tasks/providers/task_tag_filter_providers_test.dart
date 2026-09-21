import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';
import 'package:shukan/features/tasks/providers/task_tag_filter_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  const uid = 'test-user-123';

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'test@example.com'),
      signedIn: true,
    );
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer createContainer({SharedPreferences? prefs}) {
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('TaskTagFilterNotifier', () {
    test('defaults to empty set for standard viewKey', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = createContainer(prefs: prefs);

      final filter = container.read(taskTagFilterProvider('inbox'));
      expect(filter, isEmpty);
    });

    test('defaults to tagId when viewKey starts with tag_', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = createContainer(prefs: prefs);

      final filter = container.read(taskTagFilterProvider('tag_tag-work'));
      expect(filter, equals({'tag-work'}));
    });

    test('toggles tag selection and persists to SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = createContainer(prefs: prefs);

      final notifier = container.read(taskTagFilterProvider('list-1').notifier);
      expect(container.read(taskTagFilterProvider('list-1')), isEmpty);

      // Add tag
      final added = await notifier.toggleTag('tag-urgent');
      expect(added, isTrue);
      expect(
        container.read(taskTagFilterProvider('list-1')),
        equals({'tag-urgent'}),
      );
      expect(
        prefs.getStringList('task_tag_filter_list-1'),
        equals(['tag-urgent']),
      );

      // Add second tag
      await notifier.toggleTag('tag-home');
      expect(
        container.read(taskTagFilterProvider('list-1')),
        equals({'tag-urgent', 'tag-home'}),
      );

      // Remove first tag
      final removed = await notifier.toggleTag('tag-urgent');
      expect(removed, isTrue);
      expect(
        container.read(taskTagFilterProvider('list-1')),
        equals({'tag-home'}),
      );
      expect(
        prefs.getStringList('task_tag_filter_list-1'),
        equals(['tag-home']),
      );
    });

    test('enforces maximum 30 tags limit and rejects 31st tag', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = createContainer(prefs: prefs);
      final notifier = container.read(
        taskTagFilterProvider('list-cap').notifier,
      );

      for (var i = 1; i <= 30; i++) {
        final success = await notifier.toggleTag('tag-$i');
        expect(success, isTrue);
      }
      expect(
        container.read(taskTagFilterProvider('list-cap')).length,
        equals(30),
      );

      // Attempt 31st tag
      final excess = await notifier.toggleTag('tag-31');
      expect(excess, isFalse);
      expect(
        container.read(taskTagFilterProvider('list-cap')).length,
        equals(30),
      );
      expect(
        container.read(taskTagFilterProvider('list-cap')).contains('tag-31'),
        isFalse,
      );
    });

    test(
      'clearAll clears selection and removes SharedPreferences key',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final container = createContainer(prefs: prefs);
        final notifier = container.read(
          taskTagFilterProvider('list-clear').notifier,
        );

        await notifier.toggleTag('t1');
        await notifier.toggleTag('t2');
        expect(container.read(taskTagFilterProvider('list-clear')), isNotEmpty);

        await notifier.clearAll();
        expect(container.read(taskTagFilterProvider('list-clear')), isEmpty);
        expect(prefs.getStringList('task_tag_filter_list-clear'), isNull);
      },
    );

    test('restores saved tags across container reloads', () async {
      SharedPreferences.setMockInitialValues({
        'task_tag_filter_restored': ['tag-alpha', 'tag-beta'],
      });
      final prefs = await SharedPreferences.getInstance();
      final container = createContainer(prefs: prefs);

      final filter = container.read(taskTagFilterProvider('restored'));
      expect(filter, equals({'tag-alpha', 'tag-beta'}));
    });
  });

  group('tagBrowserEntriesProvider', () {
    test('computes unique tag set, counts, and alphabetical ordering from active tasks', () async {
      // Seed tags
      await fakeFirestore.collection('tags').doc('t-z').set({
        'tagId': 't-z',
        'uid': uid,
        'name': 'Zebra',
      });
      await fakeFirestore.collection('tags').doc('t-a').set({
        'tagId': 't-a',
        'uid': uid,
        'name': 'Apple',
      });
      await fakeFirestore.collection('tags').doc('t-b').set({
        'tagId': 't-b',
        'uid': uid,
        'name': 'Banana',
      });

      // Seed active tasks
      await fakeFirestore.collection('tasks').doc('task-1').set({
        'taskId': 'task-1',
        'uid': uid,
        'title': 'Task 1',
        'tagIds': ['t-z', 't-a'],
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('task-2').set({
        'taskId': 'task-2',
        'uid': uid,
        'title': 'Task 2',
        'tagIds': ['t-a', 't-b'],
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('task-3').set({
        'taskId': 'task-3',
        'uid': uid,
        'title': 'Task 3',
        'tagIds': ['t-a'],
        'deletedAt': null,
      });
      // Soft deleted task with tag — must be excluded
      await fakeFirestore.collection('tasks').doc('task-deleted').set({
        'taskId': 'task-deleted',
        'uid': uid,
        'title': 'Deleted Task',
        'tagIds': ['t-z', 't-b'],
        'deletedAt': DateTime.now().toIso8601String(),
      });
      // Other user task — must be excluded
      await fakeFirestore.collection('tasks').doc('task-other').set({
        'taskId': 'task-other',
        'uid': 'other-user',
        'title': 'Other User Task',
        'tagIds': ['t-b'],
        'deletedAt': null,
      });

      final prefs = await SharedPreferences.getInstance();
      final container = createContainer(prefs: prefs);

      // Listen to provider
      final emissions = <List<TagBrowserEntry>>[];
      container.listen<AsyncValue<List<TagBrowserEntry>>>(
        tagBrowserEntriesProvider,
        (_, next) {
          if (next.hasValue) emissions.add(next.value!);
        },
        fireImmediately: true,
      );

      await pumpEventQueue();

      expect(emissions.isNotEmpty, isTrue);
      final entries = emissions.last;
      expect(entries.length, equals(3));

      // Alphabetical ordering: Apple, Banana, Zebra
      expect(entries[0].name, equals('Apple'));
      expect(entries[0].taskCount, equals(3)); // task-1, task-2, task-3

      expect(entries[1].name, equals('Banana'));
      expect(entries[1].taskCount, equals(1)); // task-2

      expect(entries[2].name, equals('Zebra'));
      expect(entries[2].taskCount, equals(1)); // task-1
    });
  });
}
