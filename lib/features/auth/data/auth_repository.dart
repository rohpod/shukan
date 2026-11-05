import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// Set while sign-up runs its own bootstrap, which
  /// [ensureUserBootstrapped] must not race.
  Completer<void>? _signUpInProgress;

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
    final signUp = _signUpInProgress = Completer<void>();
    try {
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
    } finally {
      _signUpInProgress = null;
      signUp.complete();
    }
  }

  /// Emails a password reset link to [email].
  ///
  /// Succeeds for unknown addresses too, so the response can't be used to find
  /// out who has an account.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found') rethrow;
    }
  }

  /// Gives [user] a profile and default list if either is missing, as happens
  /// when bootstrap fails after the account is created.
  ///
  /// Never changes a `defaultListId` that is already set.
  Future<void> ensureUserBootstrapped(User user) async {
    await _signUpInProgress?.future;

    final userDocRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userDocRef.get();
    final defaultListId = userDoc.data()?['defaultListId'] as String?;
    if (defaultListId != null && defaultListId.isNotEmpty) return;

    if (!userDoc.exists) {
      final existing = await _findDefaultList(user.uid);
      if (existing == null) {
        await bootstrapUser(user);
      } else {
        await userDocRef.set({
          'uid': user.uid,
          'email': user.email ?? '',
          'displayName': '',
          'createdAt': FieldValue.serverTimestamp(),
          'defaultListId': existing,
        });
      }
      return;
    }

    final existing = await _findDefaultList(user.uid);
    if (existing != null) {
      await userDocRef.update({'defaultListId': existing});
      return;
    }

    final listDocRef = _firestore.collection('lists').doc();
    final batch = _firestore.batch();
    batch.update(userDocRef, {'defaultListId': listDocRef.id});
    batch.set(listDocRef, _defaultListData(listDocRef.id, user.uid));
    await batch.commit();
  }

  Future<String?> _findDefaultList(String uid) async {
    final lists = await _firestore
        .collection('lists')
        .where('uid', isEqualTo: uid)
        .where('isDefault', isEqualTo: true)
        .limit(1)
        .get();
    return lists.docs.isEmpty ? null : lists.docs.first.id;
  }

  Map<String, dynamic> _defaultListData(String listId, String uid) => {
    'listId': listId,
    'uid': uid,
    'name': 'Inbox',
    'createdAt': FieldValue.serverTimestamp(),
    'isDefault': true,
  };

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

    batch.set(listDocRef, _defaultListData(listDocRef.id, user.uid));

    await batch.commit();
  }

  /// Permanently deletes the signed-in user's data and account.
  ///
  /// Re-authenticates first, so a wrong password deletes nothing and Firebase
  /// accepts the final `user.delete()`. This waits for the server throughout,
  /// because a half-finished deletion must not look finished.
  Future<void> deleteAccount({
    required String password,
    int batchChunkSize = 450,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw StateError('No signed-in user with an email address');
    }

    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> ownedBy(
      String collection,
    ) async {
      final snapshot = await _firestore
          .collection(collection)
          .where('uid', isEqualTo: user.uid)
          .get();
      return snapshot.docs;
    }

    final lists = await ownedBy('lists');
    final refs = [
      ...(await ownedBy('tasks')).map((doc) => doc.reference),
      ...(await ownedBy('tags')).map((doc) => doc.reference),
      ...lists
          .where((doc) => doc.data()['isDefault'] != true)
          .map((doc) => doc.reference),
    ];

    for (var i = 0; i < refs.length; i += batchChunkSize) {
      final end = (i + batchChunkSize < refs.length)
          ? i + batchChunkSize
          : refs.length;
      final batch = _firestore.batch();
      for (final ref in refs.sublist(i, end)) {
        batch.delete(ref);
      }
      await batch.commit();
    }

    // Rules only allow deleting a default list together with the user doc.
    final finalBatch = _firestore.batch();
    for (final doc in lists.where((d) => d.data()['isDefault'] == true)) {
      finalBatch.delete(doc.reference);
    }
    finalBatch.delete(_firestore.collection('users').doc(user.uid));
    await finalBatch.commit();

    await user.delete();
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
