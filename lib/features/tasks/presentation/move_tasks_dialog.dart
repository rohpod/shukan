import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lists/providers/list_providers.dart';

/// Dialog allowing the user to pick a target list to move selected tasks into.
class MoveTasksDialog extends ConsumerWidget {
  final String excludeListId;
  final int taskCount;

  const MoveTasksDialog({
    super.key,
    required this.excludeListId,
    required this.taskCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listsAsync = ref.watch(listsForUserProvider);
    final titleText = taskCount == 1
        ? 'Move 1 task to list'
        : 'Move $taskCount tasks to list';

    return AlertDialog(
      title: Text(titleText),
      content: SizedBox(
        width: double.maxFinite,
        child: listsAsync.when(
          data: (lists) {
            final targetLists = lists
                .where((l) => l.listId != excludeListId)
                .toList();

            if (targetLists.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No other lists available',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              itemCount: targetLists.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final list = targetLists[index];
                return ListTile(
                  key: Key('moveTargetList_${list.listId}'),
                  title: Text(list.name),
                  onTap: () => Navigator.of(context).pop(list),
                );
              },
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Center(child: Text('Error loading lists: $e')),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancelMoveTaskButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
