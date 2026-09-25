/// Computes the next occurrence for a repeating task based on [baseDate] and [repeatRule].
///
/// Supported [repeatRule] values:
/// - 'daily': advances by +1 day using DateTime calendar constructor (DST-safe)
/// - 'weekly': advances by +7 days using DateTime calendar constructor (DST-safe)
/// - 'monthly': advances to the next month, clamping to the last day of the target month
///   if [baseDate.day] exceeds the target month's length (e.g., Jan 31 -> Feb 28/29)
/// - other ('none', 'custom', or unhandled): returns [baseDate] unchanged as a defensive default.
DateTime computeNextDueDate(DateTime baseDate, String repeatRule) {
  switch (repeatRule) {
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
      final clampedDay = baseDate.day > lastDayOfTargetMonth
          ? lastDayOfTargetMonth
          : baseDate.day;
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
