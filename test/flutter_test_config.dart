import 'dart:async';

import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Initialises the timezone database for every test file, so code that reads
/// `tz.local` doesn't hit a LateInitializationError. Tests that need another
/// location still set their own.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('UTC'));
  await testMain();
}
