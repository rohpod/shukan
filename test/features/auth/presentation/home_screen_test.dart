import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/presentation/home_screen.dart';
import 'package:shukan/features/lists/presentation/list_detail_screen.dart';
import 'package:shukan/features/tags/presentation/tag_browser_screen.dart';
import 'package:shukan/features/tasks/presentation/recently_deleted_screen.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  const uid = 'test-user-id';
  const defaultListId = 'inbox-id';
  const customListId = 'custom-id';

  setUp(() async {
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'test@example.com'),
      signedIn: true,
    );
    fakeFirestore = FakeFirebaseFirestore();

    // Bootstrap user and default list
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

    await fakeFirestore.collection('lists').doc(customListId).set({
      'listId': customListId,
      'uid': uid,
      'name': 'Work',
      'isDefault': false,
    });

    // Add tasks to custom list
    await fakeFirestore.collection('tasks').doc('t1').set({
      'taskId': 't1',
      'uid': uid,
      'listId': customListId,
      'title': 'Task 1',
      'deletedAt': null,
    });
    await fakeFirestore.collection('tasks').doc('t2').set({
      'taskId': 't2',
      'uid': uid,
      'listId': customListId,
      'title': 'Task 2',
      'deletedAt': null,
    });
  });

  Widget createWidgetUnderTest() {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  group('HomeScreen Lists Grid Tests', () {
    testWidgets(
      'shows lists in grid, ensures default list has no delete button and custom list has delete button',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        expect(find.text('shukan'), findsOneWidget);
        expect(find.byKey(const Key('searchButton')), findsOneWidget);
        expect(find.byKey(const Key('logoutButton')), findsOneWidget);
        expect(find.byKey(const Key('addListButton')), findsOneWidget);

        // Verify lists are rendered
        expect(find.byKey(Key('listName_$defaultListId')), findsOneWidget);
        expect(find.byKey(Key('listName_$customListId')), findsOneWidget);
        expect(find.text('DEFAULT'), findsOneWidget);

        // Default list has NO delete button
        expect(
          find.byKey(Key('deleteListButton_$defaultListId')),
          findsNothing,
        );

        // Custom list HAS a delete button
        expect(
          find.byKey(Key('deleteListButton_$customListId')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'delete list shows confirmation dialog with active task count warning and deletes list on confirm',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // Tap delete on custom list
        await tester.tap(find.byKey(Key('deleteListButton_$customListId')));
        await tester.pumpAndSettle();

        // Verify confirmation dialog and active task warning
        expect(find.text('Delete "Work"?'), findsOneWidget);
        expect(
          find.text('2 task(s) in this list will also be removed.'),
          findsOneWidget,
        );

        // Tap confirm delete
        await tester.tap(find.byKey(const Key('confirmDeleteListButton')));
        await tester.pumpAndSettle();

        // Verify custom list is deleted in Firestore
        final listDoc = await fakeFirestore
            .collection('lists')
            .doc(customListId)
            .get();
        expect(listDoc.exists, isFalse);

        // Verify tasks soft-deleted
        final t1 = await fakeFirestore.collection('tasks').doc('t1').get();
        expect(t1.data()!['deletedAt'], isNotNull);

        // List should disappear from home screen
        expect(find.byKey(Key('listName_$customListId')), findsNothing);
      },
    );

    testWidgets('create list dialog creates new list and shows it in grid', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap FAB
      await tester.tap(find.byKey(const Key('addListButton')));
      await tester.pumpAndSettle();

      expect(find.text('Create New List'), findsOneWidget);

      // Enter list name
      await tester.enterText(
        find.byKey(const Key('createListNameInput')),
        'Groceries',
      );
      await tester.tap(find.byKey(const Key('confirmCreateListButton')));
      await tester.pumpAndSettle();

      // Verify list exists in Firestore
      final lists = await fakeFirestore
          .collection('lists')
          .where('name', isEqualTo: 'Groceries')
          .get();
      expect(lists.docs.length, equals(1));
      expect(lists.docs.first.data()['isDefault'], isFalse);

      // Home screen grid should now display 'Groceries'
      expect(find.text('Groceries'), findsOneWidget);
    });

    testWidgets('rename list dialog updates list name', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap rename on default list
      await tester.tap(find.byKey(Key('renameListButton_$defaultListId')));
      await tester.pumpAndSettle();

      expect(find.text('Rename List'), findsOneWidget);

      // Enter new name
      await tester.enterText(
        find.byKey(const Key('renameListInput')),
        'Primary Inbox',
      );
      await tester.tap(find.byKey(const Key('confirmRenameListButton')));
      await tester.pumpAndSettle();

      // Verify renamed in Firestore
      final listDoc = await fakeFirestore
          .collection('lists')
          .doc(defaultListId)
          .get();
      expect(listDoc.data()!['name'], equals('Primary Inbox'));
      expect(listDoc.data()!['isDefault'], isTrue);

      expect(find.text('Primary Inbox'), findsOneWidget);
    });

    testWidgets('tapping a list navigates to ListDetailScreen and back', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap on the 'Work' list card
      await tester.tap(find.byKey(Key('listCard_$customListId')));
      await tester.pumpAndSettle();

      // Should now be on ListDetailScreen
      expect(find.byType(ListDetailScreen), findsOneWidget);
      expect(find.byKey(const Key('listDetailTitle')), findsOneWidget);
      expect(find.text('Task 1'), findsOneWidget);
      expect(find.text('Task 2'), findsOneWidget);

      // Tap back button
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // Back on HomeScreen
      expect(find.byType(ListDetailScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('tapping search button navigates to SearchScreen and back', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('searchButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('searchQueryInput')), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('searchQueryInput')), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('logout button signs user out', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('logoutButton')));
      await tester.pumpAndSettle();

      expect(mockAuth.currentUser, isNull);
    });

    testWidgets(
      'tapping recently deleted button navigates to RecentlyDeletedScreen',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('recentlyDeletedButton')), findsOneWidget);

        await tester.tap(find.byKey(const Key('recentlyDeletedButton')));
        await tester.pumpAndSettle();

        expect(find.byType(RecentlyDeletedScreen), findsOneWidget);
        expect(find.text('Recently Deleted'), findsWidgets);
      },
    );

    testWidgets('tapping tag browser button navigates to TagBrowserScreen', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tagBrowserButton')), findsOneWidget);

      await tester.tap(find.byKey(const Key('tagBrowserButton')));
      await tester.pumpAndSettle();

      expect(find.byType(TagBrowserScreen), findsOneWidget);
      expect(find.text('Tags'), findsWidgets);
    });

    testWidgets('renders active task count badge on each list card', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(Key('taskCountBadge_$defaultListId')), findsOneWidget);
      expect(find.byKey(Key('taskCountText_$defaultListId')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(Key('taskCountText_$defaultListId')))
            .data,
        '0',
      );

      expect(find.byKey(Key('taskCountBadge_$customListId')), findsOneWidget);
      expect(find.byKey(Key('taskCountText_$customListId')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(Key('taskCountText_$customListId')))
            .data,
        '2',
      );
    });

    testWidgets(
      'active task count badge updates live when tasks are added, completed, and deleted',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // Initial: Inbox has 0, Work has 2
        expect(
          tester
              .widget<Text>(find.byKey(Key('taskCountText_$defaultListId')))
              .data,
          '0',
        );
        expect(
          tester
              .widget<Text>(find.byKey(Key('taskCountText_$customListId')))
              .data,
          '2',
        );

        // 1. Add task to Inbox
        await fakeFirestore.collection('tasks').doc('t-new').set({
          'taskId': 't-new',
          'uid': uid,
          'listId': defaultListId,
          'title': 'New inbox task',
          'deletedAt': null,
          'completedAt': null,
        });
        await tester.pump();

        expect(
          tester
              .widget<Text>(find.byKey(Key('taskCountText_$defaultListId')))
              .data,
          '1',
        );

        // 2. Complete task in Work list
        await fakeFirestore.collection('tasks').doc('t1').update({
          'completedAt': Timestamp.now(),
        });
        await tester.pump();

        expect(
          tester
              .widget<Text>(find.byKey(Key('taskCountText_$customListId')))
              .data,
          '1',
        );

        // 3. Soft-delete task in Work list
        await fakeFirestore.collection('tasks').doc('t2').update({
          'deletedAt': Timestamp.now(),
        });
        await tester.pump();

        expect(
          tester
              .widget<Text>(find.byKey(Key('taskCountText_$customListId')))
              .data,
          '0',
        );
      },
    );

    testWidgets(
      'shows missed tasks banner when overdue tasks exist, and dismisses on tap',
      (tester) async {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        await fakeFirestore.collection('tasks').doc('t-overdue').set({
          'taskId': 't-overdue',
          'uid': uid,
          'listId': customListId,
          'title': 'Overdue Task',
          'dueDate': Timestamp.fromDate(yesterday),
          'deletedAt': null,
          'completedAt': null,
        });

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('missedTasksBanner')), findsOneWidget);
        expect(find.text('1 task overdue'), findsOneWidget);

        // Tap dismiss
        await tester.tap(
          find.byKey(const Key('missedTasksBannerDismissButton')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('missedTasksBanner')), findsNothing);
      },
    );
  });
}
