import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../tags/providers/tag_providers.dart';
import '../../tasks/data/task.dart';
import '../../tasks/presentation/task_list_screen.dart';
import '../../tasks/presentation/widgets/empty_state_view.dart';
import '../../tasks/providers/task_providers.dart';
import '../providers/search_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _searchController;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    final initialQuery = ref.read(searchQueryProvider);
    _searchController = TextEditingController(text: initialQuery);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        ref.read(searchQueryProvider.notifier).setQuery(value.trim());
      }
    });
  }

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
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final allTasksAsync = ref.watch(allTasksForCurrentUserProvider);
    final tagsAsync = ref.watch(tagsForCurrentUserProvider);
    final query = ref.watch(searchQueryProvider).toLowerCase();
    final completionFilter = ref.watch(searchCompletionFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('searchQueryInput'),
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search tasks, notes, tags...',
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    key: const Key('clearSearchQueryButton'),
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      _debounceTimer?.cancel();
                      ref.read(searchQueryProvider.notifier).setQuery('');
                      setState(() {});
                    },
                  )
                : null,
          ),
          onChanged: (val) {
            setState(() {});
            _onSearchChanged(val);
          },
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  key: const Key('filterChip_all'),
                  label: const Text('All'),
                  selected: completionFilter == SearchCompletionFilter.all,
                  onSelected: (selected) {
                    if (selected) {
                      ref
                          .read(searchCompletionFilterProvider.notifier)
                          .setFilter(SearchCompletionFilter.all);
                    }
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  key: const Key('filterChip_active'),
                  label: const Text('Active'),
                  selected: completionFilter == SearchCompletionFilter.active,
                  onSelected: (selected) {
                    if (selected) {
                      ref
                          .read(searchCompletionFilterProvider.notifier)
                          .setFilter(SearchCompletionFilter.active);
                    }
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  key: const Key('filterChip_completed'),
                  label: const Text('Completed'),
                  selected:
                      completionFilter == SearchCompletionFilter.completed,
                  onSelected: (selected) {
                    if (selected) {
                      ref
                          .read(searchCompletionFilterProvider.notifier)
                          .setFilter(SearchCompletionFilter.completed);
                    }
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
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

                      // Filter tasks by completion state and search query
                      final matchingTasks = allTasks.where((task) {
                        // a) Completion filter
                        switch (completionFilter) {
                          case SearchCompletionFilter.all:
                            break;
                          case SearchCompletionFilter.active:
                            if (task.isCompleted) return false;
                            break;
                          case SearchCompletionFilter.completed:
                            if (!task.isCompleted) return false;
                            break;
                        }

                        // b) Search query match
                        if (query.isNotEmpty) {
                          final titleMatches = task.title
                              .toLowerCase()
                              .contains(query);
                          final notesMatches = task.notes
                              .toLowerCase()
                              .contains(query);
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
                          onAction: () {
                            _searchController.clear();
                            _debounceTimer?.cancel();
                            ref.read(searchQueryProvider.notifier).setQuery('');
                            ref
                                .read(searchCompletionFilterProvider.notifier)
                                .setFilter(SearchCompletionFilter.active);
                            setState(() {});
                          },
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
                                (task.notes.isNotEmpty || task.url.isNotEmpty)
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                    ],
                                  )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (uid != null)
                                  IconButton(
                                    key: Key('editTaskButton_${task.taskId}'),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                    ),
                                    tooltip: 'Edit',
                                    onPressed: () =>
                                        _showEditDialog(context, uid, task),
                                  ),
                                IconButton(
                                  key: Key('deleteTaskButton_${task.taskId}'),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: Colors.redAccent,
                                  ),
                                  tooltip: 'Delete',
                                  onPressed: () async {
                                    await ref
                                        .read(taskRepositoryProvider)
                                        .softDeleteTask(task.taskId);
                                  },
                                ),
                              ],
                            ),
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
      ),
    );
  }
}
