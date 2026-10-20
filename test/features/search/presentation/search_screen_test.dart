import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/lists/presentation/list_detail_screen.dart';
import 'package:shukan/features/search/presentation/search_screen.dart';
import 'package:shukan/features/tags/providers/tag_providers.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/data/task_repository.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';
import 'package:shukan/features/tasks/providers/task_providers.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  const uid = 'test-search-user';
  final fixedClock = DateTime(2026, 10, 14, 10, 0); // Wednesday

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
        currentDateProvider.overrideWithValue(fixedClock),
        ...additionalOverrides,
      ],
      child: const MaterialApp(home: SearchScreen()),
    );
  }

  group('SearchScreen Widget & Filter Tests', () {
    testWidgets('empty query shows all tasks regardless of completion status', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Active tasks show up
      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.text('Prepare presentation'), findsOneWidget);
      // Completed task also shows up
      expect(find.text('Submit report'), findsOneWidget);
      // Deleted task is hidden
      expect(find.text('Deleted task with groceries'), findsNothing);
    });

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

        // Task remains visible with completed styling (strikethrough, grey)
        expect(find.text('Buy groceries'), findsOneWidget);
        final titleText = tester.widget<Text>(
          find.byKey(const Key('taskTitle_t-active-1')),
        );
        expect(titleText.style?.decoration, TextDecoration.lineThrough);
        expect(titleText.style?.color, Colors.grey);

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

      // All tasks reappear
      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.text('Prepare presentation'), findsOneWidget);
      expect(find.text('Submit report'), findsOneWidget);
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

    testWidgets(
      'tapping a task row opens TaskDialog in edit mode on SearchScreen',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        expect(find.text('Buy groceries'), findsOneWidget);

        // Tap task row
        await tester.tap(find.text('Buy groceries'));
        await tester.pumpAndSettle();

        expect(find.text('Edit Task'), findsOneWidget);
        expect(find.byKey(const Key('editTaskTitleInput')), findsOneWidget);
      },
    );
  });

  group('SearchScreen Add Task Action Tests', () {
    const defaultListId = 'inbox-default-id';
    const secondListId = 'work-list-id';

    Future<void> seedDefaultLists() async {
      await fakeFirestore.collection('users').doc(uid).set({
        'uid': uid,
        'email': 'search@example.com',
        'defaultListId': defaultListId,
      });
      await fakeFirestore.collection('lists').doc(defaultListId).set({
        'listId': defaultListId,
        'uid': uid,
        'name': 'Inbox',
        'isDefault': true,
      });
      await fakeFirestore.collection('lists').doc(secondListId).set({
        'listId': secondListId,
        'uid': uid,
        'name': 'Work',
        'isDefault': false,
      });
    }

    testWidgets(
      'Row is hidden for an empty query and for whitespace-only; shown for a non-empty query, including when there are zero matching results',
      (tester) async {
        await seedDefaultLists();
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // 1. Empty query -> hidden
        expect(find.byKey(const Key('searchAddTaskAction')), findsNothing);

        // 2. Whitespace-only query -> hidden
        await tester.enterText(
          find.byKey(const Key('searchQueryInput')),
          '     ',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('searchAddTaskAction')), findsNothing);

        // 3. Non-empty query with 0 matching results -> shown
        await tester.enterText(
          find.byKey(const Key('searchQueryInput')),
          'unique zero match xyz',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('noSearchResultsText')), findsOneWidget);
        expect(find.byKey(const Key('searchAddTaskAction')), findsOneWidget);
        expect(
          find.text('Add "unique zero match xyz" as a task'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Row is disabled when no default list has resolved', (
      tester,
    ) async {
      // Do NOT seed users or lists doc -> effectiveDefaultListProvider is null
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('searchQueryInput')),
        'my task',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('searchAddTaskAction')), findsOneWidget);
      final listTile = tester.widget<ListTile>(
        find.byKey(const Key('searchAddTaskAction')),
      );
      expect(listTile.onTap, isNull);
      expect(listTile.enabled, isFalse);
    });

    testWidgets(
      'Tapping with a date query like "meeting friday" parses in phase 1, and second tap confirms and creates task',
      (tester) async {
        await seedDefaultLists();
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // Query with leading/trailing spaces and date-like word "meeting friday"
        await tester.enterText(
          find.byKey(const Key('searchQueryInput')),
          '  meeting friday  ',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(find.text('Add "meeting friday" as a task'), findsOneWidget);
        expect(find.byKey(const Key('quickAddDateChip')), findsNothing);

        // First tap: runs parser, shows preview chip, updates row label, does NOT create task yet
        await tester.tap(find.byKey(const Key('searchAddTaskAction')));
        await tester.pumpAndSettle();

        expect(find.text('Add "meeting" as a task'), findsOneWidget);
        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);

        // Verify NO task created in Firestore yet
        final snapshotBefore = await fakeFirestore
            .collection('tasks')
            .where('uid', isEqualTo: uid)
            .where('title', isEqualTo: 'meeting')
            .get();
        expect(snapshotBefore.docs, isEmpty);

        // Second tap: confirms and creates task
        await tester.tap(find.byKey(const Key('searchAddTaskAction')));
        await tester.pumpAndSettle();

        // Verify task in fakeFirestore
        final snapshotAfter = await fakeFirestore
            .collection('tasks')
            .where('uid', isEqualTo: uid)
            .where('title', isEqualTo: 'meeting')
            .get();

        expect(snapshotAfter.docs.length, equals(1));
        final data = snapshotAfter.docs.first.data();
        expect(data['title'], equals('meeting'));
        expect(data['listId'], equals(defaultListId));
        expect(data['dueDate'], isNotNull);
        expect(
          (data['dueDate'] as Timestamp).toDate(),
          equals(DateTime(2026, 10, 16)),
        );
        expect(data['dueTime'], isNull);
      },
    );

    testWidgets(
      'query with only a date phrase falls back to original text as title with parsed date/time',
      (tester) async {
        await seedDefaultLists();
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('searchQueryInput')),
          'tomorrow 5pm',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(find.text('Add "tomorrow 5pm" as a task'), findsOneWidget);

        // First tap parses
        await tester.tap(find.byKey(const Key('searchAddTaskAction')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);
        expect(find.text('Tomorrow 5:00 PM'), findsOneWidget);
        // Stripped title falls back to original input
        expect(find.text('Add "tomorrow 5pm" as a task'), findsOneWidget);

        final beforeDocs = await fakeFirestore
            .collection('tasks')
            .where('uid', isEqualTo: uid)
            .where('title', isEqualTo: 'tomorrow 5pm')
            .get();
        expect(beforeDocs.docs, isEmpty);

        // Second tap confirms
        await tester.tap(find.byKey(const Key('searchAddTaskAction')));
        await tester.pumpAndSettle();

        final afterDocs = await fakeFirestore
            .collection('tasks')
            .where('uid', isEqualTo: uid)
            .where('title', isEqualTo: 'tomorrow 5pm')
            .get();
        expect(afterDocs.docs.length, equals(1));
        final data = afterDocs.docs.first.data();
        expect(data['title'], equals('tomorrow 5pm'));
        expect(data['dueTime'], equals('17:00'));
        expect(data['dueDate'], isNotNull);
        expect(
          (data['dueDate'] as Timestamp).toDate(),
          equals(DateTime(2026, 10, 15)),
        );
      },
    );

    testWidgets(
      'dismissing the chip resets the row label and a following tap re-parses fresh',
      (tester) async {
        await seedDefaultLists();
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('searchQueryInput')),
          'call mom tomorrow 6pm',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        // First tap -> chip appears, label stripped
        await tester.tap(find.byKey(const Key('searchAddTaskAction')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);
        expect(find.text('Add "call mom" as a task'), findsOneWidget);

        // Dismiss chip via close icon
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddDateChip')), findsNothing);
        expect(
          find.text('Add "call mom tomorrow 6pm" as a task'),
          findsOneWidget,
        );

        // Tap again -> re-parses fresh
        await tester.tap(find.byKey(const Key('searchAddTaskAction')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);
        expect(find.text('Add "call mom" as a task'), findsOneWidget);

        // Confirm creation
        await tester.tap(find.byKey(const Key('searchAddTaskAction')));
        await tester.pumpAndSettle();

        final snapshot = await fakeFirestore
            .collection('tasks')
            .where('uid', isEqualTo: uid)
            .where('title', isEqualTo: 'call mom')
            .get();
        expect(snapshot.docs.length, equals(1));
        final data = snapshot.docs.first.data();
        expect(data['title'], equals('call mom'));
        expect(data['dueTime'], equals('18:00'));
        expect(data['dueDate'], isNotNull);
      },
    );

    testWidgets(
      'editing the query after the chip appears resets parsed state so next tap re-parses new text',
      (tester) async {
        await seedDefaultLists();
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('searchQueryInput')),
          'call mom tomorrow',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        // Tap to parse
        await tester.tap(find.byKey(const Key('searchAddTaskAction')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);
        expect(find.text('Add "call mom" as a task'), findsOneWidget);

        // Edit text to a different query
        await tester.enterText(
          find.byKey(const Key('searchQueryInput')),
          'call dad today',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        // Chip is dismissed automatically and label resets to current query
        expect(find.byKey(const Key('quickAddDateChip')), findsNothing);
        expect(find.text('Add "call dad today" as a task'), findsOneWidget);

        // Tap now re-parses the new query
        await tester.tap(find.byKey(const Key('searchAddTaskAction')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Add "call dad" as a task'), findsOneWidget);

        // Confirm creation
        await tester.tap(find.byKey(const Key('searchAddTaskAction')));
        await tester.pumpAndSettle();

        final snapshot = await fakeFirestore
            .collection('tasks')
            .where('uid', isEqualTo: uid)
            .where('title', isEqualTo: 'call dad')
            .get();
        expect(snapshot.docs.length, equals(1));
        final data = snapshot.docs.first.data();
        expect(data['title'], equals('call dad'));
        expect(
          (data['dueDate'] as Timestamp).toDate(),
          equals(DateTime(2026, 10, 14)),
        );
        expect(data['dueTime'], isNull);
      },
    );

    testWidgets(
      'query with no date/time still creates the task in one tap without chip',
      (tester) async {
        await seedDefaultLists();
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('searchQueryInput')),
          'read novel',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(find.text('Add "read novel" as a task'), findsOneWidget);
        expect(find.byKey(const Key('quickAddDateChip')), findsNothing);

        // Single tap creates task immediately
        await tester.tap(find.byKey(const Key('searchAddTaskAction')));
        await tester.pumpAndSettle();

        final snapshot = await fakeFirestore
            .collection('tasks')
            .where('uid', isEqualTo: uid)
            .where('title', isEqualTo: 'read novel')
            .get();
        expect(snapshot.docs.length, equals(1));
        final data = snapshot.docs.first.data();
        expect(data['title'], equals('read novel'));
        expect(data['dueDate'], isNull);
        expect(data['dueTime'], isNull);
      },
    );

    testWidgets(
      'submitting via keyboard Enter action follows two-phase parse and confirm',
      (tester) async {
        await seedDefaultLists();
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('searchQueryInput')),
          'call mom tomorrow 5pm',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        // First Enter -> parses
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);
        expect(find.text('Add "call mom" as a task'), findsOneWidget);

        // Second Enter -> creates task
        await tester.showKeyboard(find.byKey(const Key('searchQueryInput')));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        final snapshot = await fakeFirestore
            .collection('tasks')
            .where('uid', isEqualTo: uid)
            .where('title', isEqualTo: 'call mom')
            .get();
        expect(snapshot.docs.length, equals(1));
        final data = snapshot.docs.first.data();
        expect(data['title'], equals('call mom'));
        expect(data['dueTime'], equals('17:00'));
        expect(data['dueDate'], isNotNull);
      },
    );

    testWidgets(
      'SnackBar shows "Added to Inbox"; tapping View opens ListDetailScreen for the default list',
      (tester) async {
        await seedDefaultLists();
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('searchQueryInput')),
          'Check emails',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('searchAddTaskAction')));
        await tester.pumpAndSettle();

        expect(find.text('Added to Inbox'), findsOneWidget);
        expect(find.text('View'), findsOneWidget);

        // Tap View action
        await tester.tap(find.text('View'));
        await tester.pumpAndSettle();

        // Pushed ListDetailScreen
        expect(find.byType(ListDetailScreen), findsOneWidget);
        expect(find.text('Inbox'), findsWidgets);
      },
    );

    testWidgets('Rapid double-tap creates only one task', (tester) async {
      await seedDefaultLists();
      final gate = Completer<void>();
      final baseRepo = TaskRepository(fakeFirestore);
      final delayedRepo = _DelayedTaskRepository(baseRepo, gate);

      await tester.pumpWidget(
        createWidgetUnderTest(
          additionalOverrides: [
            taskRepositoryProvider.overrideWithValue(delayedRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('searchQueryInput')),
        'Rapid task test',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      final actionFinder = find.byKey(const Key('searchAddTaskAction'));
      // First tap initiates task creation and sets in-flight flag
      await tester.tap(actionFinder);
      await tester.pump();

      // Second rapid tap while creation is in flight
      await tester.tap(actionFinder);
      await tester.pump();

      // Now complete the in-flight operation
      gate.complete();
      await tester.pumpAndSettle();

      final snapshot = await fakeFirestore
          .collection('tasks')
          .where('uid', isEqualTo: uid)
          .where('title', isEqualTo: 'Rapid task test')
          .get();

      expect(snapshot.docs.length, equals(1));
    });

    testWidgets(
      'The new task appears in the results for the still-active query',
      (tester) async {
        await seedDefaultLists();
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('searchQueryInput')),
          'Buy fresh apples',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        // Before adding, "Buy fresh apples" does not exist in results list
        expect(
          find.descendant(
            of: find.byKey(const Key('searchResultsListView')),
            matching: find.text('Buy fresh apples'),
          ),
          findsNothing,
        );

        await tester.tap(find.byKey(const Key('searchAddTaskAction')));
        await tester.pumpAndSettle();

        // The query is still active in the input
        final input = tester.widget<TextField>(
          find.byKey(const Key('searchQueryInput')),
        );
        expect(input.controller!.text, equals('Buy fresh apples'));

        // The new task appears in the search results
        expect(
          find.descendant(
            of: find.byKey(const Key('searchResultsListView')),
            matching: find.text('Buy fresh apples'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'renders priority markers for none, low, medium, and high on search results',
      (tester) async {
        // Seed an extra low-priority task
        await fakeFirestore.collection('tasks').doc('t-search-low').set({
          'taskId': 't-search-low',
          'uid': uid,
          'listId': 'list-1',
          'title': 'Low priority call',
          'notes': 'test note',
          'url': '',
          'priority': 'low',
          'tagIds': <String>[],
          'dueDate': null,
          'dueTime': null,
          'earlyReminderMinutes': 0,
          'repeatRule': 'none',
          'repeatCustomConfig': null,
          'order': 5,
          'subtasks': <Map<String, dynamic>>[],
          'createdAt': DateTime(2026, 1, 1, 14, 0),
          'completedAt': null,
          'deletedAt': null,
        });

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // High priority: t-active-2 ('Prepare presentation')
        expect(
          find.byKey(const Key('taskPriorityMarker_t-active-2')),
          findsOneWidget,
        );
        expect(find.text('❗❗❗'), findsOneWidget);
        final highTitle = tester.widget<Text>(
          find.byKey(const Key('taskTitle_t-active-2')),
        );
        expect(highTitle.data, equals('Prepare presentation'));

        // Medium priority: t-completed-1 ('Submit report')
        expect(
          find.byKey(const Key('taskPriorityMarker_t-completed-1')),
          findsOneWidget,
        );
        expect(find.text('❕❕'), findsOneWidget);
        final medTitle = tester.widget<Text>(
          find.byKey(const Key('taskTitle_t-completed-1')),
        );
        expect(medTitle.data, equals('Submit report'));

        // Low priority: t-search-low ('Low priority call')
        expect(
          find.byKey(const Key('taskPriorityMarker_t-search-low')),
          findsOneWidget,
        );
        expect(find.text('!'), findsOneWidget);
        final lowTitle = tester.widget<Text>(
          find.byKey(const Key('taskTitle_t-search-low')),
        );
        expect(lowTitle.data, equals('Low priority call'));

        // None priority: t-active-1 ('Buy groceries')
        expect(
          find.byKey(const Key('taskPriorityMarker_t-active-1')),
          findsNothing,
        );
        final noneTitle = tester.widget<Text>(
          find.byKey(const Key('taskTitle_t-active-1')),
        );
        expect(noneTitle.data, equals('Buy groceries'));
      },
    );
  });
}

class _DelayedTaskRepository extends TaskRepository {
  final TaskRepository _inner;
  final Completer<void> _gate;

  _DelayedTaskRepository(this._inner, this._gate)
    : super(FakeFirebaseFirestore());

  @override
  Future<Task> createTask({
    required String uid,
    required String listId,
    required String title,
    String notes = '',
    String url = '',
    DateTime? dueDate,
    String? dueTime,
  }) async {
    await _gate.future;
    return _inner.createTask(
      uid: uid,
      listId: listId,
      title: title,
      notes: notes,
      url: url,
      dueDate: dueDate,
      dueTime: dueTime,
    );
  }
}
