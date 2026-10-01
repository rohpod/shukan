import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/ui/feedback_snackbar.dart';
import '../../auth/providers/auth_providers.dart';
import '../../export/export_service.dart';
import '../../tasks/data/task.dart';
import '../../tasks/presentation/move_tasks_dialog.dart';
import '../../tasks/presentation/task_list_screen.dart';
import '../../tasks/providers/task_providers.dart';
import '../../tasks/providers/task_selection_providers.dart';
import '../../tasks/providers/task_sort_providers.dart';
import '../data/list.dart';

class ListDetailScreen extends ConsumerWidget {
  final ListModel list;
  final void Function(String content, String filename)? downloadTrigger;

  const ListDetailScreen({super.key, required this.list, this.downloadTrigger});

  Future<void> _exportList(BuildContext context, WidgetRef ref) async {
    try {
      final exportService = ref.read(exportServiceProvider);

      final tasksAsync = ref.read(tasksForListProvider(list.listId));
      final List<Task> tasks;
      if (tasksAsync.hasValue) {
        tasks = tasksAsync.value!;
      } else {
        final firestore = ref.read(firestoreProvider);
        final snapshot = await firestore
            .collection('tasks')
            .where('listId', isEqualTo: list.listId)
            .where('deletedAt', isNull: true)
            .get();
        tasks = snapshot.docs.map(Task.fromFirestore).toList();
      }

      await exportService.exportAndDownload(
        listName: list.name,
        tasks: tasks,
        downloadTrigger: downloadTrigger,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported "${list.name}" to markdown')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to export list: $e')));
      }
    }
  }

  Future<void> _handleBatchDelete(
    BuildContext context,
    WidgetRef ref,
    List<Task> selectedTasks,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final count = selectedTasks.length;
    final titleText = count == 1 ? 'Delete 1 task?' : 'Delete $count tasks?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(titleText),
        content: const Text('Tasks will be moved to Recently Deleted.'),
        actions: [
          TextButton(
            key: const Key('cancelBatchDeleteButton'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmBatchDeleteButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final taskRepo = ref.read(taskRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    final taskIds = selectedTasks.map((t) => t.taskId).toList();

    try {
      await taskRepo.softDeleteTasks(taskIds);
      ref.read(taskSelectionProvider(list.listId).notifier).clear();
      ref.read(isTaskSelectionModeActiveProvider(list.listId).notifier).exit();
      final message = count == 1 ? '1 task deleted' : '$count tasks deleted';
      showFeedbackSnackBar(
        messenger,
        message,
        actionLabel: 'Undo',
        actionKey: const Key('undoBatchDeleteButton'),
        onAction: uid == null
            ? null
            : () => taskRepo.restoreTasks(
                uid: uid,
                taskIds: taskIds,
                defaultListId: list.listId,
              ),
        actionErrorPrefix: 'Failed to undo deletion',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete tasks: $e')),
      );
    }
  }

  Future<void> _handleBatchMove(
    BuildContext context,
    WidgetRef ref,
    List<Task> selectedTasks,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final count = selectedTasks.length;
    final targetList = await showDialog<ListModel>(
      context: context,
      builder: (dialogContext) =>
          MoveTasksDialog(excludeListId: list.listId, taskCount: count),
    );

    if (targetList == null) return;

    final taskRepo = ref.read(taskRepositoryProvider);
    final taskIds = selectedTasks.map((t) => t.taskId).toList();

    try {
      await taskRepo.moveTasksToList(taskIds, targetList.listId);
      ref.read(taskSelectionProvider(list.listId).notifier).clear();
      ref.read(isTaskSelectionModeActiveProvider(list.listId).notifier).exit();
      final message = count == 1
          ? '1 task moved to "${targetList.name}"'
          : '$count tasks moved to "${targetList.name}"';
      showFeedbackSnackBar(
        messenger,
        message,
        actionLabel: 'Undo',
        actionKey: const Key('undoMoveTasksButton'),
        onAction: () => taskRepo.moveTasksToList(taskIds, list.listId),
        actionErrorPrefix: 'Failed to undo move',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to move tasks: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTasks = ref.watch(selectedTasksProvider(list.listId));
    final isSelectionActive = ref.watch(
      isSelectionModeActiveProvider(list.listId),
    );
    final sortedTasksAsync = ref.watch(sortedTasksForListProvider(list.listId));
    final completedTasksAsync = ref.watch(
      completedTasksForListProvider(list.listId),
    );
    final hasTasksToSelect =
        (sortedTasksAsync.value?.isNotEmpty ?? false) ||
        (completedTasksAsync.value?.isNotEmpty ?? false);

    return PopScope(
      canPop: !isSelectionActive,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          ref.read(taskSelectionProvider(list.listId).notifier).clear();
          ref
              .read(isTaskSelectionModeActiveProvider(list.listId).notifier)
              .exit();
        }
      },
      child: Scaffold(
        appBar: isSelectionActive
            ? AppBar(
                leading: IconButton(
                  key: const Key('selectionCloseButton'),
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    ref
                        .read(taskSelectionProvider(list.listId).notifier)
                        .clear();
                    ref
                        .read(
                          isTaskSelectionModeActiveProvider(list.listId)
                              .notifier,
                        )
                        .exit();
                  },
                ),
                title: Text(
                  '${selectedTasks.length} selected',
                  key: const Key('selectionCountTitle'),
                ),
                actions: [
                  IconButton(
                    key: const Key('selectionMoveButton'),
                    icon: const Icon(Icons.drive_file_move_outlined),
                    tooltip: 'Move to list',
                    onPressed: selectedTasks.isEmpty
                        ? null
                        : () => _handleBatchMove(context, ref, selectedTasks),
                  ),
                  IconButton(
                    key: const Key('selectionDeleteButton'),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                    onPressed: selectedTasks.isEmpty
                        ? null
                        : () => _handleBatchDelete(context, ref, selectedTasks),
                  ),
                ],
              )
            : AppBar(
                title: Text(list.name, key: const Key('listDetailTitle')),
                actions: [
                  if (hasTasksToSelect)
                    IconButton(
                      key: const Key('editTasksButton'),
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit tasks',
                      onPressed: () => ref
                          .read(
                            isTaskSelectionModeActiveProvider(list.listId)
                                .notifier,
                          )
                          .enter(),
                    ),
                  IconButton(
                    key: const Key('exportListButton'),
                    icon: const Icon(Icons.file_download_outlined),
                    tooltip: 'Export',
                    onPressed: () => _exportList(context, ref),
                  ),
                ],
              ),
        body: TaskListScreen(key: ValueKey(list.listId), listId: list.listId),
      ),
    );
  }
}
