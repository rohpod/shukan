import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lists/data/list.dart';
import '../../lists/presentation/list_detail_screen.dart';
import '../../lists/providers/list_providers.dart';
import '../providers/auth_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _showCreateDialog(
      BuildContext context, WidgetRef ref, String uid) async {
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
              await ref
                  .read(listRepositoryProvider)
                  .createList(uid: uid, name: name);
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
    final listsAsync = ref.watch(listsForUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('shukan'),
        actions: [
          IconButton(
            key: const Key('logoutButton'),
            icon: const Icon(Icons.logout),
            tooltip: 'Log Out',
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
            },
          ),
        ],
      ),
      floatingActionButton: uid != null
          ? FloatingActionButton(
              key: const Key('addListButton'),
              tooltip: 'New List',
              onPressed: () => _showCreateDialog(context, ref, uid),
              child: const Icon(Icons.add),
            )
          : null,
      body: SafeArea(
        child: listsAsync.when(
          data: (lists) {
            if (lists.isEmpty) {
              return const Center(
                child: Text('No lists found', key: Key('noListsText')),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                childAspectRatio: 1.25,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: lists.length,
              itemBuilder: (context, index) {
                final list = lists[index];

                return Card(
                  key: Key('listTile_${list.listId}'),
                  clipBehavior: Clip.antiAlias,
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    key: Key('listCard_${list.listId}'),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ListDetailScreen(list: list),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                list.isDefault
                                    ? Icons.inbox
                                    : Icons.folder_outlined,
                                color: list.isDefault
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                              ),
                              const Spacer(),
                              if (list.isDefault)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'DEFAULT',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            list.name,
                            key: Key('listName_${list.listId}'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                key: Key('renameListButton_${list.listId}'),
                                icon:
                                    const Icon(Icons.edit_outlined, size: 18),
                                tooltip: 'Rename List',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () =>
                                    _showRenameDialog(context, ref, list),
                              ),
                              if (!list.isDefault && uid != null) ...[
                                const SizedBox(width: 12),
                                IconButton(
                                  key: Key('deleteListButton_${list.listId}'),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.redAccent,
                                  ),
                                  tooltip: 'Delete List',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _showDeleteDialog(
                                      context, ref, list, uid),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
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
    );
  }
}
