import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/presentation/home_screen.dart';
import 'package:shukan/features/tasks/presentation/smart_view_detail_screen.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  const uid = 'smart-flow-user';
  const inboxListId = 'inbox-flow-1';

  setUp(() async {
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'flow@example.com'),
      signedIn: true,
    );
    fakeFirestore = FakeFirebaseFirestore();

    await fakeFirestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': 'flow@example.com',
      'defaultListId': inboxListId,
    });
    await fakeFirestore.collection('lists').doc(inboxListId).set({
      'listId': inboxListId,
      'uid': uid,
      'name': 'Inbox',
      'isDefault': true,
    });
  });

  Widget createWidgetUnderTest({DateTime? overrideDate}) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        if (overrideDate != null)
          currentDateProvider.overrideWithValue(overrideDate),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  testWidgets(
    'smart views end-to-end flow: home cards navigation, task creation, filtering',
    (tester) async {
      final wednesday = DateTime(2026, 10, 14, 10, 0);

      await tester.pumpWidget(createWidgetUnderTest(overrideDate: wednesday));
      await tester.pumpAndSettle();

      // Verify Smart Views cards are visible on HomeScreen
      expect(find.byKey(const Key('smartViewCard_today')), findsOneWidget);
      expect(find.byKey(const Key('smartViewCard_thisWeek')), findsOneWidget);
      expect(find.byKey(const Key('smartViewCard_scheduled')), findsOneWidget);

      // 1. Navigate to Today Smart View
      await tester.tap(find.byKey(const Key('smartViewCard_today')));
      await tester.pumpAndSettle();

      expect(find.byType(SmartViewDetailScreen), findsOneWidget);
      expect(find.byKey(const Key('smartViewTitle_today')), findsOneWidget);
      expect(find.byKey(const Key('noTasksText')), findsOneWidget);

      // 2. Add a new task due today via FAB
      await tester.tap(find.byKey(const Key('addSmartViewTaskButton')));
      await tester.pumpAndSettle();

      expect(find.text('New Task'), findsOneWidget);
      expect(find.text('2026-10-14'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('taskTitleInput')),
        'Dentist Appointment',
      );
      await tester.tap(find.byKey(const Key('saveTaskButton')));
      await tester.pumpAndSettle();

      // Task is now in Today view
      expect(find.text('Dentist Appointment'), findsOneWidget);

      // 3. Return to HomeScreen
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);

      // 4. Navigate to This Week view
      await tester.tap(find.byKey(const Key('smartViewCard_thisWeek')));
      await tester.pumpAndSettle();

      expect(find.byType(SmartViewDetailScreen), findsOneWidget);
      expect(find.text('Dentist Appointment'), findsOneWidget);

      // Add Saturday task
      await tester.tap(find.byKey(const Key('addSmartViewTaskButton')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('taskTitleInput')),
        'Saturday Concert',
      );

      // Pick Saturday date (Oct 17, 2026)
      await tester.tap(find.byKey(const Key('editTaskDueDateInput')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('17'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('saveTaskButton')));
      await tester.pumpAndSettle();

      // Both tasks visible in Full Week mode
      expect(find.text('Dentist Appointment'), findsOneWidget);
      expect(find.text('Saturday Concert'), findsOneWidget);

      // Switch to Work Week mode
      await tester.tap(find.byKey(const Key('workWeekFilterButton')));
      await tester.pumpAndSettle();

      // Saturday task is hidden, Wednesday task remains
      expect(find.text('Dentist Appointment'), findsOneWidget);
      expect(find.text('Saturday Concert'), findsNothing);

      // 5. Check off Dentist Appointment
      final dentistTaskDoc = await fakeFirestore
          .collection('tasks')
          .where('title', isEqualTo: 'Dentist Appointment')
          .get();
      final dentistTaskId = dentistTaskDoc.docs.first.id;

      await tester.tap(find.byKey(Key('taskCompleteCheckbox_$dentistTaskId')));
      await tester.pumpAndSettle();

      // Dentist appointment is hidden under Incomplete filter
      expect(find.text('Dentist Appointment'), findsNothing);

      // Tap Completed filter
      await tester.tap(find.byKey(const Key('completedFilterButton')));
      await tester.pumpAndSettle();

      expect(find.text('Dentist Appointment'), findsOneWidget);

      // 6. Return to HomeScreen and navigate to Scheduled view
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('smartViewCard_scheduled')));
      await tester.pumpAndSettle();

      expect(find.byType(SmartViewDetailScreen), findsOneWidget);
      expect(find.byKey(const Key('smartViewTitle_scheduled')), findsOneWidget);
    },
  );
}
