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

  group('TaskListScreen Sorting & Drag Handle Tests', () {
    testWidgets(
      'shows sort selector with Manual by default, displays drag handles',
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
        expect(find.byKey(const Key('taskDragHandle_t1')), findsOneWidget);
      },
    );

    testWidgets('switching sort mode hides drag handles and reorders tasks', (
      tester,
    ) async {
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
      expect(titlesBefore, equals(['Low Priority Task', 'High Priority Task']));
      expect(find.byKey(const Key('taskDragHandle_t1')), findsOneWidget);

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

      // Drag handles should NOT be visible when not in Manual mode
      expect(find.byKey(const Key('taskDragHandle_t1')), findsNothing);
      expect(find.byKey(const Key('taskDragHandle_t2')), findsNothing);

      // Verifies persistence in shared preferences
      expect(prefs.getString('task_sort_mode_$listId'), equals('priority'));
    });
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
      expect(find.byKey(const Key('smartTaskDragHandle_st1')), findsOneWidget);

      // Switch to Priority
      await tester.tap(find.byKey(const Key('taskSortDropdown_today')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('taskSortOption_today_priority')).last,
      );
      await tester.pumpAndSettle();

      final titles = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .where((t) => t == 'Today Low Task' || t == 'Today High Task')
          .toList();
      expect(titles, equals(['Today High Task', 'Today Low Task']));

      // In Priority mode, drag handle is hidden
      expect(find.byKey(const Key('smartTaskDragHandle_st1')), findsNothing);
      expect(prefs.getString('task_sort_mode_today'), equals('priority'));
    });
  });
}
