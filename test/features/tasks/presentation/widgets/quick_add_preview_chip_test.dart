import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/presentation/widgets/quick_add_preview_chip.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';

void main() {
  group('QuickAddPreviewChip Formatter Unit Tests', () {
    test('formatDueTime12Hour converts 24h to 12h format', () {
      expect(formatDueTime12Hour('00:00'), '12:00 AM');
      expect(formatDueTime12Hour('09:05'), '9:05 AM');
      expect(formatDueTime12Hour('12:00'), '12:00 PM');
      expect(formatDueTime12Hour('17:00'), '5:00 PM');
      expect(formatDueTime12Hour('23:59'), '11:59 PM');
      expect(formatDueTime12Hour('invalid'), 'invalid');
    });

    test('formatPreviewDate formats relative and absolute dates', () {
      final now = DateTime(2026, 10, 14, 10, 0);

      expect(formatPreviewDate(DateTime(2026, 10, 14), now), 'Today');
      expect(formatPreviewDate(DateTime(2026, 10, 15), now), 'Tomorrow');
      expect(formatPreviewDate(DateTime(2026, 10, 13), now), 'Yesterday');
      expect(formatPreviewDate(DateTime(2026, 10, 20), now), '2026-10-20');
      expect(formatPreviewDate(DateTime(2026, 1, 5), now), '2026-01-05');
    });

    test(
      'buildQuickAddChipLabel builds correct combined and individual labels',
      () {
        final now = DateTime(2026, 10, 14, 10, 0);

        expect(
          buildQuickAddChipLabel(
            dueDate: DateTime(2026, 10, 15),
            dueTime: '17:00',
            now: now,
          ),
          'Tomorrow 5:00 PM',
        );

        expect(
          buildQuickAddChipLabel(
            dueDate: DateTime(2026, 10, 14),
            dueTime: null,
            now: now,
          ),
          'Today',
        );

        expect(
          buildQuickAddChipLabel(dueDate: null, dueTime: '09:00', now: now),
          '9:00 AM',
        );

        expect(
          buildQuickAddChipLabel(dueDate: null, dueTime: null, now: now),
          '',
        );
      },
    );
  });

  group('QuickAddPreviewChip Widget Tests', () {
    final fixedClock = DateTime(2026, 10, 14, 10, 0);

    Widget createWidgetUnderTest({
      DateTime? dueDate,
      String? dueTime,
      required VoidCallback onDismiss,
    }) {
      return ProviderScope(
        overrides: [currentDateProvider.overrideWithValue(fixedClock)],
        child: MaterialApp(
          home: Scaffold(
            body: QuickAddPreviewChip(
              dueDate: dueDate,
              dueTime: dueTime,
              onDismiss: onDismiss,
            ),
          ),
        ),
      );
    }

    testWidgets('renders chip with avatar, label, and delete button', (
      tester,
    ) async {
      var dismissed = false;

      await tester.pumpWidget(
        createWidgetUnderTest(
          dueDate: DateTime(2026, 10, 15),
          dueTime: '18:00',
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);
      expect(find.text('Tomorrow 6:00 PM'), findsOneWidget);
      expect(find.byIcon(Icons.event_outlined), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });
  });
}
