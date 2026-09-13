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

    test('updateTask persists each new field individually', () async {
      final task = await repository.createTask(
        uid: 'user-abc',
        listId: 'list-xyz',
        title: 'Base Task',
      );

      // 1. Priority
      await repository.updateTask(task.taskId, priority: 'high');
      var doc = await fakeFirestore.collection('tasks').doc(task.taskId).get();
      expect(doc.data()!['priority'], equals('high'));

      // 2. Tag IDs
      await repository.updateTask(task.taskId, tagIds: ['tag-1', 'tag-2']);
      doc = await fakeFirestore.collection('tasks').doc(task.taskId).get();
      expect(doc.data()!['tagIds'], equals(['tag-1', 'tag-2']));

      // 3. Due Date
      final targetDate = DateTime(2026, 12, 25);
      await repository.updateTask(task.taskId, dueDate: targetDate);
      doc = await fakeFirestore.collection('tasks').doc(task.taskId).get();
      expect(
        (doc.data()!['dueDate'] as Timestamp).toDate(),
        equals(targetDate),
      );

      // 4. Due Time
      await repository.updateTask(task.taskId, dueTime: '15:45');
      doc = await fakeFirestore.collection('tasks').doc(task.taskId).get();
      expect(doc.data()!['dueTime'], equals('15:45'));

      // 5. Early Reminder Minutes
      await repository.updateTask(task.taskId, earlyReminderMinutes: 30);
      doc = await fakeFirestore.collection('tasks').doc(task.taskId).get();
      expect(doc.data()!['earlyReminderMinutes'], equals(30));

      // 6. Repeat Rule
      await repository.updateTask(task.taskId, repeatRule: 'monthly');
      doc = await fakeFirestore.collection('tasks').doc(task.taskId).get();
      expect(doc.data()!['repeatRule'], equals('monthly'));
    });

    test('updateTask persists all new fields together', () async {
      final task = await repository.createTask(
        uid: 'user-abc',
        listId: 'list-xyz',
        title: 'Combined Task',
      );

      final dueDate = DateTime(2026, 11, 20);

      await repository.updateTask(
        task.taskId,
        priority: 'medium',
        tagIds: ['tag-work', 'tag-urgent'],
        dueDate: dueDate,
        dueTime: '09:30',
        earlyReminderMinutes: 15,
        repeatRule: 'weekly',
      );

      final doc = await fakeFirestore
          .collection('tasks')
          .doc(task.taskId)
          .get();
      final data = doc.data()!;

      expect(data['priority'], equals('medium'));
      expect(data['tagIds'], equals(['tag-work', 'tag-urgent']));
      expect((data['dueDate'] as Timestamp).toDate(), equals(dueDate));
      expect(data['dueTime'], equals('09:30'));
      expect(data['earlyReminderMinutes'], equals(15));
      expect(data['repeatRule'], equals('weekly'));
    });

    test('updateTask clears dueDate and dueTime', () async {
      final task = await repository.createTask(
        uid: 'user-abc',
        listId: 'list-xyz',
        title: 'Timed Task',
      );

      // Set initial date & time
      await repository.updateTask(
        task.taskId,
        dueDate: DateTime(2026, 10, 10),
        dueTime: '11:00',
      );
      var doc = await fakeFirestore.collection('tasks').doc(task.taskId).get();
      expect(doc.data()!['dueDate'], isNotNull);
      expect(doc.data()!['dueTime'], equals('11:00'));

      // Clear only dueTime
      await repository.updateTask(task.taskId, clearDueTime: true);
      doc = await fakeFirestore.collection('tasks').doc(task.taskId).get();
      expect(doc.data()!['dueDate'], isNotNull);
      expect(doc.data()!['dueTime'], isNull);

      // Restore dueTime
      await repository.updateTask(task.taskId, dueTime: '12:00');
      doc = await fakeFirestore.collection('tasks').doc(task.taskId).get();
      expect(doc.data()!['dueTime'], equals('12:00'));

      // Clearing dueDate automatically clears dueTime if dueTime is not explicitly passed
      await repository.updateTask(task.taskId, clearDueDate: true);
      doc = await fakeFirestore.collection('tasks').doc(task.taskId).get();
      expect(doc.data()!['dueDate'], isNull);
      expect(doc.data()!['dueTime'], isNull);
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

    group('Subtasks', () {
      test('addSubtask appends new subtask with uuid, trimmed title, and false completed', () async {
        final task = await repository.createTask(
          uid: 'user-123',
          listId: 'inbox-456',
          title: 'Parent Task',
        );

        await repository.addSubtask(task.taskId, '  First subtask  ');

        final doc = await fakeFirestore
            .collection('tasks')
            .doc(task.taskId)
            .get();
        final subtasks = (doc.data()!['subtasks'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        expect(subtasks.length, equals(1));
        expect(subtasks[0]['id'], isNotEmpty);
        expect(subtasks[0]['title'], equals('First subtask'));
        expect(subtasks[0]['completed'], isFalse);

        // Add second subtask
        await repository.addSubtask(task.taskId, 'Second subtask');
        final doc2 = await fakeFirestore
            .collection('tasks')
            .doc(task.taskId)
            .get();
        final subtasks2 = (doc2.data()!['subtasks'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        expect(subtasks2.length, equals(2));
        expect(subtasks2[0]['title'], equals('First subtask'));
        expect(subtasks2[1]['title'], equals('Second subtask'));
        expect(subtasks2[1]['id'], isNot(equals(subtasks2[0]['id'])));
      });

      test(
        'addSubtask throws ArgumentError on empty title or non-existent task',
        () async {
          final task = await repository.createTask(
            uid: 'user-123',
            listId: 'inbox-456',
            title: 'Parent Task',
          );

          await expectLater(
            repository.addSubtask(task.taskId, '   '),
            throwsA(isA<ArgumentError>()),
          );

          await expectLater(
            repository.addSubtask('non-existent-task', 'Subtask'),
            throwsA(isA<ArgumentError>()),
          );
        },
      );

      test('toggleSubtask updates target subtask completed flag, leaves others intact', () async {
        final task = await repository.createTask(
          uid: 'user-123',
          listId: 'inbox-456',
          title: 'Parent Task',
        );

        await repository.addSubtask(task.taskId, 'Subtask 1');
        await repository.addSubtask(task.taskId, 'Subtask 2');

        final initialDoc = await fakeFirestore
            .collection('tasks')
            .doc(task.taskId)
            .get();
        final subtasks = (initialDoc.data()!['subtasks'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final sub1Id = subtasks[0]['id'] as String;

        // Toggle subtask 1 to completed
        await repository.toggleSubtask(task.taskId, sub1Id, completed: true);

        var doc = await fakeFirestore
            .collection('tasks')
            .doc(task.taskId)
            .get();
        var currentSubtasks = (doc.data()!['subtasks'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        expect(currentSubtasks[0]['completed'], isTrue);
        expect(currentSubtasks[1]['completed'], isFalse);

        // Toggle subtask 1 back to incomplete
        await repository.toggleSubtask(task.taskId, sub1Id, completed: false);
        doc = await fakeFirestore.collection('tasks').doc(task.taskId).get();
        currentSubtasks = (doc.data()!['subtasks'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        expect(currentSubtasks[0]['completed'], isFalse);

        // Throws if subtaskId not found
        await expectLater(
          repository.toggleSubtask(
            task.taskId,
            'unknown-subtask-id',
            completed: true,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test(
        'removeSubtask deletes target subtask and preserves order of remaining',
        () async {
          final task = await repository.createTask(
            uid: 'user-123',
            listId: 'inbox-456',
            title: 'Parent Task',
          );

          await repository.addSubtask(task.taskId, 'Subtask 1');
          await repository.addSubtask(task.taskId, 'Subtask 2');
          await repository.addSubtask(task.taskId, 'Subtask 3');

          final initialDoc = await fakeFirestore
              .collection('tasks')
              .doc(task.taskId)
              .get();
          final subtasks = (initialDoc.data()!['subtasks'] as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final sub2Id = subtasks[1]['id'] as String;

          await repository.removeSubtask(task.taskId, sub2Id);

          final doc = await fakeFirestore
              .collection('tasks')
              .doc(task.taskId)
              .get();
          final remaining = (doc.data()!['subtasks'] as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

          expect(remaining.length, equals(2));
          expect(remaining[0]['title'], equals('Subtask 1'));
          expect(remaining[1]['title'], equals('Subtask 3'));
        },
      );

      test('reorderSubtasks reorders correctly and throws ArgumentError on mismatched IDs', () async {
        final task = await repository.createTask(
          uid: 'user-123',
          listId: 'inbox-456',
          title: 'Parent Task',
        );

        await repository.addSubtask(task.taskId, 'A');
        await repository.addSubtask(task.taskId, 'B');
        await repository.addSubtask(task.taskId, 'C');

        final initialDoc = await fakeFirestore
            .collection('tasks')
            .doc(task.taskId)
            .get();
        final subtasks = (initialDoc.data()!['subtasks'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final aId = subtasks[0]['id'] as String;
        final bId = subtasks[1]['id'] as String;
        final cId = subtasks[2]['id'] as String;

        // Reorder: C, A, B
        await repository.reorderSubtasks(task.taskId, [cId, aId, bId]);

        var doc = await fakeFirestore
            .collection('tasks')
            .doc(task.taskId)
            .get();
        var reordered = (doc.data()!['subtasks'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        expect(reordered[0]['title'], equals('C'));
        expect(reordered[1]['title'], equals('A'));
        expect(reordered[2]['title'], equals('B'));

        // Throws on partial list (missing one)
        await expectLater(
          repository.reorderSubtasks(task.taskId, [cId, aId]),
          throwsA(isA<ArgumentError>()),
        );

        // Throws on duplicates
        await expectLater(
          repository.reorderSubtasks(task.taskId, [cId, aId, aId]),
          throwsA(isA<ArgumentError>()),
        );

        // Throws on unknown ID
        await expectLater(
          repository.reorderSubtasks(task.taskId, [cId, aId, 'ghost-id']),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('streamTask', () {
      test('emits Task entity and updates when doc changes', () async {
        final task = await repository.createTask(
          uid: 'user-123',
          listId: 'inbox-456',
          title: 'Streamed Task',
        );

        final emissions = <Task?>[];
        final subscription = repository
            .streamTask(task.taskId)
            .listen(emissions.add);

        await pumpEventQueue();
        expect(emissions.last?.title, equals('Streamed Task'));

        await repository.addSubtask(task.taskId, 'New Subtask');
        await pumpEventQueue();

        expect(emissions.last?.subtasks.length, equals(1));
        expect(emissions.last?.subtasks[0]['title'], equals('New Subtask'));

        await subscription.cancel();
      });

      test('emits null when task document does not exist', () async {
        final emissions = <Task?>[];
        final subscription = repository
            .streamTask('non-existent-task')
            .listen(emissions.add);

        await pumpEventQueue();
        expect(emissions.last, isNull);

        await subscription.cancel();
      });
    });
  });
}
