import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/presentation/home_screen.dart';
import 'package:shukan/features/tasks/presentation/recently_deleted_screen.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  const uid = 'test-uid';
  const inboxListId = 'inbox-1';

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
      'defaultListId': inboxListId,
    });
    await fakeFirestore.collection('lists').doc(inboxListId).set({
      'listId': inboxListId,
      'uid': uid,
      'name': 'Inbox',
      'isDefault': true,
      'createdAt': DateTime.now(),
    });
  });

  testWidgets(
    'full flow: create task in list, delete it, open recently deleted, verify task is displayed and can be restored',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(mockAuth),
            firestoreProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Open Inbox list
      expect(find.text('Inbox'), findsOneWidget);
      await tester.tap(find.byKey(const Key('listCard_$inboxListId')));
      await tester.pumpAndSettle();

      // 2. Add a new task
      await tester.tap(find.byKey(const Key('addTaskButton')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('taskTitleInput')),
        'Flow Task',
      );
      await tester.tap(find.byKey(const Key('saveTaskButton')));
      await tester.pumpAndSettle();

      expect(find.text('Flow Task'), findsOneWidget);

      // 3. Delete the task
      final deleteButtons = find.byTooltip('Delete');
      expect(deleteButtons, findsOneWidget);
      await tester.tap(deleteButtons);
      await tester.pumpAndSettle();

      // Task is gone from active list
      expect(find.text('Flow Task'), findsNothing);
      expect(find.text('Deleted "Flow Task"'), findsOneWidget);

      // 4. Tap Recently Deleted button in AppBar
      final recentlyDeletedButton = find.byKey(
        const Key('recentlyDeletedButton'),
      );
      expect(recentlyDeletedButton, findsOneWidget);
      await tester.tap(recentlyDeletedButton);
      await tester.pumpAndSettle();

      // 5. Verify RecentlyDeletedScreen is open and task is shown!
      expect(find.byType(RecentlyDeletedScreen), findsOneWidget);
      expect(find.text('Flow Task'), findsOneWidget);
      expect(find.byTooltip('Restore'), findsOneWidget);

      // 6. Tap Restore
      await tester.tap(find.byTooltip('Restore'));
      await tester.pumpAndSettle();

      // Task is restored and removed from Recently Deleted
      expect(find.text('Flow Task'), findsNothing);
      expect(find.text('Restored "Flow Task"'), findsOneWidget);

      // 7. Go back to list
      Navigator.of(tester.element(find.byType(RecentlyDeletedScreen))).pop();
      await tester.pumpAndSettle();

      // Verify task is back in the active list!
      expect(find.text('Flow Task'), findsOneWidget);
    },
  );
}
