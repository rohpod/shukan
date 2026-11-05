import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/core/notifications/notification_service.dart';
import 'package:shukan/core/notifications/web_reminder_scheduler.dart';
import 'package:shukan/features/tasks/data/task.dart';
import 'package:shukan/features/tasks/presentation/reminder_navigation_handler.dart';
import 'package:shukan/features/tasks/presentation/smart_view_detail_screen.dart';
import 'package:shukan/features/tasks/presentation/task_list_screen.dart';
import 'package:shukan/features/tasks/providers/task_providers.dart';

class MockNotificationService extends Mock implements NotificationService {}

class FakeScheduler extends Fake implements WebReminderScheduler {
  final controller = StreamController<int>.broadcast();

  @override
  Stream<int> get missedReminders => controller.stream;
}

void main() {
  late MockNotificationService notifications;
  late StreamController<String> taps;
  late FakeScheduler scheduler;

  const task = Task(taskId: 't1', uid: 'u1', listId: 'l1', title: 'Pay rent');

  setUp(() {
    notifications = MockNotificationService();
    taps = StreamController<String>.broadcast();
    scheduler = FakeScheduler();
    when(() => notifications.taskTaps).thenAnswer((_) => taps.stream);
    when(() => notifications.launchTaskId()).thenAnswer((_) async => null);
  });

  tearDown(() {
    taps.close();
    scheduler.controller.close();
  });

  Future<void> pumpHandler(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(
            MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'u1', email: 'a@b.c'),
            ),
          ),
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          notificationServiceProvider.overrideWithValue(notifications),
          webReminderSchedulerProvider.overrideWithValue(scheduler),
          allTasksForCurrentUserProvider.overrideWith(
            (ref) => Stream.value(const [task]),
          ),
        ],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          builder: (context, child) =>
              ReminderNavigationHandler(child: child ?? const SizedBox()),
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('clicking a notification opens its task', (tester) async {
    await pumpHandler(tester);

    taps.add('t1');
    await tester.pumpAndSettle();

    expect(find.byType(TaskDialog), findsOneWidget);
    expect(find.text('Pay rent'), findsOneWidget);
  });

  testWidgets('a notification that opened the app opens its task', (
    tester,
  ) async {
    when(() => notifications.launchTaskId()).thenAnswer((_) async => 't1');

    await pumpHandler(tester);
    await tester.pumpAndSettle();

    expect(find.byType(TaskDialog), findsOneWidget);
  });

  testWidgets('a deleted task shows a message instead of a dialog', (
    tester,
  ) async {
    await pumpHandler(tester);

    taps.add('gone');
    await tester.pumpAndSettle();

    expect(find.byType(TaskDialog), findsNothing);
    expect(find.text('That task is no longer available.'), findsOneWidget);
  });

  testWidgets('the test notification opens nothing', (tester) async {
    await pumpHandler(tester);

    taps.add(testNotificationTaskId);
    await tester.pumpAndSettle();

    expect(find.byType(TaskDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('missed reminders show a summary linking to Today', (
    tester,
  ) async {
    await pumpHandler(tester);

    scheduler.controller.add(3);
    await tester.pumpAndSettle();

    expect(find.text('3 reminders while you were away'), findsOneWidget);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.byType(SmartViewDetailScreen), findsOneWidget);
  });
}
