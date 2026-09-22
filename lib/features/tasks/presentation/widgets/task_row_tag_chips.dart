import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../tags/providers/tag_providers.dart';
import '../../data/task.dart';

/// Renders small tag chips for a task row when the tag filter is active.
class TaskRowTagChips extends ConsumerWidget {
  final Task task;

  const TaskRowTagChips({super.key, required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (task.tagIds.isEmpty) return const SizedBox.shrink();

    final tagsAsync = ref.watch(tagsForCurrentUserProvider);
    final tagMap = <String, String>{};
    if (tagsAsync.hasValue) {
      for (final tag in tagsAsync.value!) {
        tagMap[tag.tagId] = tag.name;
      }
    }

    return Padding(
      key: Key('taskRowTagChips_${task.taskId}'),
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: task.tagIds.map((tagId) {
          final tagName = tagMap[tagId] ?? tagId;
          return Container(
            key: Key('taskRowTagChip_${task.taskId}_$tagId'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant
                    .withValues(alpha: 0.5),
                width: 0.8,
              ),
            ),
            child: Text(
              '#$tagName',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
