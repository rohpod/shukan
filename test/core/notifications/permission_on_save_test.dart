import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/core/notifications/notification_service.dart';
import 'package:shukan/core/notifications/web_reminder_scheduler.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/presentation/quick_add_bar.dart';
import 'package:shukan/features/tasks/presentation/task_list_screen.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

class MockNotificationService extends Mock implements NotificationService {}

void main() {
  late MockNotificationService mockNotifService;
  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  late SharedPreferences prefs;
  int chimePrepareCount = 0;

  const uid = 'test-uid';
  const listId = 'test-list-id';

  setUpAll(() {
    registerFallbackValue(
      const Task(taskId: 'fallback', uid: 'u', listId: 'l', title: 'fallback'),
    );
  });

  setUp(() async {
    mockNotifService = MockNotificationService();
    fakeFirestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'user@test.com'),
      signedIn: true,
    );
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    chimePrepareCount = 0;

    when(() => mockNotifService.requestWebPermissionIfNeeded())
        .thenAnswer((_) async => WebPermissionResult.granted);
    when(() => mockNotifService.scheduleForTask(any()))
        .thenAnswer((_) async {});
    when(() => mockNotifService.cancelForTask(any())).thenAnswer((_) async {});

    await fakeFirestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': 'user@test.com',
      'defaultListId': listId,
    });
    await fakeFirestore.collection('lists').doc(listId).set({
      'listId': listId,
      'uid': uid,
      'name': 'Inbox',
      'isDefault': true,
    });
  });

  Widget buildScope({required Widget child}) {
    return ProviderScope(
      overrides: [
        isWebPlatformProvider.overrideWithValue(true),
        notificationServiceProvider.overrideWithValue(mockNotifService),
        sharedPreferencesProvider.overrideWithValue(prefs),
        chimePreparerProvider.overrideWithValue(() => chimePrepareCount++),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentDateProvider.overrideWithValue(DateTime(2026, 10, 15, 10, 0)),
      ],
      child: MaterialApp(
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        home: Scaffold(body: child),
      ),
    );
  }

  group('Permission and audio unlock on save', () {
    testWidgets(
      'TaskDialog save does NOT call permission or chime when dueDate is null',
      (tester) async {
        await tester.pumpWidget(
          buildScope(
            child: const TaskDialog(uid: uid, listId: listId),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('taskTitleInput')),
          'No due date task',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('saveTaskButton')));
        await tester.pumpAndSettle();

        verifyNever(() => mockNotifService.requestWebPermissionIfNeeded());
        expect(chimePrepareCount, 0);
      },
    );

    testWidgets(
      'TaskDialog save CALLS permission and chime when dueDate is set',
      (tester) async {
        await tester.pumpWidget(
          buildScope(
            child: TaskDialog(
              uid: uid,
              listId: listId,
              initialDueDate: DateTime(2026, 10, 16),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('taskTitleInput')),
          'Has due date task',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('saveTaskButton')));
        await tester.pumpAndSettle();

        verify(() => mockNotifService.requestWebPermissionIfNeeded()).called(1);
        expect(chimePrepareCount, 1);
        expect(prefs.getBool('web_notifications_prompt_shown'), isTrue);
      },
    );

    testWidgets(
      'second dated save does NOT call permission when prompt flag is already set',
      (tester) async {
        await prefs.setBool('web_notifications_prompt_shown', true);

        await tester.pumpWidget(
          buildScope(
            child: TaskDialog(
              uid: uid,
              listId: listId,
              initialDueDate: DateTime(2026, 10, 16),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('taskTitleInput')),
          'Second dated task',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('saveTaskButton')));
        await tester.pumpAndSettle();

        verifyNever(() => mockNotifService.requestWebPermissionIfNeeded());
        expect(chimePrepareCount, 1);
      },
    );

    testWidgets(
      'QuickAddBar confirm does NOT call permission or chime when date is not parsed',
      (tester) async {
        await tester.pumpWidget(
          buildScope(
            child: const QuickAddBar(uid: uid, listId: listId),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'Buy groceries',
        );
        await tester.pump();

        // First tap parses
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pump();

        // Second tap confirms
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        verifyNever(() => mockNotifService.requestWebPermissionIfNeeded());
        expect(chimePrepareCount, 0);
      },
    );

    testWidgets(
      'QuickAddBar confirm CALLS permission and chime on second tap when date is parsed',
      (tester) async {
        await tester.pumpWidget(
          buildScope(
            child: const QuickAddBar(uid: uid, listId: listId),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('quickAddTextInput')),
          'Buy milk tomorrow 3pm',
        );
        await tester.pump();

        // First tap parses
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pump();

        // Second tap confirms
        await tester.tap(find.byKey(const Key('quickAddSubmitButton')));
        await tester.pumpAndSettle();

        verify(() => mockNotifService.requestWebPermissionIfNeeded()).called(1);
        expect(chimePrepareCount, 1);
        expect(prefs.getBool('web_notifications_prompt_shown'), isTrue);
      },
    );

    testWidgets(
      'One-time SnackBar is shown when web permission is denied on save, and not repeated',
      (tester) async {
        when(() => mockNotifService.requestWebPermissionIfNeeded())
            .thenAnswer((_) async => WebPermissionResult.denied);

        await tester.pumpWidget(
          buildScope(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => TaskDialog(
                    uid: uid,
                    listId: listId,
                    initialDueDate: DateTime(2026, 10, 16),
                  ),
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open dialog
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('taskTitleInput')),
          'First task',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('saveTaskButton')));
        await tester.pumpAndSettle();

        // Verify SnackBar shown on parent scaffold
        expect(
          find.text(
            "Notifications are blocked in your browser. You won't get task reminders from this tab.",
          ),
          findsOneWidget,
        );

        // Verify SharedPreferences flag was set
        expect(prefs.getBool('web_notifications_denied_snack_shown'), isTrue);

        // Dismiss the first snackbar
        ScaffoldMessenger.of(tester.element(find.text('Open Dialog')))
            .hideCurrentSnackBar();
        await tester.pumpAndSettle();
        expect(
          find.text(
            "Notifications are blocked in your browser. You won't get task reminders from this tab.",
          ),
          findsNothing,
        );

        // Open and save a second task with due date: SnackBar must NOT be shown again
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('taskTitleInput')),
          'Second task',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('saveTaskButton')));
        await tester.pumpAndSettle();

        // Not repeated
        expect(
          find.text(
            "Notifications are blocked in your browser. You won't get task reminders from this tab.",
          ),
          findsNothing,
        );
      },
    );
  });
}
