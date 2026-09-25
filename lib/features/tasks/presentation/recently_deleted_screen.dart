import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../lists/data/list.dart';
import '../../lists/providers/list_providers.dart';
import '../data/task.dart';
import '../providers/task_providers.dart';
import 'widgets/empty_state_view.dart';

class RecentlyDeletedScreen extends ConsumerStatefulWidget {
  const RecentlyDeletedScreen({super.key});

  @override
  ConsumerState<RecentlyDeletedScreen> createState() =>
      _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends ConsumerState<RecentlyDeletedScreen> {
  bool _hasPurged = false;

  void _triggerPurgeIfNeeded(String? uid) {
    if (uid != null && !_hasPurged) {
      _hasPurged = true;
      Future.microtask(() {
        if (mounted) {
          ref.read(taskRepositoryProvider).purgeExpiredDeletedTasks(uid);
        }
      });
    }
  }

  Future<void> _showEmptyTrashDialog(BuildContext context, String uid) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Empty Recently Deleted?'),
        content: const Text(
          'All tasks in Recently Deleted will be permanently deleted. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            key: const Key('cancelEmptyTrashButton'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirmEmptyTrashButton'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await ref
                    .read(taskRepositoryProvider)
                    .emptyRecentlyDeleted(uid);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Emptied Recently Deleted')),
                  );
                }
              } catch (e) {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to empty trash: $e')),
                  );
                }
              }
            },
            child: const Text('Empty Trash'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPermanentDeleteDialog(
    BuildContext context,
    String uid,
    Task task,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permanently delete task?'),
        content: Text(
          '"${task.title}" will be permanently removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            key: const Key('cancelPermanentDeleteButton'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirmPermanentDeleteButton'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await ref
                    .read(taskRepositoryProvider)
                    .permanentlyDeleteTask(uid: uid, taskId: task.taskId);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Permanently deleted "${task.title}"'),
                    ),
                  );
                }
              } catch (e) {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete task: $e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDeletedAt(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    _triggerPurgeIfNeeded(uid);

    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Recently Deleted')),
        body: const Center(child: Text('User not signed in.')),
      );
    }

    final deletedTasksAsync = ref.watch(recentlyDeletedTasksProvider);
    final defaultListId = ref.watch(defaultListIdProvider).value;
    final listsAsync = ref.watch(listsForUserProvider);
    final listNames = {
      for (final l in (listsAsync.value ?? const <ListModel>[]))
        l.listId: l.name,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recently Deleted'),
        actions: [
          deletedTasksAsync.when(
            data: (tasks) => tasks.isNotEmpty
                ? IconButton(
                    key: const Key('emptyRecentlyDeletedButton'),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: 'Empty Recently Deleted',
                    onPressed: () => _showEmptyTrashDialog(context, uid),
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: deletedTasksAsync.when(
        data: (tasks) {
          if (tasks.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.refresh(recentlyDeletedTasksProvider.future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                  const EmptyStateView(
                    icon: Icons.delete_outline,
                    message: 'No recently deleted tasks',
                    messageKey: Key('noRecentlyDeletedTasksText'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(recentlyDeletedTasksProvider.future),
            child: ListView.separated(
              key: const Key('recentlyDeletedListView'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: tasks.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final task = tasks[index];
                final listName = listNames[task.listId];
                return ListTile(
                  key: Key('deletedTaskItem_${task.taskId}'),
                  title: Text(
                    task.title,
                    key: Key('deletedTaskTitle_${task.taskId}'),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (task.deletedAt != null)
                        Text(
                          listName != null
                              ? 'Deleted: ${_formatDeletedAt(task.deletedAt)} • List: $listName'
                              : 'Deleted: ${_formatDeletedAt(task.deletedAt)}',
                          key: Key('deletedTaskDate_${task.taskId}'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      if (task.notes.isNotEmpty)
                        Text(
                          task.notes,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('restoreTaskButton_${task.taskId}'),
                        icon: const Icon(Icons.restore, size: 20),
                        tooltip: 'Restore',
                        onPressed: () async {
                          try {
                            await ref
                                .read(taskRepositoryProvider)
                                .restoreTask(
                                  uid: uid,
                                  taskId: task.taskId,
                                  defaultListId: defaultListId,
                                );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Restored "${task.title}"'),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to restore task: $e'),
                                ),
                              );
                            }
                          }
                        },
                      ),
                      IconButton(
                        key: Key('permanentDeleteTaskButton_${task.taskId}'),
                        icon: const Icon(
                          Icons.delete_forever,
                          size: 20,
                          color: Colors.redAccent,
                        ),
                        tooltip: 'Delete Permanently',
                        onPressed: () =>
                            _showPermanentDeleteDialog(context, uid, task),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(
          key: Key('recentlyDeletedLoadingIndicator'),
          child: CircularProgressIndicator(),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 12),
                Text(
                  'Error loading recently deleted tasks: $e',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  key: const Key('retryRecentlyDeletedButton'),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  onPressed: () => ref.invalidate(recentlyDeletedTasksProvider),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
