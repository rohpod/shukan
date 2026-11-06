import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/providers/auth_providers.dart';
import 'package:shukan/features/tags/presentation/widgets/tag_chips_section.dart';
import 'package:shukan/features/tags/presentation/widgets/tag_tasks_popup.dart';
import 'package:shukan/features/tasks/providers/task_tag_filter_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  const uid = 'test-uid';

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'test@example.com'),
      signedIn: true,
    );
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestWidget({
    required String contextKey,
    required List<TagBrowserEntry> entries,
    String? testUid = uid,
  }) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentUidProvider.overrideWithValue(testUid),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: TagChipsSection(
            contextKey: contextKey,
            uid: testUid,
            entries: entries,
          ),
        ),
      ),
    );
  }

  testWidgets('renders nothing when entries is empty', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(contextKey: 'test-empty', entries: const []),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tagChipsSection_test-empty')), findsNothing);
  });

  testWidgets(
    'starts collapsed, toggles expand/collapse on header tap, and renders chips with counts',
    (tester) async {
      const entries = [
        TagBrowserEntry(tagId: 'tag-work', name: 'Work', taskCount: 3),
        TagBrowserEntry(tagId: 'tag-home', name: 'Home', taskCount: 1),
      ];

      await tester.pumpWidget(
        buildTestWidget(contextKey: 'test-section', entries: entries),
      );
      await tester.pumpAndSettle();

      // Starts collapsed
      expect(
        find.byKey(const Key('tagChipsSection_test-section')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('tagChipsSectionHeader_test-section')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(
        find.byKey(const Key('tagChip_test-section_tag-work')),
        findsNothing,
      );

      // Tap header to expand
      await tester.tap(
        find.byKey(const Key('tagChipsSectionHeader_test-section')),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(
        find.byKey(const Key('tagChip_test-section_tag-work')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('tagChip_test-section_tag-home')),
        findsOneWidget,
      );
      expect(find.text('#Work'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('#Home'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      // Tap header again to collapse
      await tester.tap(
        find.byKey(const Key('tagChipsSectionHeader_test-section')),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(
        find.byKey(const Key('tagChip_test-section_tag-work')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'tapping chip opens TagTasksPopup and long pressing opens bottom sheet',
    (tester) async {
      await fakeFirestore.collection('tags').doc('tag-work').set({
        'tagId': 'tag-work',
        'uid': uid,
        'name': 'Work',
      });

      const entries = [
        TagBrowserEntry(tagId: 'tag-work', name: 'Work', taskCount: 2),
      ];

      await tester.pumpWidget(
        buildTestWidget(contextKey: 'test-actions', entries: entries),
      );
      await tester.pumpAndSettle();

      // Expand
      await tester.tap(
        find.byKey(const Key('tagChipsSectionHeader_test-actions')),
      );
      await tester.pumpAndSettle();

      // Tap chip -> opens TagTasksPopup
      await tester.tap(find.byKey(const Key('tagChip_test-actions_tag-work')));
      await tester.pumpAndSettle();

      expect(find.byType(TagTasksPopup), findsOneWidget);
      expect(find.byKey(const Key('tagTasksPopup_tag-work')), findsOneWidget);

      // Dismiss popup
      await tester.tap(find.byKey(const Key('tagTasksPopupCloseButton')));
      await tester.pumpAndSettle();
      expect(find.byType(TagTasksPopup), findsNothing);

      // Long press chip -> opens bottom sheet
      await tester.longPress(
        find.byKey(const Key('tagChip_test-actions_tag-work')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('tagActionsBottomSheet_tag-work')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('editTagAction_tag-work')), findsOneWidget);
      expect(find.byKey(const Key('deleteTagAction_tag-work')), findsOneWidget);
    },
  );
}
