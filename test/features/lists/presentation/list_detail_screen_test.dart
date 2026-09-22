import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/lists/data/list.dart';
import 'package:shukan/features/lists/presentation/list_detail_screen.dart';
import 'package:shukan/features/tasks/presentation/recently_deleted_screen.dart';
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

  testWidgets(
    'ListDetailScreen renders AppBar with list title and embeds TaskListScreen',
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
          child: MaterialApp(home: ListDetailScreen(list: list)),
        ),
      );
      await tester.pumpAndSettle();

      // Verify AppBar title
      expect(find.byKey(const Key('listDetailTitle')), findsOneWidget);
      expect(find.text('Work Projects'), findsOneWidget);

      // Verify TaskListScreen is mounted with task content and add task button
      expect(find.byType(TaskListScreen), findsOneWidget);
      expect(find.text('Deploy project'), findsOneWidget);
      expect(find.byKey(const Key('addTaskButton')), findsOneWidget);
    },
  );

  testWidgets(
    'tapping export button triggers download and shows success snackbar',
    (tester) async {
      final list = ListModel(
        listId: listId,
        uid: uid,
        name: 'Work Projects',
        isDefault: false,
      );

      String? exportedContent;
      String? exportedFilename;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(mockAuth),
            firestoreProvider.overrideWithValue(fakeFirestore),
          ],
          child: MaterialApp(
            home: ListDetailScreen(
              list: list,
              downloadTrigger: (content, filename) {
                exportedContent = content;
                exportedFilename = filename;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify export button exists
      final exportButton = find.byKey(const Key('exportListButton'));
      expect(exportButton, findsOneWidget);

      // Tap export button
      await tester.tap(exportButton);
      await tester.pumpAndSettle();

      // Verify download trigger was called
      expect(exportedFilename, contains('work-projects'));
      expect(exportedContent, contains('# Work Projects'));
      expect(exportedContent, contains('- [ ] Deploy project'));

      // Verify success snackbar is displayed
      expect(find.text('Exported "Work Projects" to markdown'), findsOneWidget);
    },
  );

  testWidgets('shows failure snackbar if export throws an error', (
    tester,
  ) async {
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
          home: ListDetailScreen(
            list: list,
            downloadTrigger: (content, filename) {
              throw Exception('Disk full or download blocked');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final exportButton = find.byKey(const Key('exportListButton'));
    await tester.tap(exportButton);
    await tester.pumpAndSettle();

    // Verify error snackbar is displayed
    expect(
      find.textContaining(
        'Failed to export list: Exception: Disk full or download blocked',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'ListDetailScreen contains recentlyDeletedButton and navigates to RecentlyDeletedScreen',
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
          child: MaterialApp(home: ListDetailScreen(list: list)),
        ),
      );
      await tester.pumpAndSettle();

      final recentlyDeletedButton = find.byKey(
        const Key('recentlyDeletedButton'),
      );
      expect(recentlyDeletedButton, findsOneWidget);

      await tester.tap(recentlyDeletedButton);
      await tester.pumpAndSettle();

      expect(find.byType(RecentlyDeletedScreen), findsOneWidget);
    },
  );
}
