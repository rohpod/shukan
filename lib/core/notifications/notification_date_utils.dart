import 'package:timezone/timezone.dart' as tz;

/// Sensible default hour and minute for date-only tasks without a specified dueTime.
/// Set to 9:00 AM (09:00) local time.
const int kDefaultDateOnlyHour = 9;
const int kDefaultDateOnlyMinute = 0;

/// Pure utility that computes the exact [tz.TZDateTime] at which a notification should fire.
///
/// Parameters:
/// - [dueDate]: The calendar date of the task. If null, returns null.
/// - [dueTime]: Optional 24-hour time string in "HH:mm" format. If null, empty, or malformed,
///   defaults to 9:00 AM (09:00) local time.
/// - [earlyReminderMinutes]: Minutes prior to the due time when the notification should fire.
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
  int earlyReminderMinutes = 0,
  DateTime? now,
}) {
  if (dueDate == null) return null;

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

  // Ensure calendar day components are interpreted in local time.
  final localDate = dueDate.toLocal();
  final scheduledLocal = tz.TZDateTime(
    tz.local,
    localDate.year,
    localDate.month,
    localDate.day,
    hour,
    minute,
  );

  final fireTime = earlyReminderMinutes > 0
      ? scheduledLocal.subtract(Duration(minutes: earlyReminderMinutes))
      : scheduledLocal;

  final referenceNow = now ?? DateTime.now();
  if (fireTime.isBefore(referenceNow)) {
    return null;
  }

  return fireTime;
}
