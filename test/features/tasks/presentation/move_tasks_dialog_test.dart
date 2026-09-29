import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/lists/data/list.dart';
import 'package:shukan/features/lists/providers/list_providers.dart';
import 'package:shukan/features/tasks/presentation/move_tasks_dialog.dart';

void main() {
  const currentListId = 'current-list';

  final list1 = ListModel(
    listId: currentListId,
    uid: 'user-1',
    name: 'Current List',
    isDefault: false,
  );
  final list2 = ListModel(
    listId: 'target-list-1',
    uid: 'user-1',
    name: 'Target List 1',
    isDefault: false,
  );
  final list3 = ListModel(
    listId: 'target-list-2',
    uid: 'user-1',
    name: 'Target List 2',
    isDefault: false,
  );

  testWidgets(
    'displays correct singular title and lists excluding current list',
    (tester) async {
      ListModel? selectedList;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listsForUserProvider.overrideWith(
              (ref) => Stream.value([list1, list2, list3]),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedList = await showDialog<ListModel>(
                    context: context,
                    builder: (_) => const MoveTasksDialog(
                      excludeListId: currentListId,
                      taskCount: 1,
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Move 1 task to list'), findsOneWidget);
      expect(
        find.byKey(const Key('moveTargetList_current-list')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('moveTargetList_target-list-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('moveTargetList_target-list-2')),
        findsOneWidget,
      );

      // Tap target list 2
      await tester.tap(find.byKey(const Key('moveTargetList_target-list-2')));
      await tester.pumpAndSettle();

      expect(selectedList, equals(list3));
    },
  );

  testWidgets('displays correct plural title and Cancel button returns null', (
    tester,
  ) async {
    ListModel? selectedList;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listsForUserProvider.overrideWith(
            (ref) => Stream.value([list1, list2]),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedList = await showDialog<ListModel>(
                  context: context,
                  builder: (_) => const MoveTasksDialog(
                    excludeListId: currentListId,
                    taskCount: 5,
                  ),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Move 5 tasks to list'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancelMoveTaskButton')));
    await tester.pumpAndSettle();

    expect(selectedList, isNull);
  });

  testWidgets(
    'displays "No other lists available" when only current list exists',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listsForUserProvider.overrideWith((ref) => Stream.value([list1])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MoveTasksDialog(excludeListId: currentListId, taskCount: 2),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Move 2 tasks to list'), findsOneWidget);
      expect(find.text('No other lists available'), findsOneWidget);
    },
  );
}
