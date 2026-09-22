import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/task_priority_filter.dart';
import '../../providers/task_sort_providers.dart';

/// Reusable priority filter dropdown selector for task lists and smart views.
class TaskPriorityFilterSelector extends ConsumerWidget {
  final String viewKey;

  const TaskPriorityFilterSelector({super.key, required this.viewKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFilter = ref.watch(taskPriorityFilterProvider(viewKey));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_outlined, size: 16, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Text(
            'Priority:',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          DropdownButtonHideUnderline(
            child: DropdownButton<TaskPriorityFilter>(
              key: Key('taskPriorityDropdown_$viewKey'),
              value: currentFilter,
              isDense: true,
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              borderRadius: BorderRadius.circular(8),
              items: TaskPriorityFilter.values.map((filter) {
                return DropdownMenuItem<TaskPriorityFilter>(
                  key: Key('taskPriorityOption_${viewKey}_${filter.name}'),
                  value: filter,
                  child: Text(
                    filter.label,
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              }).toList(),
              onChanged: (newFilter) {
                if (newFilter != null) {
                  ref
                      .read(taskPriorityFilterProvider(viewKey).notifier)
                      .setFilter(newFilter);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
