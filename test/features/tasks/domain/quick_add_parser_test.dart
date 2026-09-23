import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/domain/quick_add_parser.dart';

void main() {
  group('parseQuickAdd unit tests', () {
    // Fixed clock: Wednesday, Oct 14, 2026 at 10:00 AM
    final fixedNow = DateTime(2026, 10, 14, 10, 0);

    test('empty or whitespace input returns empty strippedTitle and nulls', () {
      final res1 = parseQuickAdd('', now: fixedNow);
      expect(res1.strippedTitle, '');
      expect(res1.dueDate, isNull);
      expect(res1.dueTime, isNull);
      expect(res1.matchedPhrase, isNull);

      final res2 = parseQuickAdd('   ', now: fixedNow);
      expect(res2.strippedTitle, '');
      expect(res2.dueDate, isNull);
      expect(res2.dueTime, isNull);
    });

    test('no date/time phrase returns input unchanged with nulls', () {
      final res = parseQuickAdd('Buy groceries at the market', now: fixedNow);
      expect(res.strippedTitle, 'Buy groceries at the market');
      expect(res.dueDate, isNull);
      expect(res.dueTime, isNull);
      expect(res.matchedPhrase, isNull);
    });

    test('does not parse standalone numbers without time indicators', () {
      final res = parseQuickAdd('Read chapter 5 and 10 pages', now: fixedNow);
      expect(res.strippedTitle, 'Read chapter 5 and 10 pages');
      expect(res.dueDate, isNull);
      expect(res.dueTime, isNull);
    });

    group('Relative days', () {
      test('parses "today"', () {
        final res = parseQuickAdd('Doctor appointment today', now: fixedNow);
        expect(res.strippedTitle, 'Doctor appointment');
        expect(res.dueDate, DateTime(2026, 10, 14));
        expect(res.dueTime, isNull);
        expect(res.matchedPhrase?.toLowerCase(), contains('today'));
      });

      test('parses "tomorrow"', () {
        final res = parseQuickAdd('Submit essay tomorrow', now: fixedNow);
        expect(res.strippedTitle, 'Submit essay');
        expect(res.dueDate, DateTime(2026, 10, 15));
        expect(res.dueTime, isNull);
      });

      test('parses "tmrw" abbreviation', () {
        final res = parseQuickAdd('Call mom tmrw', now: fixedNow);
        expect(res.strippedTitle, 'Call mom');
        expect(res.dueDate, DateTime(2026, 10, 15));
        expect(res.dueTime, isNull);
      });

      test('parses "yesterday" for completeness', () {
        final res = parseQuickAdd('File taxes yesterday', now: fixedNow);
        expect(res.strippedTitle, 'File taxes');
        expect(res.dueDate, DateTime(2026, 10, 13));
        expect(res.dueTime, isNull);
      });
    });

    group('Weekdays', () {
      test('parses plain weekday upcoming: Wednesday to Friday is +2 days', () {
        final res = parseQuickAdd('Team sync friday', now: fixedNow);
        expect(res.strippedTitle, 'Team sync');
        expect(res.dueDate, DateTime(2026, 10, 16)); // Friday
      });

      test('parses plain weekday upcoming: Wednesday to Monday is +5 days', () {
        final res = parseQuickAdd('Review PR mon', now: fixedNow);
        expect(res.strippedTitle, 'Review PR');
        expect(res.dueDate, DateTime(2026, 10, 19)); // Monday
      });

      test('parses "this friday"', () {
        final res = parseQuickAdd('Gym workout this friday', now: fixedNow);
        expect(res.strippedTitle, 'Gym workout');
        expect(res.dueDate, DateTime(2026, 10, 16));
      });

      test('parses "next monday" (following week)', () {
        final res = parseQuickAdd('Sprint planning next monday', now: fixedNow);
        expect(res.strippedTitle, 'Sprint planning');
        expect(res.dueDate, DateTime(2026, 10, 19));
      });

      test('parses "next friday" (following week)', () {
        final res = parseQuickAdd('Release v2 next friday', now: fixedNow);
        expect(res.strippedTitle, 'Release v2');
        expect(res.dueDate, DateTime(2026, 10, 23));
      });
    });

    group('Relative offsets', () {
      test('parses "in N days"', () {
        final res = parseQuickAdd('Finish report in 3 days', now: fixedNow);
        expect(res.strippedTitle, 'Finish report');
        expect(res.dueDate, DateTime(2026, 10, 17));
      });

      test('parses "in 1 day"', () {
        final res = parseQuickAdd('Pack luggage in 1 day', now: fixedNow);
        expect(res.strippedTitle, 'Pack luggage');
        expect(res.dueDate, DateTime(2026, 10, 15));
      });

      test('parses "in N weeks"', () {
        final res = parseQuickAdd('Dental checkup in 2 weeks', now: fixedNow);
        expect(res.strippedTitle, 'Dental checkup');
        expect(res.dueDate, DateTime(2026, 10, 28));
      });
    });

    group('Times', () {
      test('parses "5pm" (defaults date to today)', () {
        final res = parseQuickAdd('Water plants 5pm', now: fixedNow);
        expect(res.strippedTitle, 'Water plants');
        expect(res.dueDate, DateTime(2026, 10, 14));
        expect(res.dueTime, '17:00');
      });

      test('parses "9am"', () {
        final res = parseQuickAdd('Morning jog 9am', now: fixedNow);
        expect(res.strippedTitle, 'Morning jog');
        expect(res.dueDate, DateTime(2026, 10, 14));
        expect(res.dueTime, '09:00');
      });

      test('parses "5:30pm"', () {
        final res = parseQuickAdd('Pick up dry cleaning 5:30pm', now: fixedNow);
        expect(res.strippedTitle, 'Pick up dry cleaning');
        expect(res.dueTime, '17:30');
      });

      test('parses "12pm" (noon) and "12am" (midnight)', () {
        final resNoon = parseQuickAdd('Lunch meeting 12pm', now: fixedNow);
        expect(resNoon.dueTime, '12:00');

        final resMidnight = parseQuickAdd('Build cut 12am', now: fixedNow);
        expect(resMidnight.dueTime, '00:00');
      });

      test('parses "noon" and "midnight" words', () {
        final resNoon = parseQuickAdd('Team lunch at noon', now: fixedNow);
        expect(resNoon.strippedTitle, 'Team lunch');
        expect(resNoon.dueTime, '12:00');

        final resMid = parseQuickAdd('Deploy at midnight', now: fixedNow);
        expect(resMid.strippedTitle, 'Deploy');
        expect(resMid.dueTime, '00:00');
      });

      test('parses 24-hour time "17:00"', () {
        final res = parseQuickAdd('Evening review 17:00', now: fixedNow);
        expect(res.strippedTitle, 'Evening review');
        expect(res.dueTime, '17:00');
      });

      test('parses time preceded by "at "', () {
        final res = parseQuickAdd('Standup at 10:15am', now: fixedNow);
        expect(res.strippedTitle, 'Standup');
        expect(res.dueTime, '10:15');
      });
    });

    group('Combinations & Prepositions', () {
      test('parses "tomorrow 5pm"', () {
        final res = parseQuickAdd(
          'Submit assignment tomorrow 5pm',
          now: fixedNow,
        );
        expect(res.strippedTitle, 'Submit assignment');
        expect(res.dueDate, DateTime(2026, 10, 15));
        expect(res.dueTime, '17:00');
        expect(res.matchedPhrase?.toLowerCase(), contains('tomorrow 5pm'));
      });

      test('parses "5pm tomorrow" (time before date)', () {
        final res = parseQuickAdd(
          'Submit assignment 5pm tomorrow',
          now: fixedNow,
        );
        expect(res.strippedTitle, 'Submit assignment');
        expect(res.dueDate, DateTime(2026, 10, 15));
        expect(res.dueTime, '17:00');
      });

      test('parses "next monday at 9am"', () {
        final res = parseQuickAdd(
          'Sprint planning next monday at 9am',
          now: fixedNow,
        );
        expect(res.strippedTitle, 'Sprint planning');
        expect(res.dueDate, DateTime(2026, 10, 19));
        expect(res.dueTime, '09:00');
      });

      test('parses leading "by" or "on" prepositions', () {
        final resBy = parseQuickAdd('Finish slides by tomorrow', now: fixedNow);
        expect(resBy.strippedTitle, 'Finish slides');
        expect(resBy.dueDate, DateTime(2026, 10, 15));

        final resOn = parseQuickAdd(
          'Team sync on friday at 3pm',
          now: fixedNow,
        );
        expect(resOn.strippedTitle, 'Team sync');
        expect(resOn.dueDate, DateTime(2026, 10, 16));
        expect(resOn.dueTime, '15:00');
      });

      test('collapses double spaces and trims title', () {
        final res = parseQuickAdd(
          '  Task   tomorrow 5pm   details  ',
          now: fixedNow,
        );
        expect(res.strippedTitle, 'Task details');
        expect(res.dueDate, DateTime(2026, 10, 15));
        expect(res.dueTime, '17:00');
      });

      test('entire input is date phrase results in empty strippedTitle', () {
        final res = parseQuickAdd('tomorrow 5pm', now: fixedNow);
        expect(res.strippedTitle, '');
        expect(res.dueDate, DateTime(2026, 10, 15));
        expect(res.dueTime, '17:00');
      });
    });
  });
}
