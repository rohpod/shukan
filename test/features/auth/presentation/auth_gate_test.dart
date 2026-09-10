import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/presentation/auth_gate.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    fakeFirestore = FakeFirebaseFirestore();
  });

  Widget createWidgetUnderTest() {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
      ],
      child: const MaterialApp(home: AuthGate()),
    );
  }

  group('AuthGate & Auth Flow Widget Tests', () {
    testWidgets('displays AuthScreen with sign-in form when unauthenticated', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('shukan'), findsOneWidget);
      expect(find.text('Sign in to your account'), findsOneWidget);
      expect(find.byKey(const Key('emailField')), findsOneWidget);
      expect(find.byKey(const Key('passwordField')), findsOneWidget);
      expect(find.byKey(const Key('submitButton')), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('shows validation errors when submitting empty form', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submitButton')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your email.'), findsOneWidget);
      expect(find.text('Please enter your password.'), findsOneWidget);
    });

    testWidgets('toggles between Sign In and Sign Up modes', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Toggle to Sign Up
      await tester.tap(find.byKey(const Key('toggleAuthModeButton')));
      await tester.pumpAndSettle();

      expect(find.text('Create a new account'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);

      // Toggle back to Sign In
      await tester.tap(find.byKey(const Key('toggleAuthModeButton')));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to your account'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets(
      'sign-up navigates to HomeScreen and logout returns to AuthScreen',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // Switch to sign up
        await tester.tap(find.byKey(const Key('toggleAuthModeButton')));
        await tester.pumpAndSettle();

        // Enter credentials
        await tester.enterText(
          find.byKey(const Key('emailField')),
          'newuser@example.com',
        );
        await tester.enterText(
          find.byKey(const Key('passwordField')),
          'password123',
        );

        // Submit
        await tester.tap(find.byKey(const Key('submitButton')));
        await tester.pumpAndSettle();

        // Should be on HomeScreen
        expect(find.text('Welcome to shukan'), findsOneWidget);
        expect(find.text('newuser@example.com'), findsOneWidget);

        // Verify Firestore data in fakeFirestore
        final userSnapshot = await fakeFirestore
            .collection('users')
            .doc(mockAuth.currentUser!.uid)
            .get();
        expect(userSnapshot.exists, isTrue);
        expect(userSnapshot.data()!['email'], equals('newuser@example.com'));

        final listId = userSnapshot.data()!['defaultListId'];
        final listSnapshot = await fakeFirestore
            .collection('lists')
            .doc(listId)
            .get();
        expect(listSnapshot.exists, isTrue);
        expect(listSnapshot.data()!['name'], equals('Inbox'));

        // Tap logout
        await tester.tap(find.byKey(const Key('logoutButton')));
        await tester.pumpAndSettle();

        // Should be back on AuthScreen
        expect(find.text('Sign in to your account'), findsOneWidget);
        expect(mockAuth.currentUser, isNull);
      },
    );
  });
}
