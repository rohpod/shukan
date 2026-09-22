import 'package:flutter/material.dart';

enum SmartViewType {
  today('Today', Icons.today),
  thisWeek('This Week', Icons.calendar_view_week),
  scheduled('Scheduled', Icons.event_note);

  final String label;
  final IconData icon;
  const SmartViewType(this.label, this.icon);
}

enum CompletionFilter {
  incomplete('Incomplete'),
  completed('Completed'),
  all('All');

  final String label;
  const CompletionFilter(this.label);
}

class SmartViewDateUtils {
  const SmartViewDateUtils._();

  /// Returns the start of day (00:00:00.000) for [date] in local time.
  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Returns the end of day (23:59:59.999) for [date] in local time.
  static DateTime endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  /// Returns the Monday 00:00:00.000 of the week containing [date] in local time.
  static DateTime startOfWeek(DateTime date) {
    final diff = date.weekday - DateTime.monday;
    final monday = DateTime(date.year, date.month, date.day - diff);
    return startOfDay(monday);
  }

  /// Returns the Sunday 23:59:59.999 of the week containing [date] in local time.
  static DateTime endOfWeek(DateTime date) {
    final diff = date.weekday - DateTime.monday;
    final monday = DateTime(date.year, date.month, date.day - diff);
    final sunday = monday.add(const Duration(days: 6));
    return endOfDay(sunday);
  }

  /// Returns true if [a] and [b] fall on the same local calendar day.
  static bool isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Returns true if [dueDate] falls strictly before the start of the calendar day of [currentDate] in local time.
  static bool isOverdue(DateTime? dueDate, DateTime currentDate) {
    if (dueDate == null) return false;
    final startOfCurrentDay = startOfDay(currentDate);
    return dueDate.isBefore(startOfCurrentDay);
  }
}
