import 'package:cloud_firestore/cloud_firestore.dart';

/// A message fit to show a user for [error], instead of the raw exception text.
///
/// [ArgumentError] messages are written for users (e.g. a duplicate tag name),
/// so they are kept. Everything else maps from its Firestore code, or falls
/// back to a generic line.
String friendlyError(Object error) {
  if (error is ArgumentError) return error.message.toString();
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return "You don't have permission to do that. Try signing in again.";
      case 'unavailable':
        return "Can't reach the server. Check your connection and try again.";
      case 'not-found':
        return 'That item no longer exists.';
      case 'failed-precondition':
        return "That can't be done right now. Please try again.";
    }
  }
  return 'Something went wrong. Please try again.';
}
