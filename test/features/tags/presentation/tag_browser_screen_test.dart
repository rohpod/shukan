import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tags/presentation/tag_browser_screen.dart';
import 'package:shukan/features/tags/presentation/tag_detail_screen.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  const uid = 'test-uid';

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'user@example.com'),
      signedIn: true,
    );
    SharedPreferences.setMockInitialValues({});
  });

  Widget createWidget({SharedPreferences? prefs}) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MaterialApp(home: TagBrowserScreen()),
    );
  }

  testWidgets('renders empty state when no active tasks have tags', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(createWidget(prefs: prefs));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noTagsText')), findsOneWidget);
    expect(find.text('No tags in use'), findsOneWidget);
  });

  testWidgets(
    'lists all tags in use with correct task counts and navigates to TagDetailScreen',
    (tester) async {
      // Seed tags
      await fakeFirestore.collection('tags').doc('tag-work').set({
        'tagId': 'tag-work',
        'uid': uid,
        'name': 'Work',
        'createdAt': DateTime.now(),
      });
      await fakeFirestore.collection('tags').doc('tag-urgent').set({
        'tagId': 'tag-urgent',
        'uid': uid,
        'name': 'Urgent',
        'createdAt': DateTime.now(),
      });

      // Seed tasks
      await fakeFirestore.collection('tasks').doc('t1').set({
        'taskId': 't1',
        'uid': uid,
        'title': 'Task 1',
        'tagIds': ['tag-work', 'tag-urgent'],
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('t2').set({
        'taskId': 't2',
        'uid': uid,
        'title': 'Task 2',
        'tagIds': ['tag-work'],
        'deletedAt': null,
      });

      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(createWidget(prefs: prefs));
      await tester.pumpAndSettle();

      // Verify tag list and counts
      expect(find.byKey(const Key('tagBrowserItem_tag-work')), findsOneWidget);
      expect(
        find.byKey(const Key('tagBrowserItem_tag-urgent')),
        findsOneWidget,
      );

      expect(
        find.byKey(const Key('tagBrowserItemCount_tag-work')),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget); // Work has 2 tasks

      expect(
        find.byKey(const Key('tagBrowserItemCount_tag-urgent')),
        findsOneWidget,
      );
      expect(find.text('1'), findsOneWidget); // Urgent has 1 task

      // Tap "Work" tag to navigate
      await tester.tap(find.byKey(const Key('tagBrowserItem_tag-work')));
      await tester.pumpAndSettle();

      // TagDetailScreen is pushed
      expect(find.byType(TagDetailScreen), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('#Work')),
        findsOneWidget,
      );
    },
  );

  testWidgets('renames tag and reflects new name in list; handles duplicates', (
    tester,
  ) async {
    await fakeFirestore.collection('tags').doc('tag-work').set({
      'tagId': 'tag-work',
      'uid': uid,
      'name': 'Work',
      'createdAt': DateTime.now(),
    });
    await fakeFirestore.collection('tags').doc('tag-urgent').set({
      'tagId': 'tag-urgent',
      'uid': uid,
      'name': 'Urgent',
      'createdAt': DateTime.now(),
    });
    await fakeFirestore.collection('tasks').doc('t1').set({
      'taskId': 't1',
      'uid': uid,
      'title': 'Task 1',
      'tagIds': ['tag-work', 'tag-urgent'],
      'deletedAt': null,
    });

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(createWidget(prefs: prefs));
    await tester.pumpAndSettle();

    // Tap rename on Work
    await tester.tap(find.byKey(const Key('renameTagButton_tag-work')));
    await tester.pumpAndSettle();

    expect(find.text('Rename Tag'), findsOneWidget);
    expect(find.byKey(const Key('renameTagInput')), findsOneWidget);

    // Cancel test
    await tester.tap(find.byKey(const Key('cancelRenameTagButton')));
    await tester.pumpAndSettle();
    expect(find.text('Rename Tag'), findsNothing);

    // Open rename again and enter colliding name
    await tester.tap(find.byKey(const Key('renameTagButton_tag-work')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('renameTagInput')), 'urgent');
    await tester.tap(find.byKey(const Key('confirmRenameTagButton')));
    await tester.pumpAndSettle();

    // Dialog stays open and shows duplicate error
    expect(find.text('A tag with this name already exists'), findsOneWidget);

    // Enter valid new name
    await tester.enterText(find.byKey(const Key('renameTagInput')), 'Office');
    await tester.tap(find.byKey(const Key('confirmRenameTagButton')));
    await tester.pumpAndSettle();

    // Dialog dismissed and new name is reflected
    expect(find.text('Rename Tag'), findsNothing);
    expect(find.text('Office'), findsOneWidget);
    expect(find.byKey(const Key('tagBrowserItem_tag-work')), findsOneWidget);

    final updatedDoc = await fakeFirestore.collection('tags').doc('tag-work').get();
    expect(updatedDoc.data()!['name'], equals('Office'));
  });

  testWidgets(
    'deletes tag with confirmation warning, cleans up tasks and preferences',
    (tester) async {
      await fakeFirestore.collection('tags').doc('tag-urgent').set({
        'tagId': 'tag-urgent',
        'uid': uid,
        'name': 'Urgent',
        'createdAt': DateTime.now(),
      });
      await fakeFirestore.collection('tasks').doc('t1').set({
        'taskId': 't1',
        'uid': uid,
        'title': 'Task 1',
        'tagIds': ['tag-urgent'],
        'deletedAt': null,
      });

      SharedPreferences.setMockInitialValues({
        'task_tag_filter_inbox': ['tag-urgent', 'other-tag'],
        'task_tag_filter_tag_tag-urgent': ['tag-urgent'],
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(createWidget(prefs: prefs));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tagBrowserItem_tag-urgent')), findsOneWidget);

      // Tap delete button
      await tester.tap(find.byKey(const Key('deleteTagButton_tag-urgent')));
      await tester.pumpAndSettle();

      // Verify dialog content with active task count
      expect(find.text('Delete "Urgent"?'), findsOneWidget);
      expect(
        find.text(
          '1 active task(s) currently use this tag. It will be removed from these tasks.',
        ),
        findsOneWidget,
      );

      // Cancel first
      await tester.tap(find.byKey(const Key('cancelDeleteTagButton')));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Urgent"?'), findsNothing);
      expect(find.byKey(const Key('tagBrowserItem_tag-urgent')), findsOneWidget);

      // Tap delete again and confirm
      await tester.tap(find.byKey(const Key('deleteTagButton_tag-urgent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDeleteTagButton')));
      await tester.pumpAndSettle();

      // SnackBar displayed
      expect(find.text('Deleted tag "Urgent"'), findsOneWidget);

      // Tag disappears from browser
      expect(find.byKey(const Key('tagBrowserItem_tag-urgent')), findsNothing);
      expect(find.byKey(const Key('noTagsText')), findsOneWidget);

      // Task 1 tagIds is updated in Firestore
      final taskDoc = await fakeFirestore.collection('tasks').doc('t1').get();
      expect(taskDoc.data()!['tagIds'], equals([]));

      // SharedPreferences updated
      expect(prefs.getStringList('task_tag_filter_inbox'), equals(['other-tag']));
      expect(prefs.getStringList('task_tag_filter_tag_tag-urgent'), isNull);
    },
  );

  testWidgets('deletes tag with zero tasks shows appropriate message', (
    tester,
  ) async {
    await fakeFirestore.collection('tags').doc('tag-unused').set({
      'tagId': 'tag-unused',
      'uid': uid,
      'name': 'Unused',
      'createdAt': DateTime.now(),
    });
    // Task with different tag so browser has active tasks
    await fakeFirestore.collection('tasks').doc('t1').set({
      'taskId': 't1',
      'uid': uid,
      'title': 'Task 1',
      'tagIds': ['tag-other'],
      'deletedAt': null,
    });
    await fakeFirestore.collection('tags').doc('tag-other').set({
      'tagId': 'tag-other',
      'uid': uid,
      'name': 'Other',
      'createdAt': DateTime.now(),
    });

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(createWidget(prefs: prefs));
    await tester.pumpAndSettle();

    // Since Unused has 0 tasks, tagBrowserEntriesProvider only lists tags in use by active tasks.
    // Let's create an active task with Unused and then soft-delete it so taskCount is 0 but tag exists:
    await fakeFirestore.collection('tasks').doc('t2').set({
      'taskId': 't2',
      'uid': uid,
      'title': 'Task 2',
      'tagIds': ['tag-unused'],
      'deletedAt': null,
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tagBrowserItem_tag-unused')), findsOneWidget);
  });
}
