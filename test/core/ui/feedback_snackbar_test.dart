import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/ui/feedback_snackbar.dart';

void main() {
  testWidgets('plain message without action shows standard snackbar', (
    tester,
  ) async {
    late ScaffoldMessengerState messenger;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  messenger = ScaffoldMessenger.of(context);
                  showFeedbackSnackBar(messenger, 'Plain notification');
                },
                child: const Text('Show'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('Plain notification'), findsOneWidget);
    expect(find.byType(SnackBarAction), findsNothing);
  });

  testWidgets('action snackbar has given Key, label and runs onAction on tap', (
    tester,
  ) async {
    late ScaffoldMessengerState messenger;
    var actionCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  messenger = ScaffoldMessenger.of(context);
                  showFeedbackSnackBar(
                    messenger,
                    'Item deleted',
                    actionLabel: 'Undo',
                    actionKey: const Key('testActionKey'),
                    onAction: () async {
                      actionCalled = true;
                    },
                  );
                },
                child: const Text('Show'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('Item deleted'), findsOneWidget);
    expect(find.byKey(const Key('testActionKey')), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('testActionKey')));
    await tester.pumpAndSettle();

    expect(actionCalled, isTrue);
  });

  testWidgets('onAction error shows <prefix>: <error>', (tester) async {
    late ScaffoldMessengerState messenger;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  messenger = ScaffoldMessenger.of(context);
                  showFeedbackSnackBar(
                    messenger,
                    'Item moved',
                    actionLabel: 'Undo',
                    actionKey: const Key('testErrorActionKey'),
                    onAction: () async {
                      throw Exception('Network timeout');
                    },
                    actionErrorPrefix: 'Failed to undo move',
                  );
                },
                child: const Text('Show'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('testErrorActionKey')));
    await tester.pumpAndSettle();

    expect(
      find.text('Failed to undo move: Exception: Network timeout'),
      findsOneWidget,
    );
  });

  testWidgets('a new snackbar replaces the previous one', (tester) async {
    late ScaffoldMessengerState messenger;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      messenger = ScaffoldMessenger.of(context);
                      showFeedbackSnackBar(messenger, 'First message');
                    },
                    child: const Text('Show First'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      messenger = ScaffoldMessenger.of(context);
                      showFeedbackSnackBar(messenger, 'Second message');
                    },
                    child: const Text('Show Second'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show First'));
    await tester.pumpAndSettle();
    expect(find.text('First message'), findsOneWidget);

    await tester.tap(find.text('Show Second'));
    await tester.pumpAndSettle();
    expect(find.text('First message'), findsNothing);
    expect(find.text('Second message'), findsOneWidget);
  });

  testWidgets('action snackbar auto-dismisses after 5 seconds', (tester) async {
    late ScaffoldMessengerState messenger;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  messenger = ScaffoldMessenger.of(context);
                  showFeedbackSnackBar(
                    messenger,
                    'Auto dismiss test',
                    actionLabel: 'Undo',
                    actionKey: const Key('testTimeoutKey'),
                    onAction: () async {},
                  );
                },
                child: const Text('Show'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Auto dismiss test'), findsOneWidget);

    // Advance 5 seconds and settle
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('Auto dismiss test'), findsNothing);
  });

  testWidgets('swipe start-to-end dismisses action snackbar', (tester) async {
    late ScaffoldMessengerState messenger;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  messenger = ScaffoldMessenger.of(context);
                  showFeedbackSnackBar(
                    messenger,
                    'Swipable notification',
                    actionLabel: 'Undo',
                    actionKey: const Key('testSwipeKey'),
                    onAction: () async {},
                  );
                },
                child: const Text('Show'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Swipable notification'), findsOneWidget);

    // End-to-start (negative dx) does NOT dismiss
    await tester.fling(
      find.text('Swipable notification'),
      const Offset(-500, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Swipable notification'), findsOneWidget);

    // Start-to-end (positive dx) DOES dismiss
    await tester.fling(
      find.text('Swipable notification'),
      const Offset(500, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Swipable notification'), findsNothing);
  });
}
