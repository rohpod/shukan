import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback_snackbar.dart';
import '../../auth/providers/auth_providers.dart';
import '../../lists/data/list.dart';
import '../../lists/presentation/list_detail_screen.dart';
import '../../lists/providers/list_providers.dart';
import '../data/task.dart';
import '../domain/smart_view_models.dart';
import '../providers/smart_view_providers.dart';
import '../providers/task_providers.dart';
import '../providers/task_sort_providers.dart';
import 'quick_add_bar.dart';
import 'task_list_screen.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/task_priority_marker.dart';

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
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => TaskDialog(
        uid: uid,
        listId: task?.listId ?? listId,
        task: task,
        initialDueDate: initialDueDate,
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
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final uid = ref.watch(currentUidProvider);
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.viewType.label)),
        body: const Center(child: Text('User not signed in.')),
      );
    }

    final tasksAsync = ref.watch(sortedSmartViewTasksProvider(widget.viewType));
    final defaultListId = ref.watch(defaultListIdProvider).value;
    final lists = ref.watch(listsForUserProvider).value ?? const <ListModel>[];
    final listNames = {for (final l in lists) l.listId: l.name};
    final effectiveList = ref.watch(effectiveDefaultListProvider);
    final effectiveListId = effectiveList?.listId;
    final destinationListName = effectiveList?.name;

    final currentDate = ref.watch(currentDateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.viewType.label,
          key: Key('smartViewTitle_${widget.viewType.name}'),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: tasksAsync.when(
              skipLoadingOnReload: true,
              data: (tasks) {
                if (tasks.isEmpty) {
                  final IconData emptyIcon;
                  final String emptyMessage;
                  final bool canAdd =
                      effectiveListId != null &&
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
                    actionKey: canAdd
                        ? const Key('emptyStateAddTaskButton')
                        : null,
                    onAction: canAdd
                        ? () {
                            final now = ref.read(currentDateProvider);
                            final initialDate = SmartViewDateUtils.startOfDay(
                              now,
                            );
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

                return ListView.builder(
                  key: Key('smartViewsListView_${widget.viewType.name}'),
                  padding: const EdgeInsets.all(12),
                  itemCount: tasks.length,
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

                    final row = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          key: Key('taskItem_${task.taskId}'),
                          onTap: () => _openTaskDialog(
                            context,
                            uid,
                            task.listId,
                            task: task,
                          ),
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
                          title: Row(
                            children: [
                              if (task.priority != 'none') ...[
                                TaskPriorityMarker(
                                  priority: task.priority,
                                  taskId: task.taskId,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  task.title,
                                  key: Key('taskTitle_${task.taskId}'),
                                  style: TextStyle(
                                    decoration: task.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: task.isCompleted
                                        ? Colors.grey
                                        : null,
                                  ),
                                ),
                              ),
                            ],
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
                                ],
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key('deleteTaskButton_${task.taskId}'),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                                tooltip: 'Delete Task',
                                onPressed: () async {
                                  final messenger = scaffoldMessenger;
                                  final taskRepo = ref.read(
                                    taskRepositoryProvider,
                                  );
                                  await taskRepo.softDeleteTask(task.taskId);
                                  if (!mounted) return;
                                  showFeedbackSnackBar(
                                    messenger,
                                    'Deleted "${task.title}"',
                                    actionLabel: 'Undo',
                                    actionKey: const Key(
                                      'undoDeleteTaskButton',
                                    ),
                                    onAction: () => taskRepo.restoreTask(
                                      uid: uid,
                                      taskId: task.taskId,
                                      defaultListId: defaultListId,
                                    ),
                                    actionErrorPrefix:
                                        'Failed to undo deletion',
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                    );

                    return row;
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
                                    ListDetailScreen(list: effectiveList),
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
