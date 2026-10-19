import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/presentation/quick_add_bar.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  const uid = 'test-user-id';
  const listId = 'test-list-id';
  final fixedClock = DateTime(2026, 10, 14, 10, 0); // Wednesday

  setUp(() async {
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'test@example.com'),
      signedIn: true,
    );
    fakeFirestore = FakeFirebaseFirestore();

    // Bootstrap user and list
    await fakeFirestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': 'test@example.com',
      'defaultListId': listId,
    });
    await fakeFirestore.collection('lists').doc(listId).set({
      'listId': listId,
      'uid': uid,
      'name': 'Inbox',
      'isDefault': true,
    });
  });

  Widget createWidgetUnderTest({
    String? listIdOverride = listId,
    String? hintText,
    void Function(Task)? onTaskCreated,
  }) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentDateProvider.overrideWithValue(fixedClock),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: QuickAddBar(
            uid: uid,
            listId: listIdOverride,
            hintText: hintText,
            onTaskCreated: onTaskCreated,
          ),
        ),
      ),
    );
  }

  group('QuickAddBar Widget Tests', () {
    testWidgets(
      'renders input and submit button, and renders no expand button',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddTextInput')), findsOneWidget);
        expect(find.byKey(const Key('quickAddSubmitButton')), findsOneWidget);
        expect(find.byKey(const Key('quickAddExpandButton')), findsNothing);
        expect(find.byKey(const Key('quickAddDateChip')), findsNothing);
        expect(find.byKey(const Key('quickAddHintText')), findsNothing);
      },
    );

    testWidgets(
      'typing + submitting date phrase shows preview chip and strips title, second submit creates task',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // 1. Enter task with date and time
        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'Submit assignment tomorrow 5pm',
        );
        await tester.pumpAndSettle();

        // 2. First submit -> runs parser
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        // Preview chip should be visible with "Tomorrow 5:00 PM"
        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);
        expect(find.text('Tomorrow 5:00 PM'), findsOneWidget);

        // Text field should show stripped title
        expect(find.text('Submit assignment'), findsOneWidget);

        // Task should NOT be created in Firestore yet
        final snapshotBefore = await fakeFirestore.collection('tasks').get();
        expect(snapshotBefore.docs, isEmpty);

        // 3. Second submit -> confirms creation
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        // Field cleared and chip removed
        expect(find.byKey(const Key('quickAddDateChip')), findsNothing);
        final inputWidget = tester.widget<TextField>(
          find.byKey(const Key('quickAddTextInput')),
        );
        expect(inputWidget.controller?.text, isEmpty);

        // Verify task persisted in Firestore
        final snapshotAfter = await fakeFirestore.collection('tasks').get();
        expect(snapshotAfter.docs.length, 1);
        final taskData = snapshotAfter.docs.first.data();
        expect(taskData['title'], 'Submit assignment');
        expect(taskData['dueTime'], '17:00');
        expect(taskData['dueDate'], isNotNull);
      },
    );

    testWidgets(
      'dismissing preview chip restores original text and clears date/time',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // Enter task
        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'Buy milk tmrw 10am',
        );
        await tester.pumpAndSettle();

        // Submit once -> preview chip shows, title is stripped
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);
        expect(find.text('Buy milk'), findsOneWidget);

        // Tap delete icon on Chip
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Preview chip should be dismissed
        expect(find.byKey(const Key('quickAddDateChip')), findsNothing);

        // Original raw text should be restored in text field
        expect(find.text('Buy milk tmrw 10am'), findsOneWidget);

        // Inline hint should never be shown
        expect(find.byKey(const Key('quickAddHintText')), findsNothing);

        // Submit task -> created with restored raw title and null due date/time
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        final snapshot = await fakeFirestore.collection('tasks').get();
        expect(snapshot.docs.length, 1);
        final taskData = snapshot.docs.first.data();
        expect(taskData['title'], 'Buy milk tmrw 10am');
        expect(taskData['dueDate'], isNull);
        expect(taskData['dueTime'], isNull);
      },
    );

    testWidgets(
      'submitting without date phrase creates title-only task immediately on single submit',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'Read chapter 4',
        );
        await tester.pumpAndSettle();

        // Single submit -> creates task immediately
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddDateChip')), findsNothing);
        expect(find.byKey(const Key('quickAddHintText')), findsNothing);
        expect(
          find.text('No date detected. Press Enter to create.'),
          findsNothing,
        );

        final snapshot = await fakeFirestore.collection('tasks').get();
        expect(snapshot.docs.length, 1);
        final taskData = snapshot.docs.first.data();
        expect(taskData['title'], 'Read chapter 4');
        expect(taskData['dueDate'], isNull);
        expect(taskData['dueTime'], isNull);

        final inputWidget = tester.widget<TextField>(
          find.byKey(const Key('quickAddTextInput')),
        );
        expect(inputWidget.controller?.text, isEmpty);
      },
    );

    testWidgets(
      'whole-input date phrase preserves original text as title with parsed date/time',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'tomorrow 5pm',
        );
        await tester.pumpAndSettle();

        // First submit -> parses and keeps 'tomorrow 5pm' as title
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);
        expect(find.text('Tomorrow 5:00 PM'), findsOneWidget);
        expect(find.text('tomorrow 5pm'), findsOneWidget);

        // Second submit -> creates task
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        final snapshot = await fakeFirestore.collection('tasks').get();
        expect(snapshot.docs.length, 1);
        final taskData = snapshot.docs.first.data();
        expect(taskData['title'], 'tomorrow 5pm');
        expect(taskData['dueDate'], isNotNull);
        expect(taskData['dueTime'], '17:00');
      },
    );

    testWidgets('submitting via keyboard Enter action works identically', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('quickAddTextInput')),
        'Pay utility bill in 2 days',
      );
      // Submit 1 via testTextInput
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);
      expect(find.text('Pay utility bill'), findsOneWidget);

      // Submit 2 via testTextInput (confirm)
      await tester.showKeyboard(find.byKey(const Key('quickAddTextInput')));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final snapshot = await fakeFirestore.collection('tasks').get();
      expect(snapshot.docs.length, 1);
      final taskData = snapshot.docs.first.data();
      expect(taskData['title'], 'Pay utility bill');
      expect(taskData['dueDate'], isNotNull);
    });

    testWidgets('renders custom hint text when provided', (tester) async {
      await tester.pumpWidget(
        createWidgetUnderTest(hintText: 'Add task to Work...'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add task to Work...'), findsOneWidget);
    });

    testWidgets(
      'renders default hint text when no custom hintText is provided',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        expect(find.text('Add a task'), findsOneWidget);
      },
    );

    testWidgets('disabled and shows loading hint when listId is null', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest(listIdOverride: null));
      await tester.pumpAndSettle();

      expect(find.text('Loading...'), findsOneWidget);

      final textField = tester.widget<TextField>(
        find.byKey(const Key('quickAddTextInput')),
      );
      expect(textField.enabled, isFalse);

      final submitButton = tester.widget<IconButton>(
        find.byKey(const Key('quickAddSubmitButton')),
      );
      expect(submitButton.onPressed, isNull);
    });

    testWidgets('invokes onTaskCreated callback after task is created', (
      tester,
    ) async {
      Task? createdTask;

      await tester.pumpWidget(
        createWidgetUnderTest(onTaskCreated: (task) => createdTask = task),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('quickAddTextInput')),
        'Buy groceries',
      );
      await tester.pumpAndSettle();

      // Submit 1 (parse)
      await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
      await tester.pumpAndSettle();

      // Submit 2 (confirm)
      await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
      await tester.pumpAndSettle();

      expect(createdTask, isNotNull);
      expect(createdTask!.title, 'Buy groceries');
      expect(createdTask!.listId, listId);
    });
  });
}
