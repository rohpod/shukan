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
import 'package:shukan/features/tasks/presentation/widgets/show_completed_toggle.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  const uid = 'test-uid';
  const listId = 'list-1';
  const otherListId = 'list-2';

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
      'name': 'My List',
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

  group('ShowCompletedToggle - TaskListScreen', () {
    testWidgets(
      'hides completed tasks by default and shows them with strikethrough when toggled',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();

        // 1 incomplete task, 1 completed task
        await fakeFirestore.collection('tasks').doc('t-inc').set({
          'taskId': 't-inc',
          'uid': uid,
          'listId': listId,
          'title': 'Incomplete Task',
          'order': 100.0,
          'dueDate': null,
          'subtasks': [],
          'createdAt': Timestamp.now(),
          'completedAt': null,
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('t-comp').set({
          'taskId': 't-comp',
          'uid': uid,
          'listId': listId,
          'title': 'Completed Task',
          'order': 200.0,
          'dueDate': null,
          'subtasks': [],
          'createdAt': Timestamp.now(),
          'completedAt': Timestamp.now(),
          'deletedAt': null,
        });

        await tester.pumpWidget(createTaskListWidget(listId, prefs: prefs));
        await tester.pumpAndSettle();

        // ShowCompletedToggle should exist
        expect(find.byType(ShowCompletedToggle), findsOneWidget);
        expect(find.byKey(Key('toggleShowCompleted_$listId')), findsOneWidget);

        // Default: incomplete visible, completed hidden
        expect(find.text('Incomplete Task'), findsOneWidget);
        expect(find.text('Completed Task'), findsNothing);

        // Tap toggle to show completed tasks
        await tester.tap(find.byKey(Key('toggleShowCompleted_$listId')));
        await tester.pumpAndSettle();

        // Both tasks now visible
        expect(find.text('Incomplete Task'), findsOneWidget);
        expect(find.text('Completed Task'), findsOneWidget);

        // Verify completed task styling (strikethrough)
        final completedText = tester.widget<Text>(find.text('Completed Task'));
        expect(
          completedText.style?.decoration,
          equals(TextDecoration.lineThrough),
        );
        expect(completedText.style?.color, equals(Colors.grey));

        final incompleteText = tester.widget<Text>(
          find.text('Incomplete Task'),
        );
        expect(
          incompleteText.style?.decoration,
          isNot(equals(TextDecoration.lineThrough)),
        );

        // Verify persistence
        expect(prefs.getBool('task_show_completed_$listId'), isTrue);

        // Tap toggle again to hide completed tasks
        await tester.tap(find.byKey(Key('toggleShowCompleted_$listId')));
        await tester.pumpAndSettle();

        expect(find.text('Incomplete Task'), findsOneWidget);
        expect(find.text('Completed Task'), findsNothing);
        expect(prefs.getBool('task_show_completed_$listId'), isFalse);
      },
    );

    testWidgets('completing a task hides it immediately when toggle is off', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();

      await fakeFirestore.collection('tasks').doc('t1').set({
        'taskId': 't1',
        'uid': uid,
        'listId': listId,
        'title': 'Active Task',
        'order': 100.0,
        'dueDate': null,
        'subtasks': [],
        'createdAt': Timestamp.now(),
        'completedAt': null,
        'deletedAt': null,
      });

      await tester.pumpWidget(createTaskListWidget(listId, prefs: prefs));
      await tester.pumpAndSettle();

      expect(find.text('Active Task'), findsOneWidget);

      // Check task complete checkbox
      await tester.tap(find.byKey(const Key('taskCompleteCheckbox_t1')));
      await tester.pumpAndSettle();

      // Immediately hidden because show completed is off
      expect(find.text('Active Task'), findsNothing);
      expect(find.byKey(const Key('noTasksText')), findsOneWidget);
    });
  });

  group('ShowCompletedToggle - SmartViewDetailScreen', () {
    testWidgets(
      'Today view hides completed tasks by default and shows today completed when toggled',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        final testDate = DateTime(2026, 9, 20, 12, 0);

        // Incomplete task due today
        await fakeFirestore.collection('tasks').doc('st-inc').set({
          'taskId': 'st-inc',
          'uid': uid,
          'listId': listId,
          'title': 'Today Incomplete',
          'order': 100.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20, 15, 0)),
          'subtasks': [],
          'createdAt': Timestamp.now(),
          'completedAt': null,
          'deletedAt': null,
        });

        // Completed task due today
        await fakeFirestore.collection('tasks').doc('st-comp').set({
          'taskId': 'st-comp',
          'uid': uid,
          'listId': listId,
          'title': 'Today Completed',
          'order': 200.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 20, 11, 0)),
          'subtasks': [],
          'createdAt': Timestamp.now(),
          'completedAt': Timestamp.now(),
          'deletedAt': null,
        });

        // Overdue completed task from yesterday (must NEVER appear in Today view)
        await fakeFirestore.collection('tasks').doc('st-past-comp').set({
          'taskId': 'st-past-comp',
          'uid': uid,
          'listId': listId,
          'title': 'Past Completed',
          'order': 300.0,
          'dueDate': Timestamp.fromDate(DateTime(2026, 9, 19, 11, 0)),
          'subtasks': [],
          'createdAt': Timestamp.now(),
          'completedAt': Timestamp.now(),
          'deletedAt': null,
        });

        await tester.pumpWidget(
          createSmartViewWidget(
            viewType: SmartViewType.today,
            currentDate: testDate,
            prefs: prefs,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ShowCompletedToggle), findsOneWidget);
        expect(
          find.byKey(const Key('toggleShowCompleted_today')),
          findsOneWidget,
        );

        // Default: only today's incomplete task visible
        expect(find.text('Today Incomplete'), findsOneWidget);
        expect(find.text('Today Completed'), findsNothing);
        expect(find.text('Past Completed'), findsNothing);

        // Toggle on Show Completed
        await tester.tap(find.byKey(const Key('toggleShowCompleted_today')));
        await tester.pumpAndSettle();

        // Today completed task is now visible with strikethrough
        expect(find.text('Today Incomplete'), findsOneWidget);
        expect(find.text('Today Completed'), findsOneWidget);
        // Overdue completed task must NOT appear
        expect(find.text('Past Completed'), findsNothing);

        final completedText = tester.widget<Text>(find.text('Today Completed'));
        expect(
          completedText.style?.decoration,
          equals(TextDecoration.lineThrough),
        );

        expect(prefs.getBool('task_show_completed_today'), isTrue);
      },
    );
  });

  group('Per-view independent persistence', () {
    testWidgets('toggling in one view does not affect other views', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(createTaskListWidget(listId, prefs: prefs));
      await tester.pumpAndSettle();

      // Toggle listId to true
      await tester.tap(find.byKey(Key('toggleShowCompleted_$listId')));
      await tester.pumpAndSettle();

      expect(prefs.getBool('task_show_completed_$listId'), isTrue);
      expect(prefs.getBool('task_show_completed_$otherListId'), isNull);
      expect(prefs.getBool('task_show_completed_today'), isNull);
      expect(prefs.getBool('task_show_completed_thisWeek'), isNull);
      expect(prefs.getBool('task_show_completed_scheduled'), isNull);
    });
  });
}
