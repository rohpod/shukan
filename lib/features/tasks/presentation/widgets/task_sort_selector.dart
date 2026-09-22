import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/task_sort_options.dart';
import '../../providers/task_sort_providers.dart';

/// Reusable sort selector widget for task lists and smart views.
class TaskSortSelector extends ConsumerWidget {
  final String viewKey;

  const TaskSortSelector({super.key, required this.viewKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSort = ref.watch(taskSortModeProvider(viewKey));

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
          Icon(Icons.sort, size: 16, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Text(
            'Sort:',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          DropdownButtonHideUnderline(
            child: DropdownButton<TaskSortOption>(
              key: Key('taskSortDropdown_$viewKey'),
              value: currentSort,
              isDense: true,
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              borderRadius: BorderRadius.circular(8),
              items: TaskSortOption.values.map((option) {
                return DropdownMenuItem<TaskSortOption>(
                  key: Key('taskSortOption_${viewKey}_${option.name}'),
                  value: option,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(option.icon, size: 14, color: Colors.grey[700]),
                      const SizedBox(width: 6),
                      Text(option.label, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (newOption) {
                if (newOption != null) {
                  ref
                      .read(taskSortModeProvider(viewKey).notifier)
                      .setSortMode(newOption);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
