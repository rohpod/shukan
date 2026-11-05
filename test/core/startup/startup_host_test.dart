import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/startup/startup_host.dart';

void main() {
  testWidgets('shows progress, then the app once start succeeds', (
    tester,
  ) async {
    final completer = Completer<Widget>();
    await tester.pumpWidget(StartupHost(start: () => completer.future));

    expect(find.byKey(const Key('startupProgress')), findsOneWidget);

    completer.complete(const MaterialApp(home: Text('ready')));
    await tester.pumpAndSettle();

    expect(find.text('ready'), findsOneWidget);
    expect(find.byKey(const Key('startupProgress')), findsNothing);
  });

  testWidgets('a failed start shows a message, and Retry runs start again', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      StartupHost(
        start: () async {
          attempts++;
          if (attempts == 1) throw StateError('no network');
          return const MaterialApp(home: Text('ready'));
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('startupErrorMessage')), findsOneWidget);
    expect(find.text('ready'), findsNothing);
    expect(attempts, 1);

    await tester.tap(find.byKey(const Key('startupRetryButton')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('ready'), findsOneWidget);
    expect(find.byKey(const Key('startupErrorMessage')), findsNothing);
  });

  testWidgets('Retry can fail again and stays on the error screen', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      StartupHost(
        start: () async {
          attempts++;
          throw StateError('still down');
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startupRetryButton')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byKey(const Key('startupErrorMessage')), findsOneWidget);
  });
}
