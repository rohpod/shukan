import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shukan/core/notifications/notification_service.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/data/task_repository.dart';

class MockNotificationService extends Mock implements NotificationService {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const Task(
        taskId: 'dummy',
        uid: 'dummy',
        listId: 'dummy',
        title: 'dummy',
      ),
    );
  });

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

    test('createTask with dueDate and dueTime persists them correctly in entity and Firestore', () async {
      const uid = 'user-123';
      const listId = 'inbox-456';
      final dueDate = DateTime(2026, 10, 15);
      const dueTime = '17:00';

      final task = await repository.createTask(
        uid: uid,
        listId: listId,
        title: 'Submit assignment',
        dueDate: dueDate,
        dueTime: dueTime,
      );

      expect(task.title, equals('Submit assignment'));
      expect(task.dueDate, equals(dueDate));
      expect(task.dueTime, equals('17:00'));

      final docSnapshot = await fakeFirestore
          .collection('tasks')
          .doc(task.taskId)
          .get();
      expect(docSnapshot.exists, isTrue);

      final data = docSnapshot.data()!;
      expect(data['dueDate'], equals(Timestamp.fromDate(dueDate)));
      expect(data['dueTime'], equals('17:00'));
    });

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

    test('streamAllTasksForUser returns all non-deleted tasks for uid across lists ordered by createdAt DESC', () async {
      const uid = 'user-stream-all';

      // 1. Task in list-A (earlier)
      await fakeFirestore.collection('tasks').doc('all-t1').set({
        'taskId': 'all-t1',
        'uid': uid,
        'listId': 'list-A',
        'title': 'Task in List A',
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

      // 2. Task in list-B (later)
      await fakeFirestore.collection('tasks').doc('all-t2').set({
        'taskId': 'all-t2',
        'uid': uid,
        'listId': 'list-B',
        'title': 'Task in List B',
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

      // 3. Soft-deleted task for same user
      await fakeFirestore.collection('tasks').doc('all-t3').set({
        'taskId': 'all-t3',
        'uid': uid,
        'listId': 'list-A',
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

      // 4. Task belonging to another user
      await fakeFirestore.collection('tasks').doc('all-t4').set({
        'taskId': 'all-t4',
        'uid': 'different-user',
        'listId': 'list-A',
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
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 13, 0)),
        'completedAt': null,
        'deletedAt': null,
      });

      final emissions = <List<Task>>[];
      final subscription = repository
          .streamAllTasksForUser(uid)
          .listen(emissions.add);

      await pumpEventQueue();

      expect(emissions.isNotEmpty, isTrue);
      final tasks = emissions.last;
      expect(tasks.length, equals(2));
      // Descending by createdAt: all-t2 (12:00) then all-t1 (10:00)
      expect(tasks[0].taskId, equals('all-t2'));
      expect(tasks[0].title, equals('Task in List B'));
      expect(tasks[1].taskId, equals('all-t1'));
      expect(tasks[1].title, equals('Task in List A'));

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

    test(
      'moveTaskToList updates listId correctly and preserves other fields',
      () async {
        await fakeFirestore.collection('lists').doc('work-123').set({
          'listId': 'work-123',
          'uid': 'user-123',
          'name': 'Work',
          'isDefault': false,
        });

        final task = await repository.createTask(
          uid: 'user-123',
          listId: 'inbox-456',
          title: 'Task to move',
          notes: 'Some notes',
        );

        await repository.moveTaskToList(task.taskId, 'work-123');

        final updatedDoc = await fakeFirestore
            .collection('tasks')
            .doc(task.taskId)
            .get();
        expect(updatedDoc.data()!['listId'], equals('work-123'));
        expect(updatedDoc.data()!['title'], equals('Task to move'));
        expect(updatedDoc.data()!['notes'], equals('Some notes'));
        expect(updatedDoc.data()!['uid'], equals('user-123'));
      },
    );

    test('moveTaskToList throws ArgumentError when target list does not exist and does not update listId', () async {
      final task = await repository.createTask(
        uid: 'user-123',
        listId: 'inbox-456',
        title: 'Task to move',
      );

      await expectLater(
        repository.moveTaskToList(task.taskId, 'nonexistent-list'),
        throwsA(isA<ArgumentError>()),
      );

      final doc = await fakeFirestore
          .collection('tasks')
          .doc(task.taskId)
          .get();
      expect(doc.data()!['listId'], equals('inbox-456'));
    });

    test('moveTaskToList throws ArgumentError when target list belongs to a different uid and does not update listId', () async {
      // list-xyz belongs to user-abc, but task belongs to user-123
      final task = await repository.createTask(
        uid: 'user-123',
        listId: 'inbox-456',
        title: 'Task to move',
      );

      await expectLater(
        repository.moveTaskToList(task.taskId, 'list-xyz'),
        throwsA(isA<ArgumentError>()),
      );

      final doc = await fakeFirestore
          .collection('tasks')
          .doc(task.taskId)
          .get();
      expect(doc.data()!['listId'], equals('inbox-456'));
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

    group('Recently Deleted operations', () {
      const uid = 'user-123';
      const otherUid = 'user-other';
      const listId = 'inbox-456';

      test('streamRecentlyDeletedTasks returns soft-deleted tasks ordered descending by deletedAt', () async {
        final time1 = DateTime(2026, 1, 1, 10, 0);
        final time2 = DateTime(2026, 1, 1, 12, 0);

        // Soft-deleted task 1
        await fakeFirestore.collection('tasks').doc('task-del-1').set({
          'taskId': 'task-del-1',
          'uid': uid,
          'listId': listId,
          'title': 'Deleted 1',
          'deletedAt': Timestamp.fromDate(time1),
        });

        // Soft-deleted task 2 (newer)
        await fakeFirestore.collection('tasks').doc('task-del-2').set({
          'taskId': 'task-del-2',
          'uid': uid,
          'listId': listId,
          'title': 'Deleted 2',
          'deletedAt': Timestamp.fromDate(time2),
        });

        // Active task (should be excluded)
        await fakeFirestore.collection('tasks').doc('task-active').set({
          'taskId': 'task-active',
          'uid': uid,
          'listId': listId,
          'title': 'Active Task',
          'deletedAt': null,
        });

        // Other user's deleted task (should be excluded)
        await fakeFirestore.collection('tasks').doc('task-other-del').set({
          'taskId': 'task-other-del',
          'uid': otherUid,
          'listId': listId,
          'title': 'Other Deleted',
          'deletedAt': Timestamp.fromDate(time2),
        });

        final deleted = await repository.streamRecentlyDeletedTasks(uid).first;

        expect(deleted.length, equals(2));
        expect(deleted[0].taskId, equals('task-del-2'));
        expect(deleted[0].title, equals('Deleted 2'));
        expect(deleted[1].taskId, equals('task-del-1'));
        expect(deleted[1].title, equals('Deleted 1'));
      });

      test('streamRecentlyDeletedTasks recovers from malformed documents gracefully and sanitizes invalid fields', () async {
        // Valid soft-deleted task
        await fakeFirestore.collection('tasks').doc('valid-del').set({
          'taskId': 'valid-del',
          'uid': uid,
          'listId': listId,
          'title': 'Valid Deleted Task',
          'deletedAt': Timestamp.now(),
        });

        // Non-deleted document (deletedAt is null, must be skipped)
        await fakeFirestore.collection('tasks').doc('non-deleted-doc').set({
          'taskId': 'non-deleted-doc',
          'uid': uid,
          'deletedAt': null,
        });

        // Document with abnormal fields (e.g. invalid subtasks type)
        await fakeFirestore.collection('tasks').doc('malformed-subtasks').set({
          'taskId': 'malformed-subtasks',
          'uid': uid,
          'deletedAt': Timestamp.now(),
          'subtasks': 'not-a-list', // Invalid type, should be safely sanitized to empty list
        });

        final deleted = await repository.streamRecentlyDeletedTasks(uid).first;

        // The non-deleted document is skipped, both soft-deleted tasks are returned with sanitized fields
        expect(deleted.length, equals(2));
        expect(deleted.any((t) => t.taskId == 'valid-del'), isTrue);
        final sanitized = deleted.firstWhere(
          (t) => t.taskId == 'malformed-subtasks',
        );
        expect(sanitized.subtasks, isEmpty);
      });

      test('softDeleteTask sets immediate Timestamp and task appears in streamRecentlyDeletedTasks', () async {
        final task = await repository.createTask(
          uid: uid,
          listId: listId,
          title: 'Immediate Soft Delete Task',
        );

        await repository.softDeleteTask(task.taskId);

        final deleted = await repository.streamRecentlyDeletedTasks(uid).first;
        expect(deleted.any((t) => t.taskId == task.taskId), isTrue);
        final found = deleted.firstWhere((t) => t.taskId == task.taskId);
        expect(found.deletedAt, isNotNull);
      });

      test(
        'restoreTask clears deletedAt and keeps listId if list exists',
        () async {
          await fakeFirestore.collection('tasks').doc('task-res-1').set({
            'taskId': 'task-res-1',
            'uid': uid,
            'listId': listId,
            'title': 'To Restore',
            'deletedAt': Timestamp.now(),
          });

          await repository.restoreTask(uid: uid, taskId: 'task-res-1');

          final doc = await fakeFirestore
              .collection('tasks')
              .doc('task-res-1')
              .get();
          expect(doc.data()!['deletedAt'], isNull);
          expect(doc.data()!['listId'], equals(listId));
        },
      );

      test(
        'restoreTask reassigns to defaultListId when original list was deleted',
        () async {
          // List 'deleted-list-id' does not exist in fakeFirestore
          await fakeFirestore.collection('tasks').doc('task-orphan').set({
            'taskId': 'task-orphan',
            'uid': uid,
            'listId': 'deleted-list-id',
            'title': 'Orphan Task',
            'deletedAt': Timestamp.now(),
          });

          await repository.restoreTask(
            uid: uid,
            taskId: 'task-orphan',
            defaultListId: 'inbox-456',
          );

          final doc = await fakeFirestore
              .collection('tasks')
              .doc('task-orphan')
              .get();
          expect(doc.data()!['deletedAt'], isNull);
          expect(doc.data()!['listId'], equals('inbox-456'));
        },
      );

      test('restoreTask resolves defaultListId from users collection if parameter omitted', () async {
        await fakeFirestore.collection('users').doc(uid).set({
          'uid': uid,
          'defaultListId': 'inbox-456',
        });

        await fakeFirestore.collection('tasks').doc('task-orphan-2').set({
          'taskId': 'task-orphan-2',
          'uid': uid,
          'listId': 'missing-list-id',
          'title': 'Orphan Task 2',
          'deletedAt': Timestamp.now(),
        });

        await repository.restoreTask(uid: uid, taskId: 'task-orphan-2');

        final doc = await fakeFirestore
            .collection('tasks')
            .doc('task-orphan-2')
            .get();
        expect(doc.data()!['deletedAt'], isNull);
        expect(doc.data()!['listId'], equals('inbox-456'));
      });

      test('restoreTask throws ArgumentError if task does not exist or user mismatch', () async {
        await fakeFirestore.collection('tasks').doc('task-other').set({
          'taskId': 'task-other',
          'uid': otherUid,
          'listId': listId,
          'title': 'Other Task',
          'deletedAt': Timestamp.now(),
        });

        expect(
          () => repository.restoreTask(uid: uid, taskId: 'non-existent'),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => repository.restoreTask(uid: uid, taskId: 'task-other'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('permanentlyDeleteTask physically removes document and enforces ownership', () async {
        await fakeFirestore.collection('tasks').doc('task-perm').set({
          'taskId': 'task-perm',
          'uid': uid,
          'listId': listId,
          'title': 'Permanent Task',
          'deletedAt': Timestamp.now(),
        });

        // Non-owner cannot delete
        expect(
          () => repository.permanentlyDeleteTask(
            uid: otherUid,
            taskId: 'task-perm',
          ),
          throwsA(isA<ArgumentError>()),
        );

        // Owner permanently deletes
        await repository.permanentlyDeleteTask(uid: uid, taskId: 'task-perm');

        final doc = await fakeFirestore
            .collection('tasks')
            .doc('task-perm')
            .get();
        expect(doc.exists, isFalse);

        // Deleting non-existent task throws
        expect(
          () => repository.permanentlyDeleteTask(uid: uid, taskId: 'task-perm'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('emptyRecentlyDeleted batch deletes all soft-deleted tasks for uid and preserves active and other user tasks', () async {
        // 2 soft-deleted tasks for uid
        await fakeFirestore.collection('tasks').doc('t-del-1').set({
          'taskId': 't-del-1',
          'uid': uid,
          'deletedAt': Timestamp.now(),
        });
        await fakeFirestore.collection('tasks').doc('t-del-2').set({
          'taskId': 't-del-2',
          'uid': uid,
          'deletedAt': Timestamp.now(),
        });

        // 1 active task for uid
        await fakeFirestore.collection('tasks').doc('t-active').set({
          'taskId': 't-active',
          'uid': uid,
          'deletedAt': null,
        });

        // 1 soft-deleted task for another user
        await fakeFirestore.collection('tasks').doc('t-other-del').set({
          'taskId': 't-other-del',
          'uid': otherUid,
          'deletedAt': Timestamp.now(),
        });

        await repository.emptyRecentlyDeleted(uid);

        // Verify soft-deleted tasks for uid are gone
        final doc1 = await fakeFirestore
            .collection('tasks')
            .doc('t-del-1')
            .get();
        final doc2 = await fakeFirestore
            .collection('tasks')
            .doc('t-del-2')
            .get();
        expect(doc1.exists, isFalse);
        expect(doc2.exists, isFalse);

        // Verify active task for uid is intact
        final docActive = await fakeFirestore
            .collection('tasks')
            .doc('t-active')
            .get();
        expect(docActive.exists, isTrue);

        // Verify other user's deleted task is intact
        final docOther = await fakeFirestore
            .collection('tasks')
            .doc('t-other-del')
            .get();
        expect(docOther.exists, isTrue);
      });

      test('restoreTask no-ops gracefully when task is already active (deletedAt is null)', () async {
        await fakeFirestore.collection('tasks').doc('t-active-restore').set({
          'taskId': 't-active-restore',
          'uid': uid,
          'listId': listId,
          'title': 'Active Task',
          'deletedAt': null,
        });

        await repository.restoreTask(uid: uid, taskId: 't-active-restore');

        final doc = await fakeFirestore
            .collection('tasks')
            .doc('t-active-restore')
            .get();
        expect(doc.data()!['deletedAt'], isNull);
        expect(doc.data()!['title'], equals('Active Task'));
      });

      test('purgeExpiredDeletedTasks permanently deletes tasks older than retention threshold and preserves others', () async {
        final now = DateTime.now();

        // 1. Expired task (deleted 35 days ago) for uid -> should be purged
        await fakeFirestore.collection('tasks').doc('t-expired-1').set({
          'taskId': 't-expired-1',
          'uid': uid,
          'title': 'Expired Task 1',
          'deletedAt': Timestamp.fromDate(
            now.subtract(const Duration(days: 35)),
          ),
        });

        // 2. Expired task (deleted 40 days ago) for uid with DateTime format -> should be purged
        await fakeFirestore.collection('tasks').doc('t-expired-2').set({
          'taskId': 't-expired-2',
          'uid': uid,
          'title': 'Expired Task 2',
          'deletedAt': now.subtract(const Duration(days: 40)),
        });

        // 3. Recently deleted task (deleted 5 days ago) for uid -> should be retained
        await fakeFirestore.collection('tasks').doc('t-recent').set({
          'taskId': 't-recent',
          'uid': uid,
          'title': 'Recent Deleted Task',
          'deletedAt': Timestamp.fromDate(
            now.subtract(const Duration(days: 5)),
          ),
        });

        // 4. Active task (deletedAt: null) for uid -> should be retained
        await fakeFirestore.collection('tasks').doc('t-active-purge').set({
          'taskId': 't-active-purge',
          'uid': uid,
          'title': 'Active Task',
          'deletedAt': null,
        });

        // 5. Expired task for another user -> should be retained
        await fakeFirestore.collection('tasks').doc('t-other-expired').set({
          'taskId': 't-other-expired',
          'uid': otherUid,
          'title': 'Other Expired Task',
          'deletedAt': Timestamp.fromDate(
            now.subtract(const Duration(days: 60)),
          ),
        });

        // Run purge
        final purgedCount = await repository.purgeExpiredDeletedTasks(
          uid,
          retention: const Duration(days: 30),
        );

        expect(purgedCount, equals(2));

        // Verify expired tasks for uid are gone
        final docExpired1 = await fakeFirestore
            .collection('tasks')
            .doc('t-expired-1')
            .get();
        final docExpired2 = await fakeFirestore
            .collection('tasks')
            .doc('t-expired-2')
            .get();
        expect(docExpired1.exists, isFalse);
        expect(docExpired2.exists, isFalse);

        // Verify recent deleted task is still intact
        final docRecent = await fakeFirestore
            .collection('tasks')
            .doc('t-recent')
            .get();
        expect(docRecent.exists, isTrue);

        // Verify active task is still intact
        final docActive = await fakeFirestore
            .collection('tasks')
            .doc('t-active-purge')
            .get();
        expect(docActive.exists, isTrue);

        // Verify other user's expired task is still intact
        final docOtherExpired = await fakeFirestore
            .collection('tasks')
            .doc('t-other-expired')
            .get();
        expect(docOtherExpired.exists, isTrue);

        // Second run should return 0 since no expired tasks remain
        final secondPurge = await repository.purgeExpiredDeletedTasks(uid);
        expect(secondPurge, equals(0));
      });

      group('streamTasksWithDueDate', () {
        test('streams tasks with dueDate sorted chronologically and tie-broken by dueTime', () async {
          // Task A: Oct 15 at 14:00
          await fakeFirestore.collection('tasks').doc('t-a').set({
            'taskId': 't-a',
            'uid': uid,
            'listId': listId,
            'title': 'Task A',
            'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
            'dueTime': '14:00',
            'order': 0,
            'deletedAt': null,
          });

          // Task B: Oct 15 at 09:00
          await fakeFirestore.collection('tasks').doc('t-b').set({
            'taskId': 't-b',
            'uid': uid,
            'listId': listId,
            'title': 'Task B',
            'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
            'dueTime': '09:00',
            'order': 0,
            'deletedAt': null,
          });

          // Task C: Oct 15 untimed
          await fakeFirestore.collection('tasks').doc('t-c').set({
            'taskId': 't-c',
            'uid': uid,
            'listId': listId,
            'title': 'Task C',
            'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
            'dueTime': null,
            'order': 0,
            'deletedAt': null,
          });

          // Task D: Oct 10 earlier date
          await fakeFirestore.collection('tasks').doc('t-d').set({
            'taskId': 't-d',
            'uid': uid,
            'listId': listId,
            'title': 'Task D',
            'dueDate': Timestamp.fromDate(DateTime(2026, 10, 10)),
            'dueTime': '11:00',
            'order': 0,
            'deletedAt': null,
          });

          // Task E: Oct 20 later date
          await fakeFirestore.collection('tasks').doc('t-e').set({
            'taskId': 't-e',
            'uid': uid,
            'listId': listId,
            'title': 'Task E',
            'dueDate': Timestamp.fromDate(DateTime(2026, 10, 20)),
            'dueTime': '08:00',
            'order': 0,
            'deletedAt': null,
          });

          // Task F: No due date (excluded)
          await fakeFirestore.collection('tasks').doc('t-f').set({
            'taskId': 't-f',
            'uid': uid,
            'listId': listId,
            'title': 'Task F',
            'dueDate': null,
            'deletedAt': null,
          });

          // Task G: Soft-deleted (excluded)
          await fakeFirestore.collection('tasks').doc('t-g').set({
            'taskId': 't-g',
            'uid': uid,
            'listId': listId,
            'title': 'Task G',
            'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
            'deletedAt': Timestamp.now(),
          });

          // Task H: Other user (excluded)
          await fakeFirestore.collection('tasks').doc('t-h').set({
            'taskId': 't-h',
            'uid': otherUid,
            'listId': listId,
            'title': 'Task H',
            'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
            'deletedAt': null,
          });

          final result = await repository
              .streamTasksWithDueDate(uid: uid)
              .first;

          expect(result.length, equals(5));
          expect(result.map((t) => t.taskId).toList(), [
            't-d', // Oct 10
            't-b', // Oct 15 09:00
            't-a', // Oct 15 14:00
            't-c', // Oct 15 untimed
            't-e', // Oct 20
          ]);
        });

        test('streamTasksWithDueDate applies startDueDate and endDueDate range query', () async {
          await fakeFirestore.collection('tasks').doc('t-in-range').set({
            'taskId': 't-in-range',
            'uid': uid,
            'listId': listId,
            'title': 'In Range',
            'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15, 12, 0)),
            'deletedAt': null,
          });

          await fakeFirestore.collection('tasks').doc('t-out-range').set({
            'taskId': 't-out-range',
            'uid': uid,
            'listId': listId,
            'title': 'Out of Range',
            'dueDate': Timestamp.fromDate(DateTime(2026, 10, 18)),
            'deletedAt': null,
          });

          final rangeResult = await repository
              .streamTasksWithDueDate(
                uid: uid,
                startDueDate: DateTime(2026, 10, 15, 0, 0),
                endDueDate: DateTime(2026, 10, 15, 23, 59, 59),
              )
              .first;

          expect(rangeResult.length, equals(1));
          expect(rangeResult.first.taskId, equals('t-in-range'));
        });

        test('streamTasksWithDueDate filters completedAt when onlyIncomplete is true', () async {
          await fakeFirestore.collection('tasks').doc('t-incomplete').set({
            'taskId': 't-incomplete',
            'uid': uid,
            'listId': listId,
            'title': 'Incomplete Task',
            'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
            'completedAt': null,
            'deletedAt': null,
          });

          await fakeFirestore.collection('tasks').doc('t-completed').set({
            'taskId': 't-completed',
            'uid': uid,
            'listId': listId,
            'title': 'Completed Task',
            'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
            'completedAt': Timestamp.now(),
            'deletedAt': null,
          });

          final incompleteResult = await repository
              .streamTasksWithDueDate(uid: uid, onlyIncomplete: true)
              .first;
          expect(incompleteResult.length, equals(1));
          expect(incompleteResult.first.taskId, equals('t-incomplete'));

          final allResult = await repository
              .streamTasksWithDueDate(uid: uid, onlyIncomplete: false)
              .first;
          expect(allResult.length, equals(2));
        });

        test(
          'streamTasksWithDueDate filters by tagIds with OR semantics',
          () async {
            await fakeFirestore.collection('tasks').doc('t-tag1').set({
              'taskId': 't-tag1',
              'uid': uid,
              'listId': listId,
              'title': 'Tag 1 Task',
              'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
              'tagIds': ['work'],
              'deletedAt': null,
            });

            await fakeFirestore.collection('tasks').doc('t-tag2').set({
              'taskId': 't-tag2',
              'uid': uid,
              'listId': listId,
              'title': 'Tag 2 Task',
              'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
              'tagIds': ['urgent'],
              'deletedAt': null,
            });

            await fakeFirestore.collection('tasks').doc('t-notag').set({
              'taskId': 't-notag',
              'uid': uid,
              'listId': listId,
              'title': 'No Tag Task',
              'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
              'tagIds': <String>[],
              'deletedAt': null,
            });

            final singleFilter = await repository
                .streamTasksWithDueDate(uid: uid, tagIds: ['work'])
                .first;
            expect(singleFilter.length, equals(1));
            expect(singleFilter.first.taskId, equals('t-tag1'));

            final orFilter = await repository
                .streamTasksWithDueDate(uid: uid, tagIds: ['work', 'urgent'])
                .first;
            expect(orFilter.length, equals(2));
            expect(
              orFilter.map((t) => t.taskId).toSet(),
              equals({'t-tag1', 't-tag2'}),
            );
          },
        );

        test(
          'streamAllActiveTasks returns only active tasks for uid',
          () async {
            await fakeFirestore.collection('tasks').doc('act-1').set({
              'taskId': 'act-1',
              'uid': uid,
              'title': 'Active 1',
              'deletedAt': null,
            });
            await fakeFirestore.collection('tasks').doc('act-del').set({
              'taskId': 'act-del',
              'uid': uid,
              'title': 'Deleted',
              'deletedAt': Timestamp.now(),
            });
            await fakeFirestore.collection('tasks').doc('act-other').set({
              'taskId': 'act-other',
              'uid': 'other-uid',
              'title': 'Other User',
              'deletedAt': null,
            });

            final activeTasks = await repository
                .streamAllActiveTasks(uid)
                .first;
            expect(activeTasks.length, equals(1));
            expect(activeTasks.first.taskId, equals('act-1'));
          },
        );

        test(
          'streamTasksForTagIds correctly returns tasks without due date',
          () async {
            // Task WITH due date
            await fakeFirestore.collection('tasks').doc('with-due').set({
              'taskId': 'with-due',
              'uid': uid,
              'title': 'Has Due Date',
              'dueDate': Timestamp.fromDate(DateTime(2026, 10, 20)),
              'tagIds': ['target-tag'],
              'deletedAt': null,
              'createdAt': Timestamp.now(),
            });

            // Task WITHOUT due date — critical test case!
            await fakeFirestore.collection('tasks').doc('no-due').set({
              'taskId': 'no-due',
              'uid': uid,
              'title': 'No Due Date',
              'dueDate': null,
              'tagIds': ['target-tag'],
              'deletedAt': null,
              'createdAt': Timestamp.now(),
            });

            // Task with different tag
            await fakeFirestore.collection('tasks').doc('other-tag').set({
              'taskId': 'other-tag',
              'uid': uid,
              'title': 'Different Tag',
              'dueDate': null,
              'tagIds': ['other-tag'],
              'deletedAt': null,
              'createdAt': Timestamp.now(),
            });

            final result = await repository
                .streamTasksForTagIds(uid: uid, tagIds: ['target-tag'])
                .first;

            expect(result.length, equals(2));
            final taskIds = result.map((t) => t.taskId).toSet();
            expect(taskIds, contains('no-due'));
            expect(taskIds, contains('with-due'));
            expect(taskIds, isNot(contains('other-tag')));
          },
        );

        test(
          'streamTasksForTagIds returns empty stream when tagIds is empty',
          () async {
            final result = await repository
                .streamTasksForTagIds(uid: uid, tagIds: [])
                .first;
            expect(result, isEmpty);
          },
        );
      });
    });

    group('Notification Lifecycle Hooks', () {
      late MockNotificationService mockNotificationService;
      late TaskRepository repoWithNotifications;

      setUp(() {
        mockNotificationService = MockNotificationService();
        repoWithNotifications = TaskRepository(
          fakeFirestore,
          mockNotificationService,
        );

        when(() => mockNotificationService.scheduleForTask(any()))
            .thenAnswer((_) async {});
        when(() => mockNotificationService.cancelForTask(any()))
            .thenAnswer((_) async {});
      });

      test(
        'createTask with dueDate calls scheduleForTask on the created task',
        () async {
          final due = DateTime.now().add(const Duration(days: 1));
          final task = await repoWithNotifications.createTask(
            uid: 'user-123',
            listId: 'inbox-456',
            title: 'Scheduled Task',
            dueDate: due,
            dueTime: '10:00',
          );

          verify(
            () => mockNotificationService.scheduleForTask(
              any(
                that: isA<Task>().having(
                  (t) => t.taskId,
                  'taskId',
                  task.taskId,
                ),
              ),
            ),
          ).called(1);
        },
      );

      test(
        'createTask without dueDate does not call scheduleForTask',
        () async {
          await repoWithNotifications.createTask(
            uid: 'user-123',
            listId: 'inbox-456',
            title: 'Unscheduled Task',
          );

          verifyNever(() => mockNotificationService.scheduleForTask(any()));
        },
      );

      test('updateTask changing dueDate reschedules notification', () async {
        final task = await repoWithNotifications.createTask(
          uid: 'user-123',
          listId: 'inbox-456',
          title: 'Initial Task',
        );
        reset(mockNotificationService);
        when(() => mockNotificationService.scheduleForTask(any()))
            .thenAnswer((_) async {});

        final newDue = DateTime.now().add(const Duration(days: 2));
        await repoWithNotifications.updateTask(task.taskId, dueDate: newDue);

        verify(
          () => mockNotificationService.scheduleForTask(
            any(
              that: isA<Task>().having((t) => t.taskId, 'taskId', task.taskId),
            ),
          ),
        ).called(1);
      });

      test(
        'updateTask NOT touching due fields does not re-fetch or reschedule',
        () async {
          final task = await repoWithNotifications.createTask(
            uid: 'user-123',
            listId: 'inbox-456',
            title: 'Initial Task',
          );
          reset(mockNotificationService);

          await repoWithNotifications.updateTask(
            task.taskId,
            title: 'Updated Title',
            notes: 'New notes',
          );

          verifyNever(() => mockNotificationService.scheduleForTask(any()));
          verifyNever(() => mockNotificationService.cancelForTask(any()));
        },
      );

      test('updateTask with clearDueDate cancels notification', () async {
        final due = DateTime.now().add(const Duration(days: 1));
        final task = await repoWithNotifications.createTask(
          uid: 'user-123',
          listId: 'inbox-456',
          title: 'Due Task',
          dueDate: due,
        );
        reset(mockNotificationService);
        when(() => mockNotificationService.cancelForTask(any()))
            .thenAnswer((_) async {});

        await repoWithNotifications.updateTask(task.taskId, clearDueDate: true);

        verify(() => mockNotificationService.cancelForTask(task.taskId))
            .called(1);
      });

      test('toggleTaskCompleted(true) cancels notification', () async {
        final due = DateTime.now().add(const Duration(days: 1));
        final task = await repoWithNotifications.createTask(
          uid: 'user-123',
          listId: 'inbox-456',
          title: 'Due Task',
          dueDate: due,
        );
        reset(mockNotificationService);
        when(() => mockNotificationService.cancelForTask(any()))
            .thenAnswer((_) async {});

        await repoWithNotifications.toggleTaskCompleted(
          task.taskId,
          isCompleted: true,
        );

        verify(() => mockNotificationService.cancelForTask(task.taskId))
            .called(1);
      });

      test(
        'toggleTaskCompleted(false) on task with dueDate reschedules',
        () async {
          final due = DateTime.now().add(const Duration(days: 1));
          final task = await repoWithNotifications.createTask(
            uid: 'user-123',
            listId: 'inbox-456',
            title: 'Due Task',
            dueDate: due,
          );
          await repoWithNotifications.toggleTaskCompleted(
            task.taskId,
            isCompleted: true,
          );
          reset(mockNotificationService);
          when(() => mockNotificationService.scheduleForTask(any()))
              .thenAnswer((_) async {});

          await repoWithNotifications.toggleTaskCompleted(
            task.taskId,
            isCompleted: false,
          );

          verify(
            () => mockNotificationService.scheduleForTask(
              any(
                that: isA<Task>().having(
                  (t) => t.taskId,
                  'taskId',
                  task.taskId,
                ),
              ),
            ),
          ).called(1);
        },
      );

      test('softDeleteTask cancels notification', () async {
        final due = DateTime.now().add(const Duration(days: 1));
        final task = await repoWithNotifications.createTask(
          uid: 'user-123',
          listId: 'inbox-456',
          title: 'Due Task',
          dueDate: due,
        );
        reset(mockNotificationService);
        when(() => mockNotificationService.cancelForTask(any()))
            .thenAnswer((_) async {});

        await repoWithNotifications.softDeleteTask(task.taskId);

        verify(() => mockNotificationService.cancelForTask(task.taskId))
            .called(1);
      });

      test('permanentlyDeleteTask cancels notification defensively', () async {
        final due = DateTime.now().add(const Duration(days: 1));
        final task = await repoWithNotifications.createTask(
          uid: 'user-123',
          listId: 'inbox-456',
          title: 'Due Task',
          dueDate: due,
        );
        reset(mockNotificationService);
        when(() => mockNotificationService.cancelForTask(any()))
            .thenAnswer((_) async {});

        await repoWithNotifications.permanentlyDeleteTask(
          uid: 'user-123',
          taskId: task.taskId,
        );

        verify(() => mockNotificationService.cancelForTask(task.taskId))
            .called(1);
      });

      test(
        'restoreTask reschedules notification if task has a dueDate',
        () async {
          final due = DateTime.now().add(const Duration(days: 1));
          final task = await repoWithNotifications.createTask(
            uid: 'user-123',
            listId: 'inbox-456',
            title: 'Due Task',
            dueDate: due,
          );
          await repoWithNotifications.softDeleteTask(task.taskId);
          reset(mockNotificationService);
          when(() => mockNotificationService.scheduleForTask(any()))
              .thenAnswer((_) async {});

          await repoWithNotifications.restoreTask(
            uid: 'user-123',
            taskId: task.taskId,
          );

          verify(
            () => mockNotificationService.scheduleForTask(
              any(
                that: isA<Task>().having(
                  (t) => t.taskId,
                  'taskId',
                  task.taskId,
                ),
              ),
            ),
          ).called(1);
        },
      );

      test('notificationService failure does not prevent Firestore operation from succeeding', () async {
        reset(mockNotificationService);
        when(() => mockNotificationService.scheduleForTask(any()))
            .thenThrow(Exception('Notification platform channel failed'));

        final due = DateTime.now().add(const Duration(days: 1));
        final task = await repoWithNotifications.createTask(
          uid: 'user-123',
          listId: 'inbox-456',
          title: 'Resilient Task',
          dueDate: due,
        );

        // Verify Firestore write succeeded despite notification failure
        expect(task.taskId, isNotEmpty);
        final docSnapshot = await fakeFirestore
            .collection('tasks')
            .doc(task.taskId)
            .get();
        expect(docSnapshot.exists, isTrue);
        expect(docSnapshot.data()!['title'], equals('Resilient Task'));
      });
    });
  });
}
