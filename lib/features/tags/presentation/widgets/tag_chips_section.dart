import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/tag_format.dart';
import '../../../tasks/providers/task_tag_filter_providers.dart';
import '../tag_actions.dart';
import 'tag_tasks_popup.dart';

/// Collapsible tag chips section showing tag chips with active task count badges.
///
/// Can be used across HomeScreen (global tags) and TaskListScreen (list-scoped tags).
/// Tapping a chip opens [TagTasksPopup]; long-pressing opens the Edit/Delete bottom sheet.
class TagChipsSection extends ConsumerWidget {
  final String contextKey;
  final String? uid;
  final List<TagBrowserEntry> entries;

  const TagChipsSection({
    super.key,
    required this.contextKey,
    required this.uid,
    required this.entries,
  });

  void _showTagBottomSheet(
    BuildContext context,
    WidgetRef ref,
    TagBrowserEntry entry,
    String uid,
  ) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          key: Key('tagActionsBottomSheet_${entry.tagId}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                formatTag(entry.name),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              key: Key('editTagAction_${entry.tagId}'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showRenameTagDialog(context, ref, entry, uid);
              },
            ),
            ListTile(
              key: Key('deleteTagAction_${entry.tagId}'),
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
              ),
              title: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showDeleteTagDialog(context, ref, entry, uid);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagChip(
    BuildContext context,
    WidgetRef ref,
    TagBrowserEntry entry,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('tagChip_${contextKey}_${entry.tagId}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          showDialog<void>(
            context: context,
            builder: (_) =>
                TagTasksPopup(tagId: entry.tagId, tagName: entry.name),
          );
        },
        onLongPress: uid == null
            ? null
            : () => _showTagBottomSheet(context, ref, entry, uid!),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant
                  .withValues(alpha: 0.5),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatTag(entry.name),
                key: Key('tagChipName_${contextKey}_${entry.tagId}'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                key: Key('tagChipCount_${contextKey}_${entry.tagId}'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${entry.taskCount}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    final isCollapsed = ref.watch(tagChipsSectionCollapsedProvider(contextKey));

    return Column(
      key: Key('tagChipsSection_$contextKey'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 24, thickness: 1),
        InkWell(
          key: Key('tagChipsSectionHeader_$contextKey'),
          onTap: () {
            ref
                .read(tagChipsSectionCollapsedProvider(contextKey).notifier)
                .toggle();
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  isCollapsed ? Icons.expand_more : Icons.expand_less,
                  key: Key('tagChipsSectionChevron_$contextKey'),
                  size: 20,
                  color: Colors.grey[700],
                ),
                const SizedBox(width: 8),
                Text(
                  'Tags',
                  key: Key('tagChipsSectionTitle_$contextKey'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!isCollapsed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entries
                  .map((entry) => _buildTagChip(context, ref, entry))
                  .toList(),
            ),
          ),
      ],
    );
  }
}
