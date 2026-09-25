import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/tasks/presentation/widgets/empty_state_view.dart';

void main() {
  group('EmptyStateView Component Tests', () {
    testWidgets('renders icon and message without action button by default', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateView(
              icon: Icons.inbox_outlined,
              message: 'No tasks yet',
              messageKey: Key('customMessageKey'),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.byKey(const Key('customMessageKey')), findsOneWidget);
      expect(find.text('No tasks yet'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets(
      'renders action button when actionLabel and onAction are provided',
      (tester) async {
        var actionTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EmptyStateView(
                icon: Icons.filter_alt_off_outlined,
                message: 'No tasks match your filters',
                actionLabel: 'Clear filters',
                actionIcon: Icons.clear,
                actionKey: const Key('testActionButton'),
                onAction: () {
                  actionTapped = true;
                },
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);
        expect(find.text('No tasks match your filters'), findsOneWidget);
        expect(find.byKey(const Key('testActionButton')), findsOneWidget);
        expect(find.text('Clear filters'), findsOneWidget);
        expect(find.byIcon(Icons.clear), findsOneWidget);

        await tester.tap(find.byKey(const Key('testActionButton')));
        await tester.pump();

        expect(actionTapped, isTrue);
      },
    );

    testWidgets('renders action button without icon if actionIcon is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateView(
              icon: Icons.inbox,
              message: 'Empty',
              actionLabel: 'Action',
              actionKey: const Key('noIconButton'),
              onAction: () {},
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('noIconButton')), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
    });
  });
}
