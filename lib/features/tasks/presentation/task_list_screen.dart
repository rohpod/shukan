import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback_snackbar.dart';
import '../../../core/ui/tag_format.dart';
import '../../auth/providers/auth_providers.dart';
import '../../lists/providers/list_providers.dart';
import '../../tags/presentation/widgets/tag_chips_section.dart';
import '../../tags/providers/tag_providers.dart';
import '../data/task.dart';
import '../domain/task_constants.dart';
import '../domain/task_priority_filter.dart';
import '../domain/task_sort_options.dart';
import '../providers/task_providers.dart';
import '../providers/task_selection_providers.dart';
import '../providers/task_sort_providers.dart';
import '../providers/task_tag_filter_providers.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/task_priority_filter_selector.dart';
import 'widgets/task_row_tag_chips.dart';
import 'widgets/task_sort_selector.dart';
import 'widgets/task_tag_filter_selector.dart';
import 'quick_add_bar.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  final String? listId;

  const TaskListScreen({super.key, this.listId});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  final Set<String> _expandedTaskIds = <String>{};

  Future<void> _showTaskDialog(
    BuildContext context,
    String uid,
    String listId, {
    Task? task,
    String? initialTitle,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => TaskDialog(
        uid: uid,
        listId: listId,
        task: task,
        initialTitle: initialTitle,
      ),
    );
  }

  Future<void> _showMoveTaskDialog(BuildContext context, Task task) async {
    final messenger = ScaffoldMessenger.of(context);
    final taskRepo = ref.read(taskRepositoryProvider);
    final originalListId = task.listId;

    final targetListName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _MoveTaskDialog(task: task),
    );

    if (targetListName != null && context.mounted) {
      showFeedbackSnackBar(
        messenger,
        'Task moved to "$targetListName"',
        actionLabel: 'Undo',
        actionKey: const Key('undoMoveTasksButton'),
        onAction: () => taskRepo.moveTaskToList(task.taskId, originalListId),
        actionErrorPrefix: 'Failed to undo move',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) {
      return const Center(child: Text('User not signed in.'));
    }

    final targetListId = widget.listId;
    if (targetListId != null) {
      return _buildContent(context, uid, targetListId);
    }

    final defaultListIdAsync = ref.watch(defaultListIdProvider);
    return defaultListIdAsync.when(
      data: (listId) {
        if (listId == null) {
          return const Center(child: Text('No default list found.'));
        }
        return _buildContent(context, uid, listId);
      },
      loading: () => const Center(
        key: Key('defaultListLoadingIndicator'),
        child: CircularProgressIndicator(),
      ),
      error: (e, _) => Center(child: Text('Error loading default list: $e')),
    );
  }

  Future<void> _showDeleteCompletedDialog(
    BuildContext context,
    String uid,
    String listId,
    List<Task> completedTasks,
    ScaffoldMessengerState scaffoldMessenger,
  ) async {
    final count = completedTasks.length;
    if (count == 0) return;
    final titleText = count == 1
        ? 'Delete 1 completed task?'
        : 'Delete $count completed tasks?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(titleText),
        content: const Text('Tasks will be moved to Recently Deleted.'),
        actions: [
          TextButton(
            key: const Key('cancelDeleteCompletedButton'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmDeleteCompletedButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final taskRepo = ref.read(taskRepositoryProvider);
    final completedTaskIds = completedTasks.map((t) => t.taskId).toList();

    try {
      await taskRepo.softDeleteTasks(completedTaskIds);
      // Clear stale selection state for any deleted tasks
      final currentSelection = ref.read(taskSelectionProvider(listId));
      final remainingSelection = currentSelection
          .where((id) => !completedTaskIds.contains(id))
          .toSet();
      ref
          .read(taskSelectionProvider(listId).notifier)
          .retainOnly(remainingSelection);

      if (!mounted) return;
      final message = count == 1
          ? '1 completed task deleted'
          : '$count completed tasks deleted';
      showFeedbackSnackBar(
        scaffoldMessenger,
        message,
        actionLabel: 'Undo',
        actionKey: const Key('undoDeleteCompletedButton'),
        onAction: () => taskRepo.restoreTasks(
          uid: uid,
          taskIds: completedTaskIds,
          defaultListId: listId,
        ),
        actionErrorPrefix: 'Failed to undo deletion',
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to delete completed tasks: $e')),
      );
    }
  }

  Widget _buildTaskRow({
    required BuildContext context,
    required Task task,
    required String uid,
    required String listId,
    required bool isCompletedSection,
    int? index,
    TaskSortOption? sortOption,
    required Set<String> selectedTaskIds,
    required bool isSelectionMode,
    required ScaffoldMessengerState scaffoldMessenger,
    required Set<String> tagFilter,
  }) {
    final isExpanded = _expandedTaskIds.contains(task.taskId);
    final isSelected = selectedTaskIds.contains(task.taskId);

    final row = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: isSelectionMode && isSelected
              ? Theme.of(context).colorScheme.primaryContainer
                    .withValues(alpha: 0.3)
              : Colors.transparent,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: isSelectionMode
                    ? Checkbox(
                        key: Key('taskSelectCheckbox_${task.taskId}'),
                        value: isSelected,
                        onChanged: (_) {
                          ref
                              .read(taskSelectionProvider(listId).notifier)
                              .toggle(task.taskId);
                        },
                      )
                    : Checkbox(
                        key: Key('taskCompleteCheckbox_${task.taskId}'),
                        value: task.isCompleted,
                        onChanged: (val) async {
                          await ref
                              .read(taskRepositoryProvider)
                              .toggleTaskCompleted(
                                task.taskId,
                                isCompleted: val ?? false,
                              );
                        },
                      ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => ref
                      .read(taskSelectionProvider(listId).notifier)
                      .toggle(task.taskId),
                  child: ListTile(
                    key: Key('taskItem_${task.taskId}'),
                    contentPadding: const EdgeInsets.only(left: 8, right: 8),
                    onTap: isSelectionMode
                        ? () => ref
                              .read(taskSelectionProvider(listId).notifier)
                              .toggle(task.taskId)
                        : () =>
                              _showTaskDialog(context, uid, listId, task: task),
                    title: Text(
                      task.title,
                      key: Key('taskTitle_${task.taskId}'),
                      style: TextStyle(
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: task.isCompleted ? Colors.grey : null,
                      ),
                    ),
                    subtitle:
                        (task.notes.isNotEmpty ||
                            task.url.isNotEmpty ||
                            tagFilter.isNotEmpty)
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (task.notes.isNotEmpty)
                                Text(
                                  task.notes,
                                  key: Key('taskNotes_${task.taskId}'),
                                  style: TextStyle(
                                    color: task.isCompleted
                                        ? Colors.grey
                                        : Colors.grey[700],
                                  ),
                                ),
                              if (task.url.isNotEmpty)
                                Text(
                                  task.url,
                                  key: Key('taskUrl_${task.taskId}'),
                                  style: const TextStyle(
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              if (tagFilter.isNotEmpty)
                                TaskRowTagChips(task: task),
                            ],
                          )
                        : null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (task.subtasks.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Text(
                          '${task.subtasks.where((s) => s['completed'] == true).length}/${task.subtasks.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    IconButton(
                      key: Key('toggleSubtasksButton_${task.taskId}'),
                      icon: Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                      ),
                      tooltip: isExpanded ? 'Hide subtasks' : 'Show subtasks',
                      onPressed: () {
                        setState(() {
                          if (isExpanded) {
                            _expandedTaskIds.remove(task.taskId);
                          } else {
                            _expandedTaskIds.add(task.taskId);
                          }
                        });
                      },
                    ),
                    IconButton(
                      key: Key('moveTaskButton_${task.taskId}'),
                      icon: const Icon(
                        Icons.drive_file_move_outlined,
                        size: 20,
                      ),
                      tooltip: 'Move to List',
                      onPressed: isSelectionMode
                          ? null
                          : () => _showMoveTaskDialog(context, task),
                    ),
                    IconButton(
                      key: Key('editTaskButton_${task.taskId}'),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Edit Task',
                      onPressed: isSelectionMode
                          ? null
                          : () => _showTaskDialog(
                              context,
                              uid,
                              listId,
                              task: task,
                            ),
                    ),
                    IconButton(
                      key: Key('deleteTaskButton_${task.taskId}'),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: 'Delete',
                      onPressed: isSelectionMode
                          ? null
                          : () async {
                              final messenger = scaffoldMessenger;
                              final taskRepo = ref.read(taskRepositoryProvider);
                              try {
                                await taskRepo.softDeleteTask(task.taskId);
                                if (!mounted) return;
                                showFeedbackSnackBar(
                                  messenger,
                                  'Deleted "${task.title}"',
                                  actionLabel: 'Undo',
                                  actionKey: const Key('undoDeleteTaskButton'),
                                  onAction: () => taskRepo.restoreTask(
                                    uid: uid,
                                    taskId: task.taskId,
                                    defaultListId: listId,
                                  ),
                                  actionErrorPrefix: 'Failed to undo deletion',
                                );
                              } catch (e) {
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to delete task: $e'),
                                  ),
                                );
                              }
                            },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (isExpanded) _buildIndentedSubtasks(context, task),
        const Divider(height: 1),
      ],
    );

    if (!isCompletedSection && !isSelectionMode && index != null) {
      return ReorderableDelayedDragStartListener(
        key: ValueKey('taskItemWrapper_${task.taskId}'),
        index: index,
        child: row,
      );
    }

    return KeyedSubtree(
      key: ValueKey('taskItemWrapper_${task.taskId}'),
      child: row,
    );
  }

  Widget _buildCompletedSection({
    required BuildContext context,
    required String uid,
    required String listId,
    required List<Task> completedTasks,
    required bool isCollapsed,
    required Set<String> selectedTaskIds,
    required bool isSelectionMode,
    required ScaffoldMessengerState scaffoldMessenger,
    required Set<String> tagFilter,
  }) {
    if (completedTasks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      key: Key('completedSection_$listId'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 24, thickness: 1),
        InkWell(
          key: Key('completedSectionHeader_$listId'),
          onTap: () {
            ref
                .read(completedSectionCollapsedProvider(listId).notifier)
                .toggle();
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  isCollapsed ? Icons.expand_more : Icons.expand_less,
                  key: Key('completedSectionChevron_$listId'),
                  size: 20,
                  color: Colors.grey[700],
                ),
                const SizedBox(width: 8),
                Text(
                  'Completed (${completedTasks.length})',
                  key: Key('completedSectionTitle_$listId'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const Spacer(),
                if (!isCollapsed)
                  TextButton.icon(
                    key: Key('deleteCompletedButton_$listId'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red[700],
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text(
                      'Delete completed',
                      style: TextStyle(fontSize: 12),
                    ),
                    onPressed: () => _showDeleteCompletedDialog(
                      context,
                      uid,
                      listId,
                      completedTasks,
                      scaffoldMessenger,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!isCollapsed)
          ...completedTasks.map(
            (task) => _buildTaskRow(
              context: context,
              task: task,
              uid: uid,
              listId: listId,
              isCompletedSection: true,
              selectedTaskIds: selectedTaskIds,
              isSelectionMode: isSelectionMode,
              scaffoldMessenger: scaffoldMessenger,
              tagFilter: tagFilter,
            ),
          ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, String uid, String listId) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final tasksAsync = ref.watch(sortedTasksForListProvider(listId));
    final completedTasksAsync = ref.watch(
      completedTasksForListProvider(listId),
    );
    final isCollapsed = ref.watch(completedSectionCollapsedProvider(listId));
    final sortOption = ref.watch(taskSortModeProvider(listId));
    final tagFilter = ref.watch(taskTagFilterProvider(listId));
    final rawTasks =
        ref.watch(tasksForListProvider(listId)).value ?? const <Task>[];
    final activeRawTasks = rawTasks.where((t) => !t.isCompleted).toList();
    final unfilteredActiveCount = activeRawTasks.length;
    final completedTasks = completedTasksAsync.value ?? const <Task>[];
    final listTagEntries =
        ref.watch(tagBrowserEntriesForListProvider(listId)).value ??
        const <TagBrowserEntry>[];

    final selectedTasks = ref.watch(selectedTasksProvider(listId));
    final isSelectionMode = ref.watch(isSelectionModeActiveProvider(listId));
    final selectedTaskIds = selectedTasks.map((t) => t.taskId).toSet();

    void updateSelectionPruning() {
      final active =
          ref.read(sortedTasksForListProvider(listId)).value ?? const <Task>[];
      final completed =
          ref.read(completedTasksForListProvider(listId)).value ??
          const <Task>[];
      final visibleIds = {
        ...active.map((t) => t.taskId),
        ...completed.map((t) => t.taskId),
      };
      ref.read(taskSelectionProvider(listId).notifier).retainOnly(visibleIds);
      if (visibleIds.isEmpty) {
        ref.read(isTaskSelectionModeActiveProvider(listId).notifier).exit();
      }
    }

    ref.listen<AsyncValue<List<Task>>>(sortedTasksForListProvider(listId), (
      previous,
      next,
    ) {
      updateSelectionPruning();
    });

    ref.listen<AsyncValue<List<Task>>>(completedTasksForListProvider(listId), (
      previous,
      next,
    ) {
      updateSelectionPruning();
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TaskSortSelector(viewKey: listId),
                  const SizedBox(width: 8),
                  TaskPriorityFilterSelector(viewKey: listId),
                  const SizedBox(width: 8),
                  TaskTagFilterSelector(viewKey: listId),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: tasksAsync.when(
              data: (activeTasks) {
                final completedSectionWidget = _buildCompletedSection(
                  context: context,
                  uid: uid,
                  listId: listId,
                  completedTasks: completedTasks,
                  isCollapsed: isCollapsed,
                  selectedTaskIds: selectedTaskIds,
                  isSelectionMode: isSelectionMode,
                  scaffoldMessenger: scaffoldMessenger,
                  tagFilter: tagFilter,
                );

                if (activeTasks.isEmpty) {
                  final Widget activeEmptyWidget;
                  if (unfilteredActiveCount > 0) {
                    activeEmptyWidget = EmptyStateView(
                      icon: Icons.filter_alt_off_outlined,
                      message: 'No tasks match your filters',
                      messageKey: const Key('noTasksText'),
                      actionLabel: 'Clear filters',
                      actionKey: Key('clearFiltersButton_$listId'),
                      onAction: () {
                        ref
                            .read(taskPriorityFilterProvider(listId).notifier)
                            .setFilter(TaskPriorityFilter.all);
                        ref
                            .read(taskTagFilterProvider(listId).notifier)
                            .clearAll();
                      },
                    );
                  } else {
                    activeEmptyWidget = EmptyStateView(
                      icon: Icons.inbox_outlined,
                      message: 'No tasks yet',
                      messageKey: const Key('noTasksText'),
                      actionLabel: 'Add task',
                      actionIcon: Icons.add,
                      actionKey: const Key('emptyStateAddTaskButton'),
                      onAction: () => _showTaskDialog(context, uid, listId),
                    );
                  }

                  if (completedTasks.isEmpty) {
                    return activeEmptyWidget;
                  }

                  return ListView(
                    key: const Key('tasksListView'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: activeEmptyWidget,
                      ),
                      completedSectionWidget,
                    ],
                  );
                }

                return ReorderableListView.builder(
                  key: const Key('tasksListView'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, index, animation) {
                    return Material(
                      elevation: 4,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      shadowColor: Theme.of(context).shadowColor
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: child,
                    );
                  },
                  itemCount: activeTasks.length,
                  onReorderItem: (oldIndex, newIndex) async {
                    if (oldIndex == newIndex) return;

                    final priorSortOption = sortOption;

                    final movedTask = activeTasks[oldIndex];
                    final remainingTasks = List<Task>.from(activeTasks)
                      ..removeAt(oldIndex);

                    int targetIndex = newIndex;
                    if (oldIndex < newIndex) {
                      targetIndex -= 1;
                    }
                    targetIndex = targetIndex.clamp(0, remainingTasks.length);

                    final Task? before = targetIndex > 0
                        ? remainingTasks[targetIndex - 1]
                        : null;
                    final Task? after = targetIndex < remainingTasks.length
                        ? remainingTasks[targetIndex]
                        : null;

                    if (before != null &&
                        after != null &&
                        TaskSortUtils.needsRenumbering(
                          before: before,
                          after: after,
                        )) {
                      final updatedList = List<Task>.from(remainingTasks)
                        ..insert(targetIndex, movedTask);
                      final batchMap = <String, double>{};
                      for (int i = 0; i < updatedList.length; i++) {
                        batchMap[updatedList[i].taskId] = (i + 1) * 1000.0;
                      }
                      await ref
                          .read(taskRepositoryProvider)
                          .batchUpdateTaskOrders(batchMap);
                    } else {
                      final newOrder = TaskSortUtils.computeMidpointOrder(
                        before: before,
                        after: after,
                      );
                      await ref
                          .read(taskRepositoryProvider)
                          .updateTaskOrder(movedTask.taskId, newOrder);
                    }

                    if (priorSortOption != TaskSortOption.manual) {
                      await ref
                          .read(taskSortModeProvider(listId).notifier)
                          .setSortMode(TaskSortOption.manual);
                      if (context.mounted) {
                        showFeedbackSnackBar(
                          scaffoldMessenger,
                          'Sort changed from ${priorSortOption.label} to Manual',
                        );
                      }
                    }
                  },
                  itemBuilder: (context, index) {
                    return _buildTaskRow(
                      context: context,
                      task: activeTasks[index],
                      uid: uid,
                      listId: listId,
                      isCompletedSection: false,
                      index: index,
                      sortOption: sortOption,
                      selectedTaskIds: selectedTaskIds,
                      isSelectionMode: isSelectionMode,
                      scaffoldMessenger: scaffoldMessenger,
                      tagFilter: tagFilter,
                    );
                  },
                  footer: completedSectionWidget,
                );
              },
              loading: () => const Center(
                key: Key('tasksLoadingIndicator'),
                child: CircularProgressIndicator(),
              ),
              error: (e, _) => Center(child: Text('Error loading tasks: $e')),
            ),
          ),
          QuickAddBar(
            uid: uid,
            listId: listId,
            expandButtonKey: const Key('addTaskButton'),
            onExpand: (text) =>
                _showTaskDialog(context, uid, listId, initialTitle: text),
          ),
          TagChipsSection(
            contextKey: listId,
            uid: uid,
            entries: listTagEntries,
          ),
        ],
      ),
    );
  }

  Widget _buildIndentedSubtasks(BuildContext context, Task task) {
    return Padding(
      padding: const EdgeInsets.only(left: 48, right: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (task.subtasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Text(
                'No subtasks yet',
                key: Key('noSubtasksText_${task.taskId}'),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          if (task.subtasks.isNotEmpty)
            ReorderableListView.builder(
              key: Key('subtasksList_${task.taskId}'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: task.subtasks.length,
              itemBuilder: (context, index) {
                final subtask = task.subtasks[index];
                final subtaskId = subtask['id'] as String? ?? '';
                final isCompleted = subtask['completed'] as bool? ?? false;
                final title = subtask['title'] as String? ?? '';

                return Container(
                  key: Key('subtaskRow_$subtaskId'),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.drag_handle,
                            size: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: Checkbox(
                          key: Key('subtaskCheckbox_$subtaskId'),
                          value: isCompleted,
                          visualDensity: VisualDensity.compact,
                          onChanged: (val) async {
                            await ref
                                .read(taskRepositoryProvider)
                                .toggleSubtask(
                                  task.taskId,
                                  subtaskId,
                                  completed: val ?? false,
                                );
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          key: Key('subtaskTitle_$subtaskId'),
                          style: TextStyle(
                            fontSize: 14,
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            color: isCompleted ? Colors.grey : null,
                          ),
                        ),
                      ),
                      IconButton(
                        key: Key('deleteSubtaskButton_$subtaskId'),
                        icon: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.grey,
                        ),
                        tooltip: 'Delete subtask',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () async {
                          await ref
                              .read(taskRepositoryProvider)
                              .removeSubtask(task.taskId, subtaskId);
                        },
                      ),
                    ],
                  ),
                );
              },
              onReorderItem: (oldIndex, newIndex) async {
                final items = List<Map<String, dynamic>>.from(task.subtasks);
                final item = items.removeAt(oldIndex);
                items.insert(newIndex, item);
                final orderedIds = items.map((e) => e['id'] as String).toList();
                await ref
                    .read(taskRepositoryProvider)
                    .reorderSubtasks(task.taskId, orderedIds);
              },
            ),
          const SizedBox(height: 6),
          _AddSubtaskInputRow(taskId: task.taskId),
        ],
      ),
    );
  }
}

class _AddSubtaskInputRow extends ConsumerStatefulWidget {
  final String taskId;

  const _AddSubtaskInputRow({required this.taskId});

  @override
  ConsumerState<_AddSubtaskInputRow> createState() =>
      _AddSubtaskInputRowState();
}

class _AddSubtaskInputRowState extends ConsumerState<_AddSubtaskInputRow> {
  late final TextEditingController _controller;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _isAdding = true);
    try {
      await ref.read(taskRepositoryProvider).addSubtask(widget.taskId, text);
      _controller.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to add subtask: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.subdirectory_arrow_right,
          size: 16,
          color: Colors.grey,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            key: Key('addSubtaskInput_${widget.taskId}'),
            controller: _controller,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Add subtask...',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: UnderlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          key: Key('addSubtaskButton_${widget.taskId}'),
          icon: _isAdding
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add, size: 18),
          tooltip: 'Add subtask',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: _isAdding ? null : _submit,
        ),
      ],
    );
  }
}

class TaskDialog extends ConsumerStatefulWidget {
  final String uid;
  final String listId;
  final Task? task;
  final DateTime? initialDueDate;
  final String? initialTitle;

  const TaskDialog({
    super.key,
    required this.uid,
    required this.listId,
    this.task,
    this.initialDueDate,
    this.initialTitle,
  });

  @override
  ConsumerState<TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends ConsumerState<TaskDialog> {
  bool get isEditing => widget.task != null;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _urlController;
  late final TextEditingController _tagInputController;

  late String _priority;
  DateTime? _dueDate;
  String? _dueTime;
  late int _earlyReminderMinutes;
  late String _repeatRule;
  late List<String> _tagIds;

  bool _isSaving = false;

  static const List<int> _defaultReminderOptions = [0, 5, 10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.task?.title ?? widget.initialTitle ?? '',
    );
    _notesController = TextEditingController(text: widget.task?.notes ?? '');
    _urlController = TextEditingController(text: widget.task?.url ?? '');
    _tagInputController = TextEditingController();

    final p = widget.task?.priority;
    _priority = (p != null && p.isNotEmpty) ? p : 'none';
    if (!kTaskPriorities.contains(_priority)) {
      _priority = 'none';
    }

    _dueDate = widget.task?.dueDate ?? widget.initialDueDate;
    _dueTime = widget.task?.dueTime;
    _earlyReminderMinutes = widget.task?.earlyReminderMinutes ?? 0;

    final r = widget.task?.repeatRule;
    _repeatRule = (r != null && r.isNotEmpty) ? r : 'none';
    if (!kTaskRepeatRules.contains(_repeatRule)) {
      _repeatRule = 'none';
    }

    _tagIds = widget.task != null
        ? List<String>.from(widget.task!.tagIds)
        : <String>[];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _urlController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  Future<void> _addTag(String name) async {
    final cleaned = stripTagPrefix(name);
    if (cleaned.isEmpty) return;
    try {
      final tagId = await ref
          .read(tagRepositoryProvider)
          .createTag(uid: widget.uid, name: cleaned);
      if (!_tagIds.contains(tagId)) {
        setState(() {
          _tagIds.add(tagId);
        });
      }
      _tagInputController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to add tag: $e')));
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      if (isEditing) {
        await ref
            .read(taskRepositoryProvider)
            .updateTask(
              widget.task!.taskId,
              title: _titleController.text,
              notes: _notesController.text,
              url: _urlController.text,
              priority: _priority,
              tagIds: _tagIds,
              dueDate: _dueDate,
              dueTime: _dueTime,
              earlyReminderMinutes: _earlyReminderMinutes,
              repeatRule: _repeatRule,
              clearDueDate: _dueDate == null,
              clearDueTime: _dueTime == null,
            );
      } else {
        final createdTask = await ref
            .read(taskRepositoryProvider)
            .createTask(
              uid: widget.uid,
              listId: widget.listId,
              title: _titleController.text,
              notes: _notesController.text,
              url: _urlController.text,
              dueDate: _dueDate,
              dueTime: _dueTime,
            );
        if (_priority != 'none' ||
            _tagIds.isNotEmpty ||
            _earlyReminderMinutes != 0 ||
            _repeatRule != 'none') {
          await ref
              .read(taskRepositoryProvider)
              .updateTask(
                createdTask.taskId,
                priority: _priority,
                tagIds: _tagIds,
                earlyReminderMinutes: _earlyReminderMinutes,
                repeatRule: _repeatRule,
              );
        }
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing
                  ? 'Failed to update task: $e'
                  : 'Failed to add task: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(tagsForUserProvider(widget.uid));
    final tagMap = <String, String>{};
    if (tagsAsync.hasValue) {
      for (final tag in tagsAsync.value!) {
        tagMap[tag.tagId] = tag.name;
      }
    }

    final reminderOptions = {
      ..._defaultReminderOptions,
      _earlyReminderMinutes,
    }.toList()..sort();

    return AlertDialog(
      title: Text(isEditing ? 'Edit Task' : 'New Task'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: Key(isEditing ? 'editTaskTitleInput' : 'taskTitleInput'),
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return isEditing
                        ? 'Title is required.'
                        : 'Please enter a title.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: Key(isEditing ? 'editTaskNotesInput' : 'taskNotesInput'),
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: Key(isEditing ? 'editTaskUrlInput' : 'taskUrlInput'),
                controller: _urlController,
                decoration: const InputDecoration(labelText: 'URL (optional)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('editTaskPriorityInput'),
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: kTaskPriorities.map((p) {
                  return DropdownMenuItem<String>(
                    value: p,
                    child: Text(p[0].toUpperCase() + p.substring(1)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _priority = val);
                  }
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                key: const Key('editTaskDueDateInput'),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dueDate ?? now,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() {
                      _dueDate = picked;
                    });
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Due Date',
                    suffixIcon: _dueDate != null
                        ? IconButton(
                            key: const Key('clearDueDateButton'),
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() {
                                _dueDate = null;
                                _dueTime = null;
                              });
                            },
                          )
                        : const Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(
                    _dueDate != null
                        ? '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}'
                        : 'None',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                key: const Key('editTaskDueTimeInput'),
                onTap: _dueDate == null
                    ? null
                    : () async {
                        TimeOfDay initial = const TimeOfDay(
                          hour: 12,
                          minute: 0,
                        );
                        if (_dueTime != null) {
                          final parts = _dueTime!.split(':');
                          if (parts.length == 2) {
                            final h = int.tryParse(parts[0]);
                            final m = int.tryParse(parts[1]);
                            if (h != null && m != null) {
                              initial = TimeOfDay(hour: h, minute: m);
                            }
                          }
                        }
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: initial,
                        );
                        if (picked != null) {
                          final formatted =
                              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                          setState(() {
                            _dueTime = formatted;
                          });
                        }
                      },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Due Time',
                    enabled: _dueDate != null,
                    suffixIcon: _dueTime != null
                        ? IconButton(
                            key: const Key('clearDueTimeButton'),
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() {
                                _dueTime = null;
                              });
                            },
                          )
                        : const Icon(Icons.access_time, size: 18),
                  ),
                  child: Text(
                    _dueDate == null
                        ? 'Set due date first'
                        : (_dueTime ?? 'None'),
                    style: TextStyle(
                      color: _dueDate == null ? Colors.grey : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: const Key('editTaskEarlyReminderInput'),
                initialValue: _earlyReminderMinutes,
                decoration: const InputDecoration(labelText: 'Early Reminder'),
                items: reminderOptions.map((minutes) {
                  String label;
                  if (minutes == 0) {
                    label = 'None';
                  } else if (minutes < 60) {
                    label = '$minutes minutes before';
                  } else {
                    label =
                        '${minutes ~/ 60} hour${minutes >= 120 ? 's' : ''} before';
                  }
                  return DropdownMenuItem<int>(
                    value: minutes,
                    child: Text(label),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _earlyReminderMinutes = val);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('editTaskRepeatRuleInput'),
                initialValue: _repeatRule,
                decoration: const InputDecoration(labelText: 'Repeat Rule'),
                items: kTaskRepeatRules.map((rule) {
                  return DropdownMenuItem<String>(
                    value: rule,
                    child: Text(rule[0].toUpperCase() + rule.substring(1)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _repeatRule = val);
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text('Tags', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (_tagIds.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _tagIds.map((tagId) {
                    final tagName = tagMap[tagId] ?? tagId;
                    return Chip(
                      key: Key('taskTagChip_$tagId'),
                      label: Text(formatTag(tagName)),
                      onDeleted: () {
                        setState(() {
                          _tagIds.remove(tagId);
                        });
                      },
                    );
                  }).toList(),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('editTaskTagInput'),
                      controller: _tagInputController,
                      decoration: const InputDecoration(
                        labelText: 'Add tag',
                        hintText: 'Press enter or + to add',
                        isDense: true,
                      ),
                      onSubmitted: _addTag,
                    ),
                  ),
                  IconButton(
                    key: const Key('addTagIconButton'),
                    icon: const Icon(Icons.add),
                    tooltip: 'Add tag',
                    onPressed: () => _addTag(_tagInputController.text),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('saveTaskButton'),
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

class _MoveTaskDialog extends ConsumerWidget {
  final Task task;

  const _MoveTaskDialog({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listsAsync = ref.watch(listsForUserProvider);

    return AlertDialog(
      title: const Text('Move Task to List'),
      content: SizedBox(
        width: double.maxFinite,
        child: listsAsync.when(
          data: (lists) {
            final targetLists = lists
                .where((l) => l.listId != task.listId)
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
                  key: Key('moveToListOption_${list.listId}'),
                  title: Text(list.name),
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await ref
                          .read(taskRepositoryProvider)
                          .moveTaskToList(task.taskId, list.listId);
                      if (context.mounted) {
                        navigator.pop(list.name);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        navigator.pop();
                      }
                      messenger.showSnackBar(
                        SnackBar(content: Text('Failed to move task: $e')),
                      );
                    }
                  },
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
