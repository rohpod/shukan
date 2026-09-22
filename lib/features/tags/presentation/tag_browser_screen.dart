import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../tasks/providers/task_sort_providers.dart';
import '../../tasks/providers/task_tag_filter_providers.dart';
import '../providers/tag_providers.dart';
import 'tag_detail_screen.dart';

/// Screen listing every distinct tag currently in use by active tasks,
/// sorted alphabetically with task counts.
class TagBrowserScreen extends ConsumerWidget {
  const TagBrowserScreen({super.key});

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    TagBrowserEntry entry,
    String uid,
  ) async {
    final controller = TextEditingController(text: entry.name);
    final formKey = GlobalKey<FormState>();
    String? serverError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rename Tag'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('renameTagInput'),
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Tag Name',
                    errorText: serverError,
                  ),
                  onChanged: (_) {
                    if (serverError != null) {
                      setDialogState(() {
                        serverError = null;
                      });
                    }
                  },
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Tag name cannot be empty.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const Key('cancelRenameTagButton'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              key: const Key('confirmRenameTagButton'),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await ref.read(tagRepositoryProvider).renameTag(
                        uid: uid,
                        tagId: entry.tagId,
                        newName: controller.text.trim(),
                      );
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                } on ArgumentError catch (e) {
                  setDialogState(() {
                    serverError = e.message.toString();
                  });
                } catch (e) {
                  setDialogState(() {
                    serverError = 'Failed to rename tag: $e';
                  });
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    TagBrowserEntry entry,
    String uid,
  ) async {
    final warningText = entry.taskCount == 0
        ? 'Are you sure you want to delete this tag? No tasks are currently using it.'
        : '${entry.taskCount} active task(s) currently use this tag. It will be removed from these tasks.';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${entry.name}"?'),
        content: Text(
          warningText,
          key: const Key('deleteTagWarningText'),
        ),
        actions: [
          TextButton(
            key: const Key('cancelDeleteTagButton'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirmDeleteTagButton'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                final prefs = ref.read(sharedPreferencesProvider);
                await ref.read(tagRepositoryProvider).deleteTag(
                      uid: uid,
                      tagId: entry.tagId,
                      preferences: prefs,
                    );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Deleted tag "${entry.name}"'),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete tag: $e'),
                      backgroundColor: Colors.red,
                    ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(tagBrowserEntriesProvider);
    final uid = ref.watch(currentUidProvider);

    return Scaffold(
      key: const Key('tagBrowserScreen'),
      appBar: AppBar(
        title: const Text('Tags'),
      ),
      body: entriesAsync.when(
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
              child: Text(
                'No tags in use',
                key: Key('noTagsText'),
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];

              return ListTile(
                key: Key('tagBrowserItem_${entry.tagId}'),
                leading: const Icon(Icons.label_outline),
                title: Text(
                  entry.name,
                  key: Key('tagBrowserItemName_${entry.tagId}'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${entry.taskCount}',
                        key: Key('tagBrowserItemCount_${entry.tagId}'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    if (uid != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        key: Key('renameTagButton_${entry.tagId}'),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: 'Rename Tag',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _showRenameDialog(
                          context,
                          ref,
                          entry,
                          uid,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: Key('deleteTagButton_${entry.tagId}'),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.redAccent,
                        ),
                        tooltip: 'Delete Tag',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _showDeleteDialog(
                          context,
                          ref,
                          entry,
                          uid,
                        ),
                      ),
                    ],
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TagDetailScreen(
                        tagId: entry.tagId,
                        tagName: entry.name,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            key: Key('tagBrowserLoadingIndicator'),
          ),
        ),
        error: (err, _) => Center(child: Text('Error loading tags: $err')),
      ),
    );
  }
}
