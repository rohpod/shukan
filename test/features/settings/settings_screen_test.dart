import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/core/notifications/notification_service.dart';
import 'package:shukan/core/notifications/web_reminder_scheduler.dart';
import 'package:shukan/features/settings/presentation/settings_screen.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

class MockNotificationService extends Mock implements NotificationService {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      WebReminder(
        task: const Task(taskId: 'f', uid: 'u', listId: 'l', title: 'f'),
        kind: WebReminderKind.due,
        fireTime: DateTime(2026),
      ),
    );
  });

  late MockNotificationService notifications;
  late FakeFirebaseFirestore firestore;
  late MockUser user;
  late SharedPreferences prefs;
  late int chimes;

  setUp(() async {
    notifications = MockNotificationService();
    firestore = FakeFirebaseFirestore();
    user = MockUser(uid: 'u1', email: 'a@b.c');
    chimes = 0;
    SharedPreferences.setMockInitialValues({'keep': true});
    prefs = await SharedPreferences.getInstance();
    when(() => notifications.webNotificationStatus)
        .thenReturn(WebNotificationStatus.granted);
    when(() => notifications.requestWebPermissionIfNeeded())
        .thenAnswer((_) async => WebPermissionResult.granted);
    when(() => notifications.showWebReminder(any()))
        .thenAnswer((_) async => true);
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    bool isWeb = true,
    void Function(String, String)? download,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(
            MockFirebaseAuth(signedIn: true, mockUser: user),
          ),
          firestoreProvider.overrideWithValue(firestore),
          notificationServiceProvider.overrideWithValue(notifications),
          isWebPlatformProvider.overrideWithValue(isWeb),
          sharedPreferencesProvider.overrideWithValue(prefs),
          chimePreparerProvider.overrideWithValue(() {}),
          chimePlayerProvider.overrideWithValue(() {
            chimes++;
            return true;
          }),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(downloadTrigger: download),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the tab-only limit is always visible on web', (tester) async {
    await pumpSettings(tester);
    expect(find.byKey(const Key('reminderTabNotice')), findsOneWidget);
  });

  testWidgets('the reminder section is hidden off web', (tester) async {
    await pumpSettings(tester, isWeb: false);
    expect(find.byKey(const Key('reminderTabNotice')), findsNothing);
  });

  testWidgets('a test notification plays the chime and shows once', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('testNotificationButton')));
    await tester.pumpAndSettle();

    expect(chimes, 1);
    final reminder =
        verify(() => notifications.showWebReminder(captureAny()))
                .captured
                .single
            as WebReminder;
    expect(reminder.task.taskId, testNotificationTaskId);
  });

  testWidgets('blocked notifications explain how to unblock them', (
    tester,
  ) async {
    when(() => notifications.webNotificationStatus)
        .thenReturn(WebNotificationStatus.blocked);

    await pumpSettings(tester);

    expect(find.textContaining('browser settings'), findsOneWidget);
    expect(find.byKey(const Key('testNotificationButton')), findsNothing);
  });

  testWidgets('notifications can be turned on after a dismissed prompt', (
    tester,
  ) async {
    when(() => notifications.webNotificationStatus)
        .thenReturn(WebNotificationStatus.notAsked);

    await pumpSettings(tester);
    when(() => notifications.webNotificationStatus)
        .thenReturn(WebNotificationStatus.granted);
    await tester.tap(find.byKey(const Key('enableNotificationsButton')));
    await tester.pumpAndSettle();

    verify(() => notifications.requestWebPermissionIfNeeded()).called(1);
    expect(find.text('Notifications are on.'), findsOneWidget);
  });

  testWidgets('export downloads a JSON file', (tester) async {
    String? filename;
    await pumpSettings(tester, download: (_, name) => filename = name);

    await tester.tap(find.byKey(const Key('exportDataButton')));
    await tester.pumpAndSettle();

    expect(filename, endsWith('.json'));
    expect(find.text('Exported your data'), findsOneWidget);
  });

  testWidgets('deleting the account needs a password and clears local data', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('deleteAccountButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeleteAccountButton')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your password to confirm.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('deleteAccountPasswordInput')),
      'password',
    );
    await tester.tap(find.byKey(const Key('confirmDeleteAccountButton')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);
    expect(prefs.getBool('keep'), isNull);
  });

  testWidgets('a wrong password keeps the dialog open with an error', (
    tester,
  ) async {
    whenCalling(Invocation.method(#reauthenticateWithCredential, null))
        .on(user)
        .thenThrow(FirebaseAuthException(code: 'wrong-password'));
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('deleteAccountButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('deleteAccountPasswordInput')),
      'bad',
    );
    await tester.tap(find.byKey(const Key('confirmDeleteAccountButton')));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect password.'), findsOneWidget);
    expect(prefs.getBool('keep'), isTrue);
  });
}
