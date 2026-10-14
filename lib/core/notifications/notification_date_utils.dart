import 'package:timezone/timezone.dart' as tz;

/// Sensible default hour and minute for date-only tasks without a specified dueTime.
/// Set to 9:00 AM (09:00) local time.
const int kDefaultDateOnlyHour = 9;
const int kDefaultDateOnlyMinute = 0;

/// Parses a "HH:mm" time string, returning `(hour, minute)`.
/// Defaults to (kDefaultDateOnlyHour, kDefaultDateOnlyMinute) (09:00) if missing or malformed.
(int, int) parseDueTime(String? dueTime) {
  int hour = kDefaultDateOnlyHour;
  int minute = kDefaultDateOnlyMinute;

  if (dueTime != null && dueTime.trim().isNotEmpty) {
    final parts = dueTime.trim().split(':');
    if (parts.length == 2) {
      final parsedH = int.tryParse(parts[0]);
      final parsedM = int.tryParse(parts[1]);
      if (parsedH != null &&
          parsedM != null &&
          parsedH >= 0 &&
          parsedH <= 23 &&
          parsedM >= 0 &&
          parsedM <= 59) {
        hour = parsedH;
        minute = parsedM;
      }
    }
  }

  return (hour, minute);
}

/// Resolves the local [tz.TZDateTime] representing the exact calendar date and time for a task.
///
/// If [dueTime] is omitted or malformed, defaults to 9:00 AM local time.
tz.TZDateTime? resolveTaskDueDateTime({
  required DateTime? dueDate,
  String? dueTime,
}) {
  if (dueDate == null) return null;

  final (hour, minute) = parseDueTime(dueTime);

  // Ensure calendar day components are interpreted in local time.
  final localDate = dueDate.toLocal();
  return tz.TZDateTime(
    tz.local,
    localDate.year,
    localDate.month,
    localDate.day,
    hour,
    minute,
  );
}

/// Resolves a plain local [DateTime] representing the exact calendar date and time for a task.
///
/// It does NOT use [tz.local], because the web timezone lookup can fail and leave [tz.local] as UTC.
/// Defaults to 9:00 AM local time when [dueTime] is missing or malformed.
DateTime? resolveTaskDueDateTimeLocal({
  required DateTime? dueDate,
  String? dueTime,
}) {
  if (dueDate == null) return null;

  final (hour, minute) = parseDueTime(dueTime);

  final localDate = dueDate.toLocal();
  return DateTime(localDate.year, localDate.month, localDate.day, hour, minute);
}

/// Pure utility that computes the exact [tz.TZDateTime] at which the main task notification should fire.
///
/// The fire time is computed exactly AT [dueDate] + [dueTime] (or 9:00 AM local time for date-only tasks),
/// independent of any early reminder settings.
///
/// Parameters:
/// - [dueDate]: The calendar date of the task. If null, returns null.
/// - [dueTime]: Optional 24-hour time string in "HH:mm" format. If null, empty, or malformed,
///   defaults to 9:00 AM (09:00) local time.
/// - [now]: Reference timestamp for past check (defaults to `DateTime.now()`).
///
/// Returns:
/// - The computed [tz.TZDateTime] in [tz.local].
/// - `null` if [dueDate] is null or if the computed fire time is strictly in the past
///   relative to [now]. When null is returned for a past task, callers should cancel any
///   existing notification.
tz.TZDateTime? computeTaskFireTime({
  required DateTime? dueDate,
  String? dueTime,
  DateTime? now,
}) {
  final scheduledLocal = resolveTaskDueDateTime(
    dueDate: dueDate,
    dueTime: dueTime,
  );
  if (scheduledLocal == null) return null;

  final referenceNow = now ?? DateTime.now();
  if (scheduledLocal.isBefore(referenceNow)) {
    return null;
  }

  return scheduledLocal;
}

/// Pure utility that computes the exact [tz.TZDateTime] at which an early reminder notification should fire.
///
/// Parameters:
/// - [dueDate]: The calendar date of the task. If null, returns null.
/// - [dueTime]: Optional 24-hour time string in "HH:mm" format. If null, empty, or malformed,
///   defaults to 9:00 AM (09:00) local time.
/// - [earlyReminderMinutes]: Minutes prior to the due time when the notification should fire.
///   If <= 0, returns null.
/// - [now]: Reference timestamp for past check (defaults to `DateTime.now()`).
///
/// Returns:
/// - The computed [tz.TZDateTime] in [tz.local] (due time minus [earlyReminderMinutes]).
/// - `null` if [dueDate] is null, [earlyReminderMinutes] <= 0, or if the early reminder fire time
///   is strictly in the past relative to [now].
tz.TZDateTime? computeEarlyReminderFireTime({
  required DateTime? dueDate,
  String? dueTime,
  required int earlyReminderMinutes,
  DateTime? now,
}) {
  if (earlyReminderMinutes <= 0) return null;

  final scheduledLocal = resolveTaskDueDateTime(
    dueDate: dueDate,
    dueTime: dueTime,
  );
  if (scheduledLocal == null) return null;

  final earlyFireTime = scheduledLocal.subtract(
    Duration(minutes: earlyReminderMinutes),
  );

  final referenceNow = now ?? DateTime.now();
  if (earlyFireTime.isBefore(referenceNow)) {
    return null;
  }

  return earlyFireTime;
}
