import 'package:flutter/material.dart';

import '../../domain/task_constants.dart';

class TaskPriorityMarker extends StatelessWidget {
  const TaskPriorityMarker({
    super.key,
    required this.priority,
    required this.taskId,
  });

  final String priority;
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final marker = taskPriorityMarker(priority);
    if (marker == null) return const SizedBox.shrink();
    return Text(
      marker,
      key: Key('taskPriorityMarker_$taskId'),
      semanticsLabel: '$priority priority',
      style: const TextStyle(fontSize: 14),
    );
  }
}
