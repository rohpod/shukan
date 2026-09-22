import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/domain/smart_view_models.dart';

void main() {
  group('SmartViewDateUtils', () {
    test('startOfDay returns 00:00:00.000 for local date', () {
      final date = DateTime(2026, 10, 15, 14, 30, 45, 123);
      final start = SmartViewDateUtils.startOfDay(date);
      expect(start, equals(DateTime(2026, 10, 15, 0, 0, 0, 0)));
    });

    test('endOfDay returns 23:59:59.999 for local date', () {
      final date = DateTime(2026, 10, 15, 14, 30);
      final end = SmartViewDateUtils.endOfDay(date);
      expect(end, equals(DateTime(2026, 10, 15, 23, 59, 59, 999)));
    });

    test('startOfWeek returns Monday 00:00:00 for any day in the week', () {
      // 2026-10-14 is Wednesday
      final wednesday = DateTime(2026, 10, 14, 16, 0);
      final monday = SmartViewDateUtils.startOfWeek(wednesday);
      expect(monday, equals(DateTime(2026, 10, 12, 0, 0, 0, 0)));
      expect(monday.weekday, equals(DateTime.monday));

      // 2026-10-18 is Sunday (should still resolve to 2026-10-12 Monday)
      final sunday = DateTime(2026, 10, 18, 22, 0);
      final mondayFromSunday = SmartViewDateUtils.startOfWeek(sunday);
      expect(mondayFromSunday, equals(DateTime(2026, 10, 12, 0, 0, 0, 0)));

      // 2026-10-12 is Monday
      final mondayItself = DateTime(2026, 10, 12, 9, 0);
      expect(
        SmartViewDateUtils.startOfWeek(mondayItself),
        equals(DateTime(2026, 10, 12, 0, 0)),
      );
    });

    test('endOfWeek returns Sunday 23:59:59.999 for the current week', () {
      final wednesday = DateTime(2026, 10, 14, 16, 0);
      final sundayEnd = SmartViewDateUtils.endOfWeek(wednesday);
      expect(sundayEnd, equals(DateTime(2026, 10, 18, 23, 59, 59, 999)));
      expect(sundayEnd.weekday, equals(DateTime.sunday));
    });

    test('isOverdue returns true when dueDate is strictly before start of current day', () {
      final today = DateTime(2026, 10, 15, 14, 30);
      final yesterday = DateTime(2026, 10, 14, 23, 59);
      final earlierToday = DateTime(2026, 10, 15, 8, 0);
      final tomorrow = DateTime(2026, 10, 16, 9, 0);

      expect(SmartViewDateUtils.isOverdue(yesterday, today), isTrue);
      expect(SmartViewDateUtils.isOverdue(earlierToday, today), isFalse);
      expect(SmartViewDateUtils.isOverdue(tomorrow, today), isFalse);
      expect(SmartViewDateUtils.isOverdue(null, today), isFalse);
    });

    test('isSameCalendarDay compares year, month, and day correctly', () {
      final d1 = DateTime(2026, 10, 15, 8, 0);
      final d2 = DateTime(2026, 10, 15, 23, 30);
      final d3 = DateTime(2026, 10, 16, 0, 1);

      expect(SmartViewDateUtils.isSameCalendarDay(d1, d2), isTrue);
      expect(SmartViewDateUtils.isSameCalendarDay(d1, d3), isFalse);
    });
  });
}
