import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tasks/presentation/task_list_screen.dart';
import 'package:shukan/features/tasks/presentation/widgets/task_row_tag_chips.dart';
import 'package:shukan/features/tasks/presentation/widgets/task_tag_filter_selector.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  const uid = 'test-uid';
  const listId = 'list-123';

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'user@example.com'),
      signedIn: true,
    );
    SharedPreferences.setMockInitialValues({});

    await fakeFirestore.collection('lists').doc(listId).set({
      'listId': listId,
      'uid': uid,
      'name': 'Inbox',
      'isDefault': true,
    });

    await fakeFirestore.collection('tags').doc('tag-work').set({
      'tagId': 'tag-work',
      'uid': uid,
      'name': 'Work',
      'createdAt': DateTime.now(),
    });
    await fakeFirestore.collection('tags').doc('tag-home').set({
      'tagId': 'tag-home',
      'uid': uid,
      'name': 'Home',
      'createdAt': DateTime.now(),
    });

    // Task 1: Work tag
    await fakeFirestore.collection('tasks').doc('t-work').set({
      'taskId': 't-work',
      'uid': uid,
      'listId': listId,
      'title': 'Work Task',
      'tagIds': ['tag-work'],
      'notes': 'Work notes',
      'deletedAt': null,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });

    // Task 2: Home tag
    await fakeFirestore.collection('tasks').doc('t-home').set({
      'taskId': 't-home',
      'uid': uid,
      'listId': listId,
      'title': 'Home Task',
      'tagIds': ['tag-home'],
      'notes': 'Home notes',
      'deletedAt': null,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
    });

    // Task 3: No tags
    await fakeFirestore.collection('tasks').doc('t-notag').set({
      'taskId': 't-notag',
      'uid': uid,
      'listId': listId,
      'title': 'Untagged Task',
      'tagIds': <String>[],
      'notes': '',
      'deletedAt': null,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 3)),
    });
  });

  Widget createWidget({SharedPreferences? prefs}) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MaterialApp(home: TaskListScreen(listId: listId)),
    );
  }

  testWidgets(
    'conditional row tag chips: hidden when inactive, shown when active',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(createWidget(prefs: prefs));
      await tester.pumpAndSettle();

      // Inactive filter: all 3 tasks appear, but NO row tag chips are rendered
      expect(find.text('Work Task'), findsOneWidget);
      expect(find.text('Home Task'), findsOneWidget);
      expect(find.text('Untagged Task'), findsOneWidget);
      expect(find.byType(TaskRowTagChips), findsNothing);

      // Open tag filter dialog and select "Work" tag
      await tester.ensureVisible(find.byType(TaskTagFilterSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TaskTagFilterSelector));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('tagFilterOption_list-123_tag-work')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('closeTagFilterButton_list-123')));
      await tester.pumpAndSettle();

      // Now filter is active: only Work Task is visible, AND TaskRowTagChips is rendered
      expect(find.text('Work Task'), findsOneWidget);
      expect(find.text('Home Task'), findsNothing);
      expect(find.text('Untagged Task'), findsNothing);
      expect(find.byType(TaskRowTagChips), findsOneWidget);
      expect(find.text('#Work'), findsOneWidget);
    },
  );

  testWidgets('OR semantics: selecting Work and Home shows both tasks', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'task_tag_filter_list-123': ['tag-work', 'tag-home'],
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(createWidget(prefs: prefs));
    await tester.pumpAndSettle();

    // Both Work Task and Home Task visible, Untagged Task omitted
    expect(find.text('Work Task'), findsOneWidget);
    expect(find.text('Home Task'), findsOneWidget);
    expect(find.text('Untagged Task'), findsNothing);

    expect(find.byType(TaskRowTagChips), findsNWidgets(2));
    expect(find.text('#Work'), findsOneWidget);
    expect(find.text('#Home'), findsOneWidget);
  });
}
