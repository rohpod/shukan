import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/presentation/home_screen.dart';

void main() {
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
      child: const MaterialApp(
        home: HomeScreen(),
      ),
    );
  }

  group('ListsDrawer and List Switching Widget Tests', () {
    testWidgets(
        'opens drawer, shows lists, ensures default list has no delete button and custom list has delete button',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Open drawer using the scaffold drawer icon / gesture
      final scaffoldFinder = find.byType(Scaffold);
      expect(scaffoldFinder, findsOneWidget);
      final scaffoldState = tester.state<ScaffoldState>(scaffoldFinder);
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Verify lists drawer is shown
      expect(find.byKey(const Key('listsDrawer')), findsOneWidget);
      expect(find.byKey(Key('listName_$defaultListId')), findsOneWidget);
      expect(find.byKey(Key('listName_$customListId')), findsOneWidget);
      expect(find.text('DEFAULT'), findsOneWidget);

      // Layer 3 Defence-in-depth: Default list has NO delete button
      expect(
        find.byKey(Key('deleteListButton_$defaultListId')),
        findsNothing,
      );

      // Custom list HAS a delete button
      expect(
        find.byKey(Key('deleteListButton_$customListId')),
        findsOneWidget,
      );
    });

    testWidgets(
        'delete list shows confirmation dialog with active task count warning and deletes list on confirm',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
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
      final listDoc =
          await fakeFirestore.collection('lists').doc(customListId).get();
      expect(listDoc.exists, isFalse);

      // Verify tasks soft-deleted
      final t1 = await fakeFirestore.collection('tasks').doc('t1').get();
      expect(t1.data()!['deletedAt'], isNotNull);

      // Re-open drawer to check it disappeared
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsNothing);
    });

    testWidgets('create list dialog creates new list and selects it',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Tap add list button
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

      // AppBar active list name should now reflect 'Groceries'
      expect(find.text('Groceries'), findsWidgets);
    });

    testWidgets('rename list dialog updates list name', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
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
      final listDoc =
          await fakeFirestore.collection('lists').doc(defaultListId).get();
      expect(listDoc.data()!['name'], equals('Primary Inbox'));
      expect(listDoc.data()!['isDefault'], isTrue);
    });

    testWidgets('tapping a list switches active list and shows its tasks',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Initially on default list (no tasks)
      expect(find.byKey(const Key('noTasksText')), findsOneWidget);

      // Open drawer and tap 'Work' list
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('listTile_$customListId')));
      await tester.pumpAndSettle();

      // Drawer closed, TaskListScreen now displays 'Work' list tasks
      expect(find.text('Task 1'), findsOneWidget);
      expect(find.text('Task 2'), findsOneWidget);
      expect(find.byKey(const Key('noTasksText')), findsNothing);
    });
  });
}
