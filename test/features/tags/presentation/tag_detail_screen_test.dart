import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tags/presentation/tag_detail_screen.dart';
import 'package:shukan/features/tasks/presentation/widgets/show_completed_toggle.dart';
import 'package:shukan/features/tasks/presentation/widgets/task_priority_filter_selector.dart';
import 'package:shukan/features/tasks/presentation/widgets/task_row_tag_chips.dart';
import 'package:shukan/features/tasks/presentation/widgets/task_sort_selector.dart';
import 'package:shukan/features/tasks/presentation/widgets/task_tag_filter_selector.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  const uid = 'test-uid';

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'user@example.com'),
      signedIn: true,
    );
    SharedPreferences.setMockInitialValues({});

    await fakeFirestore.collection('tags').doc('tag-work').set({
      'tagId': 'tag-work',
      'uid': uid,
      'name': 'Work',
      'createdAt': DateTime.now(),
    });
  });

  Widget createWidget({
    required String tagId,
    required String tagName,
    SharedPreferences? prefs,
  }) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        home: TagDetailScreen(tagId: tagId, tagName: tagName),
      ),
    );
  }

  testWidgets(
    'renders header controls, pre-selects tag, and shows tasks without due dates',
    (tester) async {
      // Task with due date
      await fakeFirestore.collection('tasks').doc('t-with-due').set({
        'taskId': 't-with-due',
        'uid': uid,
        'title': 'Task With Due Date',
        'dueDate': Timestamp.fromDate(DateTime(2026, 10, 15)),
        'tagIds': ['tag-work'],
        'notes': 'Important meeting',
        'deletedAt': null,
        'completedAt': null,
        'createdAt': Timestamp.now(),
      });

      // Task WITHOUT due date — critical verification
      await fakeFirestore.collection('tasks').doc('t-no-due').set({
        'taskId': 't-no-due',
        'uid': uid,
        'title': 'Task No Due Date',
        'dueDate': null,
        'tagIds': ['tag-work'],
        'notes': 'Ongoing project',
        'deletedAt': null,
        'completedAt': null,
        'createdAt': Timestamp.now(),
      });

      // Task with different tag
      await fakeFirestore.collection('tasks').doc('t-other').set({
        'taskId': 't-other',
        'uid': uid,
        'title': 'Personal Errand',
        'tagIds': ['tag-personal'],
        'deletedAt': null,
        'completedAt': null,
        'createdAt': Timestamp.now(),
      });

      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        createWidget(tagId: 'tag-work', tagName: 'Work', prefs: prefs),
      );
      await tester.pumpAndSettle();

      // Verify header controls are present
      expect(find.byType(TaskSortSelector), findsOneWidget);
      expect(find.byType(TaskPriorityFilterSelector), findsOneWidget);
      expect(find.byType(TaskTagFilterSelector), findsOneWidget);
      expect(find.byType(ShowCompletedToggle), findsOneWidget);

      // Verify matching tasks appear
      expect(find.text('Task With Due Date'), findsOneWidget);
      expect(find.text('Task No Due Date'), findsOneWidget);
      expect(find.text('Personal Errand'), findsNothing);

      // Tag filter is active, so TaskRowTagChips are rendered under task titles
      expect(find.byType(TaskRowTagChips), findsNWidgets(2));
      expect(find.text('#Work'), findsAtLeastNWidgets(2));
    },
  );

  testWidgets('task completion checkbox toggles completedAt', (tester) async {
    await fakeFirestore.collection('tasks').doc('t-work-toggle').set({
      'taskId': 't-work-toggle',
      'uid': uid,
      'title': 'Toggle Me',
      'tagIds': ['tag-work'],
      'deletedAt': null,
      'completedAt': null,
      'createdAt': Timestamp.now(),
    });

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      createWidget(tagId: 'tag-work', tagName: 'Work', prefs: prefs),
    );
    await tester.pumpAndSettle();

    expect(find.text('Toggle Me'), findsOneWidget);

    // Tap complete checkbox
    await tester.tap(
      find.byKey(const Key('taskCompleteCheckbox_t-work-toggle')),
    );
    await tester.pumpAndSettle();

    // Verify task is marked completed in Firestore
    final doc = await fakeFirestore
        .collection('tasks')
        .doc('t-work-toggle')
        .get();
    expect(doc.data()!['completedAt'], isNotNull);
  });

  testWidgets(
    'updates AppBar title when tag is renamed and renders empty state gracefully when tag is deleted',
    (tester) async {
      await fakeFirestore.collection('tasks').doc('t-work-live').set({
        'taskId': 't-work-live',
        'uid': uid,
        'title': 'Live Task',
        'tagIds': ['tag-work'],
        'deletedAt': null,
        'completedAt': null,
        'createdAt': Timestamp.now(),
      });

      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        createWidget(tagId: 'tag-work', tagName: 'Work', prefs: prefs),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('#Work'),
        ),
        findsOneWidget,
      );
      expect(find.text('Live Task'), findsOneWidget);

      // Rename tag in Firestore
      await fakeFirestore
          .collection('tags')
          .doc('tag-work')
          .update({'name': 'Office'});
      await tester.pumpAndSettle();

      // Title updates reactively
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('#Office'),
        ),
        findsOneWidget,
      );

      // Delete tag reference from task in Firestore (simulating deleteTag)
      await fakeFirestore.collection('tasks').doc('t-work-live').update({
        'tagIds': [],
      });
      await fakeFirestore.collection('tags').doc('tag-work').delete();
      await tester.pumpAndSettle();

      // Renders empty state gracefully without crash
      expect(find.byKey(const Key('noTasksText')), findsOneWidget);
      expect(find.text('No tasks found'), findsOneWidget);
    },
  );
}
