import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/domain/task_constants.dart';

void main() {
  group('taskPriorityMarker', () {
    test('returns correct marker for all four priorities', () {
      expect(taskPriorityMarker('high'), equals('❗❗❗'));
      expect(taskPriorityMarker('medium'), equals('❕❕'));
      expect(taskPriorityMarker('low'), equals('!'));
      expect(taskPriorityMarker('none'), isNull);
    });

    test('returns null for unknown or empty priority', () {
      expect(taskPriorityMarker(''), isNull);
      expect(taskPriorityMarker('urgent'), isNull);
    });
  });
}
