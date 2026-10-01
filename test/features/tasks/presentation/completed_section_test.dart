import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/providers/auth_providers.dart';
import 'package:shukan/features/lists/data/list.dart';
import 'package:shukan/features/lists/presentation/list_detail_screen.dart';
import 'package:shukan/features/tags/presentation/tag_detail_screen.dart';
import 'package:shukan/features/tasks/domain/smart_view_models.dart';
import 'package:shukan/features/tasks/domain/task_priority_filter.dart';
import 'package:shukan/features/tasks/domain/task_sort_options.dart';
import 'package:shukan/features/tasks/presentation/smart_view_detail_screen.dart';
import 'package:shukan/features/tasks/presentation/task_list_screen.dart';
import 'package:shukan/features/tasks/presentation/widgets/show_completed_toggle.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';
import 'package:shukan/features/tasks/providers/task_selection_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';
import 'package:shukan/features/tasks/providers/task_tag_filter_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  const uid = 'test-user-id';
  const listId = 'list-completed-test';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fakeFirestore = FakeFirebaseFirestore();
    final user = MockUser(uid: uid, email: 'user@example.com');
    mockAuth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await fakeFirestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': 'user@example.com',
      'defaultListId': listId,
    });
    await fakeFirestore.collection('lists').doc(listId).set({
      'listId': listId,
      'uid': uid,
      'name': 'Test List',
      'isDefault': true,
    });
  });

  Widget wrapWithScope(Widget child, {SharedPreferences? prefs}) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentUidProvider.overrideWithValue(uid),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  group(
    'Requirement 1: Active & completed tasks separation and header count',
    () {
      testWidgets(
        'separates active and completed tasks; shows header count; collapsed by default',
        (tester) async {
          // 2 active tasks
          await fakeFirestore.collection('tasks').doc('act-1').set({
            'taskId': 'act-1',
            'uid': uid,
            'listId': listId,
            'title': 'Active Task 1',
            'order': 1000.0,
            'isCompleted': false,
            'completedAt': null,
            'deletedAt': null,
          });
          await fakeFirestore.collection('tasks').doc('act-2').set({
            'taskId': 'act-2',
            'uid': uid,
            'listId': listId,
            'title': 'Active Task 2',
            'order': 2000.0,
            'isCompleted': false,
            'completedAt': null,
            'deletedAt': null,
          });

          // 2 completed tasks
          await fakeFirestore.collection('tasks').doc('comp-1').set({
            'taskId': 'comp-1',
            'uid': uid,
            'listId': listId,
            'title': 'Completed Task 1',
            'order': 3000.0,
            'isCompleted': true,
            'completedAt': Timestamp.fromDate(DateTime(2026, 9, 20, 10, 0)),
            'deletedAt': null,
          });
          await fakeFirestore.collection('tasks').doc('comp-2').set({
            'taskId': 'comp-2',
            'uid': uid,
            'listId': listId,
            'title': 'Completed Task 2',
            'order': 4000.0,
            'isCompleted': true,
            'completedAt': Timestamp.fromDate(DateTime(2026, 9, 20, 11, 0)),
            'deletedAt': null,
          });

          await tester.pumpWidget(
            wrapWithScope(const TaskListScreen(listId: listId)),
          );
          await tester.pumpAndSettle();

          // Active tasks are visible
          expect(find.text('Active Task 1'), findsOneWidget);
          expect(find.text('Active Task 2'), findsOneWidget);

          // Header shows count
          expect(
            find.byKey(const Key('completedSectionTitle_$listId')),
            findsOneWidget,
          );
          expect(find.text('Completed (2)'), findsOneWidget);

          // Completed rows are hidden because section is collapsed by default
          expect(find.text('Completed Task 1'), findsNothing);
          expect(find.text('Completed Task 2'), findsNothing);
        },
      );

      testWidgets(
        'Completed section is completely hidden when 0 completed tasks exist',
        (tester) async {
          await fakeFirestore.collection('tasks').doc('act-only').set({
            'taskId': 'act-only',
            'uid': uid,
            'listId': listId,
            'title': 'Only Active Task',
            'order': 1000.0,
            'isCompleted': false,
            'completedAt': null,
            'deletedAt': null,
          });

          await tester.pumpWidget(
            wrapWithScope(const TaskListScreen(listId: listId)),
          );
          await tester.pumpAndSettle();

          expect(find.text('Only Active Task'), findsOneWidget);
          expect(
            find.byKey(const Key('completedSection_$listId')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('completedSectionTitle_$listId')),
            findsNothing,
          );
        },
      );
    },
  );

  group(
    'Requirement 2: Section expansion, ordering, styling, and drag disabled',
    () {
      testWidgets(
        'expands section, sorts by completedAt descending, applies strikethrough, disables drag',
        (tester) async {
          final prefs = await SharedPreferences.getInstance();

          // 1 active task
          await fakeFirestore.collection('tasks').doc('act-1').set({
            'taskId': 'act-1',
            'uid': uid,
            'listId': listId,
            'title': 'Active Task',
            'order': 1000.0,
            'isCompleted': false,
            'completedAt': null,
            'deletedAt': null,
          });

          // Earlier completed
          await fakeFirestore.collection('tasks').doc('comp-early').set({
            'taskId': 'comp-early',
            'uid': uid,
            'listId': listId,
            'title': 'Completed Earlier',
            'order': 2000.0,
            'isCompleted': true,
            'completedAt': Timestamp.fromDate(DateTime(2026, 9, 20, 9, 0)),
            'deletedAt': null,
          });

          // Later completed (most recent)
          await fakeFirestore.collection('tasks').doc('comp-late').set({
            'taskId': 'comp-late',
            'uid': uid,
            'listId': listId,
            'title': 'Completed Later',
            'order': 3000.0,
            'isCompleted': true,
            'completedAt': Timestamp.fromDate(DateTime(2026, 9, 20, 14, 0)),
            'deletedAt': null,
          });

          // Configure manual sort mode
          await prefs.setString(
            'task_sort_mode_$listId',
            TaskSortOption.manual.name,
          );

          await tester.pumpWidget(
            wrapWithScope(const TaskListScreen(listId: listId), prefs: prefs),
          );
          await tester.pumpAndSettle();

          // Initially collapsed
          expect(find.text('Completed Earlier'), findsNothing);
          expect(find.text('Completed Later'), findsNothing);

          // Tap header to expand
          await tester.tap(
            find.byKey(const Key('completedSectionHeader_$listId')),
          );
          await tester.pumpAndSettle();

          // Now both completed tasks are visible
          expect(find.text('Completed Later'), findsOneWidget);
          expect(find.text('Completed Earlier'), findsOneWidget);

          // Verify ordering: Completed Later appears before Completed Earlier
          final lateY = tester.getTopLeft(find.text('Completed Later')).dy;
          final earlyY = tester.getTopLeft(find.text('Completed Earlier')).dy;
          expect(lateY, lessThan(earlyY));

          // Verify styling: lineThrough and checked checkbox
          final lateText = tester.widget<Text>(find.text('Completed Later'));
          expect(
            lateText.style?.decoration,
            equals(TextDecoration.lineThrough),
          );

          final earlyText = tester.widget<Text>(find.text('Completed Earlier'));
          expect(
            earlyText.style?.decoration,
            equals(TextDecoration.lineThrough),
          );

          final lateCheckbox = tester.widget<Checkbox>(
            find.byKey(const Key('taskCompleteCheckbox_comp-late')),
          );
          expect(lateCheckbox.value, isTrue);

          // In Manual sort mode: active task HAS a delayed drag listener, but completed tasks DO NOT
          expect(
            find.byType(ReorderableDelayedDragStartListener),
            findsOneWidget,
          );
          expect(find.byKey(const Key('taskDragHandle_act-1')), findsNothing);
          expect(
            find.byKey(const Key('taskDragHandle_comp-late')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('taskDragHandle_comp-early')),
            findsNothing,
          );

          // Verify persistence: saved as collapsed = false
          expect(
            prefs.getBool('task_completed_section_collapsed_$listId'),
            isFalse,
          );

          // Tap header again to collapse
          await tester.tap(
            find.byKey(const Key('completedSectionHeader_$listId')),
          );
          await tester.pumpAndSettle();

          expect(find.text('Completed Later'), findsNothing);
          expect(
            prefs.getBool('task_completed_section_collapsed_$listId'),
            isTrue,
          );
        },
      );
    },
  );

  group('Requirement 3: Priority and tag filters affect only active tasks', () {
    testWidgets(
      'priority and tag filters isolate to active tasks; completed section remains unaffected',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        // Start expanded
        await prefs.setBool('task_completed_section_collapsed_$listId', false);

        // Active tasks
        await fakeFirestore.collection('tasks').doc('act-high').set({
          'taskId': 'act-high',
          'uid': uid,
          'listId': listId,
          'title': 'High Active',
          'priority': 'high',
          'tagIds': ['work'],
          'order': 1000.0,
          'isCompleted': false,
          'completedAt': null,
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('act-low').set({
          'taskId': 'act-low',
          'uid': uid,
          'listId': listId,
          'title': 'Low Active',
          'priority': 'low',
          'tagIds': ['personal'],
          'order': 2000.0,
          'isCompleted': false,
          'completedAt': null,
          'deletedAt': null,
        });

        // Completed tasks (different priority & tags)
        await fakeFirestore.collection('tasks').doc('comp-low').set({
          'taskId': 'comp-low',
          'uid': uid,
          'listId': listId,
          'title': 'Low Completed',
          'priority': 'low',
          'tagIds': ['personal'],
          'order': 3000.0,
          'isCompleted': true,
          'completedAt': Timestamp.fromDate(DateTime(2026, 9, 20, 10, 0)),
          'deletedAt': null,
        });
        await fakeFirestore.collection('tasks').doc('comp-none').set({
          'taskId': 'comp-none',
          'uid': uid,
          'listId': listId,
          'title': 'None Completed',
          'priority': 'none',
          'tagIds': [],
          'order': 4000.0,
          'isCompleted': true,
          'completedAt': Timestamp.fromDate(DateTime(2026, 9, 20, 9, 0)),
          'deletedAt': null,
        });

        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              firebaseAuthProvider.overrideWithValue(mockAuth),
              firestoreProvider.overrideWithValue(fakeFirestore),
              currentUidProvider.overrideWithValue(uid),
              sharedPreferencesProvider.overrideWithValue(prefs),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    capturedRef = ref;
                    return const TaskListScreen(listId: listId);
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially all visible
        expect(find.text('High Active'), findsOneWidget);
        expect(find.text('Low Active'), findsOneWidget);
        expect(find.text('Low Completed'), findsOneWidget);
        expect(find.text('None Completed'), findsOneWidget);
        expect(find.text('Completed (2)'), findsOneWidget);

        // Apply Priority Filter: High
        capturedRef
            .read(taskPriorityFilterProvider(listId).notifier)
            .setFilter(TaskPriorityFilter.high);
        await tester.pumpAndSettle();

        // Active: only 'High Active' is shown, 'Low Active' is filtered out
        expect(find.text('High Active'), findsOneWidget);
        expect(find.text('Low Active'), findsNothing);

        // Completed: STILL shows BOTH completed tasks!
        expect(find.text('Low Completed'), findsOneWidget);
        expect(find.text('None Completed'), findsOneWidget);
        expect(find.text('Completed (2)'), findsOneWidget);

        // Reset priority filter and apply Tag Filter: 'personal'
        capturedRef
            .read(taskPriorityFilterProvider(listId).notifier)
            .setFilter(TaskPriorityFilter.all);
        capturedRef
            .read(taskTagFilterProvider(listId).notifier)
            .toggleTag('personal');
        await tester.pumpAndSettle();

        // Active: only 'Low Active' (which has 'personal' tag) is shown
        expect(find.text('High Active'), findsNothing);
        expect(find.text('Low Active'), findsOneWidget);

        // Completed: STILL shows BOTH completed tasks!
        expect(find.text('Low Completed'), findsOneWidget);
        expect(find.text('None Completed'), findsOneWidget);
        expect(find.text('Completed (2)'), findsOneWidget);
      },
    );
  });

  group(
    'Requirement 4: Delete completed action, confirmation, pruning, and undo',
    () {
      testWidgets(
        'delete completed shows confirmation, prunes stale selection, soft deletes, and undo restores',
        (tester) async {
          final prefs = await SharedPreferences.getInstance();
          // Start expanded
          await prefs.setBool(
            'task_completed_section_collapsed_$listId',
            false,
          );

          await fakeFirestore.collection('tasks').doc('comp-del-1').set({
            'taskId': 'comp-del-1',
            'uid': uid,
            'listId': listId,
            'title': 'Del Completed 1',
            'order': 1000.0,
            'isCompleted': true,
            'completedAt': Timestamp.fromDate(DateTime(2026, 9, 20, 10, 0)),
            'deletedAt': null,
          });
          await fakeFirestore.collection('tasks').doc('comp-del-2').set({
            'taskId': 'comp-del-2',
            'uid': uid,
            'listId': listId,
            'title': 'Del Completed 2',
            'order': 2000.0,
            'isCompleted': true,
            'completedAt': Timestamp.fromDate(DateTime(2026, 9, 20, 11, 0)),
            'deletedAt': null,
          });

          late WidgetRef capturedRef;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                firebaseAuthProvider.overrideWithValue(mockAuth),
                firestoreProvider.overrideWithValue(fakeFirestore),
                currentUidProvider.overrideWithValue(uid),
                sharedPreferencesProvider.overrideWithValue(prefs),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: Consumer(
                    builder: (context, ref, _) {
                      capturedRef = ref;
                      return const TaskListScreen(listId: listId);
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Pre-select 'comp-del-1' in selection provider
          capturedRef
              .read(taskSelectionProvider(listId).notifier)
              .toggle('comp-del-1');
          await tester.pumpAndSettle();

          expect(
            capturedRef.read(taskSelectionProvider(listId)),
            contains('comp-del-1'),
          );

          // Tap "Delete completed" button
          expect(
            find.byKey(const Key('deleteCompletedButton_$listId')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const Key('deleteCompletedButton_$listId')),
          );
          await tester.pumpAndSettle();

          // Confirmation dialog appears with count = 2
          expect(find.text('Delete 2 completed tasks?'), findsOneWidget);
          expect(
            find.text('Tasks will be moved to Recently Deleted.'),
            findsOneWidget,
          );

          // Tap Cancel: tasks remain
          await tester.tap(
            find.byKey(const Key('cancelDeleteCompletedButton')),
          );
          await tester.pumpAndSettle();

          expect(find.text('Del Completed 1'), findsOneWidget);
          expect(find.text('Del Completed 2'), findsOneWidget);

          // Tap "Delete completed" again and confirm
          await tester.tap(
            find.byKey(const Key('deleteCompletedButton_$listId')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('confirmDeleteCompletedButton')),
          );
          await tester.pumpAndSettle();

          // Tasks are deleted: verify soft deletion in Firestore
          final doc1 = await fakeFirestore
              .collection('tasks')
              .doc('comp-del-1')
              .get();
          final doc2 = await fakeFirestore
              .collection('tasks')
              .doc('comp-del-2')
              .get();
          expect(doc1.data()?['deletedAt'], isNotNull);
          expect(doc2.data()?['deletedAt'], isNotNull);

          // Stale selection for comp-del-1 was pruned
          expect(
            capturedRef.read(taskSelectionProvider(listId)),
            isNot(contains('comp-del-1')),
          );

          // Undo SnackBar is shown
          expect(find.text('2 completed tasks deleted'), findsOneWidget);
          expect(
            find.byKey(const Key('undoDeleteCompletedButton')),
            findsOneWidget,
          );

          // Tap Undo
          await tester.tap(find.byKey(const Key('undoDeleteCompletedButton')));
          await tester.pumpAndSettle();

          // Tasks restored in Firestore
          final restoredDoc1 = await fakeFirestore
              .collection('tasks')
              .doc('comp-del-1')
              .get();
          final restoredDoc2 = await fakeFirestore
              .collection('tasks')
              .doc('comp-del-2')
              .get();
          expect(restoredDoc1.data()?['deletedAt'], isNull);
          expect(restoredDoc2.data()?['deletedAt'], isNull);

          // Re-appear in UI
          expect(find.text('Del Completed 1'), findsOneWidget);
          expect(find.text('Del Completed 2'), findsOneWidget);
        },
      );
    },
  );

  group(
    'Requirement 5: Smart views and Tag Detail ShowCompletedToggle behavior',
    () {
      testWidgets(
        'Today smart view lacks ShowCompletedToggle and lacks collapsible section',
        (tester) async {
          final prefs = await SharedPreferences.getInstance();

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                firebaseAuthProvider.overrideWithValue(mockAuth),
                firestoreProvider.overrideWithValue(fakeFirestore),
                currentUidProvider.overrideWithValue(uid),
                currentDateProvider.overrideWithValue(
                  DateTime(2026, 9, 20, 10, 0),
                ),
                sharedPreferencesProvider.overrideWithValue(prefs),
              ],
              child: const MaterialApp(
                home: SmartViewDetailScreen(viewType: SmartViewType.today),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(ShowCompletedToggle), findsNothing);
          expect(
            find.byKey(const Key('toggleShowCompleted_today')),
            findsNothing,
          );
          expect(find.text('Delete completed'), findsNothing);
        },
      );

      testWidgets(
        'Scheduled smart view lacks ShowCompletedToggle and lacks collapsible section',
        (tester) async {
          final prefs = await SharedPreferences.getInstance();

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                firebaseAuthProvider.overrideWithValue(mockAuth),
                firestoreProvider.overrideWithValue(fakeFirestore),
                currentUidProvider.overrideWithValue(uid),
                currentDateProvider.overrideWithValue(
                  DateTime(2026, 9, 20, 10, 0),
                ),
                sharedPreferencesProvider.overrideWithValue(prefs),
              ],
              child: const MaterialApp(
                home: SmartViewDetailScreen(viewType: SmartViewType.scheduled),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(ShowCompletedToggle), findsNothing);
          expect(
            find.byKey(const Key('toggleShowCompleted_scheduled')),
            findsNothing,
          );
          expect(find.text('Delete completed'), findsNothing);
        },
      );

      testWidgets(
        'TagDetailScreen retains ShowCompletedToggle and lacks collapsible section',
        (tester) async {
          final prefs = await SharedPreferences.getInstance();

          await fakeFirestore.collection('tags').doc('test-tag-id').set({
            'tagId': 'test-tag-id',
            'uid': uid,
            'name': 'urgent',
            'createdAt': DateTime(2026, 9, 20, 10, 0),
          });

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                firebaseAuthProvider.overrideWithValue(mockAuth),
                firestoreProvider.overrideWithValue(fakeFirestore),
                currentUidProvider.overrideWithValue(uid),
                currentDateProvider.overrideWithValue(
                  DateTime(2026, 9, 20, 10, 0),
                ),
                sharedPreferencesProvider.overrideWithValue(prefs),
              ],
              child: const MaterialApp(
                home: TagDetailScreen(tagId: 'test-tag-id', tagName: 'urgent'),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(ShowCompletedToggle), findsOneWidget);
          expect(
            find.byKey(const Key('toggleShowCompleted_tag_test-tag-id')),
            findsOneWidget,
          );
          expect(find.text('Delete completed'), findsNothing);
        },
      );
    },
  );

  group('Requirement 6: Batch selection on active and completed rows; drag reorder active only', () {
    testWidgets(
      'double tap selects both active and completed rows; drag listener present only on active row in manual mode',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        // Expanded completed section and manual sort mode
        await prefs.setBool('task_completed_section_collapsed_$listId', false);
        await prefs.setString(
          'task_sort_mode_$listId',
          TaskSortOption.manual.name,
        );

        final listModel = ListModel(
          listId: listId,
          uid: uid,
          name: 'Test List',
          isDefault: true,
        );

        await fakeFirestore.collection('tasks').doc('batch-act').set({
          'taskId': 'batch-act',
          'uid': uid,
          'listId': listId,
          'title': 'Batch Active',
          'order': 1000.0,
          'isCompleted': false,
          'completedAt': null,
          'deletedAt': null,
        });

        await fakeFirestore.collection('tasks').doc('batch-comp').set({
          'taskId': 'batch-comp',
          'uid': uid,
          'listId': listId,
          'title': 'Batch Completed',
          'order': 2000.0,
          'isCompleted': true,
          'completedAt': Timestamp.fromDate(DateTime(2026, 9, 20, 10, 0)),
          'deletedAt': null,
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              firebaseAuthProvider.overrideWithValue(mockAuth),
              firestoreProvider.overrideWithValue(fakeFirestore),
              currentUidProvider.overrideWithValue(uid),
              sharedPreferencesProvider.overrideWithValue(prefs),
            ],
            child: MaterialApp(home: ListDetailScreen(list: listModel)),
          ),
        );
        await tester.pumpAndSettle();

        // In Manual sort mode: active task has drag listener, drag handle is removed
        expect(
          find.byType(ReorderableDelayedDragStartListener),
          findsOneWidget,
        );
        expect(find.byKey(const Key('taskDragHandle_batch-act')), findsNothing);
        expect(
          find.byKey(const Key('taskDragHandle_batch-comp')),
          findsNothing,
        );

        // Double-tap active task to enter batch selection mode
        await tester.tap(find.text('Batch Active'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('Batch Active'));
        await tester.pumpAndSettle();

        // Selection mode is active: AppBar shows "1 selected"
        expect(find.byKey(const Key('selectionCountTitle')), findsOneWidget);
        expect(find.text('1 selected'), findsOneWidget);

        // Tap the completed task's selection checkbox
        expect(
          find.byKey(const Key('taskSelectCheckbox_batch-comp')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('taskSelectCheckbox_batch-comp')),
        );
        await tester.pumpAndSettle();

        // Selection count now reflects both active and completed tasks
        expect(find.text('2 selected'), findsOneWidget);
      },
    );
  });
}
