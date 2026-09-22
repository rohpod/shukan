import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../lists/data/list.dart';
import '../../lists/providers/list_providers.dart';
import '../data/task.dart';
import '../domain/smart_view_models.dart';
import '../providers/smart_view_providers.dart';
import '../providers/task_providers.dart';
import 'task_list_screen.dart';

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
    final uid = ref.watch(currentUidProvider);
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.viewType.label)),
        body: const Center(child: Text('User not signed in.')),
      );
    }

    final tasksAsync = ref.watch(smartViewTasksProvider(widget.viewType));
    final defaultListId = ref.watch(defaultListIdProvider).value;
    final listsAsync = ref.watch(listsForUserProvider);
    final listNames = {
      for (final l in (listsAsync.value ?? const <ListModel>[]))
        l.listId: l.name,
    };
    final effectiveListId =
        defaultListId ??
        (listsAsync.value?.isNotEmpty == true
            ? listsAsync.value!.first.listId
            : 'inbox');

    final currentDate = ref.watch(currentDateProvider);
    final completionFilter = ref.watch(smartViewCompletionFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.viewType.label,
          key: Key('smartViewTitle_${widget.viewType.name}'),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('addSmartViewTaskButton'),
        tooltip: 'New Task',
        onPressed: () {
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
          );
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<CompletionFilter>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: CompletionFilter.incomplete,
                      label: Text(
                        'Incomplete',
                        key: Key('incompleteFilterButton'),
                      ),
                    ),
                    ButtonSegment(
                      value: CompletionFilter.completed,
                      label: Text(
                        'Completed',
                        key: Key('completedFilterButton'),
                      ),
                    ),
                    ButtonSegment(
                      value: CompletionFilter.all,
                      label: Text('All', key: Key('allFilterButton')),
                    ),
                  ],
                  selected: {completionFilter},
                  onSelectionChanged: (newSelection) {
                    ref
                        .read(smartViewCompletionFilterProvider.notifier)
                        .setFilter(newSelection.first);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: tasksAsync.when(
              skipLoadingOnReload: true,
              data: (tasks) {
                if (tasks.isEmpty) {
                  return const Center(
                    child: Text(
                      'No tasks found',
                      key: Key('noTasksText'),
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: tasks.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
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

                    return ListTile(
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
                      subtitle: Wrap(
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
                                  _formatDueDate(task.dueDate, task.dueTime),
                                  key: Key('taskDueDate_${task.taskId}'),
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
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: 'Delete Task',
                            onPressed: () async {
                              await ref
                                  .read(taskRepositoryProvider)
                                  .softDeleteTask(task.taskId);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Deleted "${task.title}"'),
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
        ],
      ),
    );
  }
}
