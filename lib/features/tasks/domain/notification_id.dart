/// Pure utility function to compute a deterministic 31-bit integer notification ID
/// from a Firestore String [taskId] using the 32-bit FNV-1a hash algorithm.
int taskNotificationId(String taskId) {
  var hash = 0x811c9dc5;
  for (final unit in taskId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}

/// Pure utility function to compute a deterministic 31-bit integer notification ID
/// for a task's early reminder from a Firestore String [taskId].
int taskEarlyReminderNotificationId(String taskId) {
  return taskNotificationId('early_$taskId');
}
