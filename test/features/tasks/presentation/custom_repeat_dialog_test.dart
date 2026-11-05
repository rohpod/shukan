import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tasks/presentation/task_list_screen.dart';

void main() {
  const uid = 'test-uid';
  const listId = 'test-list-id';
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
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

  // 2026-06-10 is a Wednesday.
  Future<void> seedTask({Map<String, dynamic>? config}) {
    return fakeFirestore.collection('tasks').doc('t1').set({
      'taskId': 't1',
      'uid': uid,
      'listId': listId,
      'title': 'Custom task',
      'notes': '',
      'url': '',
      'priority': 'none',
      'tagIds': <String>[],
      'dueDate': Timestamp.fromDate(DateTime(2026, 6, 10)),
      'dueTime': null,
      'earlyReminderMinutes': 0,
      'repeatRule': 'custom',
      'repeatCustomConfig': config,
      'order': 0,
      'subtasks': <Map<String, dynamic>>[],
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'completedAt': null,
      'deletedAt': null,
    });
  }

  Future<void> openEditDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(
            MockFirebaseAuth(
              mockUser: MockUser(uid: uid, email: 'test@example.com'),
              signedIn: true,
            ),
          ),
          firestoreProvider.overrideWithValue(fakeFirestore),
        ],
        child: const MaterialApp(
          home: Scaffold(body: TaskListScreen(listId: null)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('taskItem_t1')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  Future<Map<String, dynamic>> savedConfig() async {
    final doc = await fakeFirestore.collection('tasks').doc('t1').get();
    return Map<String, dynamic>.from(doc.data()!['repeatCustomConfig'] as Map);
  }

  testWidgets('an old custom task with no config shows weekly defaults', (
    tester,
  ) async {
    await seedTask();
    await openEditDialog(tester);

    expect(find.byKey(const Key('customRepeatIntervalInput')), findsOneWidget);
    expect(find.byKey(const Key('customRepeatUnitInput')), findsOneWidget);
    expect(find.text('Every week on Wed'), findsOneWidget);
    final wed = tester.widget<FilterChip>(
      find.byKey(const Key('customRepeatWeekday_3')),
    );
    expect(wed.selected, isTrue);

    await tester.tap(find.byKey(const Key('saveTaskButton')));
    await tester.pumpAndSettle();

    expect(await savedConfig(), {
      'unit': 'week',
      'interval': 1,
      'weekdays': [3],
    });
  });

  testWidgets('an out-of-range interval blocks saving', (tester) async {
    await seedTask(config: {'unit': 'day', 'interval': 2});
    await openEditDialog(tester);

    await tester.enterText(
      find.byKey(const Key('customRepeatIntervalInput')),
      '400',
    );
    await tester.tap(find.byKey(const Key('saveTaskButton')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a number from 1 to 365.'), findsOneWidget);
    expect(find.text('Edit Task'), findsOneWidget);
    expect(await savedConfig(), {'unit': 'day', 'interval': 2});
  });

  testWidgets('weeks need at least one weekday', (tester) async {
    await seedTask();
    await openEditDialog(tester);

    await tester.tap(find.byKey(const Key('customRepeatWeekday_3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveTaskButton')));
    await tester.pumpAndSettle();

    expect(find.text('Pick at least one day.'), findsOneWidget);
    expect(find.text('Edit Task'), findsOneWidget);
  });

  testWidgets('picked weekdays and interval are saved', (tester) async {
    await seedTask();
    await openEditDialog(tester);

    await tester.enterText(
      find.byKey(const Key('customRepeatIntervalInput')),
      '2',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('customRepeatWeekday_1')));
    await tester.pumpAndSettle();
    expect(find.text('Every 2 weeks on Mon, Wed'), findsOneWidget);

    await tester.tap(find.byKey(const Key('saveTaskButton')));
    await tester.pumpAndSettle();

    expect(await savedConfig(), {
      'unit': 'week',
      'interval': 2,
      'weekdays': [1, 3],
    });
  });
}
