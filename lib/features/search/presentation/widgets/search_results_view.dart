import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/providers/auth_providers.dart';
import '../../../lists/data/list.dart';
import '../../../lists/providers/list_providers.dart';
import '../../../tags/providers/tag_providers.dart';
import '../../../tasks/data/task.dart';
import '../../../tasks/presentation/task_list_screen.dart';
import '../../../tasks/presentation/widgets/empty_state_view.dart';
import '../../../tasks/presentation/widgets/quick_add_preview_chip.dart';
import '../../../tasks/presentation/widgets/task_priority_marker.dart';
import '../../../tasks/providers/task_providers.dart';
import '../../providers/search_providers.dart';

class SearchResultsView extends ConsumerWidget {
  final TextEditingController searchController;
  final bool hasParsedAdd;
  final String? parsedTitle;
  final DateTime? parsedAddDueDate;
  final String? parsedAddDueTime;
  final bool isCreatingTask;
  final VoidCallback onDismissAddChip;
  final void Function(
    BuildContext context,
    String uid,
    ListModel list,
    String trimmedQuery,
  )
  onAddTaskAction;
  final VoidCallback onClearSearch;
  final VoidCallback onCollapse;

  const SearchResultsView({
    super.key,
    required this.searchController,
    required this.hasParsedAdd,
    this.parsedTitle,
    this.parsedAddDueDate,
    this.parsedAddDueTime,
    required this.isCreatingTask,
    required this.onDismissAddChip,
    required this.onAddTaskAction,
    required this.onClearSearch,
    required this.onCollapse,
  });

  Future<void> _showEditDialog(
    BuildContext context,
    String uid,
    Task task,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          TaskDialog(uid: uid, listId: task.listId, task: task),
    );
  }

  bool _isFailedPrecondition(Object error) {
    if (error is FirebaseException && error.code == 'failed-precondition') {
      return true;
    }
    final str = error.toString().toLowerCase();
    return str.contains('failed-precondition') ||
        str.contains('requires an index');
  }

  Widget _buildErrorView(
    Object error,
    StackTrace? stackTrace,
    String contextMessage,
  ) {
    debugPrint('$contextMessage: $error');
    if (stackTrace != null) {
      debugPrint('$stackTrace');
    }
    final isFailedPrecondition = _isFailedPrecondition(error);
    final message = isFailedPrecondition
        ? 'Search is temporarily unavailable — please try again shortly'
        : 'Something went wrong';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFailedPrecondition ? Icons.schedule : Icons.error_outline,
              size: 48,
              color: isFailedPrecondition ? Colors.orange : Colors.redAccent,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              key: const Key('searchErrorText'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    final effectiveList = ref.watch(effectiveDefaultListProvider);
    final allTasksAsync = ref.watch(allTasksForCurrentUserProvider);
    final tagsAsync = ref.watch(tagsForCurrentUserProvider);
    final query = ref.watch(searchQueryProvider).toLowerCase();
    final trimmedQuery = searchController.text.trim();
    final isActionEnabled =
        effectiveList != null && !isCreatingTask && uid != null;
    final displayTitle = (hasParsedAdd && parsedTitle != null)
        ? parsedTitle!
        : trimmedQuery;
    final hasDateOrTime = parsedAddDueDate != null || parsedAddDueTime != null;

    return Column(
      children: [
        if (trimmedQuery.isNotEmpty) ...[
          ListTile(
            key: const Key('searchAddTaskAction'),
            leading: const Icon(Icons.add_circle_outline),
            title: Text(
              'Add "$displayTitle" as a task',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            trailing: (hasParsedAdd && hasDateOrTime)
                ? QuickAddPreviewChip(
                    dueDate: parsedAddDueDate,
                    dueTime: parsedAddDueTime,
                    onDismiss: onDismissAddChip,
                  )
                : null,
            enabled: isActionEnabled,
            onTap: isActionEnabled
                ? () =>
                      onAddTaskAction(context, uid, effectiveList, trimmedQuery)
                : null,
          ),
          const Divider(height: 1),
        ],
        Expanded(
          child: tagsAsync.hasError
              ? _buildErrorView(
                  tagsAsync.error!,
                  tagsAsync.stackTrace,
                  'Error in tagsForCurrentUserProvider',
                )
              : allTasksAsync.when(
                  data: (allTasks) {
                    final tagMap = tagsAsync.when(
                      data: (tags) => {
                        for (final tag in tags) tag.tagId: tag.name,
                      },
                      loading: () => <String, String>{},
                      error: (e, st) {
                        debugPrint(
                          'Error in tagsForCurrentUserProvider: $e\n$st',
                        );
                        return <String, String>{};
                      },
                    );

                    // Filter tasks by completion status and search query
                    final matchingTasks = allTasks.where((task) {
                      if (task.isCompleted) {
                        return false;
                      }

                      if (query.isNotEmpty) {
                        final titleMatches = task.title.toLowerCase().contains(
                          query,
                        );
                        final notesMatches = task.notes.toLowerCase().contains(
                          query,
                        );
                        final tagMatches = task.tagIds.any((tagId) {
                          final tagName = tagMap[tagId];
                          return tagName != null &&
                              tagName.toLowerCase().contains(query);
                        });

                        if (!titleMatches && !notesMatches && !tagMatches) {
                          return false;
                        }
                      }

                      return true;
                    }).toList();

                    if (matchingTasks.isEmpty) {
                      if (allTasks.isEmpty) {
                        return const EmptyStateView(
                          icon: Icons.search_off_outlined,
                          message: 'No tasks found',
                          messageKey: Key('noSearchResultsText'),
                        );
                      }

                      return EmptyStateView(
                        icon: Icons.filter_alt_off_outlined,
                        message: 'No matching tasks found',
                        messageKey: const Key('noSearchResultsText'),
                        actionLabel: 'Clear search',
                        actionIcon: Icons.clear,
                        actionKey: const Key('clearSearchFiltersButton'),
                        onAction: onClearSearch,
                      );
                    }

                    return ListView.separated(
                      key: const Key('searchResultsListView'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: matchingTasks.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final task = matchingTasks[index];
                        return ListTile(
                          key: Key('taskItem_${task.taskId}'),
                          onTap: uid != null
                              ? () => _showEditDialog(context, uid, task)
                              : null,
                          leading: Checkbox(
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
                          subtitle:
                              (task.notes.isNotEmpty || task.url.isNotEmpty)
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
                                  ],
                                )
                              : null,
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    key: Key('searchTasksLoadingIndicator'),
                    child: CircularProgressIndicator(),
                  ),
                  error: (e, st) => _buildErrorView(
                    e,
                    st,
                    'Error in allTasksForCurrentUserProvider',
                  ),
                ),
        ),
      ],
    );
  }
}
