import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/smart_view_providers.dart';

/// Formats a 24-hour time string ("HH:mm") into 12-hour AM/PM format (e.g. "5:00 PM").
String formatDueTime12Hour(String dueTime24) {
  final parts = dueTime24.split(':');
  if (parts.length != 2) return dueTime24;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;
  final ampm = h >= 12 ? 'PM' : 'AM';
  final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  final mStr = m.toString().padLeft(2, '0');
  return '$h12:$mStr $ampm';
}

/// Formats a [DateTime] relative to [now] as 'Today', 'Tomorrow', 'Yesterday', or 'YYYY-MM-DD'.
String formatPreviewDate(DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Builds the label text for the preview chip combining the formatted date and time.
String buildQuickAddChipLabel({
  DateTime? dueDate,
  String? dueTime,
  required DateTime now,
}) {
  final parts = <String>[];
  if (dueDate != null) {
    parts.add(formatPreviewDate(dueDate, now));
  }
  if (dueTime != null) {
    parts.add(formatDueTime12Hour(dueTime));
  }
  return parts.join(' ');
}

/// A chip displaying the parsed date and/or time preview with a dismiss button.
class QuickAddPreviewChip extends ConsumerWidget {
  final DateTime? dueDate;
  final String? dueTime;
  final VoidCallback onDismiss;

  const QuickAddPreviewChip({
    super.key,
    this.dueDate,
    this.dueTime,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(currentDateProvider);
    final label = buildQuickAddChipLabel(
      dueDate: dueDate,
      dueTime: dueTime,
      now: now,
    );

    return Chip(
      key: const Key('quickAddDateChip'),
      avatar: Icon(
        Icons.event_outlined,
        size: 16,
        color: theme.colorScheme.primary,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      deleteIcon: const Icon(Icons.close, size: 14),
      deleteButtonTooltipMessage: 'Remove date/time',
      onDeleted: onDismiss,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
