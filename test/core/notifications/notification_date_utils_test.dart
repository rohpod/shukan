import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/notifications/notification_date_utils.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('computeTaskFireTime', () {
    test('returns null when dueDate is null', () {
      final fireTime = computeTaskFireTime(
        dueDate: null,
        dueTime: '14:30',
        now: DateTime(2026, 1, 1, 10, 0),
      );
      expect(fireTime, isNull);
    });

    test('combines dueDate and valid dueTime correctly into TZDateTime', () {
      tz.setLocalLocation(tz.getLocation('UTC'));
      final dueDate = DateTime.utc(2026, 10, 15);
      final now = DateTime.utc(2026, 10, 15, 8, 0);

      final fireTime = computeTaskFireTime(
        dueDate: dueDate,
        dueTime: '14:30',
        now: now,
      );

      expect(fireTime, isNotNull);
      expect(fireTime!.year, equals(2026));
      expect(fireTime.month, equals(10));
      expect(fireTime.day, equals(15));
      expect(fireTime.hour, equals(14));
      expect(fireTime.minute, equals(30));
    });

    test(
      'defaults to 9:00 AM local time for date-only task when dueTime is null',
      () {
        tz.setLocalLocation(tz.getLocation('UTC'));
        final dueDate = DateTime.utc(2026, 10, 15);
        final now = DateTime.utc(2026, 10, 15, 8, 0);

        final fireTime = computeTaskFireTime(
          dueDate: dueDate,
          dueTime: null,
          now: now,
        );

        expect(fireTime, isNotNull);
        expect(fireTime!.hour, equals(kDefaultDateOnlyHour));
        expect(fireTime.minute, equals(kDefaultDateOnlyMinute));
      },
    );

    test(
      'defaults to 9:00 AM local time when dueTime is empty or malformed',
      () {
        tz.setLocalLocation(tz.getLocation('UTC'));
        final dueDate = DateTime.utc(2026, 10, 15);
        final now = DateTime.utc(2026, 10, 15, 8, 0);

        final fireTimeEmpty = computeTaskFireTime(
          dueDate: dueDate,
          dueTime: '   ',
          now: now,
        );
        final fireTimeMalformed = computeTaskFireTime(
          dueDate: dueDate,
          dueTime: 'invalid-time',
          now: now,
        );

        expect(fireTimeEmpty!.hour, equals(9));
        expect(fireTimeEmpty.minute, equals(0));
        expect(fireTimeMalformed!.hour, equals(9));
        expect(fireTimeMalformed.minute, equals(0));
      },
    );

    test('subtracts earlyReminderMinutes from scheduled fire time', () {
      tz.setLocalLocation(tz.getLocation('UTC'));
      final dueDate = DateTime.utc(2026, 10, 15);
      final now = DateTime.utc(2026, 10, 15, 8, 0);

      final fireTime = computeTaskFireTime(
        dueDate: dueDate,
        dueTime: '10:00',
        earlyReminderMinutes: 30,
        now: now,
      );

      expect(fireTime, isNotNull);
      expect(fireTime!.hour, equals(9));
      expect(fireTime.minute, equals(30));
    });

    test(
      'returns null if computed fire time is in the past relative to now',
      () {
        tz.setLocalLocation(tz.getLocation('UTC'));
        final dueDate = DateTime.utc(2026, 10, 15);
        // Scheduled is 10:00, but now is 10:01
        final now = DateTime.utc(2026, 10, 15, 10, 1);

        final fireTime = computeTaskFireTime(
          dueDate: dueDate,
          dueTime: '10:00',
          now: now,
        );

        expect(fireTime, isNull);
      },
    );

    test(
      'returns null if earlyReminder subtracted fire time is in the past',
      () {
        tz.setLocalLocation(tz.getLocation('UTC'));
        final dueDate = DateTime.utc(2026, 10, 15);
        // Scheduled is 10:00, 30m early reminder means 09:30. Now is 09:31.
        final now = DateTime.utc(2026, 10, 15, 9, 31);

        final fireTime = computeTaskFireTime(
          dueDate: dueDate,
          dueTime: '10:00',
          earlyReminderMinutes: 30,
          now: now,
        );

        expect(fireTime, isNull);
      },
    );

    test('DST sanity: preserves wall-clock time in winter (standard) and summer (daylight saving)', () {
      final nyLocation = tz.getLocation('America/New_York');
      tz.setLocalLocation(nyLocation);

      // Summer date in EDT (UTC-4)
      final summerDueDate = DateTime(2026, 7, 15);
      final summerNow = DateTime(2026, 7, 1, 8, 0);
      final summerFireTime = computeTaskFireTime(
        dueDate: summerDueDate,
        dueTime: '09:00',
        now: summerNow,
      );

      expect(summerFireTime, isNotNull);
      expect(summerFireTime!.hour, equals(9));
      expect(summerFireTime.minute, equals(0));
      expect(summerFireTime.timeZoneOffset.inHours, equals(-4)); // EDT

      // Winter date in EST (UTC-5)
      final winterDueDate = DateTime(2026, 1, 15);
      final winterNow = DateTime(2026, 1, 1, 8, 0);
      final winterFireTime = computeTaskFireTime(
        dueDate: winterDueDate,
        dueTime: '09:00',
        now: winterNow,
      );

      expect(winterFireTime, isNotNull);
      expect(winterFireTime!.hour, equals(9));
      expect(winterFireTime.minute, equals(0));
      expect(winterFireTime.timeZoneOffset.inHours, equals(-5)); // EST
    });

    test('DST transition day: schedules correctly across daylight saving changeover', () {
      final nyLocation = tz.getLocation('America/New_York');
      tz.setLocalLocation(nyLocation);

      // In 2026, US Daylight Saving Time ends on Sunday, Nov 1, 2026 (clocks roll back 2:00 -> 1:00)
      final transitionDueDate = DateTime(2026, 11, 1);
      final morningNow = DateTime(2026, 10, 31, 8, 0);

      final fireTime = computeTaskFireTime(
        dueDate: transitionDueDate,
        dueTime: '14:00',
        now: morningNow,
      );

      expect(fireTime, isNotNull);
      expect(fireTime!.year, equals(2026));
      expect(fireTime.month, equals(11));
      expect(fireTime.day, equals(1));
      expect(fireTime.hour, equals(14));
      expect(fireTime.minute, equals(0));
    });
  });
}
