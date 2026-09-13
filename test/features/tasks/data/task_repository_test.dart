import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/data/task_repository.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late TaskRepository repository;

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    repository = TaskRepository(fakeFirestore);

    await fakeFirestore.collection('lists').doc('inbox-456').set({
      'listId': 'inbox-456',
      'uid': 'user-123',
      'name': 'Inbox',
      'isDefault': true,
    });
    await fakeFirestore.collection('lists').doc('list-xyz').set({
      'listId': 'list-xyz',
      'uid': 'user-abc',
      'name': 'Test List',
      'isDefault': false,
    });
  });

  group('TaskRepository', () {
    test(
      'createTask writes full schema with correct defaults and uid/listId set',
      () async {
        const uid = 'user-123';
        const listId = 'inbox-456';
        const title = 'Complete quarterly taxes';
        const notes = 'Check deductions and receipts';
        const url = 'https://irs.gov';

        final task = await repository.createTask(
          uid: uid,
          listId: listId,
          title: title,
          notes: notes,
          url: url,
        );

        // Verify in-memory task entity
        expect(task.taskId, isNotEmpty);
        expect(task.uid, equals(uid));
        expect(task.listId, equals(listId));
        expect(task.title, equals(title));
        expect(task.notes, equals(notes));
        expect(task.url, equals(url));
        expect(task.priority, equals('none'));
        expect(task.tagIds, isEmpty);
        expect(task.dueDate, isNull);
        expect(task.dueTime, isNull);
        expect(task.earlyReminderMinutes, equals(0));
        expect(task.repeatRule, equals('none'));
        expect(task.repeatCustomConfig, isNull);
        expect(task.order, equals(0));
        expect(task.subtasks, isEmpty);
        expect(task.createdAt, isNotNull);
        expect(task.completedAt, isNull);
        expect(task.deletedAt, isNull);
        expect(task.isCompleted, isFalse);
        expect(task.isDeleted, isFalse);

        // Verify persisted Firestore document
        final docSnapshot = await fakeFirestore
            .collection('tasks')
            .doc(task.taskId)
            .get();
        expect(docSnapshot.exists, isTrue);

        final data = docSnapshot.data()!;
        expect(data['taskId'], equals(task.taskId));
        expect(data['uid'], equals(uid));
        expect(data['listId'], equals(listId));
        expect(data['title'], equals(title));
        expect(data['notes'], equals(notes));
        expect(data['url'], equals(url));
        expect(data['priority'], equals('none'));
        expect(data['tagIds'], equals(<String>[]));
        expect(data['dueDate'], isNull);
        expect(data['dueTime'], isNull);
        expect(data['earlyReminderMinutes'], equals(0));
        expect(data['repeatRule'], equals('none'));
        expect(data['repeatCustomConfig'], isNull);
        expect(data['order'], equals(0));
        expect(data['subtasks'], equals(<Map<String, dynamic>>[]));
        expect(data['createdAt'], isNotNull);
        expect(data['completedAt'], isNull);
        expect(data['deletedAt'], isNull);
      },
    );

    test('streamTasksForList excludes soft-deleted tasks and filters by uid+listId correctly', () async {
      const uid = 'user-1';
      const listId = 'list-1';

      // 1. Task matching user and list (active)
      await fakeFirestore.collection('tasks').doc('t1').set({
        'taskId': 't1',
        'uid': uid,
        'listId': listId,
        'title': 'Active Task 1',
        'notes': '',
        'url': '',
        'priority': 'none',
        'tagIds': [],
        'dueDate': null,
        'dueTime': null,
        'earlyReminderMinutes': 0,
        'repeatRule': 'none',
        'repeatCustomConfig': null,
        'order': 0,
        'subtasks': [],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 10, 0)),
        'completedAt': null,
        'deletedAt': null,
      });

      // 2. Soft-deleted task
      await fakeFirestore.collection('tasks').doc('t2').set({
        'taskId': 't2',
        'uid': uid,
        'listId': listId,
        'title': 'Deleted Task',
        'notes': '',
        'url': '',
        'priority': 'none',
        'tagIds': [],
        'dueDate': null,
        'dueTime': null,
        'earlyReminderMinutes': 0,
        'repeatRule': 'none',
        'repeatCustomConfig': null,
        'order': 0,
        'subtasks': [],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 11, 0)),
        'completedAt': null,
        'deletedAt': Timestamp.now(),
      });

      // 3. Task belonging to another user
      await fakeFirestore.collection('tasks').doc('t3').set({
        'taskId': 't3',
        'uid': 'other-user',
        'listId': listId,
        'title': 'Other User Task',
        'notes': '',
        'url': '',
        'priority': 'none',
        'tagIds': [],
        'dueDate': null,
        'dueTime': null,
        'earlyReminderMinutes': 0,
        'repeatRule': 'none',
        'repeatCustomConfig': null,
        'order': 0,
        'subtasks': [],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 12, 0)),
        'completedAt': null,
        'deletedAt': null,
      });

      // 4. Task belonging to another list
      await fakeFirestore.collection('tasks').doc('t4').set({
        'taskId': 't4',
        'uid': uid,
        'listId': 'other-list',
        'title': 'Other List Task',
        'notes': '',
        'url': '',
        'priority': 'none',
        'tagIds': [],
        'dueDate': null,
        'dueTime': null,
        'earlyReminderMinutes': 0,
        'repeatRule': 'none',
        'repeatCustomConfig': null,
        'order': 0,
        'subtasks': [],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 13, 0)),
        'completedAt': null,
        'deletedAt': null,
      });

      final emissions = <List<Task>>[];
      final subscription = repository
          .streamTasksForList(uid, listId)
          .listen(emissions.add);

      await pumpEventQueue();

      expect(emissions.isNotEmpty, isTrue);
      final tasks = emissions.last;
      expect(tasks.length, equals(1));
      expect(tasks.first.taskId, equals('t1'));
      expect(tasks.first.title, equals('Active Task 1'));

      await subscription.cancel();
    });

    test('updateTask only changes the specified fields, leaves placeholder fields untouched', () async {
      final initialTask = await repository.createTask(
        uid: 'user-abc',
        listId: 'list-xyz',
        title: 'Original Title',
        notes: 'Original Notes',
        url: 'https://initial.com',
      );

      await repository.updateTask(
        initialTask.taskId,
        title: 'Updated Title',
        notes: 'Updated Notes',
      );

      final doc = await fakeFirestore
          .collection('tasks')
          .doc(initialTask.taskId)
          .get();
      final data = doc.data()!;

      expect(data['title'], equals('Updated Title'));
      expect(data['notes'], equals('Updated Notes'));
      expect(data['url'], equals('https://initial.com'));
      expect(data['priority'], equals('none'));
      expect(data['tagIds'], isEmpty);
      expect(data['dueDate'], isNull);
      expect(data['earlyReminderMinutes'], equals(0));
      expect(data['repeatRule'], equals('none'));
      expect(data['order'], equals(0));
    });

    test('toggleTaskCompleted sets and clears completedAt', () async {
      final task = await repository.createTask(
        uid: 'user-abc',
        listId: 'list-xyz',
        title: 'Task To Complete',
      );

      // Mark completed
      await repository.toggleTaskCompleted(task.taskId, isCompleted: true);
      var doc = await fakeFirestore.collection('tasks').doc(task.taskId).get();
      expect(doc.data()!['completedAt'], isNotNull);

      // Unmark completed
      await repository.toggleTaskCompleted(task.taskId, isCompleted: false);
      doc = await fakeFirestore.collection('tasks').doc(task.taskId).get();
      expect(doc.data()!['completedAt'], isNull);
    });

    test(
      'softDeleteTask sets deletedAt without removing the document',
      () async {
        final task = await repository.createTask(
          uid: 'user-abc',
          listId: 'list-xyz',
          title: 'Task to Delete',
        );

        await repository.softDeleteTask(task.taskId);

        final doc = await fakeFirestore
            .collection('tasks')
            .doc(task.taskId)
            .get();
        expect(doc.exists, isTrue);
        expect(doc.data()!['deletedAt'], isNotNull);
      },
    );

    test('createTask throws ArgumentError when target list does not exist and does not write task doc', () async {
      const nonExistentListId = 'ghost-list';

      await expectLater(
        repository.createTask(
          uid: 'user-123',
          listId: nonExistentListId,
          title: 'Orphan task',
        ),
        throwsA(isA<ArgumentError>()),
      );

      final tasksSnapshot = await fakeFirestore.collection('tasks').get();
      expect(tasksSnapshot.docs.isEmpty, isTrue);
    });

    test('createTask throws ArgumentError when target list belongs to a different uid and does not write task doc', () async {
      // list-xyz belongs to user-abc, but we attempt creation as user-123
      await expectLater(
        repository.createTask(
          uid: 'user-123',
          listId: 'list-xyz',
          title: 'Unauthorized list task',
        ),
        throwsA(isA<ArgumentError>()),
      );

      final tasksSnapshot = await fakeFirestore.collection('tasks').get();
      expect(tasksSnapshot.docs.isEmpty, isTrue);
    });
  });
}
