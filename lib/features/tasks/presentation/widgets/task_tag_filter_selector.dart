import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../tags/data/tag.dart';
import '../../../tags/providers/tag_providers.dart';
import '../../providers/task_tag_filter_providers.dart';

/// Reusable multi-select tag filter dropdown selector for task lists, smart views, and tag detail.
class TaskTagFilterSelector extends ConsumerWidget {
  final String viewKey;

  const TaskTagFilterSelector({super.key, required this.viewKey});

  void _showTagFilterDialog(
    BuildContext context,
    WidgetRef ref,
    List<Tag> allTags,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, ref, _) {
            final selectedTagIds = ref.watch(taskTagFilterProvider(viewKey));
            final notifier = ref.read(taskTagFilterProvider(viewKey).notifier);

            return AlertDialog(
              key: Key('taskTagFilterDialog_$viewKey'),
              title: Row(
                children: [
                  const Icon(Icons.label_outline, size: 20),
                  const SizedBox(width: 8),
                  const Text('Filter by Tags', style: TextStyle(fontSize: 18)),
                  const Spacer(),
                  if (selectedTagIds.isNotEmpty)
                    TextButton(
                      key: Key('clearTagFilterButton_$viewKey'),
                      onPressed: () async {
                        await notifier.clearAll();
                      },
                      child: const Text('Clear all'),
                    ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: allTags.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No tags available',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 350),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: allTags.length,
                          itemBuilder: (context, index) {
                            final tag = allTags[index];
                            final isSelected = selectedTagIds.contains(
                              tag.tagId,
                            );
                            final canSelect =
                                isSelected ||
                                selectedTagIds.length <
                                    TaskTagFilterNotifier.maxTagLimit;

                            return CheckboxListTile(
                              key: Key(
                                'tagFilterOption_${viewKey}_${tag.tagId}',
                              ),
                              value: isSelected,
                              title: Text(tag.name),
                              dense: true,
                              subtitle: !canSelect && !isSelected
                                  ? const Text(
                                      'Max 30 tags reached',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange,
                                      ),
                                    )
                                  : null,
                              onChanged: canSelect || isSelected
                                  ? (bool? val) async {
                                      final success = await notifier.toggleTag(
                                        tag.tagId,
                                      );
                                      if (!success && context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Cannot select more than 30 tags (Firestore query limit).',
                                                ),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                      }
                                    }
                                  : null,
                            );
                          },
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  key: Key('closeTagFilterButton_$viewKey'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTags = ref.watch(taskTagFilterProvider(viewKey));
    final tagsAsync = ref.watch(tagsForCurrentUserProvider);
    final allTags = tagsAsync.value ?? const <Tag>[];

    final hasActiveFilter = selectedTags.isNotEmpty;

    return InkWell(
      key: Key('taskTagFilterSelector_$viewKey'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showTagFilterDialog(context, ref, allTags),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: hasActiveFilter
              ? Theme.of(context).colorScheme.primaryContainer
                    .withValues(alpha: 0.5)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasActiveFilter
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.label_outline,
              size: 16,
              color: hasActiveFilter
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[700],
            ),
            const SizedBox(width: 6),
            Text(
              hasActiveFilter ? 'Tags (${selectedTags.length})' : 'Tags: All',
              key: Key('taskTagFilterLabel_$viewKey'),
              style: TextStyle(
                fontSize: 12,
                color: hasActiveFilter
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: hasActiveFilter
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[700],
            ),
          ],
        ),
      ),
    );
  }
}
