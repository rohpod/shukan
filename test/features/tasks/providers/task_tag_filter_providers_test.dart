import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/providers/auth_providers.dart';
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
        currentUidProvider.overrideWithValue(uid),
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

  group('tagBrowserEntriesForListProvider', () {
    test(
      'aggregates tags and counts scoped only to the given listId',
      () async {
        const listA = 'list-a';
        const listB = 'list-b';

        // Seed tags
        await fakeFirestore.collection('tags').doc('t-apple').set({
          'tagId': 't-apple',
          'uid': uid,
          'name': 'Apple',
        });
        await fakeFirestore.collection('tags').doc('t-banana').set({
          'tagId': 't-banana',
          'uid': uid,
          'name': 'Banana',
        });

        // Tasks in listA
        await fakeFirestore.collection('tasks').doc('t1').set({
          'taskId': 't1',
          'uid': uid,
          'listId': listA,
          'title': 'Task 1',
          'tagIds': ['t-apple'],
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('t2').set({
          'taskId': 't2',
          'uid': uid,
          'listId': listA,
          'title': 'Task 2',
          'tagIds': ['t-apple', 't-banana'],
          'deletedAt': null,
        });

        // Task in listB (should NOT appear in listA's provider)
        await fakeFirestore.collection('tasks').doc('t3').set({
          'taskId': 't3',
          'uid': uid,
          'listId': listB,
          'title': 'Task 3',
          'tagIds': ['t-banana'],
          'deletedAt': null,
        });

        // Soft-deleted task in listA (should be excluded)
        await fakeFirestore.collection('tasks').doc('t4').set({
          'taskId': 't4',
          'uid': uid,
          'listId': listA,
          'title': 'Task 4',
          'tagIds': ['t-banana'],
          'deletedAt': DateTime.now().toIso8601String(),
        });

        final prefs = await SharedPreferences.getInstance();
        final container = createContainer(prefs: prefs);

        final emissions = <List<TagBrowserEntry>>[];
        container.listen<AsyncValue<List<TagBrowserEntry>>>(
          tagBrowserEntriesForListProvider(listA),
          (_, next) {
            if (next.hasValue) emissions.add(next.value!);
          },
          fireImmediately: true,
        );

        await pumpEventQueue();

        expect(emissions.isNotEmpty, isTrue);
        final entries = emissions.last;
        expect(entries.length, equals(2));
        expect(entries[0].name, equals('Apple'));
        expect(entries[0].taskCount, equals(2)); // t1, t2
        expect(entries[1].name, equals('Banana'));
        expect(entries[1].taskCount, equals(1)); // t2 only, not t3 or t4
      },
    );
  });

  group('tasksForTagGroupedByListProvider', () {
    test('groups active tasks by list, sorts groups alphabetically by listName, sorts tasks by createdAt ascending, and excludes completed tasks', () async {
      const listWork = 'list-work';
      const listPersonal = 'list-personal';

      // Seed lists
      await fakeFirestore.collection('lists').doc(listWork).set({
        'listId': listWork,
        'uid': uid,
        'name': 'Work',
      });
      await fakeFirestore.collection('lists').doc(listPersonal).set({
        'listId': listPersonal,
        'uid': uid,
        'name': 'Personal',
      });

      // Tag
      await fakeFirestore.collection('tags').doc('tag-urgent').set({
        'tagId': 'tag-urgent',
        'uid': uid,
        'name': 'Urgent',
      });

      // Tasks
      final tEarly = DateTime(2026, 1, 1);
      final tLate = DateTime(2026, 1, 2);

      // Work tasks: 2 active tasks
      await fakeFirestore.collection('tasks').doc('w-late').set({
        'taskId': 'w-late',
        'uid': uid,
        'listId': listWork,
        'title': 'Work Later Task',
        'tagIds': ['tag-urgent'],
        'createdAt': Timestamp.fromDate(tLate),
        'completedAt': null,
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('w-early').set({
        'taskId': 'w-early',
        'uid': uid,
        'listId': listWork,
        'title': 'Work Earlier Task',
        'tagIds': ['tag-urgent'],
        'createdAt': Timestamp.fromDate(tEarly),
        'completedAt': null,
        'deletedAt': null,
      });

      // Personal task: 1 active task
      await fakeFirestore.collection('tasks').doc('p-task').set({
        'taskId': 'p-task',
        'uid': uid,
        'listId': listPersonal,
        'title': 'Personal Task',
        'tagIds': ['tag-urgent'],
        'createdAt': Timestamp.fromDate(tEarly),
        'completedAt': null,
        'deletedAt': null,
      });

      // Completed task with the same tag — MUST be excluded
      await fakeFirestore.collection('tasks').doc('completed-task').set({
        'taskId': 'completed-task',
        'uid': uid,
        'listId': listWork,
        'title': 'Completed Task',
        'tagIds': ['tag-urgent'],
        'createdAt': Timestamp.fromDate(tEarly),
        'completedAt': Timestamp.fromDate(tLate),
        'deletedAt': null,
      });

      final prefs = await SharedPreferences.getInstance();
      final container = createContainer(prefs: prefs);

      final emissions = <List<TagTaskListGroup>>[];
      container.listen<AsyncValue<List<TagTaskListGroup>>>(
        tasksForTagGroupedByListProvider('tag-urgent'),
        (_, next) {
          if (next.hasValue) emissions.add(next.value!);
        },
        fireImmediately: true,
      );

      await pumpEventQueue();

      expect(emissions.isNotEmpty, isTrue);
      final groups = emissions.last;

      // Group ordering: Personal, then Work (alphabetical by list name)
      expect(groups.length, equals(2));
      expect(groups[0].listName, equals('Personal'));
      expect(groups[0].tasks.length, equals(1));
      expect(groups[0].tasks[0].taskId, equals('p-task'));

      expect(groups[1].listName, equals('Work'));
      expect(groups[1].tasks.length, equals(2));
      // Within Work group, sorted by createdAt ascending: w-early first, then w-late
      expect(groups[1].tasks[0].taskId, equals('w-early'));
      expect(groups[1].tasks[1].taskId, equals('w-late'));

      // Check zero completed tasks
      for (final g in groups) {
        for (final t in g.tasks) {
          expect(t.isCompleted, isFalse);
          expect(t.taskId, isNot(equals('completed-task')));
        }
      }
    });
  });

  group('tagChipsSectionCollapsedProvider', () {
    test('defaults to true and toggles independently per contextKey', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = createContainer(prefs: prefs);

      expect(container.read(tagChipsSectionCollapsedProvider('home')), isTrue);
      expect(
        container.read(tagChipsSectionCollapsedProvider('list-1')),
        isTrue,
      );

      await container
          .read(tagChipsSectionCollapsedProvider('home').notifier)
          .toggle();
      expect(container.read(tagChipsSectionCollapsedProvider('home')), isFalse);
      expect(
        container.read(tagChipsSectionCollapsedProvider('list-1')),
        isTrue,
      );

      await container
          .read(tagChipsSectionCollapsedProvider('list-1').notifier)
          .toggle();
      expect(
        container.read(tagChipsSectionCollapsedProvider('list-1')),
        isFalse,
      );

      // Verify each context key writes its own key to SharedPreferences
      expect(prefs.getBool('tag_chips_section_collapsed_home'), isFalse);
      expect(prefs.getBool('tag_chips_section_collapsed_list-1'), isFalse);
      expect(
        prefs.getKeys(),
        equals({
          'tag_chips_section_collapsed_home',
          'tag_chips_section_collapsed_list-1',
        }),
      );
    });
  });
}
