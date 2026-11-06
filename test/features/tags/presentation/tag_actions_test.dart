import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tags/presentation/tag_actions.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';
import 'package:shukan/features/tasks/providers/task_tag_filter_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  const uid = 'test-uid';

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'test@example.com'),
      signedIn: true,
    );
    SharedPreferences.setMockInitialValues({});

    await fakeFirestore.collection('tags').doc('tag-1').set({
      'tagId': 'tag-1',
      'uid': uid,
      'name': 'Work',
      'createdAt': Timestamp.now(),
    });
    await fakeFirestore.collection('tags').doc('tag-2').set({
      'tagId': 'tag-2',
      'uid': uid,
      'name': 'Personal',
      'createdAt': Timestamp.now(),
    });
  });

  Widget buildTestHarness({
    required Widget Function(BuildContext context, WidgetRef ref) builder,
    SharedPreferences? prefs,
  }) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) => builder(context, ref)),
        ),
      ),
    );
  }

  group('showRenameTagDialog', () {
    testWidgets('renames tag successfully and displays feedback snackbar', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestHarness(
          builder: (context, ref) => ElevatedButton(
            onPressed: () => showRenameTagDialog(
              context,
              ref,
              const TagBrowserEntry(tagId: 'tag-1', name: 'Work', taskCount: 3),
              uid,
            ),
            child: const Text('Open Rename'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Rename Tag'), findsOneWidget);
      expect(find.byKey(const Key('renameTagInput')), findsOneWidget);

      // Enter new name with leading '#'
      await tester.enterText(
        find.byKey(const Key('renameTagInput')),
        '#Office',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirmRenameTagButton')));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('Rename Tag'), findsNothing);

      // Feedback snackbar shown
      expect(find.text('Renamed tag to "#Office"'), findsOneWidget);

      // Tag in Firestore should be updated to bare name 'Office'
      final doc = await fakeFirestore.collection('tags').doc('tag-1').get();
      expect(doc.data()!['name'], 'Office');
    });

    testWidgets('validates empty and whitespace-only tag name', (tester) async {
      await tester.pumpWidget(
        buildTestHarness(
          builder: (context, ref) => ElevatedButton(
            onPressed: () => showRenameTagDialog(
              context,
              ref,
              const TagBrowserEntry(tagId: 'tag-1', name: 'Work', taskCount: 0),
              uid,
            ),
            child: const Text('Open Rename'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Rename'));
      await tester.pumpAndSettle();

      // Clear or enter whitespace
      await tester.enterText(find.byKey(const Key('renameTagInput')), '   ');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmRenameTagButton')));
      await tester.pumpAndSettle();

      expect(find.text('Tag name cannot be empty.'), findsOneWidget);

      // Enter '#' only
      await tester.enterText(find.byKey(const Key('renameTagInput')), '#');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmRenameTagButton')));
      await tester.pumpAndSettle();

      expect(find.text('Tag name cannot be empty.'), findsOneWidget);

      // Dialog should still be open
      expect(find.text('Rename Tag'), findsOneWidget);
    });

    testWidgets('closing dialog without changes does nothing', (tester) async {
      await tester.pumpWidget(
        buildTestHarness(
          builder: (context, ref) => ElevatedButton(
            onPressed: () => showRenameTagDialog(
              context,
              ref,
              const TagBrowserEntry(tagId: 'tag-1', name: 'Work', taskCount: 0),
              uid,
            ),
            child: const Text('Open Rename'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Rename'));
      await tester.pumpAndSettle();

      // Saving same name
      await tester.tap(find.byKey(const Key('confirmRenameTagButton')));
      await tester.pumpAndSettle();

      expect(find.text('Rename Tag'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);

      // Cancel button test
      await tester.tap(find.text('Open Rename'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cancelRenameTagButton')));
      await tester.pumpAndSettle();

      expect(find.text('Rename Tag'), findsNothing);
    });

    testWidgets('displays server error when renaming to existing tag', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestHarness(
          builder: (context, ref) => ElevatedButton(
            onPressed: () => showRenameTagDialog(
              context,
              ref,
              const TagBrowserEntry(tagId: 'tag-1', name: 'Work', taskCount: 0),
              uid,
            ),
            child: const Text('Open Rename'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Rename'));
      await tester.pumpAndSettle();

      // Rename to 'Personal' which already exists
      await tester.enterText(
        find.byKey(const Key('renameTagInput')),
        'Personal',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmRenameTagButton')));
      await tester.pumpAndSettle();

      expect(find.text('A tag with this name already exists'), findsOneWidget);
      expect(find.text('Rename Tag'), findsOneWidget);
    });
  });

  group('showDeleteTagDialog', () {
    testWidgets('shows zero tasks warning when taskCount is 0', (tester) async {
      await tester.pumpWidget(
        buildTestHarness(
          builder: (context, ref) => ElevatedButton(
            onPressed: () => showDeleteTagDialog(
              context,
              ref,
              const TagBrowserEntry(tagId: 'tag-1', name: 'Work', taskCount: 0),
              uid,
            ),
            child: const Text('Open Delete'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete "#Work"?'), findsOneWidget);
      expect(
        find.text(
          'Are you sure you want to delete this tag? No tasks are currently using it.',
        ),
        findsOneWidget,
      );

      // Cancel does not delete
      await tester.tap(find.byKey(const Key('cancelDeleteTagButton')));
      await tester.pumpAndSettle();

      expect(find.text('Delete "#Work"?'), findsNothing);
      final doc = await fakeFirestore.collection('tags').doc('tag-1').get();
      expect(doc.exists, isTrue);
    });

    testWidgets(
      'shows active tasks warning when taskCount > 0 and deletes tag on confirm',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          buildTestHarness(
            prefs: prefs,
            builder: (context, ref) => ElevatedButton(
              onPressed: () => showDeleteTagDialog(
                context,
                ref,
                const TagBrowserEntry(
                  tagId: 'tag-1',
                  name: 'Work',
                  taskCount: 3,
                ),
                uid,
              ),
              child: const Text('Open Delete'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Delete'));
        await tester.pumpAndSettle();

        expect(find.text('Delete "#Work"?'), findsOneWidget);
        expect(
          find.text(
            '3 active task(s) currently use this tag. It will be removed from these tasks.',
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('confirmDeleteTagButton')));
        await tester.pumpAndSettle();

        expect(find.text('Delete "#Work"?'), findsNothing);
        expect(find.text('Deleted tag "#Work"'), findsOneWidget);

        // Tag should be deleted from Firestore
        final doc = await fakeFirestore.collection('tags').doc('tag-1').get();
        expect(doc.exists, isFalse);
      },
    );
  });
}
