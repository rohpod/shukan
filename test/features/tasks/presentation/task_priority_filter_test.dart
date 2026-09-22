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
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  const uid = 'test-uid';
  const listId = 'list-main';
  const otherListId = 'list-other';

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
      'name': 'Main List',
      'isDefault': true,
    });
    await fakeFirestore.collection('lists').doc(otherListId).set({
      'listId': otherListId,
      'uid': uid,
      'name': 'Other List',
      'isDefault': false,
    });
  });

  Widget createTaskListWidget(String targetListId, {SharedPreferences? prefs}) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentUidProvider.overrideWithValue(uid),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        home: Scaffold(body: TaskListScreen(listId: targetListId)),
      ),
    );
  }

  Widget createSmartViewWidget({
    required SmartViewType viewType,
    DateTime? currentDate,
    SharedPreferences? prefs,
  }) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentUidProvider.overrideWithValue(uid),
        currentDateProvider.overrideWithValue(
          currentDate ?? DateTime(2026, 9, 20, 10, 0),
        ),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(home: SmartViewDetailScreen(viewType: viewType)),
    );
  }

  group('TaskPriorityFilter - TaskListScreen', () {
    testWidgets('filters tasks by priority and restores with All', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();

      // Seed tasks with high, medium, low, and none priority
      await fakeFirestore.collection('tasks').doc('t-high').set({
        'taskId': 't-high',
        'uid': uid,
        'listId': listId,
        'title': 'High Priority Item',
        'priority': 'high',
        'order': 100.0,
        'dueDate': null,
        'subtasks': [],
        'createdAt': Timestamp.now(),
        'completedAt': null,
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('t-med').set({
        'taskId': 't-med',
        'uid': uid,
        'listId': listId,
        'title': 'Medium Priority Item',
        'priority': 'medium',
        'order': 200.0,
        'dueDate': null,
        'subtasks': [],
        'createdAt': Timestamp.now(),
        'completedAt': null,
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('t-low').set({
        'taskId': 't-low',
        'uid': uid,
        'listId': listId,
        'title': 'Low Priority Item',
        'priority': 'low',
        'order': 300.0,
        'dueDate': null,
        'subtasks': [],
        'createdAt': Timestamp.now(),
        'completedAt': null,
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('t-none').set({
        'taskId': 't-none',
        'uid': uid,
        'listId': listId,
        'title': 'No Priority Item',
        'priority': 'none',
        'order': 400.0,
        'dueDate': null,
        'subtasks': [],
        'createdAt': Timestamp.now(),
        'completedAt': null,
        'deletedAt': null,
      });

      await tester.pumpWidget(createTaskListWidget(listId, prefs: prefs));
      await tester.pumpAndSettle();

      expect(find.byType(TaskPriorityFilterSelector), findsOneWidget);

      // Default is All: all 4 tasks visible
      expect(find.text('High Priority Item'), findsOneWidget);
      expect(find.text('Medium Priority Item'), findsOneWidget);
      expect(find.text('Low Priority Item'), findsOneWidget);
      expect(find.text('No Priority Item'), findsOneWidget);

      // Filter by High
      await tester.tap(find.byKey(Key('taskPriorityDropdown_$listId')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('taskPriorityOption_${listId}_high')).last,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('High Priority Item'), findsOneWidget);
      expect(find.text('Medium Priority Item'), findsNothing);
      expect(find.text('Low Priority Item'), findsNothing);
      expect(find.text('No Priority Item'), findsNothing);
      expect(prefs.getString('task_priority_filter_$listId'), equals('high'));

      // Filter by Low
      await tester.tap(find.byKey(Key('taskPriorityDropdown_$listId')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('taskPriorityOption_${listId}_low')).last,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('High Priority Item'), findsNothing);
      expect(find.text('Low Priority Item'), findsOneWidget);

      // Filter by None
      await tester.tap(find.byKey(Key('taskPriorityDropdown_$listId')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('taskPriorityOption_${listId}_none')).last,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Low Priority Item'), findsNothing);
      expect(find.text('No Priority Item'), findsOneWidget);

      // Reset to All
      await tester.tap(find.byKey(Key('taskPriorityDropdown_$listId')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('taskPriorityOption_${listId}_all')).last,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('High Priority Item'), findsOneWidget);
      expect(find.text('Medium Priority Item'), findsOneWidget);
      expect(find.text('Low Priority Item'), findsOneWidget);
      expect(find.text('No Priority Item'), findsOneWidget);
    });
  });

  group('TaskPriorityFilter - SmartViewDetailScreen', () {
    testWidgets('filters tasks by priority in Today smart view', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime(2026, 9, 20, 10, 0);

      await fakeFirestore.collection('tasks').doc('st-high').set({
        'taskId': 'st-high',
        'uid': uid,
        'listId': listId,
        'title': 'Today Urgent',
        'priority': 'high',
        'order': 100.0,
        'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20, 14, 0)),
        'subtasks': [],
        'createdAt': Timestamp.now(),
        'completedAt': null,
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('st-low').set({
        'taskId': 'st-low',
        'uid': uid,
        'listId': listId,
        'title': 'Today Minor',
        'priority': 'low',
        'order': 200.0,
        'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20, 15, 0)),
        'subtasks': [],
        'createdAt': Timestamp.now(),
        'completedAt': null,
        'deletedAt': null,
      });

      await tester.pumpWidget(
        createSmartViewWidget(
          viewType: SmartViewType.today,
          currentDate: today,
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Today Urgent'), findsOneWidget);
      expect(find.text('Today Minor'), findsOneWidget);

      // Select High
      await tester.tap(find.byKey(const Key('taskPriorityDropdown_today')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('taskPriorityOption_today_high')).last,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Today Urgent'), findsOneWidget);
      expect(find.text('Today Minor'), findsNothing);

      // Select Low
      await tester.tap(find.byKey(const Key('taskPriorityDropdown_today')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('taskPriorityOption_today_low')).last,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Today Urgent'), findsNothing);
      expect(find.text('Today Minor'), findsOneWidget);

      expect(prefs.getString('task_priority_filter_today'), equals('low'));
    });
  });

  group('Composition: Priority Filter + Completion Toggle + Sort', () {
    testWidgets('all three controls compose simultaneously in list view', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();

      // High incomplete (earlier date)
      await fakeFirestore.collection('tasks').doc('c1').set({
        'taskId': 'c1',
        'uid': uid,
        'listId': listId,
        'title': 'High Incomplete Task',
        'priority': 'high',
        'order': 100.0,
        'dueDate': Timestamp.fromDate(DateTime(2026, 9, 21)),
        'subtasks': [],
        'createdAt': Timestamp.now(),
        'completedAt': null,
        'deletedAt': null,
      });

      // High completed (later date)
      await fakeFirestore.collection('tasks').doc('c2').set({
        'taskId': 'c2',
        'uid': uid,
        'listId': listId,
        'title': 'High Completed Task',
        'priority': 'high',
        'order': 200.0,
        'dueDate': Timestamp.fromDate(DateTime(2026, 9, 25)),
        'subtasks': [],
        'createdAt': Timestamp.now(),
        'completedAt': Timestamp.now(),
        'deletedAt': null,
      });

      // Medium incomplete
      await fakeFirestore.collection('tasks').doc('c3').set({
        'taskId': 'c3',
        'uid': uid,
        'listId': listId,
        'title': 'Medium Incomplete Task',
        'priority': 'medium',
        'order': 300.0,
        'dueDate': Timestamp.fromDate(DateTime(2026, 9, 19)),
        'subtasks': [],
        'createdAt': Timestamp.now(),
        'completedAt': null,
        'deletedAt': null,
      });

      await tester.pumpWidget(createTaskListWidget(listId, prefs: prefs));
      await tester.pumpAndSettle();

      // 1. Initially, show completed is false, priority is All: c1 and c3 visible
      expect(find.text('High Incomplete Task'), findsOneWidget);
      expect(find.text('Medium Incomplete Task'), findsOneWidget);
      expect(find.text('High Completed Task'), findsNothing);

      // 2. Set Priority to High: only c1 visible
      await tester.tap(find.byKey(Key('taskPriorityDropdown_$listId')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('taskPriorityOption_${listId}_high')).last,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('High Incomplete Task'), findsOneWidget);
      expect(find.text('Medium Incomplete Task'), findsNothing);
      expect(find.text('High Completed Task'), findsNothing);

      // 3. Toggle Show completed ON: both High tasks visible, completed has lineThrough
      await tester.tap(find.byKey(Key('toggleShowCompleted_$listId')));
      await tester.pumpAndSettle();

      expect(find.text('High Incomplete Task'), findsOneWidget);
      expect(find.text('High Completed Task'), findsOneWidget);
      expect(find.text('Medium Incomplete Task'), findsNothing);

      final completedText = tester.widget<Text>(
        find.text('High Completed Task'),
      );
      expect(
        completedText.style?.decoration,
        equals(TextDecoration.lineThrough),
      );

      // 4. Sort by Due Date: c1 (Sep 21) before c2 (Sep 25)
      await tester.tap(find.byKey(Key('taskSortDropdown_$listId')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('taskSortOption_${listId}_dueDate')).last,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .where(
            (t) =>
                t == 'High Incomplete Task' ||
                t == 'High Completed Task' ||
                t == 'Medium Incomplete Task',
          )
          .toList();

      expect(texts, equals(['High Incomplete Task', 'High Completed Task']));
    });
  });

  group('Per-view independent persistence', () {
    testWidgets(
      'priority filter persists independently per view across restarts',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        await tester.pumpWidget(createTaskListWidget(listId, prefs: prefs));
        await tester.pumpAndSettle();

        // Change listId filter to Medium
        await tester.tap(find.byKey(Key('taskPriorityDropdown_$listId')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(Key('taskPriorityOption_${listId}_medium')).last,
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(
          prefs.getString('task_priority_filter_$listId'),
          equals('medium'),
        );
        expect(prefs.getString('task_priority_filter_$otherListId'), isNull);
        expect(prefs.getString('task_priority_filter_today'), isNull);

        // Rebuild widget with restored prefs
        await tester.pumpWidget(createTaskListWidget(listId, prefs: prefs));
        await tester.pumpAndSettle();

        expect(find.text('Medium'), findsOneWidget);
      },
    );
  });
}
