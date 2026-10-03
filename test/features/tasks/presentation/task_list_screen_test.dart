import 'dart:async';

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

class _DelayedSoftDeleteTaskRepository extends TaskRepository {
  _DelayedSoftDeleteTaskRepository(super.firestore);

  final Completer<void> completer = Completer<void>();

  @override
  Future<void> softDeleteTask(String taskId) async {
    await completer.future;
    await super.softDeleteTask(taskId);
  }
}

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

        // Expand completed section to reveal the completed task for editing
        await tester.tap(find.byKey(Key('completedSectionHeader_$listId')));
        await tester.pumpAndSettle();

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

    testWidgets(
      'early reminder dropdown does not expose 0 min option while preserving positive durations and none',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final mockTaskRepo = MockTaskRepository();
        final testTask = Task(
          taskId: 'task-reminder-test',
          uid: uid,
          listId: listId,
          title: 'Reminder Task',
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

        // Open edit dialog
        await tester.tap(
          find.byKey(const Key('editTaskButton_task-reminder-test')),
        );
        await tester.pumpAndSettle();

        // Verify dropdown exists
        final dropdownFinder = find.byKey(
          const Key('editTaskEarlyReminderInput'),
        );
        expect(dropdownFinder, findsOneWidget);

        final dropdownWidget = tester.widget<DropdownButton<int>>(
          find.descendant(
            of: dropdownFinder,
            matching: find.byType(DropdownButton<int>),
          ),
        );
        final itemValues = dropdownWidget.items!
            .map((item) => item.value)
            .toList();
        expect(itemValues, containsAllInOrder([0, 5, 10, 15, 30, 60]));

        final itemLabels = dropdownWidget.items!
            .map((item) => (item.child as Text).data!)
            .toList();
        expect(
          itemLabels,
          equals([
            'None',
            '5 minutes before',
            '10 minutes before',
            '15 minutes before',
            '30 minutes before',
            '1 hour before',
          ]),
        );
        expect(
          itemLabels.any((label) => RegExp(r'\b0\s*min').hasMatch(label)),
          isFalse,
        );

        // Open early reminder dropdown
        await tester.tap(dropdownFinder);
        await tester.pumpAndSettle();

        // Verify "0 min" is NOT exposed in any menu item
        expect(find.text('None (0 min)'), findsNothing);
        expect(find.text('0 min'), findsNothing);
        expect(find.text('0 minutes before'), findsNothing);

        // Verify positive duration options and "None" are present
        expect(find.text('None'), findsWidgets);
        expect(find.text('5 minutes before'), findsOneWidget);
        expect(find.text('10 minutes before'), findsOneWidget);
        expect(find.text('15 minutes before'), findsOneWidget);
        expect(find.text('30 minutes before'), findsOneWidget);
        expect(find.text('1 hour before'), findsOneWidget);

        // Select 30 minutes before and save
        await tester.tap(find.text('30 minutes before').last);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('saveTaskButton')));
        await tester.pumpAndSettle();

        verify(
          () => mockTaskRepo.updateTask(
            'task-reminder-test',
            title: 'Reminder Task',
            notes: '',
            url: '',
            priority: 'none',
            tagIds: const [],
            dueDate: null,
            dueTime: null,
            earlyReminderMinutes: 30,
            repeatRule: 'none',
            clearDueDate: true,
            clearDueTime: true,
          ),
        ).called(1);
      },
    );

    testWidgets(
      'selecting None early reminder saves earlyReminderMinutes as 0',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final mockTaskRepo = MockTaskRepository();
        final testTask = Task(
          taskId: 'task-reminder-reset',
          uid: uid,
          listId: listId,
          title: 'Reminder Reset Task',
          notes: '',
          url: '',
          priority: 'none',
          tagIds: const [],
          dueDate: null,
          dueTime: null,
          earlyReminderMinutes: 15,
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

        // Open edit dialog
        await tester.tap(
          find.byKey(const Key('editTaskButton_task-reminder-reset')),
        );
        await tester.pumpAndSettle();

        // Open dropdown
        await tester.tap(find.byKey(const Key('editTaskEarlyReminderInput')));
        await tester.pumpAndSettle();

        // Select 'None'
        await tester.tap(find.text('None').last);
        await tester.pumpAndSettle();

        // Save
        await tester.tap(find.byKey(const Key('saveTaskButton')));
        await tester.pumpAndSettle();

        verify(
          () => mockTaskRepo.updateTask(
            'task-reminder-reset',
            title: 'Reminder Reset Task',
            notes: '',
            url: '',
            priority: 'none',
            tagIds: const [],
            dueDate: null,
            dueTime: null,
            earlyReminderMinutes: 0,
            repeatRule: 'none',
            clearDueDate: true,
            clearDueTime: true,
          ),
        ).called(1);
      },
    );

    testWidgets(
      'new task dialog defaults early reminder to None and persists selected positive duration',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final mockTaskRepo = MockTaskRepository();
        final createdTask = Task(
          taskId: 'task-created-1',
          uid: uid,
          listId: listId,
          title: 'Brand New Task',
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
            .thenAnswer((_) => Stream.value([]));
        when(
          () => mockTaskRepo.createTask(
            uid: uid,
            listId: listId,
            title: 'Brand New Task',
            notes: '',
            url: '',
            dueDate: null,
            dueTime: null,
          ),
        ).thenAnswer((_) async => createdTask);
        when(
          () => mockTaskRepo.updateTask(
            'task-created-1',
            priority: any(named: 'priority'),
            tagIds: any(named: 'tagIds'),
            earlyReminderMinutes: any(named: 'earlyReminderMinutes'),
            repeatRule: any(named: 'repeatRule'),
          ),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(
          createWidgetUnderTest(taskRepository: mockTaskRepo),
        );
        await tester.pumpAndSettle();

        // Open create task dialog via FAB
        await tester.tap(find.byKey(const Key('addTaskButton')));
        await tester.pumpAndSettle();

        expect(find.text('New Task'), findsOneWidget);

        // Enter title
        await tester.enterText(
          find.byKey(const Key('taskTitleInput')),
          'Brand New Task',
        );

        final dropdownFinder = find.byKey(
          const Key('editTaskEarlyReminderInput'),
        );
        expect(dropdownFinder, findsOneWidget);

        // Verify "None (0 min)" is not shown
        expect(find.text('None (0 min)'), findsNothing);
        expect(find.text('0 min'), findsNothing);

        await tester.tap(dropdownFinder);
        await tester.pumpAndSettle();

        expect(find.text('None (0 min)'), findsNothing);
        expect(find.text('0 min'), findsNothing);
        expect(find.text('0 minutes before'), findsNothing);

        // Select 15 minutes before
        await tester.tap(find.text('15 minutes before').last);
        await tester.pumpAndSettle();

        // Tap Create
        await tester.tap(find.byKey(const Key('saveTaskButton')));
        await tester.pumpAndSettle();

        verify(
          () => mockTaskRepo.updateTask(
            'task-created-1',
            priority: 'none',
            tagIds: const [],
            earlyReminderMinutes: 15,
            repeatRule: 'none',
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
      await tester.pump(const Duration(milliseconds: 350));
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

    testWidgets('single move shows Undo and Undo moves the task back', (
      tester,
    ) async {
      const targetListId = 'target-list-undo';
      await fakeFirestore.collection('lists').doc(targetListId).set({
        'listId': targetListId,
        'uid': uid,
        'name': 'Target List',
        'isDefault': false,
      });

      const taskId = 'task-move-undo';
      await fakeFirestore.collection('tasks').doc(taskId).set({
        'taskId': taskId,
        'uid': uid,
        'listId': listId,
        'title': 'Task to Move and Undo',
        'notes': '',
        'url': '',
        'priority': 'none',
        'tagIds': <String>[],
        'dueDate': null,
        'dueTime': null,
        'earlyReminderMinutes': 0,
        'repeatRule': 'none',
        'repeatCustomConfig': null,
        'order': 0,
        'subtasks': <Map<String, dynamic>>[],
        'createdAt': Timestamp.now(),
        'completedAt': null,
        'deletedAt': null,
      });

      await tester.pumpWidget(createWidgetUnderTest(customListId: listId));
      await tester.pumpAndSettle();

      // Tap move button
      await tester.tap(find.byKey(const Key('moveTaskButton_$taskId')));
      await tester.pumpAndSettle();

      // Tap target list option
      await tester.tap(find.byKey(const Key('moveToListOption_$targetListId')));
      await tester.pumpAndSettle();

      // Verify SnackBar with Undo action
      expect(find.text('Task moved to "Target List"'), findsOneWidget);
      expect(find.byKey(const Key('undoMoveTasksButton')), findsOneWidget);

      // Tap Undo action
      await tester.tap(find.byKey(const Key('undoMoveTasksButton')));
      await tester.pumpAndSettle();

      // Verify task was moved back to original listId
      final doc = await fakeFirestore.collection('tasks').doc(taskId).get();
      expect(doc.data()!['listId'], equals(listId));
    });

    testWidgets(
      'soft delete shows Undo SnackBar, and tapping Undo restores the task',
      (tester) async {
        const taskId = 'task-undo-1';
        await fakeFirestore.collection('tasks').doc(taskId).set({
          'taskId': taskId,
          'uid': uid,
          'listId': listId,
          'title': 'Task to undo',
          'notes': '',
          'url': '',
          'priority': 'none',
          'tagIds': <String>[],
          'dueDate': null,
          'dueTime': null,
          'earlyReminderMinutes': 0,
          'repeatRule': 'none',
          'repeatCustomConfig': null,
          'order': 0,
          'subtasks': <Map<String, dynamic>>[],
          'createdAt': Timestamp.now(),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(createWidgetUnderTest(customListId: listId));
        await tester.pumpAndSettle();

        expect(find.text('Task to undo'), findsOneWidget);

        // Tap delete
        await tester.tap(find.byKey(const Key('deleteTaskButton_$taskId')));
        await tester.pumpAndSettle();

        // Task removed from view, SnackBar shown
        expect(find.text('Task to undo'), findsNothing);
        expect(find.text('Deleted "Task to undo"'), findsOneWidget);
        expect(find.byKey(const Key('undoDeleteTaskButton')), findsOneWidget);

        // Tap Undo button
        await tester.tap(find.byKey(const Key('undoDeleteTaskButton')));
        await tester.pumpAndSettle();

        // Verify task is back in view and Firestore deletedAt is null
        expect(find.text('Task to undo'), findsOneWidget);
        final doc = await fakeFirestore.collection('tasks').doc(taskId).get();
        expect(doc.data()!['deletedAt'], isNull);
      },
    );

    testWidgets('soft delete Undo SnackBar auto-dismisses after 5 seconds', (
      tester,
    ) async {
      const taskId = 'task-undo-timeout';
      await fakeFirestore.collection('tasks').doc(taskId).set({
        'taskId': taskId,
        'uid': uid,
        'listId': listId,
        'title': 'Task to timeout',
        'notes': '',
        'url': '',
        'priority': 'none',
        'tagIds': <String>[],
        'dueDate': null,
        'dueTime': null,
        'earlyReminderMinutes': 0,
        'repeatRule': 'none',
        'repeatCustomConfig': null,
        'order': 0,
        'subtasks': <Map<String, dynamic>>[],
        'createdAt': Timestamp.now(),
        'completedAt': null,
        'deletedAt': null,
      });

      await tester.pumpWidget(createWidgetUnderTest(customListId: listId));
      await tester.pumpAndSettle();

      expect(find.text('Task to timeout'), findsOneWidget);

      // Tap delete
      await tester.tap(find.byKey(const Key('deleteTaskButton_$taskId')));
      await tester.pumpAndSettle();

      // Verify SnackBar is shown
      expect(find.text('Deleted "Task to timeout"'), findsOneWidget);
      expect(find.byKey(const Key('undoDeleteTaskButton')), findsOneWidget);

      // Advance 5 seconds and settle
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Verify SnackBar is dismissed
      expect(find.text('Deleted "Task to timeout"'), findsNothing);
    });

    testWidgets(
      'soft delete Undo SnackBar is dismissed by start-to-end swipe before timeout',
      (tester) async {
        const taskId = 'task-undo-swipe';
        await fakeFirestore.collection('tasks').doc(taskId).set({
          'taskId': taskId,
          'uid': uid,
          'listId': listId,
          'title': 'Task to swipe',
          'notes': '',
          'url': '',
          'priority': 'none',
          'tagIds': <String>[],
          'dueDate': null,
          'dueTime': null,
          'earlyReminderMinutes': 0,
          'repeatRule': 'none',
          'repeatCustomConfig': null,
          'order': 0,
          'subtasks': <Map<String, dynamic>>[],
          'createdAt': Timestamp.now(),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(createWidgetUnderTest(customListId: listId));
        await tester.pumpAndSettle();

        expect(find.text('Task to swipe'), findsOneWidget);

        // Tap delete
        await tester.tap(find.byKey(const Key('deleteTaskButton_$taskId')));
        await tester.pumpAndSettle();

        // SnackBar shown
        expect(find.text('Deleted "Task to swipe"'), findsOneWidget);

        // Incidental swipe to the left does NOT dismiss it
        await tester.fling(
          find.text('Deleted "Task to swipe"'),
          const Offset(-500, 0),
          1000,
        );
        await tester.pumpAndSettle();
        expect(find.text('Deleted "Task to swipe"'), findsOneWidget);

        // Deliberate start-to-end swipe (positive dx) DOES dismiss it
        await tester.fling(
          find.text('Deleted "Task to swipe"'),
          const Offset(500, 0),
          1000,
        );
        await tester.pumpAndSettle();

        // Verify SnackBar dismissed immediately before 5 seconds
        expect(find.text('Deleted "Task to swipe"'), findsNothing);
      },
    );

    testWidgets(
      'soft delete Undo SnackBar appears even if row Element unmounts during softDeleteTask',
      (tester) async {
        const taskId = 'task-undo-unmount';
        await fakeFirestore.collection('tasks').doc(taskId).set({
          'taskId': taskId,
          'uid': uid,
          'listId': listId,
          'title': 'Task unmounted',
          'notes': '',
          'url': '',
          'priority': 'none',
          'tagIds': <String>[],
          'dueDate': null,
          'dueTime': null,
          'earlyReminderMinutes': 0,
          'repeatRule': 'none',
          'repeatCustomConfig': null,
          'order': 0,
          'subtasks': <Map<String, dynamic>>[],
          'createdAt': Timestamp.now(),
          'completedAt': null,
          'deletedAt': null,
        });

        final delayedRepo = _DelayedSoftDeleteTaskRepository(fakeFirestore);

        await tester.pumpWidget(
          createWidgetUnderTest(
            customListId: listId,
            taskRepository: delayedRepo,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Task unmounted'), findsOneWidget);

        // Tap delete
        await tester.tap(find.byKey(const Key('deleteTaskButton_$taskId')));
        await tester.pump(); // Starts softDeleteTask, awaiting completer

        // Simulate live Firestore stream updating and rebuilding list while softDeleteTask is awaiting
        await fakeFirestore.collection('tasks').doc(taskId).update({
          'deletedAt': Timestamp.now(),
        });
        await tester
            .pump(); // Rebuilds TaskListScreen: row Element is unmounted!

        expect(find.text('Task unmounted'), findsNothing);

        // Complete the pending softDeleteTask
        delayedRepo.completer.complete();
        await tester.pump(); // Resumes after softDeleteTask await

        // Verify SnackBar still appears despite row Element being unmounted
        expect(find.text('Deleted "Task unmounted"'), findsOneWidget);
        expect(find.byKey(const Key('undoDeleteTaskButton')), findsOneWidget);
      },
    );

    testWidgets(
      'double-tapping task row selects the task and activates selection mode',
      (tester) async {
        const taskId = 'task-double-tap';
        await fakeFirestore.collection('tasks').doc(taskId).set({
          'taskId': taskId,
          'uid': uid,
          'listId': listId,
          'title': 'Task for Double Tap',
          'notes': '',
          'url': '',
          'priority': 'none',
          'tagIds': [],
          'dueDate': null,
          'dueTime': null,
          'order': 0,
          'subtasks': [],
          'createdAt': Timestamp.now(),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('taskItem_$taskId')), findsOneWidget);
        expect(
          find.byKey(const Key('taskSelectCheckbox_$taskId')),
          findsNothing,
        );

        // Double tap on task row
        await tester.tap(find.byKey(const Key('taskItem_$taskId')));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byKey(const Key('taskItem_$taskId')));
        await tester.pumpAndSettle();

        // Selection mode activated: checkbox is now visible and checked
        expect(
          find.byKey(const Key('taskSelectCheckbox_$taskId')),
          findsOneWidget,
        );
        final checkbox = tester.widget<Checkbox>(
          find.byKey(const Key('taskSelectCheckbox_$taskId')),
        );
        expect(checkbox.value, isTrue);
      },
    );

    testWidgets(
      'task row has no drag handle icon and uses ReorderableDelayedDragStartListener in manual sort mode',
      (tester) async {
        const taskId = 'task-reorder-check';
        await fakeFirestore.collection('tasks').doc(taskId).set({
          'taskId': taskId,
          'uid': uid,
          'listId': listId,
          'title': 'Task for Reorder Check',
          'notes': '',
          'url': '',
          'priority': 'none',
          'order': 0,
          'subtasks': [],
          'createdAt': Timestamp.now(),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // Dedicated drag handle icon is removed
        expect(find.byKey(const Key('taskDragHandle_$taskId')), findsNothing);
        // Delayed drag start listener is present for manual reordering
        expect(
          find.byType(ReorderableDelayedDragStartListener),
          findsOneWidget,
        );

        // Verify proxyDecorator on ReorderableListView renders styled Material
        final listView = tester.widget<ReorderableListView>(
          find.byKey(const Key('tasksListView')),
        );
        expect(listView.proxyDecorator, isNotNull);
      },
    );
  });
}
