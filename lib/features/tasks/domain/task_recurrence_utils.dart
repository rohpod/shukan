import '../../../core/notifications/notification_date_utils.dart';
import '../data/task.dart';
import 'calendar_utils.dart';
import 'custom_repeat.dart';

/// Computes the next occurrence for a repeating task based on [baseDate] and [repeatRule].
///
/// Supported [repeatRule] values:
/// - 'daily': advances by +1 day using DateTime calendar constructor (DST-safe)
/// - 'weekly': advances by +7 days using DateTime calendar constructor (DST-safe)
/// - 'monthly': advances to the next month, clamping to the last day of the target month
///   if [baseDate.day] exceeds the target month's length (e.g., Jan 31 -> Feb 28/29)
///   Pass [anchorDay] to clamp from the originally intended day instead of
///   [baseDate.day], so Jan 31 -> Feb 28 -> Mar 31 rather than drifting to Mar 28.
/// - 'custom': follows [customConfig] (see [CustomRepeat]); an invalid or
///   missing config returns [baseDate] unchanged
/// - other ('none' or unhandled): returns [baseDate] unchanged as a defensive default.
DateTime computeNextDueDate(
  DateTime baseDate,
  String repeatRule, {
  int? anchorDay,
  Map<String, dynamic>? customConfig,
}) {
  switch (repeatRule) {
    case 'custom':
      final custom = CustomRepeat.fromMap(customConfig);
      return custom == null ? baseDate : _nextCustom(baseDate, custom);
    case 'daily':
      return DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day + 1,
        baseDate.hour,
        baseDate.minute,
      );
    case 'weekly':
      return DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day + 7,
        baseDate.hour,
        baseDate.minute,
      );
    case 'monthly':
      final targetMonth = baseDate.month + 1;
      final targetYear = baseDate.year + (targetMonth > 12 ? 1 : 0);
      final normalizedMonth = targetMonth > 12 ? targetMonth - 12 : targetMonth;
      final lastDayOfTargetMonth = DateTime(
        targetYear,
        normalizedMonth + 1,
        0,
      ).day;
      final targetDay = anchorDay ?? baseDate.day;
      final clampedDay = targetDay > lastDayOfTargetMonth
          ? lastDayOfTargetMonth
          : targetDay;
      return DateTime(
        targetYear,
        normalizedMonth,
        clampedDay,
        baseDate.hour,
        baseDate.minute,
      );
    default:
      return baseDate;
  }
}

DateTime _nextCustom(DateTime base, CustomRepeat custom) {
  if (!custom.isWeekly) return addCalendarDays(base, custom.interval);

  // Weeks run Monday to Sunday. Take the next selected day later in this
  // week, otherwise jump `interval` weeks from this week's Monday. The base
  // weekday needn't be selected, since the user can pick any due date.
  final days = custom.weekdays;
  for (final day in days) {
    if (day > base.weekday) {
      return addCalendarDays(base, day - base.weekday);
    }
  }
  final mondayOffset = custom.interval * 7 - (base.weekday - 1);
  return addCalendarDays(base, mondayOffset + days.first - 1);
}

/// Whether completing [task] should advance it to a next occurrence.
///
/// A 'custom' task with a missing or invalid config doesn't repeat.
bool taskRepeats(Task task) {
  if (task.repeatRule == 'none') return false;
  if (task.repeatRule == 'custom') {
    return CustomRepeat.fromMap(task.repeatCustomConfig) != null;
  }
  return true;
}

/// A short description of how [task] repeats, e.g. `Daily` or
/// `Every 2 weeks on Mon, Wed`. Empty when it doesn't repeat.
String repeatSummary(Task task) {
  switch (task.repeatRule) {
    case 'daily':
      return 'Daily';
    case 'weekly':
      return 'Weekly';
    case 'monthly':
      return 'Monthly';
    case 'custom':
      return CustomRepeat.fromMap(task.repeatCustomConfig)?.summary ?? '';
    default:
      return '';
  }
}

/// The day of the month a monthly [task] is meant to fall on.
///
/// [Task.repeatAnchorDay] only counts while the due date is still that day
/// clamped to its month. Once the user picks a different date, the new date
/// becomes the anchor.
int resolveRepeatAnchorDay(Task task) {
  final dueDate = task.dueDate;
  if (dueDate == null) return task.repeatAnchorDay ?? 1;
  final anchor = task.repeatAnchorDay;
  if (anchor == null) return dueDate.day;
  final lastDay = DateTime(dueDate.year, dueDate.month + 1, 0).day;
  return dueDate.day == (anchor > lastDay ? lastDay : anchor)
      ? anchor
      : dueDate.day;
}

/// Returns the first occurrence of repeating [task] after its current due date
/// that is not already overdue at [now].
///
/// Tasks with no due date repeat from the start of today.
DateTime nextOccurrenceAfter(Task task, DateTime now) {
  final anchorDay = resolveRepeatAnchorDay(task);
  var next = task.dueDate ?? DateTime(now.year, now.month, now.day);
  while (true) {
    final following = computeNextDueDate(
      next,
      task.repeatRule,
      anchorDay: anchorDay,
      customConfig: task.repeatCustomConfig,
    );
    if (!following.isAfter(next)) return next;
    next = following;
    if (!isTaskOverdue(dueDate: next, dueTime: task.dueTime, now: now)) {
      return next;
    }
  }
}
