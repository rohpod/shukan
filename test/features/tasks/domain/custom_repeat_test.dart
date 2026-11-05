import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/domain/custom_repeat.dart';
import 'package:shukan/features/tasks/domain/task_recurrence_utils.dart';

Map<String, dynamic> days(int interval) => {
  'unit': 'day',
  'interval': interval,
};

Map<String, dynamic> weeks(int interval, List<int> weekdays) => {
  'unit': 'week',
  'interval': interval,
  'weekdays': weekdays,
};

Task custom(Map<String, dynamic>? config, {DateTime? due, String? dueTime}) =>
    Task(
      taskId: 't',
      uid: 'u',
      listId: 'l',
      title: 'Custom',
      repeatRule: 'custom',
      repeatCustomConfig: config,
      dueDate: due,
      dueTime: dueTime,
    );

void main() {
  group('CustomRepeat.fromMap', () {
    test('returns null for a missing map', () {
      expect(CustomRepeat.fromMap(null), isNull);
    });

    test('parses day and week configs', () {
      expect(
        CustomRepeat.fromMap(days(3)),
        const CustomRepeat(unit: 'day', interval: 3),
      );
      expect(
        CustomRepeat.fromMap(weeks(2, [3, 1, 3])),
        const CustomRepeat(unit: 'week', interval: 2, weekdays: [1, 3]),
      );
    });

    test('rejects invalid maps', () {
      for (final bad in <Map<String, dynamic>>[
        {},
        {'unit': 'month', 'interval': 1},
        {'unit': 'day', 'interval': 0},
        {'unit': 'day', 'interval': 366},
        {'unit': 'day', 'interval': 1.5},
        {'unit': 'day', 'interval': '2'},
        {'unit': 'week', 'interval': 1},
        weeks(1, []),
        weeks(1, [0]),
        weeks(1, [8]),
        {
          'unit': 'week',
          'interval': 1,
          'weekdays': [1, 'x'],
        },
      ]) {
        expect(CustomRepeat.fromMap(bad), isNull, reason: '$bad');
      }
    });

    test('toMap round-trips', () {
      for (final map in [
        days(4),
        weeks(2, [1, 5]),
      ]) {
        expect(CustomRepeat.fromMap(map)!.toMap(), map);
      }
    });
  });

  group('computeNextDueDate custom', () {
    test('every N days keeps the time of day', () {
      expect(
        computeNextDueDate(
          DateTime(2026, 6, 10, 9, 30),
          'custom',
          customConfig: days(3),
        ),
        DateTime(2026, 6, 13, 9, 30),
      );
    });

    test('every N days crosses a DST change by calendar day', () {
      expect(
        computeNextDueDate(
          DateTime(2026, 3, 7, 9, 30),
          'custom',
          customConfig: days(2),
        ),
        DateTime(2026, 3, 9, 9, 30),
      );
    });

    test('takes the next selected weekday later in the same week', () {
      // Wed 2026-06-10 -> Fri 2026-06-12
      expect(
        computeNextDueDate(
          DateTime(2026, 6, 10, 8),
          'custom',
          customConfig: weeks(2, [1, 3, 5]),
        ),
        DateTime(2026, 6, 12, 8),
      );
    });

    test(
      'jumps interval weeks from this week\'s Monday after the last day',
      () {
        // Fri 2026-06-12 with Mon/Wed/Fri every 2 weeks -> Mon 2026-06-22
        expect(
          computeNextDueDate(
            DateTime(2026, 6, 12),
            'custom',
            customConfig: weeks(2, [1, 3, 5]),
          ),
          DateTime(2026, 6, 22),
        );
      },
    );

    test('works when the due weekday is not selected', () {
      // Sun 2026-06-14, only Tue selected, every week -> Tue 2026-06-16
      expect(
        computeNextDueDate(
          DateTime(2026, 6, 14),
          'custom',
          customConfig: weeks(1, [2]),
        ),
        DateTime(2026, 6, 16),
      );
      // Wed 2026-06-10, only Mon selected, every 3 weeks -> Mon 2026-06-29
      expect(
        computeNextDueDate(
          DateTime(2026, 6, 10),
          'custom',
          customConfig: weeks(3, [1]),
        ),
        DateTime(2026, 6, 29),
      );
    });

    test('weekly jump across a DST change keeps the time', () {
      // Fri 2026-03-06 10:00, Fri only, every 2 weeks -> Fri 2026-03-20 10:00
      expect(
        computeNextDueDate(
          DateTime(2026, 3, 6, 10),
          'custom',
          customConfig: weeks(2, [5]),
        ),
        DateTime(2026, 3, 20, 10),
      );
    });

    test('null or invalid config leaves the date unchanged', () {
      final base = DateTime(2026, 6, 10);
      expect(computeNextDueDate(base, 'custom'), base);
      expect(
        computeNextDueDate(base, 'custom', customConfig: {'unit': 'day'}),
        base,
      );
    });
  });

  group('nextOccurrenceAfter custom', () {
    test('an overdue task catches up to the next non-overdue date', () {
      final task = custom(days(3), due: DateTime(2026, 6, 1));
      // 1, 4, 7, 10 -> first one not overdue at 06-08 is 06-10
      expect(
        nextOccurrenceAfter(task, DateTime(2026, 6, 8, 12)),
        DateTime(2026, 6, 10),
      );
    });

    test('weekly catch-up lands on a selected weekday', () {
      final task = custom(weeks(1, [1, 4]), due: DateTime(2026, 6, 1));
      // Mon 06-01 -> Thu 06-04 -> Mon 06-08 -> Thu 06-11; now is Tue 06-09
      expect(
        nextOccurrenceAfter(task, DateTime(2026, 6, 9, 12)),
        DateTime(2026, 6, 11),
      );
    });
  });

  group('taskRepeats', () {
    test('is false for none and for custom without a valid config', () {
      expect(taskRepeats(custom(null)), isFalse);
      expect(taskRepeats(custom({'unit': 'day'})), isFalse);
      expect(
        taskRepeats(const Task(taskId: 't', uid: 'u', listId: 'l', title: 'x')),
        isFalse,
      );
    });

    test('is true for custom with a valid config and for built-in rules', () {
      expect(taskRepeats(custom(days(2))), isTrue);
      expect(
        taskRepeats(
          const Task(
            taskId: 't',
            uid: 'u',
            listId: 'l',
            title: 'x',
            repeatRule: 'daily',
          ),
        ),
        isTrue,
      );
    });
  });

  group('repeatSummary', () {
    test('describes each rule', () {
      expect(repeatSummary(custom(days(1))), 'Daily');
      expect(repeatSummary(custom(days(3))), 'Every 3 days');
      expect(repeatSummary(custom(weeks(1, [2]))), 'Every week on Tue');
      expect(
        repeatSummary(custom(weeks(2, [1, 3]))),
        'Every 2 weeks on Mon, Wed',
      );
      expect(repeatSummary(custom(null)), '');
    });
  });

  group('Task equality', () {
    test('compares repeatCustomConfig by value', () {
      expect(
        custom(weeks(2, [1, 3])),
        custom({
          'unit': 'week',
          'interval': 2,
          'weekdays': [1, 3],
        }),
      );
      expect(custom(weeks(2, [1, 3])) == custom(weeks(2, [1, 4])), isFalse);
    });
  });
}
