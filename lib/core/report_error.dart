import 'package:flutter/foundation.dart';

/// Single place for uncaught errors to go. It only logs for now; a crash
/// reporting service would plug in here.
void reportError(Object error, StackTrace? stack, {String? source}) {
  debugPrint('Unhandled error${source != null ? ' ($source)' : ''}: $error');
  if (stack != null) debugPrintStack(stackTrace: stack, maxFrames: 20);
}
