import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/domain/task_recurrence_utils.dart';

void main() {
  group('computeNextDueDate', () {
    group('daily', () {
      test('advances by simple +1 day', () {
        final base = DateTime(2026, 5, 10, 14, 30);
        final next = computeNextDueDate(base, 'daily');
        expect(next, equals(DateTime(2026, 5, 11, 14, 30)));
      });

      test('advances across month boundary', () {
        final base = DateTime(2026, 1, 31, 9, 0);
        final next = computeNextDueDate(base, 'daily');
        expect(next, equals(DateTime(2026, 2, 1, 9, 0)));
      });

      test('advances across year boundary', () {
        final base = DateTime(2026, 12, 31, 23, 59);
        final next = computeNextDueDate(base, 'daily');
        expect(next, equals(DateTime(2027, 1, 1, 23, 59)));
      });
    });

    group('weekly', () {
      test('advances by simple +7 days', () {
        final base = DateTime(2026, 5, 10, 10, 15);
        final next = computeNextDueDate(base, 'weekly');
        expect(next, equals(DateTime(2026, 5, 17, 10, 15)));
      });

      test('advances across month boundary', () {
        final base = DateTime(2026, 1, 28, 8, 45);
        final next = computeNextDueDate(base, 'weekly');
        expect(next, equals(DateTime(2026, 2, 4, 8, 45)));
      });

      test('advances across year boundary', () {
        final base = DateTime(2026, 12, 28, 12, 0);
        final next = computeNextDueDate(base, 'weekly');
        expect(next, equals(DateTime(2027, 1, 4, 12, 0)));
      });
    });

    group('monthly clamping', () {
      test('Jan 31 -> Feb 28 in non-leap year (2026)', () {
        final base = DateTime(2026, 1, 31, 16, 0);
        final next = computeNextDueDate(base, 'monthly');
        expect(next, equals(DateTime(2026, 2, 28, 16, 0)));
      });

      test('Jan 31 -> Feb 29 in leap year (2028)', () {
        final base = DateTime(2028, 1, 31, 16, 0);
        final next = computeNextDueDate(base, 'monthly');
        expect(next, equals(DateTime(2028, 2, 29, 16, 0)));
      });

      test('Mar 31 -> Apr 30 (31-day month to 30-day month)', () {
        final base = DateTime(2026, 3, 31, 11, 30);
        final next = computeNextDueDate(base, 'monthly');
        expect(next, equals(DateTime(2026, 4, 30, 11, 30)));
      });

      test('Aug 31 -> Sep 30 (31-day month to 30-day month)', () {
        final base = DateTime(2026, 8, 31, 18, 0);
        final next = computeNextDueDate(base, 'monthly');
        expect(next, equals(DateTime(2026, 9, 30, 18, 0)));
      });

      test('May 31 -> Jun 30', () {
        final base = DateTime(2026, 5, 31, 9, 0);
        final next = computeNextDueDate(base, 'monthly');
        expect(next, equals(DateTime(2026, 6, 30, 9, 0)));
      });

      test('Dec 15 -> Jan 15 of following year (year rollover)', () {
        final base = DateTime(2026, 12, 15, 14, 0);
        final next = computeNextDueDate(base, 'monthly');
        expect(next, equals(DateTime(2027, 1, 15, 14, 0)));
      });

      test(
        'Dec 31 -> Jan 31 of following year (no clamping needed in Jan)',
        () {
          final base = DateTime(2026, 12, 31, 20, 0);
          final next = computeNextDueDate(base, 'monthly');
          expect(next, equals(DateTime(2027, 1, 31, 20, 0)));
        },
      );
    });

    group('monthly non-clamping', () {
      test('mid-month date advances cleanly without clamping', () {
        final base = DateTime(2026, 4, 15, 13, 45);
        final next = computeNextDueDate(base, 'monthly');
        expect(next, equals(DateTime(2026, 5, 15, 13, 45)));
      });

      test('28th of Feb advances to 28th of Mar', () {
        final base = DateTime(2026, 2, 28, 8, 0);
        final next = computeNextDueDate(base, 'monthly');
        expect(next, equals(DateTime(2026, 3, 28, 8, 0)));
      });
    });

    group('time-of-day preservation', () {
      test(
        'preserves exact hour and minute for daily, weekly, and monthly',
        () {
          final base = DateTime(2026, 6, 20, 7, 42);

          final dailyNext = computeNextDueDate(base, 'daily');
          expect(dailyNext.hour, equals(7));
          expect(dailyNext.minute, equals(42));

          final weeklyNext = computeNextDueDate(base, 'weekly');
          expect(weeklyNext.hour, equals(7));
          expect(weeklyNext.minute, equals(42));

          final monthlyNext = computeNextDueDate(base, 'monthly');
          expect(monthlyNext.hour, equals(7));
          expect(monthlyNext.minute, equals(42));
        },
      );
    });

    group('defensive fallback for none and custom', () {
      test('returns baseDate unchanged for none', () {
        final base = DateTime(2026, 7, 1, 12, 0);
        final next = computeNextDueDate(base, 'none');
        expect(next, equals(base));
      });

      test('returns baseDate unchanged for custom', () {
        final base = DateTime(2026, 7, 1, 12, 0);
        final next = computeNextDueDate(base, 'custom');
        expect(next, equals(base));
      });

      test('returns baseDate unchanged for unknown rule', () {
        final base = DateTime(2026, 7, 1, 12, 0);
        final next = computeNextDueDate(base, 'yearly');
        expect(next, equals(base));
      });
    });
  });
}
