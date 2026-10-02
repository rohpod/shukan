import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/providers/auth_providers.dart';
import 'package:shukan/features/tags/presentation/tag_detail_screen.dart';
import 'package:shukan/features/tasks/domain/smart_view_models.dart';
import 'package:shukan/features/tasks/presentation/smart_view_detail_screen.dart';
import 'package:shukan/features/tasks/presentation/task_list_screen.dart';
import 'package:shukan/features/tasks/presentation/widgets/task_sort_selector.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  const uid = 'test-uid';
  const listId = 'inbox-list';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fakeFirestore = FakeFirebaseFirestore();
    final user = MockUser(uid: uid, email: 'test@example.com');
    mockAuth = MockFirebaseAuth(mockUser: user, signedIn: true);

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

  Widget createTaskListWidget({SharedPreferences? prefs}) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentUidProvider.overrideWithValue(uid),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MaterialApp(
        home: Scaffold(body: TaskListScreen(listId: listId)),
      ),
    );
  }

  Widget createSmartViewWidget({
    required SmartViewType viewType,
    SharedPreferences? prefs,
  }) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentUidProvider.overrideWithValue(uid),
        currentDateProvider.overrideWithValue(DateTime(2026, 9, 20)),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(home: SmartViewDetailScreen(viewType: viewType)),
    );
  }

  Widget createTagDetailWidget({
    required String tagId,
    required String tagName,
    SharedPreferences? prefs,
  }) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentUidProvider.overrideWithValue(uid),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        home: TagDetailScreen(tagId: tagId, tagName: tagName),
      ),
    );
  }

  group('TaskListScreen Sorting & Drag Handle Tests', () {
    testWidgets(
      'shows sort selector with Manual by default, enables delayed drag listener',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        // Add two tasks
        await fakeFirestore.collection('tasks').doc('t1').set({
          'taskId': 't1',
          'uid': uid,
          'listId': listId,
          'title': 'Task A',
          'priority': 'none',
          'order': 100.0,
          'dueDate': null,
          'subtasks': [],
          'createdAt': Timestamp.now(),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(createTaskListWidget(prefs: prefs));
        await tester.pumpAndSettle();

        expect(find.byType(TaskSortSelector), findsOneWidget);
        expect(find.text('Manual'), findsOneWidget);
        expect(
          find.byType(ReorderableDelayedDragStartListener),
          findsOneWidget,
        );
        expect(find.byKey(const Key('taskDragHandle_t1')), findsNothing);
      },
    );

    testWidgets(
      'switching sort mode reorders tasks and keeps drag listener enabled',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        await fakeFirestore.collection('tasks').doc('t1').set({
          'taskId': 't1',
          'uid': uid,
          'listId': listId,
          'title': 'Low Priority Task',
          'priority': 'low',
          'order': 100.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 25)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'completedAt': null,
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('t2').set({
          'taskId': 't2',
          'uid': uid,
          'listId': listId,
          'title': 'High Priority Task',
          'priority': 'high',
          'order': 200.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 15)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(createTaskListWidget(prefs: prefs));
        await tester.pumpAndSettle();

        // In Manual mode, t1 (100) comes before t2 (200)
        final titlesBefore = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .where((t) => t == 'Low Priority Task' || t == 'High Priority Task')
            .toList();
        expect(
          titlesBefore,
          equals(['Low Priority Task', 'High Priority Task']),
        );
        expect(find.byType(ReorderableDelayedDragStartListener), findsWidgets);
        expect(find.byKey(const Key('taskDragHandle_t1')), findsNothing);

        // Tap sort dropdown and select Priority
        await tester.tap(find.byKey(Key('taskSortDropdown_$listId')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(Key('taskSortOption_${listId}_priority')).last,
        );
        await tester.pumpAndSettle();

        // In Priority mode, High Priority comes first
        final titlesAfterPriority = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .where((t) => t == 'Low Priority Task' || t == 'High Priority Task')
            .toList();
        expect(
          titlesAfterPriority,
          equals(['High Priority Task', 'Low Priority Task']),
        );

        // Drag listeners remain active across sort modes, and handles remain absent
        expect(
          find.byType(ReorderableDelayedDragStartListener),
          findsNWidgets(2),
        );
        expect(find.byKey(const Key('taskDragHandle_t1')), findsNothing);
        expect(find.byKey(const Key('taskDragHandle_t2')), findsNothing);

        // Verifies persistence in shared preferences
        expect(prefs.getString('task_sort_mode_$listId'), equals('priority'));
      },
    );

    testWidgets(
      'reordering task in non-manual sort mode switches to Manual and shows notice',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        await fakeFirestore.collection('tasks').doc('t1').set({
          'taskId': 't1',
          'uid': uid,
          'listId': listId,
          'title': 'Low Priority Task',
          'priority': 'low',
          'order': 100.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 25)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'completedAt': null,
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('t2').set({
          'taskId': 't2',
          'uid': uid,
          'listId': listId,
          'title': 'High Priority Task',
          'priority': 'high',
          'order': 200.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 15)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'completedAt': null,
          'deletedAt': null,
        });

        // Start in Priority sort mode
        await prefs.setString('task_sort_mode_$listId', 'priority');

        await tester.pumpWidget(createTaskListWidget(prefs: prefs));
        await tester.pumpAndSettle();

        expect(find.text('Priority'), findsOneWidget);

        final reorderable = tester.widget<ReorderableListView>(
          find.byKey(const Key('tasksListView')),
        );
        // Drag index 0 (t2) to index 2 (after t1)
        reorderable.onReorderItem!(0, 2);
        await tester.pumpAndSettle();

        // Sort mode changed to Manual
        expect(prefs.getString('task_sort_mode_$listId'), equals('manual'));
        expect(
          find.text('Sort changed from Priority to Manual'),
          findsOneWidget,
        );

        // Firestore updated t2 order to be after t1
        final snapT2 = await fakeFirestore.collection('tasks').doc('t2').get();
        final snapT1 = await fakeFirestore.collection('tasks').doc('t1').get();
        expect(
          (snapT2.data()!['order'] as num).toDouble(),
          greaterThan((snapT1.data()!['order'] as num).toDouble()),
        );
      },
    );

    testWidgets(
      'reordering task while already in Manual mode shows no notice',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        await fakeFirestore.collection('tasks').doc('t1').set({
          'taskId': 't1',
          'uid': uid,
          'listId': listId,
          'title': 'Task 1',
          'priority': 'none',
          'order': 100.0,
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'completedAt': null,
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('t2').set({
          'taskId': 't2',
          'uid': uid,
          'listId': listId,
          'title': 'Task 2',
          'priority': 'none',
          'order': 200.0,
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'completedAt': null,
          'deletedAt': null,
        });

        await prefs.setString('task_sort_mode_$listId', 'manual');

        await tester.pumpWidget(createTaskListWidget(prefs: prefs));
        await tester.pumpAndSettle();

        final reorderable = tester.widget<ReorderableListView>(
          find.byKey(const Key('tasksListView')),
        );
        reorderable.onReorderItem!(0, 2);
        await tester.pumpAndSettle();

        expect(find.textContaining('Sort changed'), findsNothing);
      },
    );
  });

  group('SmartViewDetailScreen Sorting Tests', () {
    testWidgets('shows sort selector and sorts tasks in smart view', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();

      // Add two tasks for Today (2026-09-20)
      await fakeFirestore.collection('tasks').doc('st1').set({
        'taskId': 'st1',
        'uid': uid,
        'listId': listId,
        'title': 'Today Low Task',
        'priority': 'low',
        'order': 100.0,
        'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20)),
        'subtasks': [],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'completedAt': null,
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('st2').set({
        'taskId': 'st2',
        'uid': uid,
        'listId': listId,
        'title': 'Today High Task',
        'priority': 'high',
        'order': 200.0,
        'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20)),
        'subtasks': [],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
        'completedAt': null,
        'deletedAt': null,
      });

      await tester.pumpWidget(
        createSmartViewWidget(viewType: SmartViewType.today, prefs: prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TaskSortSelector), findsOneWidget);
      expect(find.text('Due date'), findsOneWidget);

      // Default Due date sort: High Priority comes before Low Priority (tie-break by priority)
      var titles = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .where((t) => t == 'Today Low Task' || t == 'Today High Task')
          .toList();
      expect(titles, equals(['Today High Task', 'Today Low Task']));

      // In Due date mode, drag listener is present across sort modes and handle is removed
      expect(find.byType(ReorderableDelayedDragStartListener), findsWidgets);
      expect(find.byKey(const Key('smartTaskDragHandle_st1')), findsNothing);

      // Switch to Priority
      await tester.tap(find.byKey(const Key('taskSortDropdown_today')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('taskSortOption_today_priority')).last,
      );
      await tester.pumpAndSettle();

      titles = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .where((t) => t == 'Today Low Task' || t == 'Today High Task')
          .toList();
      expect(titles, equals(['Today High Task', 'Today Low Task']));

      // In Priority mode, drag listener remains present
      expect(find.byType(ReorderableDelayedDragStartListener), findsWidgets);
      expect(find.byKey(const Key('smartTaskDragHandle_st1')), findsNothing);
      expect(prefs.getString('task_sort_mode_today'), equals('priority'));

      // Switch to Manual
      await tester.tap(find.byKey(const Key('taskSortDropdown_today')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('taskSortOption_today_manual')).last,
      );
      await tester.pumpAndSettle();

      // In Manual mode, tasks are ordered by order (st1: 100.0 < st2: 200.0)
      titles = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .where((t) => t == 'Today Low Task' || t == 'Today High Task')
          .toList();
      expect(titles, equals(['Today Low Task', 'Today High Task']));
      // Long-press drag listener is present for manual mode, drag handle icon is removed
      expect(find.byType(ReorderableDelayedDragStartListener), findsWidgets);
      expect(find.byKey(const Key('smartTaskDragHandle_st1')), findsNothing);
      expect(prefs.getString('task_sort_mode_today'), equals('manual'));
    });

    testWidgets(
      'reordering task in smart view while in Due date mode switches to Manual and shows notice',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        await fakeFirestore.collection('tasks').doc('st1').set({
          'taskId': 'st1',
          'uid': uid,
          'listId': listId,
          'title': 'Today Low Task',
          'priority': 'low',
          'order': 100.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'completedAt': null,
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('st2').set({
          'taskId': 'st2',
          'uid': uid,
          'listId': listId,
          'title': 'Today High Task',
          'priority': 'high',
          'order': 200.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(
          createSmartViewWidget(viewType: SmartViewType.today, prefs: prefs),
        );
        await tester.pumpAndSettle();

        expect(find.text('Due date'), findsOneWidget);

        final reorderable = tester.widget<ReorderableListView>(
          find.byKey(const Key('smartViewsListView_today')),
        );
        reorderable.onReorderItem!(0, 2);
        await tester.pumpAndSettle();

        expect(prefs.getString('task_sort_mode_today'), equals('manual'));
        expect(
          find.text('Sort changed from Due date to Manual'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'reordering task in smart view while already in Manual mode shows no notice',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        await fakeFirestore.collection('tasks').doc('st1').set({
          'taskId': 'st1',
          'uid': uid,
          'listId': listId,
          'title': 'Today Low Task',
          'priority': 'low',
          'order': 100.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'completedAt': null,
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('st2').set({
          'taskId': 'st2',
          'uid': uid,
          'listId': listId,
          'title': 'Today High Task',
          'priority': 'high',
          'order': 200.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'completedAt': null,
          'deletedAt': null,
        });

        await prefs.setString('task_sort_mode_today', 'manual');

        await tester.pumpWidget(
          createSmartViewWidget(viewType: SmartViewType.today, prefs: prefs),
        );
        await tester.pumpAndSettle();

        final reorderable = tester.widget<ReorderableListView>(
          find.byKey(const Key('smartViewsListView_today')),
        );
        reorderable.onReorderItem!(0, 2);
        await tester.pumpAndSettle();

        expect(find.textContaining('Sort changed'), findsNothing);
      },
    );
  });

  group('TagDetailScreen Sorting & Reordering Tests', () {
    testWidgets(
      'shows sort selector and keeps drag listener enabled across sort modes',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        await fakeFirestore.collection('tags').doc('tag-work').set({
          'tagId': 'tag-work',
          'uid': uid,
          'name': 'Work',
          'createdAt': DateTime.now(),
        });

        await fakeFirestore.collection('tasks').doc('tt1').set({
          'taskId': 'tt1',
          'uid': uid,
          'listId': listId,
          'title': 'Work Low Task',
          'priority': 'low',
          'order': 100.0,
          'tagIds': ['tag-work'],
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 25)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'completedAt': null,
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('tt2').set({
          'taskId': 'tt2',
          'uid': uid,
          'listId': listId,
          'title': 'Work High Task',
          'priority': 'high',
          'order': 200.0,
          'tagIds': ['tag-work'],
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 15)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(
          createTagDetailWidget(
            tagId: 'tag-work',
            tagName: 'Work',
            prefs: prefs,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ReorderableDelayedDragStartListener), findsWidgets);
        expect(find.byKey(const Key('taskDragHandle_tt1')), findsNothing);

        // Switch to Priority
        await tester.tap(
          find.byKey(const Key('taskSortDropdown_tag_tag-work')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('taskSortOption_tag_tag-work_priority')).last,
        );
        await tester.pumpAndSettle();

        // Drag listener remains enabled
        expect(find.byType(ReorderableDelayedDragStartListener), findsWidgets);
        expect(
          prefs.getString('task_sort_mode_tag_tag-work'),
          equals('priority'),
        );
      },
    );

    testWidgets(
      'reordering task in tag detail while in non-manual sort mode switches to Manual and shows notice',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        await fakeFirestore.collection('tags').doc('tag-work').set({
          'tagId': 'tag-work',
          'uid': uid,
          'name': 'Work',
          'createdAt': DateTime.now(),
        });

        await fakeFirestore.collection('tasks').doc('tt1').set({
          'taskId': 'tt1',
          'uid': uid,
          'listId': listId,
          'title': 'Work Low Task',
          'priority': 'low',
          'order': 100.0,
          'tagIds': ['tag-work'],
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 25)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'completedAt': null,
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('tt2').set({
          'taskId': 'tt2',
          'uid': uid,
          'listId': listId,
          'title': 'Work High Task',
          'priority': 'high',
          'order': 200.0,
          'tagIds': ['tag-work'],
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 15)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'completedAt': null,
          'deletedAt': null,
        });

        await prefs.setString('task_sort_mode_tag_tag-work', 'priority');

        await tester.pumpWidget(
          createTagDetailWidget(
            tagId: 'tag-work',
            tagName: 'Work',
            prefs: prefs,
          ),
        );
        await tester.pumpAndSettle();

        final reorderable = tester.widget<ReorderableListView>(
          find.byKey(const Key('tagTaskList_tag_tag-work')),
        );
        reorderable.onReorderItem!(0, 2);
        await tester.pumpAndSettle();

        expect(
          prefs.getString('task_sort_mode_tag_tag-work'),
          equals('manual'),
        );
        expect(
          find.text('Sort changed from Priority to Manual'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'reordering task in tag detail while already in Manual mode shows no notice',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        await fakeFirestore.collection('tags').doc('tag-work').set({
          'tagId': 'tag-work',
          'uid': uid,
          'name': 'Work',
          'createdAt': DateTime.now(),
        });

        await fakeFirestore.collection('tasks').doc('tt1').set({
          'taskId': 'tt1',
          'uid': uid,
          'listId': listId,
          'title': 'Work Low Task',
          'priority': 'low',
          'order': 100.0,
          'tagIds': ['tag-work'],
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'completedAt': null,
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('tt2').set({
          'taskId': 'tt2',
          'uid': uid,
          'listId': listId,
          'title': 'Work High Task',
          'priority': 'high',
          'order': 200.0,
          'tagIds': ['tag-work'],
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'completedAt': null,
          'deletedAt': null,
        });

        await prefs.setString('task_sort_mode_tag_tag-work', 'manual');

        await tester.pumpWidget(
          createTagDetailWidget(
            tagId: 'tag-work',
            tagName: 'Work',
            prefs: prefs,
          ),
        );
        await tester.pumpAndSettle();

        final reorderable = tester.widget<ReorderableListView>(
          find.byKey(const Key('tagTaskList_tag_tag-work')),
        );
        reorderable.onReorderItem!(0, 2);
        await tester.pumpAndSettle();

        expect(find.textContaining('Sort changed'), findsNothing);
      },
    );
  });
}
