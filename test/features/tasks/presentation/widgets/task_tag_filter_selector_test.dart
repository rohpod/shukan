import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
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

    // Seed tags
    await fakeFirestore.collection('tags').doc('tag-work').set({
      'tagId': 'tag-work',
      'uid': uid,
      'name': 'Work',
      'createdAt': DateTime.now(),
    });
    await fakeFirestore.collection('tags').doc('tag-life').set({
      'tagId': 'tag-life',
      'uid': uid,
      'name': 'Life',
      'createdAt': DateTime.now(),
    });
  });

  Widget createWidget({required String viewKey, SharedPreferences? prefs}) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        home: Scaffold(body: TaskTagFilterSelector(viewKey: viewKey)),
      ),
    );
  }

  testWidgets('renders "Tags: All" when no tag filter is active', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(createWidget(viewKey: 'test-view', prefs: prefs));
    await tester.pumpAndSettle();

    expect(find.text('Tags: All'), findsOneWidget);
  });

  testWidgets('shows dialog with checkboxes and toggles tag selection', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(createWidget(viewKey: 'test-view', prefs: prefs));
    await tester.pumpAndSettle();

    // Tap selector to open dialog
    await tester.tap(find.byKey(const Key('taskTagFilterSelector_test-view')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('taskTagFilterDialog_test-view')),
      findsOneWidget,
    );
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Life'), findsOneWidget);

    // Tap "Work" tag checkbox
    await tester.tap(
      find.byKey(const Key('tagFilterOption_test-view_tag-work')),
    );
    await tester.pumpAndSettle();

    // Close dialog
    await tester.tap(find.byKey(const Key('closeTagFilterButton_test-view')));
    await tester.pumpAndSettle();

    // Selector now reflects 1 active tag
    expect(find.text('Tags (1)'), findsOneWidget);
    expect(
      prefs.getStringList('task_tag_filter_test-view'),
      equals(['tag-work']),
    );
  });

  testWidgets('clear all button removes all selected tags', (tester) async {
    SharedPreferences.setMockInitialValues({
      'task_tag_filter_test-view': ['tag-work', 'tag-life'],
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(createWidget(viewKey: 'test-view', prefs: prefs));
    await tester.pumpAndSettle();

    expect(find.text('Tags (2)'), findsOneWidget);

    // Open dialog
    await tester.tap(find.byKey(const Key('taskTagFilterSelector_test-view')));
    await tester.pumpAndSettle();

    // Tap "Clear all"
    await tester.tap(find.byKey(const Key('clearTagFilterButton_test-view')));
    await tester.pumpAndSettle();

    // Close dialog
    await tester.tap(find.byKey(const Key('closeTagFilterButton_test-view')));
    await tester.pumpAndSettle();

    expect(find.text('Tags: All'), findsOneWidget);
    expect(prefs.getStringList('task_tag_filter_test-view'), isNull);
  });
}
