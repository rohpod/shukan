import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/data/task.dart';
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

  group('nextOccurrenceAfter', () {
    Task repeating(
      String rule,
      DateTime dueDate, {
      String? dueTime,
      int? anchor,
    }) => Task(
      taskId: 't',
      uid: 'u',
      listId: 'l',
      title: 'Repeat',
      repeatRule: rule,
      dueDate: dueDate,
      dueTime: dueTime,
      repeatAnchorDay: anchor,
    );

    test('an on-time task advances one period', () {
      final task = repeating('daily', DateTime(2026, 6, 10));
      expect(
        nextOccurrenceAfter(task, DateTime(2026, 6, 10, 15)),
        DateTime(2026, 6, 11),
      );
    });

    test('a task completed early still advances one period', () {
      final task = repeating('weekly', DateTime(2026, 6, 20));
      expect(
        nextOccurrenceAfter(task, DateTime(2026, 6, 10)),
        DateTime(2026, 6, 27),
      );
    });

    test('an overdue date-only task catches up to today', () {
      final task = repeating('daily', DateTime(2026, 6, 5));
      expect(
        nextOccurrenceAfter(task, DateTime(2026, 6, 10, 15)),
        DateTime(2026, 6, 10),
      );
    });

    test('an overdue timed task skips a time that already passed today', () {
      final task = repeating('daily', DateTime(2026, 6, 5), dueTime: '09:00');
      expect(
        nextOccurrenceAfter(task, DateTime(2026, 6, 10, 15)),
        DateTime(2026, 6, 11),
      );
    });

    test('an overdue weekly task keeps its weekday', () {
      final task = repeating('weekly', DateTime(2026, 5, 4));
      final next = nextOccurrenceAfter(task, DateTime(2026, 6, 10));
      expect(next, DateTime(2026, 6, 15));
      expect(next.weekday, DateTime.monday);
    });

    test('monthly repeats return to the anchor day after a short month', () {
      var task = repeating('monthly', DateTime(2026, 1, 31));
      final seen = <String>[];
      var now = DateTime(2026, 1, 31);
      for (var i = 0; i < 4; i++) {
        final anchor = resolveRepeatAnchorDay(task);
        final next = nextOccurrenceAfter(task, now);
        seen.add('${next.month}/${next.day}');
        task = repeating('monthly', next, anchor: anchor);
        now = next;
      }
      expect(seen, ['2/28', '3/31', '4/30', '5/31']);
    });

    test('moving the due date replaces the anchor', () {
      final task = repeating('monthly', DateTime(2026, 3, 15), anchor: 31);
      expect(resolveRepeatAnchorDay(task), 15);
    });

    test('a task with no due date repeats from today', () {
      const task = Task(
        taskId: 't',
        uid: 'u',
        listId: 'l',
        title: 'Repeat',
        repeatRule: 'daily',
      );
      expect(
        nextOccurrenceAfter(task, DateTime(2026, 6, 10, 15)),
        DateTime(2026, 6, 11),
      );
    });

    test('an unknown rule returns the due date instead of looping', () {
      final task = repeating('none', DateTime(2026, 6, 5));
      expect(
        nextOccurrenceAfter(task, DateTime(2026, 6, 10)),
        DateTime(2026, 6, 5),
      );
    });
  });
}
