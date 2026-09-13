import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../tasks/providers/task_providers.dart';
import '../data/list.dart';
import '../providers/list_providers.dart';

class ListsDrawer extends ConsumerWidget {
  const ListsDrawer({super.key});

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref, String uid) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create New List'),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('createListNameInput'),
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'List Name',
              hintText: 'e.g. Work, Groceries',
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter a list name.';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirmCreateListButton'),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final name = controller.text.trim();
              final created = await ref
                  .read(listRepositoryProvider)
                  .createList(uid: uid, name: name);
              ref.read(selectedListIdProvider.notifier).state = created.listId;
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(
      BuildContext context, WidgetRef ref, ListModel list) async {
    final controller = TextEditingController(text: list.name);
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename List'),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('renameListInput'),
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'New Name'),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'List name cannot be empty.';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirmRenameListButton'),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await ref
                  .read(listRepositoryProvider)
                  .renameList(list.listId, controller.text.trim());
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteDialog(
      BuildContext context, WidgetRef ref, ListModel list, String uid) async {
    final taskCount = await ref
        .read(listRepositoryProvider)
        .getActiveTaskCountForList(uid: uid, listId: list.listId);

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${list.name}"?'),
        content: Text(
          '$taskCount task(s) in this list will also be removed.',
          key: const Key('deleteListWarningText'),
        ),
        actions: [
          TextButton(
            key: const Key('cancelDeleteListButton'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirmDeleteListButton'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await ref
                  .read(listRepositoryProvider)
                  .deleteList(list.listId, uid);
              if (ref.read(selectedListIdProvider) == list.listId) {
                ref.read(selectedListIdProvider.notifier).state = null;
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
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
    final uid = ref.watch(currentUidProvider);
    final user = ref.watch(currentUserProvider);
    final listsAsync = ref.watch(listsForUserProvider);
    final selectedListId = ref.watch(selectedListIdProvider);
    final defaultListId = ref.watch(defaultListIdProvider).value;
    final activeListId = selectedListId ?? defaultListId;

    return Drawer(
      key: const Key('listsDrawer'),
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lists',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (user?.email != null)
                          Text(
                            user!.email!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer
                                  .withValues(alpha: 0.8),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (uid != null)
                    IconButton(
                      key: const Key('addListButton'),
                      icon: const Icon(Icons.add),
                      tooltip: 'New List',
                      onPressed: () => _showCreateDialog(context, ref, uid),
                    ),
                ],
              ),
            ),

            // Lists list
            Expanded(
              child: listsAsync.when(
                data: (lists) {
                  if (lists.isEmpty) {
                    return const Center(
                      child: Text('No lists found', key: Key('noListsText')),
                    );
                  }

                  return ListView.builder(
                    itemCount: lists.length,
                    itemBuilder: (context, index) {
                      final list = lists[index];
                      final isSelected = list.listId == activeListId;

                      return ListTile(
                        key: Key('listTile_${list.listId}'),
                        selected: isSelected,
                        selectedTileColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.12),
                        leading: Icon(
                          list.isDefault ? Icons.inbox : Icons.list_alt,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                list.name,
                                key: Key('listName_${list.listId}'),
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (list.isDefault)
                              Container(
                                margin: const EdgeInsets.only(left: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'DEFAULT',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: Key('renameListButton_${list.listId}'),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Rename List',
                              onPressed: () =>
                                  _showRenameDialog(context, ref, list),
                            ),
                            // Layer 3 defence-in-depth: hidden if isDefault
                            if (!list.isDefault && uid != null)
                              IconButton(
                                key: Key('deleteListButton_${list.listId}'),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
                                tooltip: 'Delete List',
                                onPressed: () =>
                                  _showDeleteDialog(context, ref, list, uid),
                              ),
                          ],
                        ),
                        onTap: () {
                          ref.read(selectedListIdProvider.notifier).state =
                              list.listId;
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(
                  key: Key('listsLoadingIndicator'),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Center(
                  child: Text('Error loading lists: $e'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
