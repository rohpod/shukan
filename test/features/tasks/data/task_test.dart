import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/data/task.dart';

void main() {
  group('Task Model Tests', () {
    test('fromMap parses standard Firestore map with Timestamps', () {
      final now = DateTime.now();
      final map = <String, dynamic>{
        'uid': 'user-1',
        'listId': 'list-1',
        'title': 'Test Title',
        'notes': 'Test notes',
        'url': 'https://example.com',
        'priority': 'high',
        'tagIds': ['tag1', 'tag2'],
        'dueDate': Timestamp.fromDate(now),
        'dueTime': '14:00',
        'earlyReminderMinutes': 15,
        'repeatRule': 'weekly',
        'repeatCustomConfig': {
          'days': ['mon', 'wed'],
        },
        'order': 3,
        'subtasks': [
          {'id': 's1', 'title': 'Sub 1', 'completed': false},
        ],
        'createdAt': Timestamp.fromDate(now),
        'completedAt': Timestamp.fromDate(now),
        'deletedAt': Timestamp.fromDate(now),
      };

      final task = Task.fromMap(map, 'task-1');
      expect(task.taskId, equals('task-1'));
      expect(task.uid, equals('user-1'));
      expect(task.listId, equals('list-1'));
      expect(task.title, equals('Test Title'));
      expect(task.notes, equals('Test notes'));
      expect(task.url, equals('https://example.com'));
      expect(task.priority, equals('high'));
      expect(task.tagIds, equals(['tag1', 'tag2']));
      expect(task.dueDate, isNotNull);
      expect(task.dueTime, equals('14:00'));
      expect(task.earlyReminderMinutes, equals(15));
      expect(task.repeatRule, equals('weekly'));
      expect(
        task.repeatCustomConfig,
        equals({
          'days': ['mon', 'wed'],
        }),
      );
      expect(task.order, equals(3));
      expect(task.subtasks.length, equals(1));
      expect(task.createdAt, isNotNull);
      expect(task.completedAt, isNotNull);
      expect(task.deletedAt, isNotNull);
      expect(task.isCompleted, isTrue);
      expect(task.isDeleted, isTrue);
    });

    test(
      'fromMap handles ISO strings and int epoch milliseconds for dates',
      () {
        final dateIso = '2026-03-01T12:00:00.000Z';
        final epochMs = 1772366400000;

        final map = <String, dynamic>{
          'uid': 'user-1',
          'listId': 'list-1',
          'title': 'Test Title',
          'dueDate': dateIso,
          'createdAt': epochMs,
          'deletedAt': dateIso,
        };

        final task = Task.fromMap(map, 'task-dates');
        expect(task.dueDate, equals(DateTime.parse(dateIso)));
        expect(
          task.createdAt,
          equals(DateTime.fromMillisecondsSinceEpoch(epochMs)),
        );
        expect(task.deletedAt, equals(DateTime.parse(dateIso)));
        expect(task.isDeleted, isTrue);
      },
    );

    test('fromMap gracefully defaults corrupted and unexpected types without crashing', () {
      final map = <String, dynamic>{
        'uid': 12345, // Number instead of string
        'title': null,
        'subtasks': 'not-a-list', // Invalid type
        'earlyReminderMinutes': 'not-a-num',
        'repeatCustomConfig': 'not-a-map',
        'order': null,
      };

      final task = Task.fromMap(map, 'task-corrupt');
      expect(task.uid, equals('12345'));
      expect(task.title, equals(''));
      expect(task.subtasks, isEmpty);
      expect(task.earlyReminderMinutes, equals(0));
      expect(task.repeatCustomConfig, isNull);
      expect(task.order, equals(0));
    });
  });
}
