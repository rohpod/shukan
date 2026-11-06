import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/web_reminder_scheduler.dart';
import '../../auth/providers/auth_providers.dart';
import 'task_providers.dart';
import 'task_sort_providers.dart';

const purgeInterval = Duration(hours: 24);

/// Permanently deletes expired Recently Deleted tasks, at most once per
/// [purgeInterval] per user. Watched from the home screen so the purge doesn't
/// depend on the user opening Recently Deleted.
///
/// Errors are logged, not thrown. Without SharedPreferences there is no way to
/// rate-limit, so it does nothing.
final dailyPurgeProvider = FutureProvider<void>((ref) async {
  final uid = ref.watch(currentUidProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  if (uid == null || prefs == null) return;

  final now = ref.read(reminderClockProvider)();
  final key = 'tasks_last_purge_$uid';
  final last = prefs.getInt(key);
  if (last != null &&
      now.difference(DateTime.fromMillisecondsSinceEpoch(last)) <
          purgeInterval) {
    return;
  }

  try {
    await ref.read(taskRepositoryProvider).purgeExpiredDeletedTasks(uid);
    await prefs.setInt(key, now.millisecondsSinceEpoch);
  } catch (e) {
    debugPrint('Daily purge failed: $e');
  }
});
