import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/presentation/widgets/task_schedule_line.dart';
import 'package:shukan/features/tasks/presentation/widgets/task_url_link.dart';
import 'package:shukan/features/tasks/providers/missed_tasks_providers.dart';

Task task({
  DateTime? due,
  String? time,
  String rule = 'none',
  Map<String, dynamic>? config,
  String url = '',
  DateTime? completedAt,
}) => Task(
  taskId: 't1',
  uid: 'u',
  listId: 'l',
  title: 'T',
  dueDate: due,
  dueTime: time,
  repeatRule: rule,
  repeatCustomConfig: config,
  url: url,
  completedAt: completedAt,
);

Widget host(Widget child) => ProviderScope(
  overrides: [
    currentMinuteProvider.overrideWith(
      (ref) => Stream.value(DateTime(2026, 6, 10, 12)),
    ),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  group('formatDueDate', () {
    test('formats date with and without time', () {
      expect(formatDueDate(DateTime(2026, 6, 3), null), '2026-06-03');
      expect(formatDueDate(DateTime(2026, 6, 3), '09:05'), '2026-06-03 09:05');
      expect(formatDueDate(null, '09:05'), '');
    });
  });

  group('TaskScheduleLine', () {
    testWidgets('shows date, time and repeat summary', (tester) async {
      await tester.pumpWidget(
        host(
          TaskScheduleLine(
            task: task(
              due: DateTime(2026, 6, 20),
              time: '09:00',
              rule: 'custom',
              config: {'unit': 'day', 'interval': 3},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('2026-06-20 09:00'), findsOneWidget);
      expect(find.text('Every 3 days'), findsOneWidget);
      final date = tester.widget<Text>(find.byKey(const Key('taskDueDate_t1')));
      expect(date.style?.color, Colors.blueGrey);
    });

    testWidgets('is red when overdue, but not when completed', (tester) async {
      await tester.pumpWidget(
        host(TaskScheduleLine(task: task(due: DateTime(2026, 6, 1)))),
      );
      await tester.pump();
      var date = tester.widget<Text>(find.byKey(const Key('taskDueDate_t1')));
      expect(date.style?.color, Colors.red.shade700);
      expect(find.byKey(const Key('taskRepeat_t1')), findsNothing);

      await tester.pumpWidget(
        host(
          TaskScheduleLine(
            task: task(
              due: DateTime(2026, 6, 1),
              completedAt: DateTime(2026, 6, 2),
            ),
          ),
        ),
      );
      await tester.pump();
      date = tester.widget<Text>(find.byKey(const Key('taskDueDate_t1')));
      expect(date.style?.color, Colors.blueGrey);
    });

    testWidgets('renders nothing without a due date', (tester) async {
      await tester.pumpWidget(host(TaskScheduleLine(task: task())));
      expect(find.byKey(const Key('taskDueDate_t1')), findsNothing);
    });
  });

  group('TaskUrlLink', () {
    testWidgets('a valid URL is tappable, styled as a link', (tester) async {
      await tester.pumpWidget(
        host(TaskUrlLink(task: task(url: 'https://example.com'))),
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('taskUrl_t1')),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a disabled link and an unsafe URL are not tappable', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          TaskUrlLink(task: task(url: 'https://example.com'), enabled: false),
        ),
      );
      expect(find.byType(InkWell), findsNothing);

      await tester.pumpWidget(
        host(TaskUrlLink(task: task(url: 'javascript:alert(1)'))),
      );
      expect(find.byType(InkWell), findsNothing);
      expect(find.text('javascript:alert(1)'), findsOneWidget);
      final text = tester.widget<Text>(find.byKey(const Key('taskUrl_t1')));
      expect(text.style, isNull);
    });
  });
}
