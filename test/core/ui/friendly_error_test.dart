import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/ui/friendly_error.dart';

void main() {
  FirebaseException firebase(String code) =>
      FirebaseException(plugin: 'cloud_firestore', code: code, message: 'raw');

  test('maps known Firestore codes to plain messages', () {
    for (final code in [
      'permission-denied',
      'unavailable',
      'not-found',
      'failed-precondition',
    ]) {
      final message = friendlyError(firebase(code));
      expect(message, isNot(contains('raw')), reason: code);
      expect(message, isNot(contains(code)), reason: code);
    }
    expect(
      friendlyError(firebase('unavailable')),
      isNot(friendlyError(firebase('not-found'))),
    );
  });

  test('keeps ArgumentError messages', () {
    expect(
      friendlyError(ArgumentError('A tag named "home" already exists.')),
      'A tag named "home" already exists.',
    );
  });

  test('hides everything else behind a generic message', () {
    const generic = 'Something went wrong. Please try again.';
    expect(friendlyError(Exception('socket closed')), generic);
    expect(friendlyError(firebase('weird-code')), generic);
    expect(friendlyError(StateError('x')), generic);
  });
}
