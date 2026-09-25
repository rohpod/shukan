import 'package:flutter/material.dart';

/// Reusable empty-state view for zero-task screens, supporting both genuinely
/// empty and filtered-to-zero states with optional action buttons.
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String message;
  final Key? messageKey;
  final String? actionLabel;
  final IconData? actionIcon;
  final Key? actionKey;
  final VoidCallback? onAction;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.message,
    this.messageKey,
    this.actionLabel,
    this.actionIcon,
    this.actionKey,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              key: messageKey,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              if (actionIcon != null)
                OutlinedButton.icon(
                  key: actionKey,
                  onPressed: onAction,
                  icon: Icon(actionIcon, size: 18),
                  label: Text(actionLabel!),
                )
              else
                OutlinedButton(
                  key: actionKey,
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
