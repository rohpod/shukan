import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/data/task_repository.dart';
import 'package:shukan/features/tasks/presentation/task_list_screen.dart';
import 'package:shukan/features/tasks/providers/task_providers.dart';

class MockTaskRepository extends Mock implements TaskRepository {}

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  const uid = 'test-uid';
  const listId = 'test-list-id';

  setUp(() async {
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'test@example.com'),
      signedIn: true,
    );
    fakeFirestore = FakeFirebaseFirestore();

    // Bootstrap user in Firestore
    await fakeFirestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': 'test@example.com',
      'defaultListId': listId,
    });
    await fakeFirestore.collection('lists').doc(listId).set({
      'listId': listId,
      'uid': uid,
      'name': 'Inbox',
      'isDefault': true,
    });
  });

  Widget createWidgetUnderTest({
    String? customListId,
    TaskRepository? taskRepository,
  }) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        if (taskRepository != null)
          taskRepositoryProvider.overrideWithValue(taskRepository),
      ],
      child: MaterialApp(
        home: Scaffold(body: TaskListScreen(listId: customListId)),
      ),
    );
  }

  group('TaskListScreen Widget Tests', () {
    testWidgets('shows empty state when no tasks exist', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('noTasksText')), findsOneWidget);
      expect(find.text('No tasks yet'), findsOneWidget);
      expect(find.byKey(const Key('addTaskButton')), findsOneWidget);
    });

    testWidgets(
      'creates a task, toggles complete, edits, and soft-deletes it',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // 1. Open create task dialog via FAB
        await tester.tap(find.byKey(const Key('addTaskButton')));
        await tester.pumpAndSettle();

        expect(find.text('New Task'), findsOneWidget);

        // Enter task details and create task
        await tester.enterText(
          find.byKey(const Key('taskTitleInput')),
          'Buy milk',
        );
        await tester.enterText(
          find.byKey(const Key('taskNotesInput')),
          '2% organic milk',
        );
        await tester.enterText(
          find.byKey(const Key('taskUrlInput')),
          'https://example.com/store',
        );
        await tester.tap(find.byKey(const Key('saveTaskButton')));
        await tester.pumpAndSettle();

        // Verify task appears in the list
        expect(find.text('Buy milk'), findsOneWidget);
        expect(find.text('2% organic milk'), findsOneWidget);
        expect(find.text('https://example.com/store'), findsOneWidget);
        expect(find.byKey(const Key('noTasksText')), findsNothing);

        // Verify Firestore document exists
        final tasksSnapshot = await fakeFirestore
            .collection('tasks')
            .where('uid', isEqualTo: uid)
            .get();
        expect(tasksSnapshot.docs.length, equals(1));
        final taskId = tasksSnapshot.docs.first.id;

        // 2. Toggle complete
        final checkboxFinder = find.byKey(Key('taskCompleteCheckbox_$taskId'));
        expect(checkboxFinder, findsOneWidget);
        await tester.tap(checkboxFinder);
        await tester.pumpAndSettle();

        var doc = await fakeFirestore.collection('tasks').doc(taskId).get();
        expect(doc.data()!['completedAt'], isNotNull);

        // 3. Edit task
        await tester.tap(find.byKey(Key('editTaskButton_$taskId')));
        await tester.pumpAndSettle();

        expect(find.text('Edit Task'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('editTaskTitleInput')),
          'Buy oat milk',
        );
        await tester.enterText(
          find.byKey(const Key('editTaskNotesInput')),
          'Barista edition',
        );
        await tester.tap(find.byKey(const Key('saveTaskButton')));
        await tester.pumpAndSettle();

        // Verify updated task in UI and Firestore
        expect(find.text('Buy oat milk'), findsOneWidget);
        expect(find.text('Barista edition'), findsOneWidget);
        doc = await fakeFirestore.collection('tasks').doc(taskId).get();
        expect(doc.data()!['title'], equals('Buy oat milk'));
        expect(doc.data()!['notes'], equals('Barista edition'));

        // 4. Soft delete task
        await tester.tap(find.byKey(Key('deleteTaskButton_$taskId')));
        await tester.pumpAndSettle();

        // Task is removed from UI and shows empty state
        expect(find.text('Buy oat milk'), findsNothing);
        expect(find.byKey(const Key('noTasksText')), findsOneWidget);

        // Verify document still exists in Firestore but with deletedAt set
        doc = await fakeFirestore.collection('tasks').doc(taskId).get();
        expect(doc.exists, isTrue);
        expect(doc.data()!['deletedAt'], isNotNull);
      },
    );

    testWidgets(
      'edit task dialog sets priority, tag, due date/time, repeat rule, and calls updateTask',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final mockTaskRepo = MockTaskRepository();
        final testTask = Task(
          taskId: 'task-abc',
          uid: uid,
          listId: listId,
          title: 'Initial Task',
          notes: '',
          url: '',
          priority: 'none',
          tagIds: const [],
          dueDate: null,
          dueTime: null,
          earlyReminderMinutes: 0,
          repeatRule: 'none',
          createdAt: DateTime(2026, 1, 1),
        );

        when(() => mockTaskRepo.streamTasksForList(uid, listId))
            .thenAnswer((_) => Stream.value([testTask]));
        when(
          () => mockTaskRepo.updateTask(
            any(),
            title: any(named: 'title'),
            notes: any(named: 'notes'),
            url: any(named: 'url'),
            priority: any(named: 'priority'),
            tagIds: any(named: 'tagIds'),
            dueDate: any(named: 'dueDate'),
            dueTime: any(named: 'dueTime'),
            earlyReminderMinutes: any(named: 'earlyReminderMinutes'),
            repeatRule: any(named: 'repeatRule'),
            clearDueDate: any(named: 'clearDueDate'),
            clearDueTime: any(named: 'clearDueTime'),
          ),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(
          createWidgetUnderTest(taskRepository: mockTaskRepo),
        );
        await tester.pumpAndSettle();

        // 1. Open edit dialog
        expect(
          find.byKey(const Key('editTaskButton_task-abc')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('editTaskButton_task-abc')));
        await tester.pumpAndSettle();

        expect(find.text('Edit Task'), findsOneWidget);

        // 2. Select priority -> 'high'
        await tester.tap(find.byKey(const Key('editTaskPriorityInput')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('High').last);
        await tester.pumpAndSettle();

        // 3. Add tag via chip input
        await tester.enterText(
          find.byKey(const Key('editTaskTagInput')),
          'urgent',
        );
        await tester.tap(find.byKey(const Key('addTagIconButton')));
        await tester.pumpAndSettle();

        expect(find.text('urgent'), findsOneWidget);

        // 4. Set due date via showDatePicker
        await tester.tap(find.byKey(const Key('editTaskDueDateInput')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        // 5. Set due time via showTimePicker
        await tester.tap(find.byKey(const Key('editTaskDueTimeInput')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        // 6. Select repeat rule -> 'weekly'
        await tester.tap(find.byKey(const Key('editTaskRepeatRuleInput')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Weekly').last);
        await tester.pumpAndSettle();

        // 7. Tap Save
        await tester.tap(find.byKey(const Key('saveTaskButton')));
        await tester.pumpAndSettle();

        // 8. Confirm updateTask was called with expected values
        verify(
          () => mockTaskRepo.updateTask(
            'task-abc',
            title: 'Initial Task',
            notes: '',
            url: '',
            priority: 'high',
            tagIds: any(named: 'tagIds', that: isNotEmpty),
            dueDate: any(named: 'dueDate', that: isNotNull),
            dueTime: any(named: 'dueTime', that: isNotNull),
            earlyReminderMinutes: any(named: 'earlyReminderMinutes'),
            repeatRule: 'weekly',
            clearDueDate: false,
            clearDueTime: false,
          ),
        ).called(1);
      },
    );

    testWidgets(
      'clearing due date resets due time in edit dialog and passes clear flags',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final mockTaskRepo = MockTaskRepository();
        final testTask = Task(
          taskId: 'task-with-date',
          uid: uid,
          listId: listId,
          title: 'Dated Task',
          notes: '',
          url: '',
          priority: 'low',
          tagIds: const [],
          dueDate: DateTime(2026, 12, 1),
          dueTime: '10:00',
          earlyReminderMinutes: 10,
          repeatRule: 'daily',
          createdAt: DateTime(2026, 1, 1),
        );

        when(() => mockTaskRepo.streamTasksForList(uid, listId))
            .thenAnswer((_) => Stream.value([testTask]));
        when(
          () => mockTaskRepo.updateTask(
            any(),
            title: any(named: 'title'),
            notes: any(named: 'notes'),
            url: any(named: 'url'),
            priority: any(named: 'priority'),
            tagIds: any(named: 'tagIds'),
            dueDate: any(named: 'dueDate'),
            dueTime: any(named: 'dueTime'),
            earlyReminderMinutes: any(named: 'earlyReminderMinutes'),
            repeatRule: any(named: 'repeatRule'),
            clearDueDate: any(named: 'clearDueDate'),
            clearDueTime: any(named: 'clearDueTime'),
          ),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(
          createWidgetUnderTest(taskRepository: mockTaskRepo),
        );
        await tester.pumpAndSettle();

        // Open edit dialog
        await tester.tap(
          find.byKey(const Key('editTaskButton_task-with-date')),
        );
        await tester.pumpAndSettle();

        // Tap clear date button
        expect(find.byKey(const Key('clearDueDateButton')), findsOneWidget);
        await tester.tap(find.byKey(const Key('clearDueDateButton')));
        await tester.pumpAndSettle();

        // Verify due date and due time are cleared in UI
        expect(find.text('Set due date first'), findsOneWidget);

        // Save
        await tester.tap(find.byKey(const Key('saveTaskButton')));
        await tester.pumpAndSettle();

        verify(
          () => mockTaskRepo.updateTask(
            'task-with-date',
            title: 'Dated Task',
            notes: '',
            url: '',
            priority: 'low',
            tagIds: const [],
            dueDate: null,
            dueTime: null,
            earlyReminderMinutes: 10,
            repeatRule: 'daily',
            clearDueDate: true,
            clearDueTime: true,
          ),
        ).called(1);
      },
    );

    testWidgets('tapping task row opens edit task popup dialog', (
      tester,
    ) async {
      await fakeFirestore.collection('tasks').doc('task-row-tap').set({
        'taskId': 'task-row-tap',
        'uid': uid,
        'listId': listId,
        'title': 'Tappable Task',
        'notes': 'Tap me',
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
        'createdAt': Timestamp.now(),
        'completedAt': null,
        'deletedAt': null,
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('taskItem_task-row-tap')), findsOneWidget);

      // Tap the task row directly
      await tester.tap(find.byKey(const Key('taskItem_task-row-tap')));
      await tester.pumpAndSettle();

      // Confirms edit popup dialog opened
      expect(find.text('Edit Task'), findsOneWidget);
      expect(find.byKey(const Key('editTaskTitleInput')), findsOneWidget);
    });

    testWidgets(
      'dropdown button shows/hides indented subtasks, adds subtask inline, toggles, and deletes',
      (tester) async {
        final taskDoc = fakeFirestore.collection('tasks').doc('task-with-subs');
        await taskDoc.set({
          'taskId': 'task-with-subs',
          'uid': uid,
          'listId': listId,
          'title': 'Task with Subtasks',
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
          'subtasks': [
            {'id': 'sub-1', 'title': 'Existing subtask 1', 'completed': false},
          ],
          'createdAt': Timestamp.now(),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // Subtasks are initially collapsed/hidden
        expect(find.byKey(const Key('subtaskRow_sub-1')), findsNothing);
        expect(
          find.byKey(const Key('toggleSubtasksButton_task-with-subs')),
          findsOneWidget,
        );

        // 1. Tap dropdown button to show subtasks
        await tester.tap(
          find.byKey(const Key('toggleSubtasksButton_task-with-subs')),
        );
        await tester.pumpAndSettle();

        // Now subtask is visible
        expect(find.byKey(const Key('subtaskRow_sub-1')), findsOneWidget);
        expect(find.text('Existing subtask 1'), findsOneWidget);

        // 2. Add a new subtask inline
        await tester.enterText(
          find.byKey(const Key('addSubtaskInput_task-with-subs')),
          'Second inline subtask',
        );
        await tester.tap(
          find.byKey(const Key('addSubtaskButton_task-with-subs')),
        );
        await tester.pumpAndSettle();

        // Verify second subtask appears in UI and Firestore
        expect(find.text('Second inline subtask'), findsOneWidget);
        var snap = await taskDoc.get();
        var subtasks = (snap.data()!['subtasks'] as List<dynamic>);
        expect(subtasks.length, equals(2));

        // 3. Toggle subtask completion via checkbox
        final checkboxFinder = find.byKey(const Key('subtaskCheckbox_sub-1'));
        expect(checkboxFinder, findsOneWidget);
        await tester.tap(checkboxFinder);
        await tester.pumpAndSettle();

        snap = await taskDoc.get();
        subtasks = (snap.data()!['subtasks'] as List<dynamic>);
        expect(subtasks[0]['completed'], isTrue);
        // Parent task completedAt is still null
        expect(snap.data()!['completedAt'], isNull);

        // 4. Delete subtask via delete button
        final deleteBtn = find.byKey(const Key('deleteSubtaskButton_sub-1'));
        expect(deleteBtn, findsOneWidget);
        await tester.tap(deleteBtn);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('subtaskRow_sub-1')), findsNothing);
        snap = await taskDoc.get();
        subtasks = (snap.data()!['subtasks'] as List<dynamic>);
        expect(subtasks.length, equals(1));

        // 5. Tap dropdown button to hide subtasks
        await tester.tap(
          find.byKey(const Key('toggleSubtasksButton_task-with-subs')),
        );
        await tester.pumpAndSettle();

        // Subtasks are hidden again
        expect(find.text('Second inline subtask'), findsNothing);
      },
    );

    testWidgets(
      'reorders subtasks inline via ReorderableListView onReorderItem',
      (tester) async {
        final taskDoc = fakeFirestore.collection('tasks').doc('task-reorder');
        await taskDoc.set({
          'taskId': 'task-reorder',
          'uid': uid,
          'listId': listId,
          'title': 'Reorder Task',
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
          'subtasks': [
            {'id': 'sub-a', 'title': 'Sub A', 'completed': false},
            {'id': 'sub-b', 'title': 'Sub B', 'completed': false},
            {'id': 'sub-c', 'title': 'Sub C', 'completed': false},
          ],
          'createdAt': Timestamp.now(),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // Expand subtasks
        await tester.tap(
          find.byKey(const Key('toggleSubtasksButton_task-reorder')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('subtasksList_task-reorder')),
          findsOneWidget,
        );

        // Move index 0 to index 2
        final reorderableWidget = tester.widget<ReorderableListView>(
          find.byKey(const Key('subtasksList_task-reorder')),
        );
        reorderableWidget.onReorderItem?.call(0, 2);
        await tester.pumpAndSettle();

        // Verify new order in Firestore: B, C, A
        final snap = await taskDoc.get();
        final subtasks = (snap.data()!['subtasks'] as List<dynamic>);
        expect(subtasks[0]['id'], equals('sub-b'));
        expect(subtasks[1]['id'], equals('sub-c'));
        expect(subtasks[2]['id'], equals('sub-a'));
      },
    );

    testWidgets(
      'move task button opens list picker, selects a list, and calls moveTaskToList',
      (tester) async {
        final mockTaskRepo = MockTaskRepository();
        const targetListId = 'other-list-456';

        // Add a second list for this user in fakeFirestore
        await fakeFirestore.collection('lists').doc(targetListId).set({
          'listId': targetListId,
          'uid': uid,
          'name': 'Work Projects',
          'isDefault': false,
          'createdAt': Timestamp.now(),
        });

        final testTask = Task(
          taskId: 'task-move-1',
          uid: uid,
          listId: listId,
          title: 'Task to be moved',
          notes: '',
          url: '',
          priority: 'none',
          tagIds: const [],
          dueDate: null,
          dueTime: null,
          earlyReminderMinutes: 0,
          repeatRule: 'none',
          createdAt: DateTime(2026, 1, 1),
        );

        when(() => mockTaskRepo.streamTasksForList(uid, listId))
            .thenAnswer((_) => Stream.value([testTask]));
        when(() => mockTaskRepo.moveTaskToList('task-move-1', targetListId))
            .thenAnswer((_) async {});

        await tester.pumpWidget(
          createWidgetUnderTest(taskRepository: mockTaskRepo),
        );
        await tester.pumpAndSettle();

        // 1. Verify task item and move button are present
        final moveButtonFinder = find.byKey(
          const Key('moveTaskButton_task-move-1'),
        );
        expect(moveButtonFinder, findsOneWidget);

        // 2. Tap the move button to open the list picker dialog
        await tester.tap(moveButtonFinder);
        await tester.pumpAndSettle();

        expect(find.text('Move Task to List'), findsOneWidget);

        // Current list (Inbox) should be excluded
        expect(find.byKey(const Key('moveToListOption_$listId')), findsNothing);

        // Target list (Work Projects) should be visible
        final targetListOption = find.byKey(
          const Key('moveToListOption_$targetListId'),
        );
        expect(targetListOption, findsOneWidget);
        expect(find.text('Work Projects'), findsOneWidget);

        // 3. Tap target list option
        await tester.tap(targetListOption);
        await tester.pumpAndSettle();

        // 4. Verify moveTaskToList was called with expected IDs
        verify(() => mockTaskRepo.moveTaskToList('task-move-1', targetListId))
            .called(1);

        // 5. Verify confirmation SnackBar
        expect(find.text('Task moved to "Work Projects"'), findsOneWidget);
      },
    );
  });
}
