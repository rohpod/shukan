import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/search/presentation/search_screen.dart';
import 'package:shukan/features/tags/presentation/tag_browser_screen.dart';
import 'package:shukan/features/tags/presentation/tag_detail_screen.dart';
import 'package:shukan/features/tasks/domain/smart_view_models.dart';
import 'package:shukan/features/tasks/presentation/recently_deleted_screen.dart';
import 'package:shukan/features/tasks/presentation/smart_view_detail_screen.dart';
import 'package:shukan/features/tasks/presentation/task_list_screen.dart';
import 'package:shukan/features/tasks/presentation/widgets/empty_state_view.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  const uid = 'test-empty-state-user';
  const listId = 'list-inbox';
  final fixedDate = DateTime(2026, 10, 15, 12, 0);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'user@example.com'),
      signedIn: true,
    );
    fakeFirestore = FakeFirebaseFirestore();

    // User & default list setup
    await fakeFirestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': 'user@example.com',
      'defaultListId': listId,
    });
    await fakeFirestore.collection('lists').doc(listId).set({
      'listId': listId,
      'uid': uid,
      'name': 'Inbox',
      'isDefault': true,
      'createdAt': Timestamp.now(),
    });
  });

  Widget wrapWithScope(Widget child, {List<dynamic> extraOverrides = const []}) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentDateProvider.overrideWithValue(fixedDate),
        ...extraOverrides,
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  group('TaskListScreen Empty State Tests', () {
    testWidgets(
      'renders genuinely empty state when list has 0 tasks, with "Add task" button',
      (tester) async {
        await tester.pumpWidget(wrapWithScope(const TaskListScreen(listId: listId)));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
        expect(find.text('No tasks yet'), findsOneWidget);
        expect(find.byKey(const Key('emptyStateAddTaskButton')), findsOneWidget);
        expect(find.byKey(const Key('noTasksText')), findsOneWidget);

        // Tap Add task button opens TaskDialog
        await tester.tap(find.byKey(const Key('emptyStateAddTaskButton')));
        await tester.pumpAndSettle();

        expect(find.text('New Task'), findsOneWidget);
      },
    );

    testWidgets(
      'renders filtered-to-zero when all tasks are completed and hidden by default, tapping "Clear filters" reveals them',
      (tester) async {
        // Create 2 completed tasks in the list
        await fakeFirestore.collection('tasks').doc('t-comp-1').set({
          'taskId': 't-comp-1',
          'uid': uid,
          'listId': listId,
          'title': 'Completed Task 1',
          'isCompleted': true,
          'completedAt': Timestamp.now(),
          'deletedAt': null,
          'priority': 'none',
          'tagIds': [],
          'order': 0,
        });
        await fakeFirestore.collection('tasks').doc('t-comp-2').set({
          'taskId': 't-comp-2',
          'uid': uid,
          'listId': listId,
          'title': 'Completed Task 2',
          'isCompleted': true,
          'completedAt': Timestamp.now(),
          'deletedAt': null,
          'priority': 'none',
          'tagIds': [],
          'order': 1,
        });

        await tester.pumpWidget(wrapWithScope(const TaskListScreen(listId: listId)));
        await tester.pumpAndSettle();

        // Tasks exist, but hidden because completion toggle is false -> filtered to zero!
        expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);
        expect(find.text('No tasks match your filters'), findsOneWidget);
        expect(find.byKey(Key('clearFiltersButton_$listId')), findsOneWidget);

        // Tap Clear filters -> sets showCompleted to true
        await tester.tap(find.byKey(Key('clearFiltersButton_$listId')));
        await tester.pumpAndSettle();

        // Tasks are now revealed!
        expect(find.text('Completed Task 1'), findsOneWidget);
        expect(find.text('Completed Task 2'), findsOneWidget);
      },
    );
  });

  group('SmartViewDetailScreen Empty State Tests', () {
    testWidgets(
      'Today view: genuinely empty shows "Nothing due today" and "Add task" button',
      (tester) async {
        await tester.pumpWidget(
          wrapWithScope(const SmartViewDetailScreen(viewType: SmartViewType.today)),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.today_outlined), findsOneWidget);
        expect(find.text('Nothing due today'), findsOneWidget);
        expect(find.byKey(const Key('emptyStateAddTaskButton')), findsOneWidget);

        await tester.tap(find.byKey(const Key('emptyStateAddTaskButton')));
        await tester.pumpAndSettle();

        expect(find.text('New Task'), findsOneWidget);
      },
    );

    testWidgets(
      'This Week view: genuinely empty shows "No tasks scheduled this week" and "Add task" button',
      (tester) async {
        await tester.pumpWidget(
          wrapWithScope(const SmartViewDetailScreen(viewType: SmartViewType.thisWeek)),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.calendar_view_week_outlined), findsOneWidget);
        expect(find.text('No tasks scheduled this week'), findsOneWidget);
        expect(find.byKey(const Key('emptyStateAddTaskButton')), findsOneWidget);
      },
    );

    testWidgets(
      'Scheduled view: genuinely empty shows "No scheduled tasks" with NO "Add task" button',
      (tester) async {
        await tester.pumpWidget(
          wrapWithScope(const SmartViewDetailScreen(viewType: SmartViewType.scheduled)),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.event_note_outlined), findsOneWidget);
        expect(find.text('No scheduled tasks'), findsOneWidget);
        expect(find.byKey(const Key('emptyStateAddTaskButton')), findsNothing);
      },
    );

    testWidgets(
      'Smart view: filtered-to-zero when all due tasks are completed and hidden by default, tapping "Clear filters" reveals them',
      (tester) async {
        await fakeFirestore.collection('tasks').doc('t-today-comp').set({
          'taskId': 't-today-comp',
          'uid': uid,
          'listId': listId,
          'title': 'Done Today',
          'isCompleted': true,
          'completedAt': Timestamp.now(),
          'dueDate': Timestamp.fromDate(fixedDate),
          'deletedAt': null,
          'priority': 'none',
          'tagIds': [],
        });

        await tester.pumpWidget(
          wrapWithScope(const SmartViewDetailScreen(viewType: SmartViewType.today)),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);
        expect(find.text('No tasks match your filters'), findsOneWidget);
        expect(find.byKey(const Key('clearFiltersButton_today')), findsOneWidget);

        // Tap Clear filters -> sets showCompleted to true
        await tester.tap(find.byKey(const Key('clearFiltersButton_today')));
        await tester.pumpAndSettle();

        expect(find.text('Done Today'), findsOneWidget);
      },
    );
  });

  group('TagDetailScreen Empty State Tests', () {
    const tagId = 'tag-school';
    const tagName = 'school';

    testWidgets(
      'renders genuinely empty state when no tasks have this tag',
      (tester) async {
        await fakeFirestore.collection('tags').doc(tagId).set({
          'tagId': tagId,
          'uid': uid,
          'name': tagName,
        });

        await tester.pumpWidget(
          wrapWithScope(const TagDetailScreen(tagId: tagId, tagName: tagName)),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(EmptyStateView),
            matching: find.byIcon(Icons.label_outline),
          ),
          findsOneWidget,
        );
        expect(find.text('No tasks found'), findsOneWidget);
        expect(find.byKey(const Key('emptyStateAddTaskButton')), findsNothing);
      },
    );

    testWidgets(
      'renders filtered-to-zero when tag tasks are completed and hidden by default, tapping "Clear filters" reveals them',
      (tester) async {
        await fakeFirestore.collection('tags').doc(tagId).set({
          'tagId': tagId,
          'uid': uid,
          'name': tagName,
        });
        await fakeFirestore.collection('tasks').doc('t-tag-done').set({
          'taskId': 't-tag-done',
          'uid': uid,
          'listId': listId,
          'title': 'School Homework Done',
          'isCompleted': true,
          'completedAt': Timestamp.now(),
          'deletedAt': null,
          'priority': 'none',
          'tagIds': [tagId],
        });

        await tester.pumpWidget(
          wrapWithScope(const TagDetailScreen(tagId: tagId, tagName: tagName)),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);
        expect(find.text('No tasks match your filters'), findsOneWidget);
        expect(find.byKey(const Key('clearFiltersButton_tag_tag-school')), findsOneWidget);

        await tester.tap(find.byKey(const Key('clearFiltersButton_tag_tag-school')));
        await tester.pumpAndSettle();

        expect(find.text('School Homework Done'), findsOneWidget);
      },
    );
  });

  group('SearchScreen Empty State Tests', () {
    testWidgets(
      'renders "No tasks found" with search_off icon when account has 0 tasks',
      (tester) async {
        await tester.pumpWidget(wrapWithScope(const SearchScreen()));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.search_off_outlined), findsOneWidget);
        expect(find.text('No tasks found'), findsOneWidget);
        expect(find.byKey(const Key('noSearchResultsText')), findsOneWidget);
      },
    );

    testWidgets(
      'renders "No matching tasks found" with "Clear search" button when query yields 0 matches',
      (tester) async {
        await fakeFirestore.collection('tasks').doc('t-active').set({
          'taskId': 't-active',
          'uid': uid,
          'listId': listId,
          'title': 'Read a book',
          'isCompleted': false,
          'completedAt': null,
          'deletedAt': null,
          'priority': 'none',
          'tagIds': [],
        });

        await tester.pumpWidget(wrapWithScope(const SearchScreen()));
        await tester.pumpAndSettle();

        // Initially shows active task
        expect(find.text('Read a book'), findsOneWidget);

        // Search for something that doesn't match
        await tester.enterText(find.byKey(const Key('searchQueryInput')), 'quantum physics');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);
        expect(find.text('No matching tasks found'), findsOneWidget);
        expect(find.byKey(const Key('clearSearchFiltersButton')), findsOneWidget);

        // Tap Clear search
        await tester.tap(find.byKey(const Key('clearSearchFiltersButton')));
        await tester.pumpAndSettle();

        // Read a book task reappears!
        expect(find.text('Read a book'), findsOneWidget);
      },
    );
  });

  group('RecentlyDeletedScreen & TagBrowserScreen Empty State Tests', () {
    testWidgets('RecentlyDeletedScreen renders EmptyStateView with delete_outline icon', (
      tester,
    ) async {
      await tester.pumpWidget(wrapWithScope(const RecentlyDeletedScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.text('No recently deleted tasks'), findsOneWidget);
      expect(find.byKey(const Key('noRecentlyDeletedTasksText')), findsOneWidget);
    });

    testWidgets('TagBrowserScreen renders EmptyStateView with label_outline icon', (
      tester,
    ) async {
      await tester.pumpWidget(wrapWithScope(const TagBrowserScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.label_outline), findsOneWidget);
      expect(find.text('No tags in use'), findsOneWidget);
      expect(find.byKey(const Key('noTagsText')), findsOneWidget);
    });
  });
}
