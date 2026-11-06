import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/providers/auth_providers.dart';
import 'package:shukan/features/tasks/domain/smart_view_models.dart';
import 'package:shukan/features/tasks/presentation/smart_view_detail_screen.dart';
import 'package:shukan/features/tasks/presentation/task_list_screen.dart';
import 'package:shukan/features/tasks/presentation/widgets/task_priority_filter_selector.dart';
import 'package:shukan/features/tasks/presentation/widgets/task_row_tag_chips.dart';
import 'package:shukan/features/tasks/presentation/widgets/task_sort_selector.dart';
import 'package:shukan/features/tasks/presentation/widgets/task_tag_filter_selector.dart';
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

  group('SmartViewDetailScreen Fixed Due-Date & Absence of Controls Tests', () {
    testWidgets(
      'no sort, priority filter, or tag filter selectors render on any smart view',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        for (final viewType in SmartViewType.values) {
          await tester.pumpWidget(
            createSmartViewWidget(viewType: viewType, prefs: prefs),
          );
          await tester.pumpAndSettle();

          expect(find.byType(TaskSortSelector), findsNothing);
          expect(find.byType(TaskPriorityFilterSelector), findsNothing);
          expect(find.byType(TaskTagFilterSelector), findsNothing);
          expect(find.byType(ReorderableListView), findsNothing);
          expect(
            find.byType(ReorderableDelayedDragStartListener),
            findsNothing,
          );
        }
      },
    );

    testWidgets(
      'tasks in smart view are always displayed in due-date order regardless of stored sort-mode preference',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('task_sort_mode_today', 'manual');

        // Add 3 tasks for Today (2026-09-20)
        // st1: Later time (14:00), low priority, lower order
        await fakeFirestore.collection('tasks').doc('st1').set({
          'taskId': 'st1',
          'uid': uid,
          'listId': listId,
          'title': 'Later Low Task',
          'priority': 'low',
          'order': 100.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20, 14, 0)),
          'dueTime': '14:00',
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'completedAt': null,
          'deletedAt': null,
        });
        // st2: Earlier time (09:00), medium priority, higher order
        await fakeFirestore.collection('tasks').doc('st2').set({
          'taskId': 'st2',
          'uid': uid,
          'listId': listId,
          'title': 'Earlier Medium Task',
          'priority': 'medium',
          'order': 300.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20, 9, 0)),
          'dueTime': '09:00',
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'completedAt': null,
          'deletedAt': null,
        });
        // st3: Later time (14:00), high priority, mid order
        await fakeFirestore.collection('tasks').doc('st3').set({
          'taskId': 'st3',
          'uid': uid,
          'listId': listId,
          'title': 'Later High Task',
          'priority': 'high',
          'order': 200.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20, 14, 0)),
          'dueTime': '14:00',
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 3)),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(
          createSmartViewWidget(viewType: SmartViewType.today, prefs: prefs),
        );
        await tester.pumpAndSettle();

        // Due date sort order:
        // 1. Earlier Medium Task (09:00)
        // 2. Later High Task (14:00, high priority)
        // 3. Later Low Task (14:00, low priority)
        final titles = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .where(
              (t) =>
                  t == 'Earlier Medium Task' ||
                  t == 'Later High Task' ||
                  t == 'Later Low Task',
            )
            .toList();
        expect(
          titles,
          equals(['Earlier Medium Task', 'Later High Task', 'Later Low Task']),
        );
      },
    );

    testWidgets(
      'dragging a smart-view task row does not reorder or alter task order in Firestore',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        await fakeFirestore.collection('tasks').doc('st1').set({
          'taskId': 'st1',
          'uid': uid,
          'listId': listId,
          'title': 'Today Task 1',
          'priority': 'none',
          'order': 100.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20, 10, 0)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'completedAt': null,
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('st2').set({
          'taskId': 'st2',
          'uid': uid,
          'listId': listId,
          'title': 'Today Task 2',
          'priority': 'none',
          'order': 200.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20, 11, 0)),
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(
          createSmartViewWidget(viewType: SmartViewType.today, prefs: prefs),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ReorderableDelayedDragStartListener), findsNothing);

        // Attempt drag gesture
        await tester.drag(find.text('Today Task 1'), const Offset(0, 150));
        await tester.pumpAndSettle();

        // Tasks in Firestore remain untouched
        final doc1 = await fakeFirestore.collection('tasks').doc('st1').get();
        final doc2 = await fakeFirestore.collection('tasks').doc('st2').get();
        expect(doc1.data()!['order'], equals(100.0));
        expect(doc2.data()!['order'], equals(200.0));
      },
    );

    testWidgets(
      'no tag chips render on smart-view rows even when tasks have tags',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        await fakeFirestore.collection('tasks').doc('st-tagged').set({
          'taskId': 'st-tagged',
          'uid': uid,
          'listId': listId,
          'title': 'Tagged Smart Task',
          'priority': 'none',
          'order': 100.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20, 10, 0)),
          'tagIds': ['tag-1', 'tag-2'],
          'subtasks': [],
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(
          createSmartViewWidget(viewType: SmartViewType.today, prefs: prefs),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tagged Smart Task'), findsOneWidget);
        expect(find.byType(TaskRowTagChips), findsNothing);
      },
    );
  });
}
