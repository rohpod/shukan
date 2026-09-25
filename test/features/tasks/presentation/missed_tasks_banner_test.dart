import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/tasks/domain/smart_view_models.dart';
import 'package:shukan/features/tasks/presentation/missed_tasks_banner.dart';
import 'package:shukan/features/tasks/presentation/smart_view_detail_screen.dart';
import 'package:shukan/features/tasks/providers/missed_tasks_providers.dart';

import 'package:timezone/data/latest_all.dart' as tz_data;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  const uid = 'test-user-id';
  const defaultListId = 'inbox-id';

  setUp(() async {
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'test@example.com'),
      signedIn: true,
    );
    fakeFirestore = FakeFirebaseFirestore();

    await fakeFirestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': 'test@example.com',
      'defaultListId': defaultListId,
    });

    await fakeFirestore.collection('lists').doc(defaultListId).set({
      'listId': defaultListId,
      'uid': uid,
      'name': 'Inbox',
      'isDefault': true,
    });
  });

  Widget buildTestableWidget({
    int overdueCount = 0,
    ProviderContainer? container,
  }) {
    if (container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MissedTasksBanner(),
                Expanded(child: Center(child: Text('Content'))),
              ],
            ),
          ),
        ),
      );
    }

    return ProviderScope(
      overrides: [
        overdueTaskCountProvider.overrideWithValue(overdueCount),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MissedTasksBanner(),
              Expanded(child: Center(child: Text('Content'))),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('renders nothing when no tasks are overdue', (tester) async {
    await tester.pumpWidget(buildTestableWidget(overdueCount: 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('missedTasksBanner')), findsNothing);
    expect(find.byKey(const Key('missedTasksBannerText')), findsNothing);
    expect(find.text('Content'), findsOneWidget);
  });

  testWidgets('renders singular text "1 task overdue" when count is 1', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestableWidget(overdueCount: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('missedTasksBanner')), findsOneWidget);
    expect(find.text('1 task overdue'), findsOneWidget);
    expect(find.byKey(const Key('missedTasksBannerIcon')), findsOneWidget);
    expect(
      find.byKey(const Key('missedTasksBannerDismissButton')),
      findsOneWidget,
    );
    expect(find.text('Content'), findsOneWidget);
  });

  testWidgets('renders plural text "3 tasks overdue" when count is 3', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestableWidget(overdueCount: 3));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('missedTasksBanner')), findsOneWidget);
    expect(find.text('3 tasks overdue'), findsOneWidget);
    expect(find.byKey(const Key('missedTasksBannerIcon')), findsOneWidget);
    expect(
      find.byKey(const Key('missedTasksBannerDismissButton')),
      findsOneWidget,
    );
    expect(find.text('Content'), findsOneWidget);
  });

  testWidgets('tapping dismiss hides the banner', (tester) async {
    await tester.pumpWidget(buildTestableWidget(overdueCount: 2));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('missedTasksBanner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('missedTasksBannerDismissButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('missedTasksBanner')), findsNothing);
    expect(find.text('Content'), findsOneWidget);
  });

  testWidgets(
    'banner stays dismissed after simulating a rebuild, but reappears if session provider is reset',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          overdueTaskCountProvider.overrideWithValue(2),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          firestoreProvider.overrideWithValue(fakeFirestore),
        ],
      );
      addTearDown(container.dispose);

      // 1. Initial display in session
      await tester.pumpWidget(buildTestableWidget(container: container));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('missedTasksBanner')), findsOneWidget);

      // 2. Dismiss banner
      await tester.tap(find.byKey(const Key('missedTasksBannerDismissButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('missedTasksBanner')), findsNothing);

      // 3. Simulate screen navigation/rebuild with the same session container
      await tester.pumpWidget(buildTestableWidget(container: container));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('missedTasksBanner')), findsNothing);

      // 4. Invalidate provider (simulating a cold restart / new session)
      container.invalidate(missedTasksBannerDismissedProvider);
      await tester.pumpWidget(buildTestableWidget(container: container));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('missedTasksBanner')), findsOneWidget);
      expect(find.text('2 tasks overdue'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping the banner (when not dismissed) navigates to SmartViewDetailScreen with SmartViewType.today',
    (tester) async {
      await tester.pumpWidget(buildTestableWidget(overdueCount: 2));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('missedTasksBanner')), findsOneWidget);

      // Tap on the tap area (or text) of the banner
      await tester.tap(find.byKey(const Key('missedTasksBannerTapArea')));
      await tester.pumpAndSettle();

      // Navigated to SmartViewDetailScreen with Today
      expect(find.byType(SmartViewDetailScreen), findsOneWidget);
      final smartViewScreen = tester.widget<SmartViewDetailScreen>(
        find.byType(SmartViewDetailScreen),
      );
      expect(smartViewScreen.viewType, equals(SmartViewType.today));
      expect(find.text('Today'), findsWidgets);
    },
  );
}
