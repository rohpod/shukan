import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/providers/auth_providers.dart';
import 'package:shukan/features/lists/data/list.dart';
import 'package:shukan/features/lists/presentation/list_detail_screen.dart';
import 'package:shukan/features/lists/providers/list_providers.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/domain/smart_view_models.dart';
import 'package:shukan/features/tasks/presentation/smart_view_detail_screen.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';
import 'package:shukan/features/tasks/providers/task_providers.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  const uid = 'test-user-smart';
  const defaultListId = 'inbox-100';

  setUp(() async {
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'user@example.com'),
      signedIn: true,
    );
    fakeFirestore = FakeFirebaseFirestore();

    // Bootstrap user and inbox list
    await fakeFirestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': 'user@example.com',
      'defaultListId': defaultListId,
    });
    await fakeFirestore.collection('lists').doc(defaultListId).set({
      'listId': defaultListId,
      'uid': uid,
      'name': 'Inbox',
      'isDefault': true,
    });
  });

  Widget createWidgetUnderTest(
    SmartViewType viewType, {
    DateTime? overrideDate,
  }) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        if (overrideDate != null)
          currentDateProvider.overrideWithValue(overrideDate),
      ],
      child: MaterialApp(home: SmartViewDetailScreen(viewType: viewType)),
    );
  }

  group('SmartViewDetailScreen Widget Tests', () {
    testWidgets(
      'Today view renders title, completion filters, and matching tasks',
      (tester) async {
        final today = DateTime(2026, 10, 14, 12, 0);

        await fakeFirestore.collection('tasks').doc('t-today-1').set({
          'taskId': 't-today-1',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Pay Electricity Bill',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 14, 15, 0)),
          'dueTime': '15:00',
          'priority': 'high',
          'deletedAt': null,
          'completedAt': null,
        });

        await tester.pumpWidget(
          createWidgetUnderTest(SmartViewType.today, overrideDate: today),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('smartViewTitle_today')), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);

        // Work week toggle should NOT be visible on Today view
        expect(find.byKey(const Key('workWeekFilterButton')), findsNothing);

        // Show completed toggle button should be visible
        expect(
          find.byKey(const Key('toggleShowCompleted_today')),
          findsOneWidget,
        );

        // Task is rendered
        expect(find.text('Pay Electricity Bill'), findsOneWidget);
        expect(find.text('HIGH'), findsOneWidget);
        expect(find.textContaining('15:00'), findsOneWidget);
        expect(find.textContaining('List: Inbox'), findsOneWidget);
      },
    );

    testWidgets(
      'This Week view renders all tasks for the week without week toggles',
      (tester) async {
        final wednesday = DateTime(2026, 10, 14, 10, 0);

        // Thursday task
        await fakeFirestore.collection('tasks').doc('t-thurs').set({
          'taskId': 't-thurs',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Thursday Review',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
          'deletedAt': null,
          'completedAt': null,
        });

        // Saturday task
        await fakeFirestore.collection('tasks').doc('t-sat').set({
          'taskId': 't-sat',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Saturday Hike',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 17)),
          'deletedAt': null,
          'completedAt': null,
        });

        await tester.pumpWidget(
          createWidgetUnderTest(
            SmartViewType.thisWeek,
            overrideDate: wednesday,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('smartViewTitle_thisWeek')),
          findsOneWidget,
        );
        // Week toggles must NOT exist
        expect(find.byKey(const Key('workWeekFilterButton')), findsNothing);
        expect(find.byKey(const Key('fullWeekFilterButton')), findsNothing);

        // All week tasks visible
        expect(find.text('Thursday Review'), findsOneWidget);
        expect(find.text('Saturday Hike'), findsOneWidget);
      },
    );

    testWidgets(
      'Scheduled view renders due date and time under each task row',
      (tester) async {
        final now = DateTime(2026, 10, 14, 10, 0);

        await fakeFirestore.collection('tasks').doc('t-sched-1').set({
          'taskId': 't-sched-1',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Dentist Appointment',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 20, 14, 30)),
          'dueTime': '14:30',
          'deletedAt': null,
          'completedAt': null,
        });

        await fakeFirestore.collection('tasks').doc('t-sched-2').set({
          'taskId': 't-sched-2',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Tax Submission',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 25)),
          'deletedAt': null,
          'completedAt': null,
        });

        await tester.pumpWidget(
          createWidgetUnderTest(SmartViewType.scheduled, overrideDate: now),
        );
        await tester.pumpAndSettle();

        expect(find.text('Dentist Appointment'), findsOneWidget);
        expect(find.text('Tax Submission'), findsOneWidget);

        // Due date subheading on line 2
        expect(find.byKey(const Key('taskDueDate_t-sched-1')), findsOneWidget);
        expect(find.text('2026-10-20 14:30'), findsOneWidget);

        expect(find.byKey(const Key('taskDueDate_t-sched-2')), findsOneWidget);
        expect(find.text('2026-10-25'), findsOneWidget);
      },
    );

    testWidgets(
      'Today view renders overdue tasks highlighted in red and today tasks in blueGrey',
      (tester) async {
        final today = DateTime(2026, 10, 14, 10, 0);

        // Overdue task
        await fakeFirestore.collection('tasks').doc('t-overdue').set({
          'taskId': 't-overdue',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Late Report',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 12, 17, 0)),
          'dueTime': '17:00',
          'deletedAt': null,
          'completedAt': null,
        });

        // Today task
        await fakeFirestore.collection('tasks').doc('t-today').set({
          'taskId': 't-today',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Today Standup',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 14, 9, 30)),
          'dueTime': '09:30',
          'deletedAt': null,
          'completedAt': null,
        });

        await tester.pumpWidget(
          createWidgetUnderTest(SmartViewType.today, overrideDate: today),
        );
        await tester.pumpAndSettle();

        expect(find.text('Late Report'), findsOneWidget);
        expect(find.text('Today Standup'), findsOneWidget);

        final overdueText = tester.widget<Text>(
          find.byKey(const Key('taskDueDate_t-overdue')),
        );
        expect(overdueText.style?.color, equals(Colors.red.shade700));

        final todayText = tester.widget<Text>(
          find.byKey(const Key('taskDueDate_t-today')),
        );
        expect(todayText.style?.color, equals(Colors.blueGrey));
      },
    );

    testWidgets(
      'checkbox toggles task completion and updates view accordingly',
      (tester) async {
        final today = DateTime(2026, 10, 14, 10, 0);

        await fakeFirestore.collection('tasks').doc('t-toggle').set({
          'taskId': 't-toggle',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Grocery Shopping',
          'dueDate': Timestamp.fromDate(DateTime(2026, 10, 14)),
          'deletedAt': null,
          'completedAt': null,
        });

        await tester.pumpWidget(
          createWidgetUnderTest(SmartViewType.today, overrideDate: today),
        );
        await tester.pumpAndSettle();

        expect(find.text('Grocery Shopping'), findsOneWidget);

        // Tap checkbox to complete task
        await tester.tap(
          find.byKey(const Key('taskCompleteCheckbox_t-toggle')),
        );
        await tester.pumpAndSettle();

        // Because show completed is off by default, completed task disappears
        expect(find.text('Grocery Shopping'), findsNothing);
        expect(find.byKey(const Key('noTasksText')), findsOneWidget);

        // Tap "Show completed" toggle
        await tester.tap(find.byKey(const Key('toggleShowCompleted_today')));
        await tester.pumpAndSettle();

        // Now visible
        expect(find.text('Grocery Shopping'), findsOneWidget);
      },
    );

    testWidgets('delete task soft-deletes with undo SnackBar', (tester) async {
      final today = DateTime(2026, 10, 14, 10, 0);

      await fakeFirestore.collection('tasks').doc('t-del').set({
        'taskId': 't-del',
        'uid': uid,
        'listId': defaultListId,
        'title': 'Task to delete',
        'dueDate': Timestamp.fromDate(DateTime(2026, 10, 14)),
        'deletedAt': null,
        'completedAt': null,
      });

      await tester.pumpWidget(
        createWidgetUnderTest(SmartViewType.today, overrideDate: today),
      );
      await tester.pumpAndSettle();

      expect(find.text('Task to delete'), findsOneWidget);

      // Tap delete button
      await tester.tap(find.byKey(const Key('deleteTaskButton_t-del')));
      await tester.pumpAndSettle();

      // Task is removed and SnackBar with Undo is shown
      expect(find.text('Task to delete'), findsNothing);
      expect(find.text('Deleted "Task to delete"'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      // Tap Undo
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Task is restored
      expect(find.text('Task to delete'), findsOneWidget);
    });

    testWidgets('FAB opens TaskDialog with initial dueDate pre-populated', (
      tester,
    ) async {
      final today = DateTime(2026, 10, 14, 10, 0);

      await tester.pumpWidget(
        createWidgetUnderTest(SmartViewType.today, overrideDate: today),
      );
      await tester.pumpAndSettle();

      // Tap FAB
      await tester.tap(find.byKey(const Key('addSmartViewTaskButton')));
      await tester.pumpAndSettle();

      // TaskDialog is open
      expect(find.text('New Task'), findsOneWidget);
      expect(find.text('2026-10-14'), findsOneWidget);
    });

    testWidgets('renders friendly timeout message when stream times out', (
      tester,
    ) async {
      final controller = StreamController<List<Task>>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(uid),
            firebaseAuthProvider.overrideWithValue(mockAuth),
            firestoreProvider.overrideWithValue(fakeFirestore),
            smartViewTimeoutProvider.overrideWithValue(
              const Duration(milliseconds: 50),
            ),
            smartViewTasksProvider.overrideWith(
              (ref, viewType) => controller.stream.timeoutFirstEvent(
                ref.watch(smartViewTimeoutProvider),
                message: 'This is taking longer than expected — check your connection or try again',
              ),
            ),
          ],
          child: const MaterialApp(
            home: SmartViewDetailScreen(viewType: SmartViewType.today),
          ),
        ),
      );

      expect(
        find.byKey(const Key('smartViewLoadingIndicator')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(
        find.text(
          'This is taking longer than expected — check your connection or try again',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('smartViewErrorText')), findsOneWidget);
    });

    testWidgets(
      'QuickAddBar is disabled without crashing while lists are still resolving',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              firebaseAuthProvider.overrideWithValue(mockAuth),
              firestoreProvider.overrideWithValue(fakeFirestore),
              currentUidProvider.overrideWithValue(uid),
              listsForUserProvider.overrideWith(
                (ref) => const Stream<List<ListModel>>.empty(),
              ),
              defaultListIdProvider.overrideWith(
                (ref) => const Stream<String?>.empty(),
              ),
            ],
            child: const MaterialApp(
              home: SmartViewDetailScreen(viewType: SmartViewType.thisWeek),
            ),
          ),
        );
        await tester.pump();

        // Verify loading hint text
        expect(find.text('Loading...'), findsOneWidget);

        // Verify textfield is disabled
        final textField = tester.widget<TextField>(
          find.byKey(const Key('quickAddTextInput')),
        );
        expect(textField.enabled, isFalse);

        // Verify submit button is disabled
        final submitButton = tester.widget<IconButton>(
          find.byKey(const Key('quickAddSubmitButton')),
        );
        expect(submitButton.onPressed, isNull);

        // Verify expand button is disabled
        final expandButton = tester.widget<IconButton>(
          find.byKey(const Key('addSmartViewTaskButton')),
        );
        expect(expandButton.onPressed, isNull);
      },
    );

    testWidgets(
      'hint text reflects destination list name on smart view screens',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest(SmartViewType.thisWeek));
        await tester.pumpAndSettle();

        expect(find.text('Add task to Inbox...'), findsOneWidget);
      },
    );

    testWidgets(
      'creating date-less task from SmartViewDetailScreen shows SnackBar with working View action',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest(SmartViewType.thisWeek));
        await tester.pumpAndSettle();

        // Enter date-less task title
        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'Buy groceries',
        );
        await tester.pumpAndSettle();

        // First tap -> parse
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        // Second tap -> create
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        // Verify SnackBar appeared with "Added to Inbox" and "View" action
        expect(find.text('Added to Inbox'), findsOneWidget);
        expect(find.text('View'), findsOneWidget);

        // Tap "View" action
        await tester.tap(find.text('View'));
        await tester.pumpAndSettle();

        // Should navigate to ListDetailScreen for Inbox
        expect(find.byType(ListDetailScreen), findsOneWidget);
      },
    );
  });
}
