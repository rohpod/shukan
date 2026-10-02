import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/lists/data/list.dart';
import 'package:shukan/features/lists/presentation/list_detail_screen.dart';
import 'package:shukan/features/tasks/data/task_repository.dart';
import 'package:shukan/features/tasks/domain/task_priority_filter.dart';
import 'package:shukan/features/tasks/presentation/task_list_screen.dart';
import 'package:shukan/features/tasks/providers/task_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

Future<void> _doubleTapRow(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapRow(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

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

  group('Batch selection and multi-task actions', () {
    testWidgets(
      'double tap enters selection mode, tap toggles, and deselecting last exits',
      (tester) async {
        await fakeFirestore.collection('tasks').doc('t2').set({
          'taskId': 't2',
          'uid': uid,
          'listId': listId,
          'title': 'Write unit tests',
          'deletedAt': null,
        });

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
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: MaterialApp(home: ListDetailScreen(list: list)),
          ),
        );
        await tester.pumpAndSettle();

        // Initially normal AppBar
        expect(find.byKey(const Key('listDetailTitle')), findsOneWidget);
        expect(find.byKey(const Key('selectionCountTitle')), findsNothing);

        // Double tap first task row
        await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));

        // Selection mode active
        expect(find.byKey(const Key('listDetailTitle')), findsNothing);
        expect(find.byKey(const Key('selectionCloseButton')), findsOneWidget);
        expect(find.byKey(const Key('selectionMoveButton')), findsOneWidget);
        expect(find.byKey(const Key('selectionDeleteButton')), findsOneWidget);
        expect(find.byKey(const Key('selectionCountTitle')), findsOneWidget);
        expect(find.text('1 selected'), findsOneWidget);

        // Tap second task row to toggle it into selection
        await _tapRow(tester, find.byKey(const Key('taskItem_t2')));
        expect(find.text('2 selected'), findsOneWidget);

        // Tap second task row again to deselect it
        await _tapRow(tester, find.byKey(const Key('taskItem_t2')));
        expect(find.text('1 selected'), findsOneWidget);

        // Tap first task row to deselect the last selected task -> exits mode
        await _tapRow(tester, find.byKey(const Key('taskItem_t1')));

        expect(find.byKey(const Key('listDetailTitle')), findsOneWidget);
        expect(find.byKey(const Key('selectionCountTitle')), findsNothing);
      },
    );

    testWidgets('selectionCloseButton exits selection mode', (tester) async {
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
            taskRepositoryProvider.overrideWithValue(
              TaskRepository(fakeFirestore),
            ),
          ],
          child: MaterialApp(home: ListDetailScreen(list: list)),
        ),
      );
      await tester.pumpAndSettle();

      await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));
      expect(find.byKey(const Key('selectionCountTitle')), findsOneWidget);

      await tester.tap(find.byKey(const Key('selectionCloseButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('selectionCountTitle')), findsNothing);
      expect(find.byKey(const Key('listDetailTitle')), findsOneWidget);
    });

    testWidgets(
      'while selecting, row buttons are disabled, drag handle hidden, and tapping does not open edit dialog',
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
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: MaterialApp(home: ListDetailScreen(list: list)),
          ),
        );
        await tester.pumpAndSettle();

        // Enter selection mode
        await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));

        // Verify row buttons disabled
        final moveBtn = tester.widget<IconButton>(
          find.byKey(const Key('moveTaskButton_t1')),
        );
        final editBtn = tester.widget<IconButton>(
          find.byKey(const Key('editTaskButton_t1')),
        );
        final delBtn = tester.widget<IconButton>(
          find.byKey(const Key('deleteTaskButton_t1')),
        );
        expect(moveBtn.onPressed, isNull);
        expect(editBtn.onPressed, isNull);
        expect(delBtn.onPressed, isNull);

        // Verify drag handle is hidden
        expect(find.byKey(const Key('taskDragHandle_t1')), findsNothing);

        // Tap row -> toggles selection instead of opening edit dialog
        await _tapRow(tester, find.byKey(const Key('taskItem_t1')));
        expect(find.text('Edit Task'), findsNothing);

        // Now outside selection mode, tap row opens edit dialog
        await _tapRow(tester, find.byKey(const Key('taskItem_t1')));
        expect(find.text('Edit Task'), findsOneWidget);
      },
    );

    testWidgets(
      'delete flow: shows confirmation dialog, Cancel keeps tasks, Confirm soft-deletes and exits',
      (tester) async {
        await fakeFirestore.collection('tasks').doc('t2').set({
          'taskId': 't2',
          'uid': uid,
          'listId': listId,
          'title': 'Task 2',
          'deletedAt': null,
        });

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
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: MaterialApp(home: ListDetailScreen(list: list)),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Single selection: verify singular wording
        await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));

        await tester.tap(find.byKey(const Key('selectionDeleteButton')));
        await tester.pumpAndSettle();

        expect(find.text('Delete 1 task?'), findsOneWidget);
        expect(
          find.text('Tasks will be moved to Recently Deleted.'),
          findsOneWidget,
        );

        // Tap Cancel
        await tester.tap(find.byKey(const Key('cancelBatchDeleteButton')));
        await tester.pumpAndSettle();

        // Selection still active
        expect(find.text('1 selected'), findsOneWidget);

        // 2. Multi selection: select t2 as well
        await _tapRow(tester, find.byKey(const Key('taskItem_t2')));
        expect(find.text('2 selected'), findsOneWidget);

        await tester.tap(find.byKey(const Key('selectionDeleteButton')));
        await tester.pumpAndSettle();

        expect(find.text('Delete 2 tasks?'), findsOneWidget);

        // Tap Confirm
        await tester.tap(find.byKey(const Key('confirmBatchDeleteButton')));
        await tester.pumpAndSettle();

        // Soft-deleted in Firestore
        final doc1 = await fakeFirestore.collection('tasks').doc('t1').get();
        final doc2 = await fakeFirestore.collection('tasks').doc('t2').get();
        expect(doc1.data()!['deletedAt'], isNotNull);
        expect(doc2.data()!['deletedAt'], isNotNull);

        // Exited selection mode and shows SnackBar
        expect(find.byKey(const Key('selectionCountTitle')), findsNothing);
        expect(find.text('2 tasks deleted'), findsOneWidget);
      },
    );

    testWidgets(
      'move flow: excludes current list, moves selected tasks, and exits selection mode',
      (tester) async {
        await fakeFirestore.collection('lists').doc('dest-list').set({
          'listId': 'dest-list',
          'uid': uid,
          'name': 'Personal List',
          'isDefault': false,
        });

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
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: MaterialApp(home: ListDetailScreen(list: list)),
          ),
        );
        await tester.pumpAndSettle();

        await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));

        await tester.tap(find.byKey(const Key('selectionMoveButton')));
        await tester.pumpAndSettle();

        expect(find.text('Move 1 task to list'), findsOneWidget);
        expect(find.byKey(Key('moveTargetList_$listId')), findsNothing);
        expect(
          find.byKey(const Key('moveTargetList_dest-list')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('moveTargetList_dest-list')));
        await tester.pumpAndSettle();

        final doc = await fakeFirestore.collection('tasks').doc('t1').get();
        expect(doc.data()!['listId'], equals('dest-list'));

        expect(find.byKey(const Key('selectionCountTitle')), findsNothing);
        expect(find.text('1 task moved to "Personal List"'), findsOneWidget);
      },
    );

    testWidgets(
      'move flow edge case: shows "No other lists available" when no other lists exist',
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
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: MaterialApp(home: ListDetailScreen(list: list)),
          ),
        );
        await tester.pumpAndSettle();

        await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));

        await tester.tap(find.byKey(const Key('selectionMoveButton')));
        await tester.pumpAndSettle();

        expect(find.text('No other lists available'), findsOneWidget);

        await tester.tap(find.byKey(const Key('cancelMoveTaskButton')));
        await tester.pumpAndSettle();
        expect(find.text('1 selected'), findsOneWidget);
      },
    );

    testWidgets(
      'back navigation clears selection first and pops only when not selecting',
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
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => ElevatedButton(
                  key: const Key('openScreenButton'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ListDetailScreen(list: list),
                    ),
                  ),
                  child: const Text('Open Screen'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to ListDetailScreen
        await tester.tap(find.byKey(const Key('openScreenButton')));
        await tester.pumpAndSettle();

        expect(find.byType(ListDetailScreen), findsOneWidget);

        // Enter selection mode
        await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));
        expect(find.text('1 selected'), findsOneWidget);

        // Trigger system back
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // Selection should be cleared, but still on ListDetailScreen
        expect(find.text('1 selected'), findsNothing);
        expect(find.byType(ListDetailScreen), findsOneWidget);
        expect(find.byKey(const Key('listDetailTitle')), findsOneWidget);

        // Second system back pops the screen
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(ListDetailScreen), findsNothing);
        expect(find.byKey(const Key('openScreenButton')), findsOneWidget);
      },
    );

    testWidgets(
      'task removed from stream while selected prunes from selection',
      (tester) async {
        await fakeFirestore.collection('tasks').doc('t2').set({
          'taskId': 't2',
          'uid': uid,
          'listId': listId,
          'title': 'Task 2',
          'deletedAt': null,
        });

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
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: MaterialApp(home: ListDetailScreen(list: list)),
          ),
        );
        await tester.pumpAndSettle();

        // Select t1 and t2
        await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));
        await _tapRow(tester, find.byKey(const Key('taskItem_t2')));
        expect(find.text('2 selected'), findsOneWidget);

        // Delete t1 from Firestore stream
        await fakeFirestore.collection('tasks').doc('t1').delete();
        await tester.pumpAndSettle();

        // t1 is pruned, count drops to 1
        expect(find.text('1 selected'), findsOneWidget);

        // Delete t2 from Firestore stream
        await fakeFirestore.collection('tasks').doc('t2').delete();
        await tester.pumpAndSettle();

        // Selection mode exited
        expect(find.byKey(const Key('selectionCountTitle')), findsNothing);
        expect(find.byKey(const Key('listDetailTitle')), findsOneWidget);
      },
    );

    testWidgets(
      'selected tasks hidden by a filter change are dropped from the selection and count',
      (tester) async {
        await fakeFirestore.collection('tasks').doc('t2').set({
          'taskId': 't2',
          'uid': uid,
          'listId': listId,
          'title': 'Task 2',
          'priority': 'high',
          'deletedAt': null,
        });

        await fakeFirestore.collection('tasks').doc('t1').set({
          'taskId': 't1',
          'uid': uid,
          'listId': listId,
          'title': 'Deploy project',
          'priority': 'none',
          'deletedAt': null,
        });

        final list = ListModel(
          listId: listId,
          uid: uid,
          name: 'Work Projects',
          isDefault: false,
        );

        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              firebaseAuthProvider.overrideWithValue(mockAuth),
              firestoreProvider.overrideWithValue(fakeFirestore),
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: Consumer(
              builder: (context, ref, child) {
                container = ProviderScope.containerOf(context);
                return MaterialApp(home: ListDetailScreen(list: list));
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Select t1 and t2
        await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));
        await _tapRow(tester, find.byKey(const Key('taskItem_t2')));
        expect(find.text('2 selected'), findsOneWidget);

        // Change priority filter to high (which filters out t1)
        await container
            .read(taskPriorityFilterProvider(listId).notifier)
            .setFilter(TaskPriorityFilter.high);
        await tester.pumpAndSettle();

        // t1 is filtered out and pruned from selection
        expect(find.text('1 selected'), findsOneWidget);
        expect(find.byKey(const Key('taskSelectCheckbox_t2')), findsOneWidget);
        expect(find.byKey(const Key('taskSelectCheckbox_t1')), findsNothing);
      },
    );

    testWidgets(
      'selection is dropped when leaving and re-entering the screen (autoDispose)',
      (tester) async {
        final list = ListModel(
          listId: listId,
          uid: uid,
          name: 'Work Projects',
          isDefault: false,
        );

        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              firebaseAuthProvider.overrideWithValue(mockAuth),
              firestoreProvider.overrideWithValue(fakeFirestore),
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: Builder(
                builder: (context) => ElevatedButton(
                  key: const Key('openScreenButton'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ListDetailScreen(list: list),
                    ),
                  ),
                  child: const Text('Open Screen'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open ListDetailScreen
        await tester.tap(find.byKey(const Key('openScreenButton')));
        await tester.pumpAndSettle();

        // Select t1
        await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));
        expect(find.text('1 selected'), findsOneWidget);

        // Pop the screen back to home
        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();

        // Open ListDetailScreen again
        await tester.tap(find.byKey(const Key('openScreenButton')));
        await tester.pumpAndSettle();

        // Selection should be empty
        expect(find.byKey(const Key('selectionCountTitle')), findsNothing);
        expect(find.byKey(const Key('listDetailTitle')), findsOneWidget);
      },
    );

    testWidgets(
      'tapping edit button enters selection mode at 0 selected with actions disabled, and selecting enables them',
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
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: MaterialApp(home: ListDetailScreen(list: list)),
          ),
        );
        await tester.pumpAndSettle();

        // Verify editTasksButton is present in the normal AppBar
        final editButton = find.byKey(const Key('editTasksButton'));
        expect(editButton, findsOneWidget);

        // Tap the editTasksButton
        await tester.tap(editButton);
        await tester.pumpAndSettle();

        // Selection mode is now active with '0 selected'
        expect(find.byKey(const Key('listDetailTitle')), findsNothing);
        expect(find.byKey(const Key('selectionCloseButton')), findsOneWidget);
        expect(find.byKey(const Key('selectionCountTitle')), findsOneWidget);
        expect(find.text('0 selected'), findsOneWidget);

        // Move and Delete buttons are disabled
        final moveBtn = tester.widget<IconButton>(
          find.byKey(const Key('selectionMoveButton')),
        );
        final delBtn = tester.widget<IconButton>(
          find.byKey(const Key('selectionDeleteButton')),
        );
        expect(moveBtn.onPressed, isNull);
        expect(delBtn.onPressed, isNull);

        // Selection checkbox should now be visible on t1
        expect(find.byKey(const Key('taskSelectCheckbox_t1')), findsOneWidget);

        // Tap the task item to select it
        await _tapRow(tester, find.byKey(const Key('taskItem_t1')));

        // Count updates and buttons become enabled
        expect(find.text('1 selected'), findsOneWidget);
        final moveBtnEnabled = tester.widget<IconButton>(
          find.byKey(const Key('selectionMoveButton')),
        );
        final delBtnEnabled = tester.widget<IconButton>(
          find.byKey(const Key('selectionDeleteButton')),
        );
        expect(moveBtnEnabled.onPressed, isNotNull);
        expect(delBtnEnabled.onPressed, isNotNull);

        // Tapping selectionCloseButton exits selection mode
        await tester.tap(find.byKey(const Key('selectionCloseButton')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('selectionCountTitle')), findsNothing);
        expect(find.byKey(const Key('listDetailTitle')), findsOneWidget);
        expect(find.byKey(const Key('editTasksButton')), findsOneWidget);
      },
    );

    testWidgets(
      'edit button is hidden when list has no tasks, and appears when task is added',
      (tester) async {
        // Delete t1 seeded in setUp
        await fakeFirestore.collection('tasks').doc('t1').delete();

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
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: MaterialApp(home: ListDetailScreen(list: list)),
          ),
        );
        await tester.pumpAndSettle();

        // Edit button should be hidden for empty list
        expect(find.byKey(const Key('editTasksButton')), findsNothing);

        // Add a task to Firestore
        await fakeFirestore.collection('tasks').doc('t-new').set({
          'taskId': 't-new',
          'uid': uid,
          'listId': listId,
          'title': 'New Task',
          'deletedAt': null,
        });
        await tester.pumpAndSettle();

        // Edit button should now appear
        expect(find.byKey(const Key('editTasksButton')), findsOneWidget);
      },
    );

    testWidgets('edit button is hidden when filters hide all tasks', (
      tester,
    ) async {
      await fakeFirestore.collection('tasks').doc('t1').update({
        'priority': 'low',
      });

      final list = ListModel(
        listId: listId,
        uid: uid,
        name: 'Work Projects',
        isDefault: false,
      );

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(mockAuth),
            firestoreProvider.overrideWithValue(fakeFirestore),
            taskRepositoryProvider.overrideWithValue(
              TaskRepository(fakeFirestore),
            ),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(home: ListDetailScreen(list: list));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Edit button is visible initially
      expect(find.byKey(const Key('editTasksButton')), findsOneWidget);

      // Filter for high priority (which hides the low priority task)
      await container
          .read(taskPriorityFilterProvider(listId).notifier)
          .setFilter(TaskPriorityFilter.high);
      await tester.pumpAndSettle();

      // Edit button is now hidden
      expect(find.byKey(const Key('editTasksButton')), findsNothing);
    });

    testWidgets(
      'batch delete shows Undo action and tapping Undo restores all deleted tasks',
      (tester) async {
        await fakeFirestore.collection('tasks').doc('t2').set({
          'taskId': 't2',
          'uid': uid,
          'listId': listId,
          'title': 'Task 2',
          'deletedAt': null,
        });

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
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: MaterialApp(home: ListDetailScreen(list: list)),
          ),
        );
        await tester.pumpAndSettle();

        // Select t1 and t2
        await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));
        await _tapRow(tester, find.byKey(const Key('taskItem_t2')));
        expect(find.text('2 selected'), findsOneWidget);

        // Delete
        await tester.tap(find.byKey(const Key('selectionDeleteButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirmBatchDeleteButton')));
        await tester.pumpAndSettle();

        // Verify soft-deleted
        var doc1 = await fakeFirestore.collection('tasks').doc('t1').get();
        var doc2 = await fakeFirestore.collection('tasks').doc('t2').get();
        expect(doc1.data()!['deletedAt'], isNotNull);
        expect(doc2.data()!['deletedAt'], isNotNull);

        // Verify SnackBar and Undo action
        expect(find.text('2 tasks deleted'), findsOneWidget);
        expect(find.byKey(const Key('undoBatchDeleteButton')), findsOneWidget);

        // Tap Undo
        await tester.tap(find.byKey(const Key('undoBatchDeleteButton')));
        await tester.pumpAndSettle();

        // Both tasks restored
        doc1 = await fakeFirestore.collection('tasks').doc('t1').get();
        doc2 = await fakeFirestore.collection('tasks').doc('t2').get();
        expect(doc1.data()!['deletedAt'], isNull);
        expect(doc2.data()!['deletedAt'], isNull);
        expect(find.text('Deploy project'), findsOneWidget);
        expect(find.text('Task 2'), findsOneWidget);
      },
    );

    testWidgets(
      'batch move shows Undo action and tapping Undo moves tasks back to source list',
      (tester) async {
        await fakeFirestore.collection('lists').doc('dest-list').set({
          'listId': 'dest-list',
          'uid': uid,
          'name': 'Personal List',
          'isDefault': false,
        });

        await fakeFirestore.collection('tasks').doc('t2').set({
          'taskId': 't2',
          'uid': uid,
          'listId': listId,
          'title': 'Task 2',
          'deletedAt': null,
        });

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
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: MaterialApp(home: ListDetailScreen(list: list)),
          ),
        );
        await tester.pumpAndSettle();

        // Select t1 and t2
        await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));
        await _tapRow(tester, find.byKey(const Key('taskItem_t2')));

        // Tap move
        await tester.tap(find.byKey(const Key('selectionMoveButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('moveTargetList_dest-list')));
        await tester.pumpAndSettle();

        // Verify moved
        var doc1 = await fakeFirestore.collection('tasks').doc('t1').get();
        var doc2 = await fakeFirestore.collection('tasks').doc('t2').get();
        expect(doc1.data()!['listId'], equals('dest-list'));
        expect(doc2.data()!['listId'], equals('dest-list'));

        // Verify SnackBar and Undo action
        expect(find.text('2 tasks moved to "Personal List"'), findsOneWidget);
        expect(find.byKey(const Key('undoMoveTasksButton')), findsOneWidget);

        // Tap Undo
        await tester.tap(find.byKey(const Key('undoMoveTasksButton')));
        await tester.pumpAndSettle();

        // Both tasks moved back to source listId
        doc1 = await fakeFirestore.collection('tasks').doc('t1').get();
        doc2 = await fakeFirestore.collection('tasks').doc('t2').get();
        expect(doc1.data()!['listId'], equals(listId));
        expect(doc2.data()!['listId'], equals(listId));
      },
    );

    testWidgets('batch move Undo shows error snackbar when moving back fails', (
      tester,
    ) async {
      await fakeFirestore.collection('lists').doc('dest-list').set({
        'listId': 'dest-list',
        'uid': uid,
        'name': 'Personal List',
        'isDefault': false,
      });

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
            taskRepositoryProvider.overrideWithValue(
              TaskRepository(fakeFirestore),
            ),
          ],
          child: MaterialApp(home: ListDetailScreen(list: list)),
        ),
      );
      await tester.pumpAndSettle();

      await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));

      await tester.tap(find.byKey(const Key('selectionMoveButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('moveTargetList_dest-list')));
      await tester.pumpAndSettle();

      // Delete the original source list so move back fails
      await fakeFirestore.collection('lists').doc(listId).delete();

      // Tap Undo
      await tester.tap(find.byKey(const Key('undoMoveTasksButton')));
      await tester.pumpAndSettle();

      // Verify failure snackbar appears
      expect(
        find.textContaining(
          'Failed to undo move: Invalid argument(s): List not found: $listId',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'tapping batch delete Undo after popping ListDetailScreen does not throw',
      (tester) async {
        final list = ListModel(
          listId: listId,
          uid: uid,
          name: 'Work Projects',
          isDefault: false,
        );

        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              firebaseAuthProvider.overrideWithValue(mockAuth),
              firestoreProvider.overrideWithValue(fakeFirestore),
              taskRepositoryProvider.overrideWithValue(
                TaskRepository(fakeFirestore),
              ),
            ],
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    key: const Key('openScreenButton'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ListDetailScreen(list: list),
                      ),
                    ),
                    child: const Text('Open Screen'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open ListDetailScreen
        await tester.tap(find.byKey(const Key('openScreenButton')));
        await tester.pumpAndSettle();

        // Select and delete t1
        await _doubleTapRow(tester, find.byKey(const Key('taskItem_t1')));
        await tester.tap(find.byKey(const Key('selectionDeleteButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirmBatchDeleteButton')));
        await tester.pumpAndSettle();

        // Pop ListDetailScreen while the SnackBar is visible on root ScaffoldMessenger
        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();

        expect(find.byType(ListDetailScreen), findsNothing);
        expect(find.byKey(const Key('undoBatchDeleteButton')), findsOneWidget);

        // Tap Undo on root ScaffoldMessenger
        await tester.tap(find.byKey(const Key('undoBatchDeleteButton')));
        await tester.pumpAndSettle();

        // Verify task was restored without throwing any disposed ref exception
        final doc = await fakeFirestore.collection('tasks').doc('t1').get();
        expect(doc.data()!['deletedAt'], isNull);
      },
    );
  });
}
