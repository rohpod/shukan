import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/domain/notification_id.dart';

void main() {
  group('taskNotificationId', () {
    test('is deterministic - same input produces same output across calls', () {
      const taskId1 = 'task-abc-123-xyz';
      const taskId2 = 'task-def-456-uvw';

      final id1Call1 = taskNotificationId(taskId1);
      final id1Call2 = taskNotificationId(taskId1);
      final id2Call1 = taskNotificationId(taskId2);
      final id2Call2 = taskNotificationId(taskId2);

      expect(id1Call1, equals(id1Call2));
      expect(id2Call1, equals(id2Call2));
      expect(id1Call1, isNot(equals(id2Call1)));
    });

    test('always returns a non-negative 31-bit integer', () {
      final sampleTaskIds = [
        '',
        'a',
        'task-1',
        '00000000-0000-0000-0000-000000000000',
        '7nK3pQ9vRtLm4sW1yZ8x',
        'zzzzzzzzzzzzzzzzzzzz',
        'ABCDEFG123456!@#\$%^&*()',
      ];

      for (final id in sampleTaskIds) {
        final notificationId = taskNotificationId(id);
        expect(notificationId, isNonNegative);
        expect(notificationId, lessThanOrEqualTo(0x7FFFFFFF));
      }
    });

    test(
      'exhibits basic distribution sanity without collisions on sample IDs',
      () {
        final generatedIds = <int>{};
        final testCases = List.generate(50, (i) => 'firestore-doc-id-$i');

        for (final id in testCases) {
          final notifId = taskNotificationId(id);
          expect(
            generatedIds.contains(notifId),
            isFalse,
            reason: 'Collision detected for taskId: $id',
          );
          generatedIds.add(notifId);
        }

        expect(generatedIds.length, equals(50));
      },
    );
  });

  group('taskEarlyReminderNotificationId', () {
    test('is deterministic - same input produces same output across calls', () {
      const taskId1 = 'task-abc-123-xyz';
      const taskId2 = 'task-def-456-uvw';

      final id1Call1 = taskEarlyReminderNotificationId(taskId1);
      final id1Call2 = taskEarlyReminderNotificationId(taskId1);
      final id2Call1 = taskEarlyReminderNotificationId(taskId2);
      final id2Call2 = taskEarlyReminderNotificationId(taskId2);

      expect(id1Call1, equals(id1Call2));
      expect(id2Call1, equals(id2Call2));
      expect(id1Call1, isNot(equals(id2Call1)));
    });

    test('is distinct from taskNotificationId for the same taskId', () {
      final sampleTaskIds = [
        'task-1',
        'task-abc-123-xyz',
        '00000000-0000-0000-0000-000000000000',
        '7nK3pQ9vRtLm4sW1yZ8x',
        'my-important-task',
      ];

      for (final id in sampleTaskIds) {
        final mainId = taskNotificationId(id);
        final earlyId = taskEarlyReminderNotificationId(id);
        expect(
          earlyId,
          isNot(equals(mainId)),
          reason: 'Early reminder ID collided with main ID for taskId: $id',
        );
      }
    });

    test('always returns a non-negative 31-bit integer', () {
      final sampleTaskIds = [
        '',
        'a',
        'task-1',
        '00000000-0000-0000-0000-000000000000',
        '7nK3pQ9vRtLm4sW1yZ8x',
        'zzzzzzzzzzzzzzzzzzzz',
        'ABCDEFG123456!@#\$%^&*()',
      ];

      for (final id in sampleTaskIds) {
        final notificationId = taskEarlyReminderNotificationId(id);
        expect(notificationId, isNonNegative);
        expect(notificationId, lessThanOrEqualTo(0x7FFFFFFF));
      }
    });
  });
}
