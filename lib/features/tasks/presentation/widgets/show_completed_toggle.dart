import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/task_sort_providers.dart';

/// Reusable toggle button for showing / hiding completed tasks in task lists and smart views.
class ShowCompletedToggle extends ConsumerWidget {
  final String viewKey;

  const ShowCompletedToggle({super.key, required this.viewKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showCompleted = ref.watch(showCompletedTasksProvider(viewKey));

    return Tooltip(
      message: showCompleted ? 'Hide completed tasks' : 'Show completed tasks',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('toggleShowCompleted_$viewKey'),
          onTap: () {
            ref.read(showCompletedTasksProvider(viewKey).notifier).toggle();
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: showCompleted
                  ? Theme.of(context).colorScheme.primaryContainer
                        .withValues(alpha: 0.5)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: showCompleted
                    ? Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.5)
                    : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  showCompleted
                      ? Icons.visibility
                      : Icons.visibility_off_outlined,
                  size: 16,
                  color: showCompleted
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[700],
                ),
                const SizedBox(width: 6),
                Text(
                  'Show completed',
                  style: TextStyle(
                    fontSize: 12,
                    color: showCompleted
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[700],
                    fontWeight: showCompleted
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
