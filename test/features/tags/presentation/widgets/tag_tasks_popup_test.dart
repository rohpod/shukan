import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/providers/auth_providers.dart';
import 'package:shukan/features/tags/presentation/widgets/tag_tasks_popup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  const uid = 'test-uid';

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'test@example.com'),
      signedIn: true,
    );
  });

  Widget buildPopupWidget({required String tagId, String? tagName}) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentUidProvider.overrideWithValue(uid),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => TagTasksPopup(tagId: tagId, tagName: tagName),
                );
              },
              child: const Text('Open Popup'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows empty state when no active tasks carry the tag', (
    tester,
  ) async {
    await fakeFirestore.collection('tags').doc('tag-empty').set({
      'tagId': 'tag-empty',
      'uid': uid,
      'name': 'EmptyTag',
    });

    await tester.pumpWidget(
      buildPopupWidget(tagId: 'tag-empty', tagName: 'EmptyTag'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Popup'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tagTasksPopup_tag-empty')), findsOneWidget);
    expect(find.text('#EmptyTag'), findsOneWidget);
    expect(find.byKey(const Key('tagTasksPopupEmptyText')), findsOneWidget);
    expect(find.text('No active tasks with this tag'), findsOneWidget);
  });

  testWidgets(
    'groups tasks by list alphabetically, orders tasks by createdAt ascending, and never shows completed tasks',
    (tester) async {
      await fakeFirestore.collection('tags').doc('tag-urgent').set({
        'tagId': 'tag-urgent',
        'uid': uid,
        'name': 'Urgent',
      });

      // Lists: Zebra List and Alpha List
      await fakeFirestore.collection('lists').doc('list-z').set({
        'listId': 'list-z',
        'uid': uid,
        'name': 'Zebra List',
      });
      await fakeFirestore.collection('lists').doc('list-a').set({
        'listId': 'list-a',
        'uid': uid,
        'name': 'Alpha List',
      });

      final early = DateTime(2026, 1, 10);
      final late = DateTime(2026, 1, 20);

      // Tasks in Zebra List
      await fakeFirestore.collection('tasks').doc('z-late').set({
        'taskId': 'z-late',
        'uid': uid,
        'listId': 'list-z',
        'title': 'Zebra Late Task',
        'notes': 'late note',
        'tagIds': ['tag-urgent'],
        'createdAt': Timestamp.fromDate(late),
        'completedAt': null,
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('z-early').set({
        'taskId': 'z-early',
        'uid': uid,
        'listId': 'list-z',
        'title': 'Zebra Early Task',
        'notes': '',
        'tagIds': ['tag-urgent'],
        'createdAt': Timestamp.fromDate(early),
        'completedAt': null,
        'deletedAt': null,
      });

      // Task in Alpha List
      await fakeFirestore.collection('tasks').doc('a-task').set({
        'taskId': 'a-task',
        'uid': uid,
        'listId': 'list-a',
        'title': 'Alpha Task',
        'notes': '',
        'tagIds': ['tag-urgent'],
        'createdAt': Timestamp.fromDate(early),
        'completedAt': null,
        'deletedAt': null,
      });

      // Completed task with the same tag — must NEVER appear
      await fakeFirestore.collection('tasks').doc('a-completed').set({
        'taskId': 'a-completed',
        'uid': uid,
        'listId': 'list-a',
        'title': 'Completed Alpha Task',
        'notes': '',
        'tagIds': ['tag-urgent'],
        'createdAt': Timestamp.fromDate(early),
        'completedAt': Timestamp.fromDate(late),
        'deletedAt': null,
      });

      await tester.pumpWidget(
        buildPopupWidget(tagId: 'tag-urgent', tagName: 'Urgent'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Popup'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tagTasksPopup_tag-urgent')), findsOneWidget);

      // Verify list headings are rendered
      expect(
        find.byKey(const Key('tagTasksPopupGroupHeading_tag-urgent_list-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('tagTasksPopupGroupHeading_tag-urgent_list-z')),
        findsOneWidget,
      );
      expect(find.text('Alpha List'), findsOneWidget);
      expect(find.text('Zebra List'), findsOneWidget);

      // Check group ordering: Alpha List appears above Zebra List
      final alphaOffset = tester.getTopLeft(
        find.byKey(const Key('tagTasksPopupGroupHeading_tag-urgent_list-a')),
      );
      final zebraOffset = tester.getTopLeft(
        find.byKey(const Key('tagTasksPopupGroupHeading_tag-urgent_list-z')),
      );
      expect(alphaOffset.dy, lessThan(zebraOffset.dy));

      // Check task ordering in Zebra List: z-early appears above z-late
      final zEarlyOffset = tester.getTopLeft(
        find.byKey(const Key('tagTasksPopupTask_tag-urgent_z-early')),
      );
      final zLateOffset = tester.getTopLeft(
        find.byKey(const Key('tagTasksPopupTask_tag-urgent_z-late')),
      );
      expect(zEarlyOffset.dy, lessThan(zLateOffset.dy));

      // Check active tasks are rendered
      expect(find.text('Alpha Task'), findsOneWidget);
      expect(find.text('Zebra Early Task'), findsOneWidget);
      expect(find.text('Zebra Late Task'), findsOneWidget);
      expect(find.text('late note'), findsOneWidget);

      // Verify completed task is NOT rendered
      expect(find.text('Completed Alpha Task'), findsNothing);
      expect(
        find.byKey(const Key('tagTasksPopupTask_tag-urgent_a-completed')),
        findsNothing,
      );

      // Verify NO checkboxes exist anywhere in the popup
      expect(find.byType(Checkbox), findsNothing);

      // Test close button
      await tester.tap(find.byKey(const Key('tagTasksPopupCloseButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tagTasksPopup_tag-urgent')), findsNothing);
    },
  );
}
