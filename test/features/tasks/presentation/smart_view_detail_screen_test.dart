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

        // Show completed toggle button should NOT be visible
        expect(
          find.byKey(const Key('toggleShowCompleted_today')),
          findsNothing,
        );

        // Task is rendered
        expect(find.text('Pay Electricity Bill'), findsOneWidget);
        // Old priority chip no longer renders
        expect(find.text('HIGH'), findsNothing);
        // New priority marker renders
        expect(
          find.byKey(const Key('taskPriorityMarker_t-today-1')),
          findsOneWidget,
        );
        expect(find.text('❗❗❗'), findsOneWidget);
        final titleWidget = tester.widget<Text>(
          find.byKey(const Key('taskTitle_t-today-1')),
        );
        expect(titleWidget.data, equals('Pay Electricity Bill'));
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

        // Completed tasks are permanently hidden in smart views
        expect(find.text('Grocery Shopping'), findsNothing);
        expect(find.byKey(const Key('noTasksText')), findsOneWidget);
        expect(
          find.byKey(const Key('toggleShowCompleted_today')),
          findsNothing,
        );
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

    testWidgets('delete task undo SnackBar auto-dismisses after 5 seconds', (
      tester,
    ) async {
      final today = DateTime(2026, 10, 14, 10, 0);

      await fakeFirestore.collection('tasks').doc('t-del-timeout').set({
        'taskId': 't-del-timeout',
        'uid': uid,
        'listId': defaultListId,
        'title': 'Task to delete timeout',
        'dueDate': Timestamp.fromDate(DateTime(2026, 10, 14)),
        'deletedAt': null,
        'completedAt': null,
      });

      await tester.pumpWidget(
        createWidgetUnderTest(SmartViewType.today, overrideDate: today),
      );
      await tester.pumpAndSettle();

      expect(find.text('Task to delete timeout'), findsOneWidget);

      // Tap delete button
      await tester.tap(find.byKey(const Key('deleteTaskButton_t-del-timeout')));
      await tester.pumpAndSettle();

      // Verify task removed and SnackBar with Undo is shown
      expect(find.text('Task to delete timeout'), findsNothing);
      expect(find.text('Deleted "Task to delete timeout"'), findsOneWidget);
      expect(find.byKey(const Key('undoDeleteTaskButton')), findsOneWidget);

      // Advance 5 seconds and settle
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Verify SnackBar is dismissed
      expect(find.text('Deleted "Task to delete timeout"'), findsNothing);
    });

    testWidgets(
      'Empty state Add task button opens TaskDialog with initial dueDate pre-populated',
      (tester) async {
        final today = DateTime(2026, 10, 14, 10, 0);

        await tester.pumpWidget(
          createWidgetUnderTest(SmartViewType.today, overrideDate: today),
        );
        await tester.pumpAndSettle();

        // Tap Add task button in empty state
        await tester.tap(find.byKey(const Key('emptyStateAddTaskButton')));
        await tester.pumpAndSettle();

        // TaskDialog is open
        expect(find.text('New Task'), findsOneWidget);
        expect(find.text('2026-10-14'), findsOneWidget);
      },
    );

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

        // Tap submit -> creates task immediately on first submit
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

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

    testWidgets(
      'tapping a task row opens TaskDialog in edit mode on SmartViewDetailScreen',
      (tester) async {
        final today = DateTime(2026, 10, 14, 10, 0);
        await fakeFirestore.collection('tasks').doc('smart-edit-1').set({
          'taskId': 'smart-edit-1',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Test Smart Task',
          'notes': 'Smart notes',
          'url': '',
          'priority': 'none',
          'tagIds': <String>[],
          'order': 1000.0,
          'createdAt': Timestamp.now(),
          'dueDate': Timestamp.fromDate(today),
          'dueTime': null,
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(
          createWidgetUnderTest(SmartViewType.today, overrideDate: today),
        );
        await tester.pumpAndSettle();

        expect(find.text('Test Smart Task'), findsOneWidget);

        // Tap task row
        await tester.tap(find.text('Test Smart Task'));
        await tester.pumpAndSettle();

        expect(find.text('Edit Task'), findsOneWidget);
        expect(find.text('Smart notes'), findsOneWidget);
      },
    );

    testWidgets(
      'renders priority markers correctly for none, low, medium, and high on SmartViewDetailScreen',
      (tester) async {
        final today = DateTime(2026, 10, 14, 10, 0);

        await fakeFirestore.collection('tasks').doc('smart-p-high').set({
          'taskId': 'smart-p-high',
          'uid': uid,
          'listId': defaultListId,
          'title': 'High Smart Task',
          'priority': 'high',
          'createdAt': Timestamp.now(),
          'dueDate': Timestamp.fromDate(today),
          'completedAt': null,
          'deletedAt': null,
        });

        await fakeFirestore.collection('tasks').doc('smart-p-med').set({
          'taskId': 'smart-p-med',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Medium Smart Task',
          'priority': 'medium',
          'createdAt': Timestamp.now(),
          'dueDate': Timestamp.fromDate(today),
          'completedAt': null,
          'deletedAt': null,
        });

        await fakeFirestore.collection('tasks').doc('smart-p-low').set({
          'taskId': 'smart-p-low',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Low Smart Task',
          'priority': 'low',
          'createdAt': Timestamp.now(),
          'dueDate': Timestamp.fromDate(today),
          'completedAt': null,
          'deletedAt': null,
        });

        await fakeFirestore.collection('tasks').doc('smart-p-none').set({
          'taskId': 'smart-p-none',
          'uid': uid,
          'listId': defaultListId,
          'title': 'None Smart Task',
          'priority': 'none',
          'createdAt': Timestamp.now(),
          'dueDate': Timestamp.fromDate(today),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(
          createWidgetUnderTest(SmartViewType.today, overrideDate: today),
        );
        await tester.pumpAndSettle();

        // High priority
        expect(
          find.byKey(const Key('taskPriorityMarker_smart-p-high')),
          findsOneWidget,
        );
        expect(find.text('❗❗❗'), findsOneWidget);
        final highTitle = tester.widget<Text>(
          find.byKey(const Key('taskTitle_smart-p-high')),
        );
        expect(highTitle.data, equals('High Smart Task'));

        // Medium priority
        expect(
          find.byKey(const Key('taskPriorityMarker_smart-p-med')),
          findsOneWidget,
        );
        expect(find.text('❕❕'), findsOneWidget);
        final medTitle = tester.widget<Text>(
          find.byKey(const Key('taskTitle_smart-p-med')),
        );
        expect(medTitle.data, equals('Medium Smart Task'));

        // Low priority
        expect(
          find.byKey(const Key('taskPriorityMarker_smart-p-low')),
          findsOneWidget,
        );
        expect(find.text('!'), findsOneWidget);
        final lowTitle = tester.widget<Text>(
          find.byKey(const Key('taskTitle_smart-p-low')),
        );
        expect(lowTitle.data, equals('Low Smart Task'));

        // None priority
        expect(
          find.byKey(const Key('taskPriorityMarker_smart-p-none')),
          findsNothing,
        );
        final noneTitle = tester.widget<Text>(
          find.byKey(const Key('taskTitle_smart-p-none')),
        );
        expect(noneTitle.data, equals('None Smart Task'));

        // Confirm old chips do not render
        expect(find.text('HIGH'), findsNothing);
        expect(find.text('MEDIUM'), findsNothing);
        expect(find.text('LOW'), findsNothing);
      },
    );
  });
}
