import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/search/presentation/search_screen.dart';
import 'package:shukan/features/tags/providers/tag_providers.dart';
import 'package:shukan/features/tasks/providers/task_providers.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  const uid = 'test-search-user';

  setUp(() async {
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'search@example.com'),
      signedIn: true,
    );
    fakeFirestore = FakeFirebaseFirestore();

    // 1. Tags
    await fakeFirestore.collection('tags').doc('tag-work').set({
      'tagId': 'tag-work',
      'uid': uid,
      'name': 'WorkProject',
    });
    await fakeFirestore.collection('tags').doc('tag-home').set({
      'tagId': 'tag-home',
      'uid': uid,
      'name': 'Household',
    });

    // 2. Tasks across multiple lists
    // Task 1: Active, matched by title
    await fakeFirestore.collection('tasks').doc('t-active-1').set({
      'taskId': 't-active-1',
      'uid': uid,
      'listId': 'list-1',
      'title': 'Buy groceries',
      'notes': 'Apples and bananas',
      'url': '',
      'priority': 'none',
      'tagIds': ['tag-home'],
      'dueDate': null,
      'dueTime': null,
      'earlyReminderMinutes': 0,
      'repeatRule': 'none',
      'repeatCustomConfig': null,
      'order': 0,
      'subtasks': [],
      'createdAt': DateTime(2026, 1, 1, 10, 0),
      'completedAt': null,
      'deletedAt': null,
    });

    // Task 2: Active, matched by notes
    await fakeFirestore.collection('tasks').doc('t-active-2').set({
      'taskId': 't-active-2',
      'uid': uid,
      'listId': 'list-2',
      'title': 'Prepare presentation',
      'notes': 'Quarterly budget review details',
      'url': '',
      'priority': 'high',
      'tagIds': ['tag-work'],
      'dueDate': null,
      'dueTime': null,
      'earlyReminderMinutes': 0,
      'repeatRule': 'none',
      'repeatCustomConfig': null,
      'order': 1,
      'subtasks': [],
      'createdAt': DateTime(2026, 1, 1, 11, 0),
      'completedAt': null,
      'deletedAt': null,
    });

    // Task 3: Completed task, matched by tag name 'WorkProject'
    await fakeFirestore.collection('tasks').doc('t-completed-1').set({
      'taskId': 't-completed-1',
      'uid': uid,
      'listId': 'list-1',
      'title': 'Submit report',
      'notes': 'Finalized docs',
      'url': '',
      'priority': 'medium',
      'tagIds': ['tag-work'],
      'dueDate': null,
      'dueTime': null,
      'earlyReminderMinutes': 0,
      'repeatRule': 'none',
      'repeatCustomConfig': null,
      'order': 2,
      'subtasks': [],
      'createdAt': DateTime(2026, 1, 1, 12, 0),
      'completedAt': DateTime(2026, 1, 1, 13, 0),
      'deletedAt': null,
    });

    // Task 4: Deleted task (should be excluded)
    await fakeFirestore.collection('tasks').doc('t-deleted').set({
      'taskId': 't-deleted',
      'uid': uid,
      'listId': 'list-1',
      'title': 'Deleted task with groceries',
      'notes': '',
      'url': '',
      'priority': 'none',
      'tagIds': [],
      'dueDate': null,
      'dueTime': null,
      'earlyReminderMinutes': 0,
      'repeatRule': 'none',
      'repeatCustomConfig': null,
      'order': 3,
      'subtasks': [],
      'createdAt': DateTime(2026, 1, 1, 9, 0),
      'completedAt': null,
      'deletedAt': DateTime.now(),
    });
  });

  Widget createWidgetUnderTest({List<dynamic> additionalOverrides = const []}) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        ...additionalOverrides,
      ],
      child: const MaterialApp(home: SearchScreen()),
    );
  }

  group('SearchScreen Widget & Filter Tests', () {
    testWidgets(
      'empty query defaults to Active filter (hiding completed tasks)',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // "Active" chip is selected by default
        expect(find.text('Buy groceries'), findsOneWidget);
        expect(find.text('Prepare presentation'), findsOneWidget);
        // Completed task is hidden
        expect(find.text('Submit report'), findsNothing);
        // Deleted task is hidden
        expect(find.text('Deleted task with groceries'), findsNothing);
      },
    );

    testWidgets('matching by title with case-insensitivity', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Enter query "GROCERIES" in uppercase
      await tester.enterText(
        find.byKey(const Key('searchQueryInput')),
        'GROCERIES',
      );
      // Wait for debounce timer (300ms)
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.text('Prepare presentation'), findsNothing);
    });

    testWidgets('matching by notes with case-insensitivity', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Search for word in notes: "buDGet"
      await tester.enterText(
        find.byKey(const Key('searchQueryInput')),
        'buDGet',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Prepare presentation'), findsOneWidget);
      expect(find.text('Buy groceries'), findsNothing);
    });

    testWidgets('matching by tag name with case-insensitivity', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tag for 'Buy groceries' is 'Household' -> search 'house'
      await tester.enterText(
        find.byKey(const Key('searchQueryInput')),
        'house',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.text('Prepare presentation'), findsNothing);
    });

    testWidgets('completion filter: All, Completed, Active', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // 1. Switch to 'All'
      await tester.tap(find.byKey(const Key('filterChip_all')));
      await tester.pumpAndSettle();

      // All 3 non-deleted tasks show up
      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.text('Prepare presentation'), findsOneWidget);
      expect(find.text('Submit report'), findsOneWidget);

      // 2. Switch to 'Completed'
      await tester.tap(find.byKey(const Key('filterChip_completed')));
      await tester.pumpAndSettle();

      expect(find.text('Submit report'), findsOneWidget);
      expect(find.text('Buy groceries'), findsNothing);
      expect(find.text('Prepare presentation'), findsNothing);

      // 3. Switch back to 'Active'
      await tester.tap(find.byKey(const Key('filterChip_active')));
      await tester.pumpAndSettle();

      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.text('Prepare presentation'), findsOneWidget);
      expect(find.text('Submit report'), findsNothing);
    });

    testWidgets('shows empty results placeholder when no tasks match', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('searchQueryInput')),
        'nonexistent query 123',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('noSearchResultsText')), findsOneWidget);
      expect(find.text('No matching tasks found'), findsOneWidget);
    });

    testWidgets(
      'toggling task checkbox updates completed status via repository',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        final checkboxFinder = find.byKey(
          const Key('taskCompleteCheckbox_t-active-1'),
        );
        expect(checkboxFinder, findsOneWidget);

        // Check task complete
        await tester.tap(checkboxFinder);
        await tester.pumpAndSettle();

        // In Active filter, completing it causes it to disappear from the active view
        expect(find.text('Buy groceries'), findsNothing);

        // In Firestore, completedAt should now be populated
        final doc = await fakeFirestore
            .collection('tasks')
            .doc('t-active-1')
            .get();
        expect(doc.data()!['completedAt'], isNotNull);
      },
    );

    testWidgets('clear query button resets search input and results', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('searchQueryInput')),
        'groceries',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Prepare presentation'), findsNothing);

      // Tap clear button
      expect(find.byKey(const Key('clearSearchQueryButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('clearSearchQueryButton')));
      await tester.pumpAndSettle();

      // All active tasks reappear
      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.text('Prepare presentation'), findsOneWidget);
    });

    testWidgets(
      'displays user-friendly message for FAILED_PRECONDITION error on tasks stream without infinite spinner',
      (tester) async {
        await tester.pumpWidget(
          createWidgetUnderTest(
            additionalOverrides: [
              allTasksForCurrentUserProvider.overrideWith(
                (ref) => Stream.error(
                  FirebaseException(
                    plugin: 'cloud_firestore',
                    code: 'failed-precondition',
                    message: 'The query requires an index.',
                  ),
                ),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('searchErrorText')), findsOneWidget);
        expect(
          find.text(
            'Search is temporarily unavailable — please try again shortly',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('searchTasksLoadingIndicator')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'displays generic message for other errors on tasks stream without infinite spinner',
      (tester) async {
        await tester.pumpWidget(
          createWidgetUnderTest(
            additionalOverrides: [
              allTasksForCurrentUserProvider.overrideWith(
                (ref) => Stream.error(Exception('Network disconnected')),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('searchErrorText')), findsOneWidget);
        expect(find.text('Something went wrong'), findsOneWidget);
        expect(
          find.byKey(const Key('searchTasksLoadingIndicator')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'displays error message when tags stream fails without infinite spinner',
      (tester) async {
        await tester.pumpWidget(
          createWidgetUnderTest(
            additionalOverrides: [
              tagsForCurrentUserProvider.overrideWith(
                (ref) => Stream.error(
                  FirebaseException(
                    plugin: 'cloud_firestore',
                    code: 'failed-precondition',
                  ),
                ),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('searchErrorText')), findsOneWidget);
        expect(
          find.text(
            'Search is temporarily unavailable — please try again shortly',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('searchTasksLoadingIndicator')),
          findsNothing,
        );
      },
    );
  });
}
