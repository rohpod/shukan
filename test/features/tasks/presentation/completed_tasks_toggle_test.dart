import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/providers/auth_providers.dart';
import 'package:shukan/features/tasks/domain/smart_view_models.dart';
import 'package:shukan/features/tasks/presentation/smart_view_detail_screen.dart';
import 'package:shukan/features/tasks/presentation/task_list_screen.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  const uid = 'test-uid';
  const listId = 'list-1';
  const otherListId = 'list-2';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fakeFirestore = FakeFirebaseFirestore();
    final user = MockUser(uid: uid, email: 'test@example.com');
    mockAuth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await fakeFirestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': 'test@example.com',
      'defaultListId': listId,
    });
    await fakeFirestore.collection('lists').doc(listId).set({
      'listId': listId,
      'uid': uid,
      'name': 'My List',
      'isDefault': true,
    });
    await fakeFirestore.collection('lists').doc(otherListId).set({
      'listId': otherListId,
      'uid': uid,
      'name': 'Other List',
      'isDefault': false,
    });
  });

  Widget createTaskListWidget(String targetListId, {SharedPreferences? prefs}) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentUidProvider.overrideWithValue(uid),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        home: Scaffold(body: TaskListScreen(listId: targetListId)),
      ),
    );
  }

  Widget createSmartViewWidget({
    required SmartViewType viewType,
    DateTime? currentDate,
    SharedPreferences? prefs,
  }) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentUidProvider.overrideWithValue(uid),
        currentDateProvider.overrideWithValue(
          currentDate ?? DateTime(2026, 9, 20, 10, 0),
        ),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(home: SmartViewDetailScreen(viewType: viewType)),
    );
  }

  group('Show-completed toggle - TaskListScreen removal', () {
    testWidgets('TaskListScreen has no show-completed toggle', (tester) async {
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(createTaskListWidget(listId, prefs: prefs));
      await tester.pumpAndSettle();

      expect(find.byKey(Key('toggleShowCompleted_$listId')), findsNothing);
    });
  });

  group('Show-completed toggle - SmartViewDetailScreen removal', () {
    testWidgets('SmartViewDetailScreen has no show-completed toggle', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        createSmartViewWidget(viewType: SmartViewType.today, prefs: prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggleShowCompleted_today')), findsNothing);
    });
  });
}
