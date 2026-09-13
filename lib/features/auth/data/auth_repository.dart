import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthRepository(this._auth, this._firestore);

  /// Stream of user authentication state changes.
  /// Emits the current user immediately upon listening, and subsequently on any change.
  Stream<User?> authStateChanges() {
    return Stream<User?>.multi((controller) {
      controller.add(_auth.currentUser);
      final subscription = _auth.authStateChanges().listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    }).distinct();
  }

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Failed to obtain user after sign-up.',
      );
    }

    await bootstrapUser(user);

    return credential;
  }

  @visibleForTesting
  Future<void> bootstrapUser(User user) async {
    final listDocRef = _firestore.collection('lists').doc();
    final userDocRef = _firestore.collection('users').doc(user.uid);

    final batch = _firestore.batch();

    batch.set(userDocRef, {
      'uid': user.uid,
      'email': user.email ?? '',
      'displayName': '',
      'createdAt': FieldValue.serverTimestamp(),
      'defaultListId': listDocRef.id,
    });

    batch.set(listDocRef, {
      'listId': listDocRef.id,
      'uid': user.uid,
      'name': 'Inbox',
      'createdAt': FieldValue.serverTimestamp(),
      'isDefault': true,
    });

    await batch.commit();
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
