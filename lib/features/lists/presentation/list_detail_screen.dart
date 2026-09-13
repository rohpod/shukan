import 'package:flutter/material.dart';

import '../../tasks/presentation/task_list_screen.dart';
import '../data/list.dart';

class ListDetailScreen extends StatelessWidget {
  final ListModel list;

  const ListDetailScreen({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          list.name,
          key: const Key('listDetailTitle'),
        ),
      ),
      body: TaskListScreen(
        key: ValueKey(list.listId),
        listId: list.listId,
      ),
    );
  }
}
