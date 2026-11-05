/// Returns [date] moved by [days] calendar days, keeping its time of day.
///
/// Use this instead of `date.add(Duration(days: n))`: a calendar day is not
/// always 24 hours, so adding a [Duration] lands on the wrong date across a
/// daylight-saving change.
DateTime addCalendarDays(DateTime date, int days) {
  return DateTime(
    date.year,
    date.month,
    date.day + days,
    date.hour,
    date.minute,
    date.second,
    date.millisecond,
  );
}
