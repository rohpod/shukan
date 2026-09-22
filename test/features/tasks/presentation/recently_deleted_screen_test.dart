import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tasks/presentation/recently_deleted_screen.dart';
import 'package:shukan/features/tasks/providers/task_providers.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  const uid = 'test-uid';
  const defaultListId = 'inbox-123';

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
      'defaultListId': defaultListId,
    });
    await fakeFirestore.collection('lists').doc(defaultListId).set({
      'listId': defaultListId,
      'uid': uid,
      'name': 'Inbox',
      'isDefault': true,
    });
  });

  Widget createWidgetUnderTest() {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
      ],
      child: const MaterialApp(home: RecentlyDeletedScreen()),
    );
  }

  group('RecentlyDeletedScreen Widget Tests', () {
    testWidgets('shows empty state when no recently deleted tasks exist', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('noRecentlyDeletedTasksText')),
        findsOneWidget,
      );
      expect(find.text('No recently deleted tasks'), findsOneWidget);
      expect(find.byKey(const Key('emptyRecentlyDeletedButton')), findsNothing);
    });

    testWidgets('renders list of soft-deleted tasks', (tester) async {
      final deleteTime = DateTime.now().subtract(const Duration(days: 2));
      await fakeFirestore.collection('tasks').doc('del-task-1').set({
        'taskId': 'del-task-1',
        'uid': uid,
        'listId': defaultListId,
        'title': 'Deleted Meeting',
        'notes': 'Some notes here',
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
        'deletedAt': Timestamp.fromDate(deleteTime),
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('deletedTaskItem_del-task-1')),
        findsOneWidget,
      );
      expect(find.text('Deleted Meeting'), findsOneWidget);
      expect(find.text('Some notes here'), findsOneWidget);
      expect(
        find.byKey(const Key('restoreTaskButton_del-task-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('permanentDeleteTaskButton_del-task-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('emptyRecentlyDeletedButton')),
        findsOneWidget,
      );
    });

    testWidgets('tapping restore button restores task and shows SnackBar', (
      tester,
    ) async {
      await fakeFirestore.collection('tasks').doc('del-task-restore').set({
        'taskId': 'del-task-restore',
        'uid': uid,
        'listId': defaultListId,
        'title': 'Task to restore',
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
        'deletedAt': Timestamp.now(),
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Task to restore'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('restoreTaskButton_del-task-restore')),
      );
      await tester.pumpAndSettle();

      // Task is removed from Recently Deleted view and SnackBar is shown
      expect(find.text('Task to restore'), findsNothing);
      expect(find.text('Restored "Task to restore"'), findsOneWidget);

      // Verify Firestore deletedAt is null
      final doc = await fakeFirestore
          .collection('tasks')
          .doc('del-task-restore')
          .get();
      expect(doc.data()!['deletedAt'], isNull);
    });

    testWidgets(
      'tapping permanent delete shows dialog, cancel aborts, confirm deletes permanently',
      (tester) async {
        await fakeFirestore.collection('tasks').doc('del-task-perm').set({
          'taskId': 'del-task-perm',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Permanent target',
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
          'deletedAt': Timestamp.now(),
        });

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // Tap permanent delete icon
        await tester.tap(
          find.byKey(const Key('permanentDeleteTaskButton_del-task-perm')),
        );
        await tester.pumpAndSettle();

        // Dialog is open
        expect(find.text('Permanently delete task?'), findsOneWidget);
        expect(
          find.byKey(const Key('cancelPermanentDeleteButton')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('confirmPermanentDeleteButton')),
          findsOneWidget,
        );

        // Tap cancel
        await tester.tap(find.byKey(const Key('cancelPermanentDeleteButton')));
        await tester.pumpAndSettle();

        // Task still in list and in Firestore
        expect(find.text('Permanent target'), findsOneWidget);
        var doc = await fakeFirestore
            .collection('tasks')
            .doc('del-task-perm')
            .get();
        expect(doc.exists, isTrue);

        // Tap permanent delete icon again and confirm
        await tester.tap(
          find.byKey(const Key('permanentDeleteTaskButton_del-task-perm')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('confirmPermanentDeleteButton')));
        await tester.pumpAndSettle();

        // Task is gone from UI and Firestore
        expect(find.text('Permanent target'), findsNothing);
        doc = await fakeFirestore
            .collection('tasks')
            .doc('del-task-perm')
            .get();
        expect(doc.exists, isFalse);
      },
    );

    testWidgets(
      'tapping empty trash shows confirmation dialog and empties all tasks on confirm',
      (tester) async {
        await fakeFirestore.collection('tasks').doc('del-1').set({
          'taskId': 'del-1',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Del 1',
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
          'deletedAt': Timestamp.now(),
        });
        await fakeFirestore.collection('tasks').doc('del-2').set({
          'taskId': 'del-2',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Del 2',
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
          'deletedAt': Timestamp.now(),
        });

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        expect(find.text('Del 1'), findsOneWidget);
        expect(find.text('Del 2'), findsOneWidget);

        // Tap empty trash in AppBar
        await tester.tap(find.byKey(const Key('emptyRecentlyDeletedButton')));
        await tester.pumpAndSettle();

        // Dialog opens
        expect(find.text('Empty Recently Deleted?'), findsOneWidget);
        expect(find.byKey(const Key('cancelEmptyTrashButton')), findsOneWidget);
        expect(
          find.byKey(const Key('confirmEmptyTrashButton')),
          findsOneWidget,
        );

        // Confirm empty trash
        await tester.tap(find.byKey(const Key('confirmEmptyTrashButton')));
        await tester.pumpAndSettle();

        // UI shows empty state
        expect(find.text('Del 1'), findsNothing);
        expect(find.text('Del 2'), findsNothing);
        expect(
          find.byKey(const Key('noRecentlyDeletedTasksText')),
          findsOneWidget,
        );

        // Verify Firestore docs are deleted
        final doc1 = await fakeFirestore.collection('tasks').doc('del-1').get();
        final doc2 = await fakeFirestore.collection('tasks').doc('del-2').get();
        expect(doc1.exists, isFalse);
        expect(doc2.exists, isFalse);
      },
    );

    testWidgets('shows RefreshIndicator on empty state', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('shows RefreshIndicator on populated state', (tester) async {
      await fakeFirestore.collection('tasks').doc('del-refresh').set({
        'taskId': 'del-refresh',
        'uid': uid,
        'listId': defaultListId,
        'title': 'To Refresh',
        'deletedAt': Timestamp.now(),
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('shows error state with retry button when stream fails', (
      tester,
    ) async {
      var callCount = 0;
      final errorOverride = recentlyDeletedTasksProvider.overrideWith((ref) {
        callCount++;
        return Stream.error(Exception('Network timeout'));
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(mockAuth),
            firestoreProvider.overrideWithValue(fakeFirestore),
            errorOverride,
          ],
          child: const MaterialApp(home: RecentlyDeletedScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Network timeout'), findsOneWidget);
      final retryButton = find.byKey(const Key('retryRecentlyDeletedButton'));
      expect(retryButton, findsOneWidget);

      await tester.tap(retryButton);
      await tester.pump();

      expect(callCount, greaterThanOrEqualTo(2));
    });

    testWidgets('displays list origin name in task subtitle when available', (
      tester,
    ) async {
      await fakeFirestore.collection('lists').doc('custom-list-99').set({
        'listId': 'custom-list-99',
        'uid': uid,
        'name': 'Marketing Campaign',
        'isDefault': false,
      });

      await fakeFirestore.collection('tasks').doc('task-with-list').set({
        'taskId': 'task-with-list',
        'uid': uid,
        'listId': 'custom-list-99',
        'title': 'Q4 Strategy Doc',
        'deletedAt': Timestamp.now(),
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Q4 Strategy Doc'), findsOneWidget);
      expect(find.textContaining('List: Marketing Campaign'), findsOneWidget);
    });

    testWidgets(
      'automatically purges tasks older than 30 days on screen init',
      (tester) async {
        final expiredDate = DateTime.now().subtract(const Duration(days: 35));
        await fakeFirestore.collection('tasks').doc('task-auto-purge').set({
          'taskId': 'task-auto-purge',
          'uid': uid,
          'listId': defaultListId,
          'title': 'Old Deleted Task',
          'deletedAt': Timestamp.fromDate(expiredDate),
        });

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        final doc = await fakeFirestore
            .collection('tasks')
            .doc('task-auto-purge')
            .get();
        expect(doc.exists, isFalse);
      },
    );
  });
}
