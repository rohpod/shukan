import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/smart_view_models.dart';
import '../providers/missed_tasks_providers.dart';
import 'smart_view_detail_screen.dart';

/// An in-app banner displayed once per app session when the user has overdue tasks.
///
/// Disappears when dismissed or when there are no overdue tasks.
class MissedTasksBanner extends ConsumerWidget {
  const MissedTasksBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDismissed = ref.watch(missedTasksBannerDismissedProvider);
    final count = ref.watch(overdueTaskCountProvider);

    if (isDismissed || count <= 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final backgroundColor = Colors.red.shade100;
    final foregroundColor = Colors.red.shade900;
    final message = count == 1 ? '1 task overdue' : '$count tasks overdue';

    return Material(
      color: backgroundColor,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Container(
          key: const Key('missedTasksBanner'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  key: const Key('missedTasksBannerTapArea'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SmartViewDetailScreen(
                          viewType: SmartViewType.today,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          key: const Key('missedTasksBannerIcon'),
                          size: 16,
                          color: foregroundColor,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            message,
                            key: const Key('missedTasksBannerText'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: foregroundColor,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('missedTasksBannerDismissButton'),
                icon: const Icon(Icons.close, size: 16),
                color: foregroundColor,
                tooltip: 'Dismiss',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () {
                  ref.read(missedTasksBannerDismissedProvider.notifier).state =
                      true;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
