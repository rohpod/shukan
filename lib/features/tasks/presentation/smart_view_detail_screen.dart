import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../lists/data/list.dart';
import '../../lists/presentation/list_detail_screen.dart';
import '../../lists/providers/list_providers.dart';
import '../data/task.dart';
import '../domain/smart_view_models.dart';
import '../domain/task_priority_filter.dart';
import '../domain/task_sort_options.dart';
import '../providers/smart_view_providers.dart';
import '../providers/task_providers.dart';
import '../providers/task_sort_providers.dart';
import '../providers/task_tag_filter_providers.dart';
import 'task_list_screen.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/show_completed_toggle.dart';
import 'widgets/task_priority_filter_selector.dart';
import 'widgets/task_row_tag_chips.dart';
import 'widgets/task_sort_selector.dart';
import 'widgets/task_tag_filter_selector.dart';
import 'quick_add_bar.dart';

class SmartViewDetailScreen extends ConsumerStatefulWidget {
  final SmartViewType viewType;

  const SmartViewDetailScreen({super.key, required this.viewType});

  @override
  ConsumerState<SmartViewDetailScreen> createState() =>
      _SmartViewDetailScreenState();
}

class _SmartViewDetailScreenState extends ConsumerState<SmartViewDetailScreen> {
  Future<void> _openTaskDialog(
    BuildContext context,
    String uid,
    String listId, {
    Task? task,
    DateTime? initialDueDate,
    String? initialTitle,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => TaskDialog(
        uid: uid,
        listId: task?.listId ?? listId,
        task: task,
        initialDueDate: initialDueDate,
        initialTitle: initialTitle,
      ),
    );
  }

  String _formatDueDate(DateTime? date, String? dueTime) {
    if (date == null) return '';
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    if (dueTime != null && dueTime.isNotEmpty) {
      return '$y-$m-$d $dueTime';
    }
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.viewType.label)),
        body: const Center(child: Text('User not signed in.')),
      );
    }

    final tasksAsync = ref.watch(sortedSmartViewTasksProvider(widget.viewType));
    final sortOption = ref.watch(taskSortModeProvider(widget.viewType.name));
    final tagFilter = ref.watch(taskTagFilterProvider(widget.viewType.name));
    final defaultListId = ref.watch(defaultListIdProvider).value;
    final lists = ref.watch(listsForUserProvider).value ?? const <ListModel>[];
    final listNames = {for (final l in lists) l.listId: l.name};

    ListModel? effectiveList;
    if (lists.isNotEmpty) {
      if (defaultListId != null) {
        for (final l in lists) {
          if (l.listId == defaultListId) {
            effectiveList = l;
            break;
          }
        }
      }
      effectiveList ??= lists.first;
    }

    final effectiveListId = effectiveList?.listId;
    final destinationListName = effectiveList?.name;

    final currentDate = ref.watch(currentDateProvider);

    final viewKey = widget.viewType.name;
    final unfilteredTasks =
        ref.watch(unfilteredSmartViewTasksProvider(widget.viewType)).value ??
            const <Task>[];
    final unfilteredCount = unfilteredTasks.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.viewType.label,
          key: Key('smartViewTitle_${widget.viewType.name}'),
        ),
      ),
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
                  ShowCompletedToggle(viewKey: viewKey),
                  const SizedBox(width: 8),
                  TaskTagFilterSelector(viewKey: viewKey),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: tasksAsync.when(
              skipLoadingOnReload: true,
              data: (tasks) {
                if (tasks.isEmpty) {
                  if (unfilteredCount > 0) {
                    final allCompleted =
                        unfilteredTasks.every((t) => t.isCompleted);
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
                            .clearAll();
                        ref
                            .read(showCompletedTasksProvider(viewKey).notifier)
                            .setShowCompleted(allCompleted);
                      },
                    );
                  }

                  final IconData emptyIcon;
                  final String emptyMessage;
                  final bool canAdd = effectiveListId != null &&
                      widget.viewType != SmartViewType.scheduled;

                  switch (widget.viewType) {
                    case SmartViewType.today:
                      emptyIcon = Icons.today_outlined;
                      emptyMessage = 'Nothing due today';
                      break;
                    case SmartViewType.thisWeek:
                      emptyIcon = Icons.calendar_view_week_outlined;
                      emptyMessage = 'No tasks scheduled this week';
                      break;
                    case SmartViewType.scheduled:
                      emptyIcon = Icons.event_note_outlined;
                      emptyMessage = 'No scheduled tasks';
                      break;
                  }

                  return EmptyStateView(
                    icon: emptyIcon,
                    message: emptyMessage,
                    messageKey: const Key('noTasksText'),
                    actionLabel: canAdd ? 'Add task' : null,
                    actionIcon: canAdd ? Icons.add : null,
                    actionKey:
                        canAdd ? const Key('emptyStateAddTaskButton') : null,
                    onAction: canAdd
                        ? () {
                            final now = ref.read(currentDateProvider);
                            final initialDate =
                                SmartViewDateUtils.startOfDay(now);
                            _openTaskDialog(
                              context,
                              uid,
                              effectiveListId,
                              initialDueDate: initialDate,
                            );
                          }
                        : null,
                  );
                }

                return ReorderableListView.builder(
                  key: Key('smartViewsListView_${widget.viewType.name}'),
                  padding: const EdgeInsets.all(12),
                  buildDefaultDragHandles: false,
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
                    final listName = listNames[task.listId] ?? 'Inbox';
                    final isOverdue =
                        SmartViewDateUtils.isOverdue(
                          task.dueDate,
                          currentDate,
                        ) &&
                        !task.isCompleted;
                    final dueDateColor = isOverdue
                        ? Colors.red.shade700
                        : Colors.blueGrey;

                    return Column(
                      key: ValueKey('smartTaskItemWrapper_${task.taskId}'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          key: Key('taskItem_${task.taskId}'),
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (sortOption == TaskSortOption.manual)
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Icon(
                                      Icons.drag_handle,
                                      key: Key(
                                        'smartTaskDragHandle_${task.taskId}',
                                      ),
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              Checkbox(
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
                            ],
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
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (task.dueDate != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.calendar_today,
                                          size: 13,
                                          color: dueDateColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDueDate(
                                            task.dueDate,
                                            task.dueTime,
                                          ),
                                          key: Key(
                                            'taskDueDate_${task.taskId}',
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: dueDateColor,
                                            fontWeight: isOverdue
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  Text(
                                    '• List: $listName',
                                    key: Key('taskListOrigin_${task.taskId}'),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  if (task.priority != 'none')
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: task.priority == 'high'
                                            ? Colors.red.shade100
                                            : (task.priority == 'medium'
                                                  ? Colors.orange.shade100
                                                  : Colors.blue.shade100),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        task.priority.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: task.priority == 'high'
                                              ? Colors.red.shade900
                                              : (task.priority == 'medium'
                                                    ? Colors.orange.shade900
                                                    : Colors.blue.shade900),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (tagFilter.isNotEmpty)
                                TaskRowTagChips(task: task),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key('editTaskButton_${task.taskId}'),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                tooltip: 'Edit Task',
                                onPressed: () => _openTaskDialog(
                                  context,
                                  uid,
                                  task.listId,
                                  task: task,
                                ),
                              ),
                              IconButton(
                                key: Key('deleteTaskButton_${task.taskId}'),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                                tooltip: 'Delete Task',
                                onPressed: () async {
                                  await ref
                                      .read(taskRepositoryProvider)
                                      .softDeleteTask(task.taskId);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .clearSnackBars();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Deleted "${task.title}"',
                                        ),
                                        action: SnackBarAction(
                                          label: 'Undo',
                                          onPressed: () async {
                                            await ref
                                                .read(taskRepositoryProvider)
                                                .restoreTask(
                                                  uid: uid,
                                                  taskId: task.taskId,
                                                  defaultListId: defaultListId,
                                                );
                                          },
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  key: Key('smartViewLoadingIndicator'),
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    e is TimeoutException
                        ? (e.message ??
                              'This is taking longer than expected — check your connection or try again')
                        : 'Error loading tasks: $e',
                    key: const Key('smartViewErrorText'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          QuickAddBar(
            uid: uid,
            listId: effectiveListId,
            hintText: destinationListName != null
                ? 'Add task to $destinationListName...'
                : null,
            expandButtonKey: const Key('addSmartViewTaskButton'),
            onExpand: effectiveListId == null
                ? null
                : (text) {
                    final now = ref.read(currentDateProvider);
                    final initialDate = widget.viewType == SmartViewType.today
                        ? SmartViewDateUtils.startOfDay(now)
                        : (widget.viewType == SmartViewType.thisWeek
                              ? SmartViewDateUtils.startOfDay(now)
                              : SmartViewDateUtils.startOfDay(now));

                    _openTaskDialog(
                      context,
                      uid,
                      effectiveListId,
                      initialDueDate: initialDate,
                      initialTitle: text,
                    );
                  },
            onTaskCreated: (task) {
              if (!context.mounted) return;
              final listName = destinationListName ?? 'list';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added to $listName'),
                  action: effectiveList != null
                      ? SnackBarAction(
                          label: 'View',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    ListDetailScreen(list: effectiveList!),
                              ),
                            );
                          },
                        )
                      : null,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
