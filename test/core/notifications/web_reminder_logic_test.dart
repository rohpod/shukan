import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/notifications/web_reminder_logic.dart';
import 'package:shukan/features/tasks/data/task.dart';

void main() {
  group('web_reminder_logic', () {
    final baseDueDate = DateTime(2026, 10, 15);
    final taskWithTime = Task(
      taskId: 'task-1',
      uid: 'u1',
      listId: 'l1',
      title: 'Submit quarterly report',
      dueDate: baseDueDate,
      dueTime: '14:30',
      earlyReminderMinutes: 15,
    );

    test('due and early fire at the right instants', () {
      final earlyInstant = DateTime(2026, 10, 15, 14, 15);
      final dueInstant = DateTime(2026, 10, 15, 14, 30);

      // At early instant: only early reminder is due
      final earlyReminders = dueWebReminders([taskWithTime], earlyInstant, {});
      expect(earlyReminders.length, 1);
      expect(earlyReminders.first.kind, WebReminderKind.early);
      expect(earlyReminders.first.fireTime, earlyInstant);
      expect(
        earlyReminders.first.key,
        'task-1:early:${earlyInstant.millisecondsSinceEpoch}',
      );

      // At due instant (with early key already fired): only due reminder is due
      final fired = {earlyReminders.first.key};
      final dueReminders = dueWebReminders([taskWithTime], dueInstant, fired);
      expect(dueReminders.length, 1);
      expect(dueReminders.first.kind, WebReminderKind.due);
      expect(dueReminders.first.fireTime, dueInstant);
      expect(
        dueReminders.first.key,
        'task-1:due:${dueInstant.millisecondsSinceEpoch}',
      );
    });

    test('earlyReminderMinutes 0 gives no early reminder', () {
      final taskNoEarly = Task(
        taskId: 'task-no-early',
        uid: 'u1',
        listId: 'l1',
        title: 'Standup',
        dueDate: baseDueDate,
        dueTime: '10:00',
        earlyReminderMinutes: 0,
      );

      final earlyInstant = DateTime(2026, 10, 15, 9, 50);
      final reminders = dueWebReminders([taskNoEarly], earlyInstant, {});
      expect(reminders, isEmpty);

      final dueInstant = DateTime(2026, 10, 15, 10, 0);
      final dueReminders = dueWebReminders([taskNoEarly], dueInstant, {});
      expect(dueReminders.length, 1);
      expect(dueReminders.first.kind, WebReminderKind.due);
    });

    test('date-only task defaults to 09:00', () {
      final dateOnlyTask = Task(
        taskId: 'task-date-only',
        uid: 'u1',
        listId: 'l1',
        title: 'Review PRs',
        dueDate: baseDueDate,
      );

      final beforeNine = DateTime(2026, 10, 15, 8, 59);
      expect(dueWebReminders([dateOnlyTask], beforeNine, {}), isEmpty);

      final atNine = DateTime(2026, 10, 15, 9, 0);
      final reminders = dueWebReminders([dateOnlyTask], atNine, {});
      expect(reminders.length, 1);
      expect(reminders.first.fireTime, DateTime(2026, 10, 15, 9, 0));
    });

    test('completed and deleted tasks are skipped', () {
      final completedTask = Task(
        taskId: 'task-done',
        uid: 'u1',
        listId: 'l1',
        title: 'Done task',
        dueDate: baseDueDate,
        dueTime: '12:00',
        completedAt: DateTime.now(),
      );
      final deletedTask = Task(
        taskId: 'task-del',
        uid: 'u1',
        listId: 'l1',
        title: 'Deleted task',
        dueDate: baseDueDate,
        dueTime: '12:00',
        deletedAt: DateTime.now(),
      );
      final noDueDateTask = const Task(
        taskId: 'task-no-date',
        uid: 'u1',
        listId: 'l1',
        title: 'No date task',
      );

      final now = DateTime(2026, 10, 15, 12, 0);
      final reminders = dueWebReminders(
        [completedTask, deletedTask, noDueDateTask],
        now,
        {},
      );
      expect(reminders, isEmpty);
    });

    test('just before fireTime is not returned', () {
      final now = DateTime(2026, 10, 15, 14, 29, 59);
      final reminders = dueWebReminders([taskWithTime], now, {});
      // At 14:29:59, early was at 14:15 which is past grace (14m59s > 2m), and due (14:30) is in future.
      expect(reminders, isEmpty);
    });

    test('inside grace returned', () {
      final dueInstant = DateTime(2026, 10, 15, 14, 30);
      final insideGrace = dueInstant.add(const Duration(minutes: 1));
      final reminders = dueWebReminders([taskWithTime], insideGrace, {});
      expect(reminders.any((r) => r.kind == WebReminderKind.due), isTrue);
    });

    test('past grace not returned', () {
      final dueInstant = DateTime(2026, 10, 15, 14, 30);
      final pastGrace = dueInstant.add(const Duration(minutes: 3));
      final reminders = dueWebReminders([taskWithTime], pastGrace, {});
      expect(reminders, isEmpty);
    });

    test('a fired key suppresses', () {
      final dueInstant = DateTime(2026, 10, 15, 14, 30);
      final firedKey = 'task-1:due:${dueInstant.millisecondsSinceEpoch}';
      final reminders = dueWebReminders([taskWithTime], dueInstant, {firedKey});
      expect(reminders.where((r) => r.kind == WebReminderKind.due), isEmpty);
    });

    test('an edited time produces a new key', () {
      final initialDue = DateTime(2026, 10, 15, 14, 30);
      final initialKey = 'task-1:due:${initialDue.millisecondsSinceEpoch}';

      final editedTask = taskWithTime.copyWith(dueTime: '15:00');
      final newDue = DateTime(2026, 10, 15, 15, 0);

      final reminders = dueWebReminders([editedTask], newDue, {initialKey});
      expect(reminders.length, 1);
      expect(reminders.first.fireTime, newDue);
      expect(
        reminders.first.key,
        'task-1:due:${newDue.millisecondsSinceEpoch}',
      );
      expect(reminders.first.key, isNot(equals(initialKey)));
    });

    test('a repeating task whose dueDate advanced produces a new key', () {
      final initialDue = DateTime(2026, 10, 15, 14, 30);
      final initialKey = 'task-1:due:${initialDue.millisecondsSinceEpoch}';

      final advancedTask = taskWithTime.copyWith(
        dueDate: DateTime(2026, 10, 16),
      );
      final advancedDue = DateTime(2026, 10, 16, 14, 30);

      final reminders = dueWebReminders(
        [advancedTask],
        advancedDue,
        {initialKey},
      );
      expect(reminders.length, 1);
      expect(reminders.first.fireTime, advancedDue);
      expect(
        reminders.first.key,
        'task-1:due:${advancedDue.millisecondsSinceEpoch}',
      );
      expect(reminders.first.key, isNot(equals(initialKey)));
    });
  });
}
