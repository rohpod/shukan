import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/lists/presentation/widgets/list_name_dialog.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    Future<void> Function(BuildContext, String) onConfirm, {
    String initialName = '',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            key: const Key('open'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ListNameDialog(
                title: 'Name',
                confirmLabel: 'Save',
                inputKey: const Key('input'),
                confirmKey: const Key('confirm'),
                cancelKey: const Key('cancel'),
                emptyMessage: 'Enter a name.',
                initialName: initialName,
                onConfirm: onConfirm,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty name shows the message and does not confirm', (
    tester,
  ) async {
    var calls = 0;
    await open(tester, (_, _) async => calls++);

    await tester.enterText(find.byKey(const Key('input')), '   ');
    await tester.tap(find.byKey(const Key('confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a name.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('confirms with the trimmed name and closes without errors', (
    tester,
  ) async {
    String? name;
    await open(tester, (context, n) async {
      name = n;
      Navigator.of(context).pop();
    }, initialName: 'Old');

    await tester.enterText(find.byKey(const Key('input')), '  Groceries ');
    await tester.tap(find.byKey(const Key('confirm')));
    // Frames during the exit animation, while the field is still mounted.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(name, 'Groceries');
    expect(find.byKey(const Key('input')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel closes the dialog without errors', (tester) async {
    await open(tester, (_, _) async {});

    await tester.tap(find.byKey(const Key('cancel')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('input')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
