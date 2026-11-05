import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tasks/presentation/task_list_screen.dart';

void main() {
  const uid = 'test-uid';
  const listId = 'test-list-id';
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
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

  Future<void> seedTask(String url) {
    return fakeFirestore.collection('tasks').doc('t1').set({
      'taskId': 't1',
      'uid': uid,
      'listId': listId,
      'title': 'Task',
      'notes': '',
      'url': url,
      'priority': 'none',
      'tagIds': <String>[],
      'dueDate': null,
      'dueTime': null,
      'earlyReminderMinutes': 0,
      'repeatRule': 'none',
      'repeatCustomConfig': null,
      'order': 0,
      'subtasks': <Map<String, dynamic>>[],
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'completedAt': null,
      'deletedAt': null,
    });
  }

  Future<void> openEditDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(
            MockFirebaseAuth(
              mockUser: MockUser(uid: uid, email: 'test@example.com'),
              signedIn: true,
            ),
          ),
          firestoreProvider.overrideWithValue(fakeFirestore),
        ],
        child: const MaterialApp(
          home: Scaffold(body: TaskListScreen(listId: null)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('taskItem_t1')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  testWidgets('an unsafe URL blocks saving', (tester) async {
    await seedTask('');
    await openEditDialog(tester);

    await tester.enterText(
      find.byKey(const Key('editTaskUrlInput')),
      'javascript:alert(1)',
    );
    await tester.tap(find.byKey(const Key('saveTaskButton')));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a valid web link (http or https).'),
      findsOneWidget,
    );
    expect(find.text('Edit Task'), findsOneWidget);
  });

  testWidgets('a bare domain is accepted', (tester) async {
    await seedTask('');
    await openEditDialog(tester);

    await tester.enterText(
      find.byKey(const Key('editTaskUrlInput')),
      'example.com',
    );
    await tester.tap(find.byKey(const Key('saveTaskButton')));
    await tester.pumpAndSettle();

    expect(find.text('Edit Task'), findsNothing);
  });

  testWidgets('fields stop at the lengths the rules allow', (tester) async {
    await seedTask('');
    await openEditDialog(tester);

    Future<String> typed(String key, int n) async {
      await tester.enterText(find.byKey(Key(key)), 'a' * n);
      await tester.pump();
      return tester
          .widget<TextFormField>(find.byKey(Key(key)))
          .controller!
          .text;
    }

    expect((await typed('editTaskTitleInput', 600)).length, 500);
    expect((await typed('editTaskNotesInput', 10100)).length, 10000);
    expect((await typed('editTaskUrlInput', 2100)).length, 2048);
  });
}
