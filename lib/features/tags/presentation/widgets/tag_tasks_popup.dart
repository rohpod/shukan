import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/tag_format.dart';
import '../../../tasks/providers/task_tag_filter_providers.dart';
import '../../providers/tag_providers.dart';

/// Modal dialog showing all active (incomplete, non-deleted) tasks carrying [tagId],
/// grouped by list name heading and ordered by createdAt ascending within each group.
class TagTasksPopup extends ConsumerWidget {
  final String tagId;
  final String? tagName;

  const TagTasksPopup({super.key, required this.tagId, this.tagName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsForCurrentUserProvider).value ?? [];
    final tag = tags.where((t) => t.tagId == tagId).firstOrNull;
    final displayName = tag?.name ?? tagName ?? tagId;

    final groupedAsync = ref.watch(tasksForTagGroupedByListProvider(tagId));

    return AlertDialog(
      key: Key('tagTasksPopup_$tagId'),
      title: Row(
        children: [
          const Icon(Icons.label_outline, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              formatTag(displayName),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: groupedAsync.when(
            data: (groups) {
              final nonEmptyGroups = groups
                  .where((g) => g.tasks.isNotEmpty)
                  .toList();

              if (nonEmptyGroups.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No active tasks with this tag',
                    key: Key('tagTasksPopupEmptyText'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                itemCount: nonEmptyGroups.length,
                itemBuilder: (context, groupIndex) {
                  final group = nonEmptyGroups[groupIndex];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (groupIndex > 0) const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          group.listName,
                          key: Key(
                            'tagTasksPopupGroupHeading_${tagId}_${group.listId}',
                          ),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                      const Divider(height: 1),
                      ...group.tasks.map(
                        (task) => ListTile(
                          key: Key('tagTasksPopupTask_${tagId}_${task.taskId}'),
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          title: Text(task.title),
                          subtitle: task.notes.isNotEmpty
                              ? Text(
                                  task.notes,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                )
                              : null,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(
                  key: Key('tagTasksPopupLoadingIndicator'),
                ),
              ),
            ),
            error: (err, _) => Center(
              child: Text(
                'Error loading tasks: $err',
                key: const Key('tagTasksPopupErrorText'),
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('tagTasksPopupCloseButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
