import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tasks/presentation/task_list_screen.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  const uid = 'test-uid';
  const listId = 'test-list-id';

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
      'defaultListId': listId,
    });
    await fakeFirestore.collection('lists').doc(listId).set({
      'listId': listId,
      'uid': uid,
      'name': 'Inbox',
      'isDefault': true,
    });
  });

  Widget createWidgetUnderTest({String? customListId}) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: TaskListScreen(listId: customListId),
        ),
      ),
    );
  }

  group('TaskListScreen Widget Tests', () {
    testWidgets('shows empty state when no tasks exist', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('noTasksText')), findsOneWidget);
      expect(find.text('No tasks yet'), findsOneWidget);
      expect(find.byKey(const Key('taskTitleInput')), findsOneWidget);
      expect(find.byKey(const Key('addTaskButton')), findsOneWidget);
    });

    testWidgets('creates a task, toggles complete, edits, and soft-deletes it',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // 1. Enter task details and add task
      await tester.enterText(
        find.byKey(const Key('taskTitleInput')),
        'Buy milk',
      );
      await tester.enterText(
        find.byKey(const Key('taskNotesInput')),
        '2% organic milk',
      );
      await tester.enterText(
        find.byKey(const Key('taskUrlInput')),
        'https://example.com/store',
      );
      await tester.tap(find.byKey(const Key('addTaskButton')));
      await tester.pumpAndSettle();

      // Verify task appears in the list
      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('2% organic milk'), findsOneWidget);
      expect(find.text('https://example.com/store'), findsOneWidget);
      expect(find.byKey(const Key('noTasksText')), findsNothing);

      // Verify Firestore document exists
      final tasksSnapshot = await fakeFirestore
          .collection('tasks')
          .where('uid', isEqualTo: uid)
          .get();
      expect(tasksSnapshot.docs.length, equals(1));
      final taskId = tasksSnapshot.docs.first.id;

      // 2. Toggle complete
      final checkboxFinder =
          find.byKey(Key('taskCompleteCheckbox_$taskId'));
      expect(checkboxFinder, findsOneWidget);
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      var doc = await fakeFirestore.collection('tasks').doc(taskId).get();
      expect(doc.data()!['completedAt'], isNotNull);

      // 3. Edit task
      await tester.tap(find.byKey(Key('editTaskButton_$taskId')));
      await tester.pumpAndSettle();

      expect(find.text('Edit Task'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('editTaskTitleInput')),
        'Buy oat milk',
      );
      await tester.enterText(
        find.byKey(const Key('editTaskNotesInput')),
        'Barista edition',
      );
      await tester.tap(find.byKey(const Key('saveTaskButton')));
      await tester.pumpAndSettle();

      // Verify updated task in UI and Firestore
      expect(find.text('Buy oat milk'), findsOneWidget);
      expect(find.text('Barista edition'), findsOneWidget);
      doc = await fakeFirestore.collection('tasks').doc(taskId).get();
      expect(doc.data()!['title'], equals('Buy oat milk'));
      expect(doc.data()!['notes'], equals('Barista edition'));

      // 4. Soft delete task
      await tester.tap(find.byKey(Key('deleteTaskButton_$taskId')));
      await tester.pumpAndSettle();

      // Task is removed from UI and shows empty state
      expect(find.text('Buy oat milk'), findsNothing);
      expect(find.byKey(const Key('noTasksText')), findsOneWidget);

      // Verify document still exists in Firestore but with deletedAt set
      doc = await fakeFirestore.collection('tasks').doc(taskId).get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['deletedAt'], isNotNull);
    });
  });
}
