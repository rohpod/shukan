import 'package:flutter/material.dart';

enum SmartViewType {
  today('Today', Icons.today),
  thisWeek('This Week', Icons.calendar_view_week),
  scheduled('Scheduled', Icons.event_note);

  final String label;
  final IconData icon;
  const SmartViewType(this.label, this.icon);
}

enum WeekFilter {
  workWeek('Work week', 'Mon–Fri'),
  fullWeek('Full week', 'Mon–Sun');

  final String label;
  final String subtitle;
  const WeekFilter(this.label, this.subtitle);
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

  /// Returns the end of week (Friday 23:59:59.999 for workWeek, Sunday 23:59:59.999 for fullWeek) in local time.
  static DateTime endOfWeek(DateTime date, WeekFilter filter) {
    final diff = date.weekday - DateTime.monday;
    final monday = DateTime(date.year, date.month, date.day - diff);
    final targetDayOffset = filter == WeekFilter.workWeek
        ? 4
        : 6; // +4 for Fri, +6 for Sun
    final targetDay = monday.add(Duration(days: targetDayOffset));
    return endOfDay(targetDay);
  }

  /// Returns true if [a] and [b] fall on the same local calendar day.
  static bool isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
