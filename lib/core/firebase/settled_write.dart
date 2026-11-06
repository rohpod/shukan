import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/web_reminder_scheduler.dart';

/// How long a write waits for the server before the caller carries on.
const writeAckWait = Duration(milliseconds: 400);

/// Waits for [write], but no longer than [writeAckWait].
///
/// A Firestore write applies locally at once, but its Future only completes
/// when the server acknowledges it, which never happens offline. Waiting
/// briefly keeps quick failures, such as a rules rejection, on the normal error
/// path without hanging offline. A failure after that goes to [onLateFailure].
Future<void> settleWrite(
  Future<void> write, {
  void Function(Object error)? onLateFailure,
}) {
  final settled = Completer<void>();
  final timer = Timer(writeAckWait, () {
    if (!settled.isCompleted) settled.complete();
  });

  write.then(
    (_) {
      timer.cancel();
      if (!settled.isCompleted) settled.complete();
    },
    onError: (Object error, StackTrace stackTrace) {
      timer.cancel();
      if (settled.isCompleted) {
        debugPrint('Write failed after the caller moved on: $error');
        onLateFailure?.call(error);
      } else {
        settled.completeError(error, stackTrace);
      }
    },
  );

  return settled.future;
}

/// Tells the user a write failed after the screen that made it moved on.
final lateWriteFailureProvider = Provider<void Function(Object)>((ref) {
  return (_) {
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text("A recent change couldn't be saved. Please try again."),
      ),
    );
  };
});
