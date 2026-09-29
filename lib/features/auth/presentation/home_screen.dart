import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback_snackbar.dart';
import '../../lists/data/list.dart';
import '../../lists/presentation/list_detail_screen.dart';
import '../../lists/providers/list_providers.dart';
import '../../tags/presentation/tag_browser_screen.dart';
import '../../search/presentation/search_screen.dart';
import '../../tasks/domain/smart_view_models.dart';
import '../../tasks/presentation/missed_tasks_banner.dart';
import '../../tasks/presentation/recently_deleted_screen.dart';
import '../../tasks/presentation/smart_view_detail_screen.dart';
import '../../tasks/providers/smart_view_providers.dart';
import '../../tasks/providers/task_providers.dart';
import '../providers/auth_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _showCreateDialog(
    BuildContext context,
    WidgetRef ref,
    String uid,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
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
              showFeedbackSnackBar(messenger, 'Created list "$name"');
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    ListModel list,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
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
              final newName = controller.text.trim();
              if (newName == list.name) {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                return;
              }
              await ref
                  .read(listRepositoryProvider)
                  .renameList(list.listId, newName);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              showFeedbackSnackBar(messenger, 'Renamed list to "$newName"');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    ListModel list,
    String uid,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final listName = list.name;
    final taskCount = await ref
        .read(listRepositoryProvider)
        .getActiveTaskCountForList(uid: uid, listId: list.listId);

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "$listName"?'),
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
              showFeedbackSnackBar(messenger, 'Deleted list "$listName"');
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
    final recentlyDeletedCount = ref.watch(recentlyDeletedCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('shukan'),
        actions: [
          IconButton(
            key: const Key('tagBrowserButton'),
            icon: const Icon(Icons.label_outline),
            tooltip: 'Tags',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TagBrowserScreen(),
                ),
              );
            },
          ),
          IconButton(
            key: const Key('searchButton'),
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
              );
            },
          ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MissedTasksBanner(),
            _buildSmartViews(context, ref),
            Expanded(
              child: listsAsync.when(
                data: (lists) {
                  final showRecentlyDeleted = recentlyDeletedCount > 0;
                  if (lists.isEmpty && !showRecentlyDeleted) {
                    return const Center(
                      child: Text('No lists found', key: Key('noListsText')),
                    );
                  }

                  final totalItemCount =
                      lists.length + (showRecentlyDeleted ? 1 : 0);

                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 280,
                          childAspectRatio: 1.0,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: totalItemCount,
                    itemBuilder: (context, index) {
                      if (index < lists.length) {
                        final list = lists[index];
                        return _buildUserListCard(context, ref, list, uid);
                      }
                      return _buildRecentlyDeletedCard(
                        context,
                        recentlyDeletedCount,
                      );
                    },
                  );
                },
                loading: () => const Center(
                  key: Key('listsLoadingIndicator'),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Center(child: Text('Error loading lists: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountBadge(
    BuildContext context,
    int count, {
    Key? badgeKey,
    Key? textKey,
  }) {
    final theme = Theme.of(context);
    return Container(
      key: badgeKey,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: count > 0
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        key: textKey,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: count > 0
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildListCard({
    required BuildContext context,
    required Key cardKey,
    required Key inkWellKey,
    required VoidCallback onTap,
    required Widget icon,
    required Widget countBadge,
    required String title,
    required Key titleKey,
    Widget? tag,
    Widget? actions,
  }) {
    return Card(
      key: cardKey,
      clipBehavior: Clip.antiAlias,
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        key: inkWellKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  icon,
                  const Spacer(),
                  if (tag != null) ...[tag, const SizedBox(width: 6)],
                  countBadge,
                ],
              ),
              const Spacer(),
              Text(
                title,
                key: titleKey,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              actions ?? const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserListCard(
    BuildContext context,
    WidgetRef ref,
    ListModel list,
    String? uid,
  ) {
    final theme = Theme.of(context);
    return _buildListCard(
      context: context,
      cardKey: Key('listTile_${list.listId}'),
      inkWellKey: Key('listCard_${list.listId}'),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ListDetailScreen(list: list)),
        );
      },
      icon: Icon(
        list.isDefault ? Icons.inbox : Icons.folder_outlined,
        color: list.isDefault
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      tag: list.isDefault
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'DEFAULT',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      countBadge: Consumer(
        builder: (context, ref, _) {
          final count = ref.watch(activeTaskCountForListProvider(list.listId));
          return _buildCountBadge(
            context,
            count,
            badgeKey: Key('taskCountBadge_${list.listId}'),
            textKey: Key('taskCountText_${list.listId}'),
          );
        },
      ),
      title: list.name,
      titleKey: Key('listName_${list.listId}'),
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            key: Key('renameListButton_${list.listId}'),
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Rename List',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _showRenameDialog(context, ref, list),
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
              onPressed: () => _showDeleteDialog(context, ref, list, uid),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentlyDeletedCard(BuildContext context, int count) {
    final theme = Theme.of(context);
    return _buildListCard(
      context: context,
      cardKey: const Key('listTile_recentlyDeleted'),
      inkWellKey: const Key('listCard_recentlyDeleted'),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const RecentlyDeletedScreen(),
          ),
        );
      },
      icon: Icon(
        Icons.delete_outline,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      countBadge: _buildCountBadge(
        context,
        count,
        badgeKey: const Key('taskCountBadge_recentlyDeleted'),
        textKey: const Key('taskCountText_recentlyDeleted'),
      ),
      title: 'Recently Deleted',
      titleKey: const Key('listName_recentlyDeleted'),
      actions: null,
    );
  }

  Widget _buildSmartViews(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSmartViewCard(context, ref, SmartViewType.today),
              const SizedBox(width: 8),
              _buildSmartViewCard(context, ref, SmartViewType.thisWeek),
              const SizedBox(width: 8),
              _buildSmartViewCard(context, ref, SmartViewType.scheduled),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildSmartViewCard(
    BuildContext context,
    WidgetRef ref,
    SmartViewType type,
  ) {
    final count = ref.watch(smartViewCountProvider(type));
    final theme = Theme.of(context);

    return Expanded(
      child: Card(
        key: Key('smartViewCard_${type.name}'),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: InkWell(
          key: Key('smartViewInkWell_${type.name}'),
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SmartViewDetailScreen(viewType: type),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(type.icon, size: 22, color: theme.colorScheme.primary),
                    if (count > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          key: Key('smartViewCount_${type.name}'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  type.label,
                  key: Key('smartViewLabel_${type.name}'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
