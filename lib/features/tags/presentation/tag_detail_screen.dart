import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback_snackbar.dart';
import '../../auth/providers/auth_providers.dart';
import '../../tasks/data/task.dart';
import '../../tasks/domain/task_priority_filter.dart';
import '../../tasks/domain/task_sort_options.dart';
import '../../tasks/presentation/widgets/empty_state_view.dart';
import '../../tasks/presentation/widgets/show_completed_toggle.dart';
import '../../tasks/presentation/widgets/task_priority_filter_selector.dart';
import '../../tasks/presentation/widgets/task_row_tag_chips.dart';
import '../../tasks/presentation/widgets/task_sort_selector.dart';
import '../../tasks/presentation/widgets/task_tag_filter_selector.dart';
import '../../tasks/providers/task_providers.dart';
import '../../tasks/providers/task_sort_providers.dart';
import '../../tasks/providers/task_tag_filter_providers.dart';
import '../providers/tag_providers.dart';

/// Full screen view displaying tasks matching tag filter criteria,
/// equipped with its own independent sort mode, priority filter, completion toggle, and tag filter.
class TagDetailScreen extends ConsumerStatefulWidget {
  final String tagId;
  final String tagName;

  const TagDetailScreen({
    super.key,
    required this.tagId,
    required this.tagName,
  });

  @override
  ConsumerState<TagDetailScreen> createState() => _TagDetailScreenState();
}

class _TagDetailScreenState extends ConsumerState<TagDetailScreen> {
  String get viewKey => 'tag_${widget.tagId}';

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final tasksAsync = ref.watch(sortedTasksForTagDetailProvider(viewKey));
    final sortOption = ref.watch(taskSortModeProvider(viewKey));
    final tagFilter = ref.watch(taskTagFilterProvider(viewKey));
    final unfilteredTasks =
        ref.watch(rawTasksForTagProvider(widget.tagId)).value ?? const <Task>[];
    final unfilteredCount = unfilteredTasks.length;
    final tagsAsync = ref.watch(tagsForCurrentUserProvider);
    final currentTag = tagsAsync.value
        ?.where((t) => t.tagId == widget.tagId)
        .firstOrNull;
    final displayName = currentTag?.name ?? widget.tagName;

    return Scaffold(
      key: const Key('tagDetailScreen'),
      appBar: AppBar(title: Text('#$displayName')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TaskSortSelector(viewKey: viewKey),
                  const SizedBox(width: 8),
                  TaskPriorityFilterSelector(viewKey: viewKey),
                  const SizedBox(width: 8),
                  TaskTagFilterSelector(viewKey: viewKey),
                  const SizedBox(width: 8),
                  ShowCompletedToggle(viewKey: viewKey),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: tasksAsync.when(
              data: (tasks) {
                if (tasks.isEmpty) {
                  if (unfilteredCount > 0) {
                    final allCompleted = unfilteredTasks.every(
                      (t) => t.isCompleted,
                    );
                    return EmptyStateView(
                      icon: Icons.filter_alt_off_outlined,
                      message: 'No tasks match your filters',
                      messageKey: const Key('noTasksText'),
                      actionLabel: 'Clear filters',
                      actionKey: Key('clearFiltersButton_$viewKey'),
                      onAction: () {
                        ref
                            .read(taskPriorityFilterProvider(viewKey).notifier)
                            .setFilter(TaskPriorityFilter.all);
                        ref
                            .read(taskTagFilterProvider(viewKey).notifier)
                            .setSelectedTags({widget.tagId});
                        ref
                            .read(showCompletedTasksProvider(viewKey).notifier)
                            .setShowCompleted(allCompleted);
                      },
                    );
                  }

                  return const EmptyStateView(
                    icon: Icons.label_outline,
                    message: 'No tasks found',
                    messageKey: Key('noTasksText'),
                  );
                }

                return ReorderableListView.builder(
                  key: Key('tagTaskList_$viewKey'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
                  itemCount: tasks.length,
                  onReorderItem: (oldIndex, newIndex) async {
                    if (sortOption != TaskSortOption.manual) return;
                    if (oldIndex == newIndex) return;

                    final movedTask = tasks[oldIndex];
                    final remainingTasks = List<Task>.from(tasks)
                      ..removeAt(oldIndex);

                    final Task? before = newIndex > 0
                        ? remainingTasks[newIndex - 1]
                        : null;
                    final Task? after = newIndex < remainingTasks.length
                        ? remainingTasks[newIndex]
                        : null;

                    if (before != null &&
                        after != null &&
                        TaskSortUtils.needsRenumbering(
                          before: before,
                          after: after,
                        )) {
                      final updatedList = List<Task>.from(remainingTasks)
                        ..insert(newIndex, movedTask);
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
                  },
                  itemBuilder: (context, index) {
                    final task = tasks[index];

                    final row = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          key: Key('taskItem_${task.taskId}'),
                          leading: Checkbox(
                            key: Key('taskCompleteCheckbox_${task.taskId}'),
                            value: task.isCompleted,
                            onChanged: (val) async {
                              if (val != null) {
                                await ref
                                    .read(taskRepositoryProvider)
                                    .toggleTaskCompleted(
                                      task.taskId,
                                      isCompleted: val,
                                    );
                              }
                            },
                          ),
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
                          subtitle: Column(
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
                              if (tagFilter.isNotEmpty)
                                TaskRowTagChips(task: task),
                            ],
                          ),
                          trailing: IconButton(
                            key: Key('deleteTaskButton_${task.taskId}'),
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: 'Delete',
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final taskRepo = ref.read(taskRepositoryProvider);
                              try {
                                await taskRepo.softDeleteTask(task.taskId);
                                if (!context.mounted) return;
                                showFeedbackSnackBar(
                                  messenger,
                                  'Deleted "${task.title}"',
                                  actionLabel: 'Undo',
                                  actionKey: const Key('undoDeleteTaskButton'),
                                  onAction: uid == null
                                      ? null
                                      : () => taskRepo.restoreTask(
                                          uid: uid,
                                          taskId: task.taskId,
                                        ),
                                  actionErrorPrefix: 'Failed to undo deletion',
                                );
                              } catch (e) {
                                if (context.mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Failed to delete task: $e',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                    );

                    if (sortOption == TaskSortOption.manual) {
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey('tagTaskItemWrapper_${task.taskId}'),
                        index: index,
                        child: row,
                      );
                    }

                    return KeyedSubtree(
                      key: ValueKey('tagTaskItemWrapper_${task.taskId}'),
                      child: row,
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  key: Key('tagDetailLoadingIndicator'),
                ),
              ),
              error: (err, _) =>
                  Center(child: Text('Error loading tasks: $err')),
            ),
          ),
        ],
      ),
    );
  }
}
