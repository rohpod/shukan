import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../export/export_service.dart';
import '../../tasks/data/task.dart';
import '../../tasks/presentation/task_list_screen.dart';
import '../../tasks/providers/task_providers.dart';
import '../data/list.dart';

class ListDetailScreen extends ConsumerWidget {
  final ListModel list;
  final void Function(String content, String filename)? downloadTrigger;

  const ListDetailScreen({super.key, required this.list, this.downloadTrigger});

  Future<void> _exportList(BuildContext context, WidgetRef ref) async {
    try {
      final exportService = ref.read(exportServiceProvider);

      final tasksAsync = ref.read(tasksForListProvider(list.listId));
      final List<Task> tasks;
      if (tasksAsync.hasValue) {
        tasks = tasksAsync.value!;
      } else {
        final firestore = ref.read(firestoreProvider);
        final snapshot = await firestore
            .collection('tasks')
            .where('listId', isEqualTo: list.listId)
            .where('deletedAt', isNull: true)
            .get();
        tasks = snapshot.docs.map(Task.fromFirestore).toList();
      }

      await exportService.exportAndDownload(
        listName: list.name,
        tasks: tasks,
        downloadTrigger: downloadTrigger,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported "${list.name}" to markdown')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to export list: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(list.name, key: const Key('listDetailTitle')),
        actions: [
          IconButton(
            key: const Key('exportListButton'),
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export',
            onPressed: () => _exportList(context, ref),
          ),
        ],
      ),
      body: TaskListScreen(key: ValueKey(list.listId), listId: list.listId),
    );
  }
}
