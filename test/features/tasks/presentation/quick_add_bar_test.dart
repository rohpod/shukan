import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/data/task_repository.dart';
import 'package:shukan/features/tasks/presentation/quick_add_bar.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';
import 'package:shukan/features/tasks/providers/task_providers.dart';

class _DelayedTaskRepository extends TaskRepository {
  final TaskRepository _inner;
  final Completer<void> _gate;
  int createCalls = 0;

  _DelayedTaskRepository(this._inner, this._gate)
    : super(FakeFirebaseFirestore());

  @override
  Future<Task> createTask({
    required String uid,
    required String listId,
    required String title,
    String notes = '',
    String url = '',
    DateTime? dueDate,
    String? dueTime,
  }) async {
    createCalls++;
    await _gate.future;
    return _inner.createTask(
      uid: uid,
      listId: listId,
      title: title,
      notes: notes,
      url: url,
      dueDate: dueDate,
      dueTime: dueTime,
    );
  }
}

class _FailingTaskRepository extends TaskRepository {
  final TaskRepository _inner;
  int createCalls = 0;
  bool shouldFail = true;

  _FailingTaskRepository(this._inner) : super(FakeFirebaseFirestore());

  @override
  Future<Task> createTask({
    required String uid,
    required String listId,
    required String title,
    String notes = '',
    String url = '',
    DateTime? dueDate,
    String? dueTime,
  }) async {
    createCalls++;
    if (shouldFail) {
      throw Exception('Simulated create failure');
    }
    return _inner.createTask(
      uid: uid,
      listId: listId,
      title: title,
      notes: notes,
      url: url,
      dueDate: dueDate,
      dueTime: dueTime,
    );
  }
}

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
    List<dynamic> additionalOverrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentDateProvider.overrideWithValue(fixedClock),
        ...additionalOverrides,
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
        expect(find.text('Submit assignment tomorrow 5pm'), findsNothing);

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

        // Verify task persisted in Firestore with stripped title
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

        // Submit once -> preview chip shows and title is stripped
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);
        expect(find.text('Buy milk'), findsOneWidget);

        // Tap delete icon on Chip
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Preview chip should be dismissed
        expect(find.byKey(const Key('quickAddDateChip')), findsNothing);

        // Original typed text should be restored in text field
        expect(find.text('Buy milk tmrw 10am'), findsOneWidget);

        // Hint text must be absent
        expect(find.byKey(const Key('quickAddHintText')), findsNothing);
        expect(
          find.text('No date detected. Press Enter to create.'),
          findsNothing,
        );

        // Submit task -> created with raw title and null due date/time
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
      'submitting without date phrase creates task immediately on first submit with no hint',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'Read chapter 4',
        );
        await tester.pumpAndSettle();

        // First submit -> creates task immediately with no hint
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
      },
    );

    testWidgets(
      'editing text while preview chip is visible preserves the chip and parsed date',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'Submit assignment tomorrow 5pm',
        );
        await tester.pumpAndSettle();

        // Submit 1 (parse)
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);
        expect(find.text('Submit assignment'), findsOneWidget);

        // Edit text
        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'Submit math assignment',
        );
        await tester.pumpAndSettle();

        // Chip still visible
        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);

        // Submit 2 (confirm)
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        final snapshot = await fakeFirestore.collection('tasks').get();
        expect(snapshot.docs.length, 1);
        final taskData = snapshot.docs.first.data();
        expect(taskData['title'], 'Submit math assignment');
        expect(taskData['dueTime'], '17:00');
        expect(taskData['dueDate'], isNotNull);
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

    testWidgets('renders default hint text "Add a task" when not provided', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Add a task'), findsOneWidget);
    });

    testWidgets('renders custom hint text when provided', (tester) async {
      await tester.pumpWidget(
        createWidgetUnderTest(hintText: 'Add task to Work...'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add task to Work...'), findsOneWidget);
    });

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

    testWidgets(
      'rapid double submit via keyboard Enter action creates exactly one task',
      (tester) async {
        final gate = Completer<void>();
        final baseRepo = TaskRepository(fakeFirestore);
        final delayedRepo = _DelayedTaskRepository(baseRepo, gate);

        await tester.pumpWidget(
          createWidgetUnderTest(
            additionalOverrides: [
              taskRepositoryProvider.overrideWithValue(delayedRepo),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'Submit essay tomorrow 5pm',
        );
        await tester.pumpAndSettle();

        // 1. First Enter -> runs parser
        await tester.showKeyboard(find.byKey(const Key('quickAddTextInput')));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quickAddDateChip')), findsOneWidget);

        // 2. Second Enter -> triggers creation (in-flight)
        await tester.showKeyboard(find.byKey(const Key('quickAddTextInput')));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        // 3. Third rapid Enter while in-flight -> should be ignored
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        gate.complete();
        await tester.pumpAndSettle();

        expect(delayedRepo.createCalls, equals(1));
        final snapshot = await fakeFirestore.collection('tasks').get();
        expect(snapshot.docs.length, equals(1));
        expect(snapshot.docs.first.data()['title'], equals('Submit essay'));
      },
    );

    testWidgets(
      'rapid submit via Enter followed immediately by submit button tap creates exactly one task',
      (tester) async {
        final gate = Completer<void>();
        final baseRepo = TaskRepository(fakeFirestore);
        final delayedRepo = _DelayedTaskRepository(baseRepo, gate);

        await tester.pumpWidget(
          createWidgetUnderTest(
            additionalOverrides: [
              taskRepositoryProvider.overrideWithValue(delayedRepo),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'Buy groceries',
        );
        await tester.pumpAndSettle();

        // Date-less task: first Enter initiates create
        await tester.showKeyboard(find.byKey(const Key('quickAddTextInput')));
        await tester.testTextInput.receiveAction(TextInputAction.done);

        // Immediate tap on submit button before gate completes
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pump();

        gate.complete();
        await tester.pumpAndSettle();

        expect(delayedRepo.createCalls, equals(1));
        final snapshot = await fakeFirestore.collection('tasks').get();
        expect(snapshot.docs.length, equals(1));
        expect(snapshot.docs.first.data()['title'], equals('Buy groceries'));
      },
    );

    testWidgets('after a failed create the bar is usable again', (
      tester,
    ) async {
      final baseRepo = TaskRepository(fakeFirestore);
      final failingRepo = _FailingTaskRepository(baseRepo);

      await tester.pumpWidget(
        createWidgetUnderTest(
          additionalOverrides: [
            taskRepositoryProvider.overrideWithValue(failingRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('quickAddTextInput')),
        'Task with error',
      );
      await tester.pumpAndSettle();

      // Attempt 1: fails
      await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
      await tester.pumpAndSettle();

      expect(failingRepo.createCalls, equals(1));
      expect(find.textContaining('Failed to add task'), findsOneWidget);

      final snapshotAfterFail = await fakeFirestore.collection('tasks').get();
      expect(snapshotAfterFail.docs, isEmpty);

      // Verify bar is not stuck in saving state and can be re-submitted
      final submitButton = tester.widget<IconButton>(
        find.byKey(const Key('quickAddSubmitButton')),
      );
      expect(submitButton.onPressed, isNotNull);

      // Attempt 2: retry after resolving failure
      failingRepo.shouldFail = false;
      await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
      await tester.pumpAndSettle();

      expect(failingRepo.createCalls, equals(2));
      final snapshotAfterRetry = await fakeFirestore.collection('tasks').get();
      expect(snapshotAfterRetry.docs.length, equals(1));
      expect(
        snapshotAfterRetry.docs.first.data()['title'],
        equals('Task with error'),
      );
    });

    testWidgets(
      'submitting the same text twice sequentially creates two separate tasks',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // 1. First submission
        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'Repeated task',
        );
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        // 2. Second submission with identical text
        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'Repeated task',
        );
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        final snapshot = await fakeFirestore.collection('tasks').get();
        expect(snapshot.docs.length, equals(2));
        expect(snapshot.docs[0].data()['title'], equals('Repeated task'));
        expect(snapshot.docs[1].data()['title'], equals('Repeated task'));
        expect(snapshot.docs[0].id, isNot(equals(snapshot.docs[1].id)));
      },
    );
  });
}
