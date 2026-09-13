import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_status_provider.dart';

/// A persistent banner displayed when the app is offline or has uncommitted changes.
///
/// Disappears completely when [SyncStatus.synced].
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatusAsync = ref.watch(syncStatusProvider);
    final status = syncStatusAsync.value ?? SyncStatus.synced;

    if (status == SyncStatus.synced) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isPendingWrites = status == SyncStatus.offlinePendingWrites;

    // Theme-derived colours for unobtrusive presentation
    final Color backgroundColor;
    final Color foregroundColor;
    final String message;
    final IconData icon;

    if (isPendingWrites) {
      backgroundColor = Colors.amber.shade100;
      foregroundColor = Colors.amber.shade900;
      message = 'Offline — changes will sync when reconnected';
      icon = Icons.cloud_off_rounded;
    } else {
      backgroundColor = theme.colorScheme.surfaceContainerHighest;
      foregroundColor = theme.colorScheme.onSurfaceVariant;
      message = 'Offline — working from cache';
      icon = Icons.cloud_off_outlined;
    }

    return Material(
      color: backgroundColor,
      child: SafeArea(
        top: true,
        bottom: false,
        child: Container(
          key: const Key('syncBanner'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                key: const Key('syncBannerIcon'),
                size: 16,
                color: foregroundColor,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  key: const Key('syncBannerText'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
