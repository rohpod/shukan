import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/settled_write.dart';

void main() {
  test('a quick success completes with the write', () async {
    await settleWrite(Future<void>.value());
  });

  test('a quick failure reaches the caller', () async {
    Object? late;
    await expectLater(
      settleWrite(
        Future<void>.error(StateError('denied')),
        onLateFailure: (e) => late = e,
      ),
      throwsStateError,
    );
    expect(late, isNull);
  });

  test('a write that never completes stops blocking the caller', () {
    fakeAsync((async) {
      var done = false;
      settleWrite(Completer<void>().future).then((_) => done = true);

      async.elapse(writeAckWait - const Duration(milliseconds: 1));
      expect(done, isFalse);

      async.elapse(const Duration(milliseconds: 1));
      expect(done, isTrue);
    });
  });

  test('a failure after the wait goes to onLateFailure', () {
    fakeAsync((async) {
      final write = Completer<void>();
      Object? late;
      Object? callerError;
      settleWrite(
        write.future,
        onLateFailure: (e) => late = e,
      ).catchError((Object e) => callerError = e);

      async.elapse(writeAckWait);
      write.completeError(StateError('rejected'));
      async.flushMicrotasks();

      expect(late, isStateError);
      expect(callerError, isNull);
    });
  });
}
