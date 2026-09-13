import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/lists/data/list.dart';
import 'package:shukan/features/lists/presentation/list_detail_screen.dart';
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

    // Seed list and a task
    await fakeFirestore.collection('lists').doc(listId).set({
      'listId': listId,
      'uid': uid,
      'name': 'Work Projects',
      'isDefault': false,
    });

    await fakeFirestore.collection('tasks').doc('t1').set({
      'taskId': 't1',
      'uid': uid,
      'listId': listId,
      'title': 'Deploy project',
      'deletedAt': null,
    });
  });

  testWidgets('ListDetailScreen renders AppBar with list title and embeds TaskListScreen',
      (tester) async {
    final list = ListModel(
      listId: listId,
      uid: uid,
      name: 'Work Projects',
      isDefault: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          firestoreProvider.overrideWithValue(fakeFirestore),
        ],
        child: MaterialApp(
          home: ListDetailScreen(list: list),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify AppBar title
    expect(find.byKey(const Key('listDetailTitle')), findsOneWidget);
    expect(find.text('Work Projects'), findsOneWidget);

    // Verify TaskListScreen is mounted with task content
    expect(find.byType(TaskListScreen), findsOneWidget);
    expect(find.text('Deploy project'), findsOneWidget);
    expect(find.byKey(const Key('taskTitleInput')), findsOneWidget);
  });
}
