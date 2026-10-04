import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback_snackbar.dart';
import '../../../core/ui/tag_format.dart';
import '../../tasks/providers/task_sort_providers.dart';
import '../../tasks/providers/task_tag_filter_providers.dart';
import '../providers/tag_providers.dart';

/// Displays a dialog to rename an existing tag.
///
/// Preserves the tag's bare name in storage while accepting inputs with or without
/// a leading '#' and displaying feedback with '#' formatting.
Future<void> showRenameTagDialog(
  BuildContext context,
  WidgetRef ref,
  TagBrowserEntry entry,
  String uid,
) async {
  final messenger = ScaffoldMessenger.of(context);
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
                  prefixText: '#',
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
                  if (val == null || stripTagPrefix(val).isEmpty) {
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
              final newName = stripTagPrefix(controller.text);
              if (newName == entry.name) {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                return;
              }
              try {
                await ref
                    .read(tagRepositoryProvider)
                    .renameTag(uid: uid, tagId: entry.tagId, newName: newName);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                showFeedbackSnackBar(
                  messenger,
                  'Renamed tag to "${formatTag(newName)}"',
                );
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

/// Displays a confirmation dialog to delete an existing tag, warning if active tasks use it.
Future<void> showDeleteTagDialog(
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
      title: Text('Delete "${formatTag(entry.name)}"?'),
      content: Text(warningText, key: const Key('deleteTagWarningText')),
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
              await ref
                  .read(tagRepositoryProvider)
                  .deleteTag(uid: uid, tagId: entry.tagId, preferences: prefs);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted tag "${formatTag(entry.name)}"'),
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
