const List<String> kTaskPriorities = ['none', 'low', 'medium', 'high'];

/// Returns a priority marker string based on the task priority.
/// - 'high' -> '❗❗❗'
/// - 'medium' -> '❕❕'
/// - 'low' -> '!'
/// - 'none' / other -> null
String? taskPriorityMarker(String priority) {
  switch (priority) {
    case 'high':
      return '❗❗❗';
    case 'medium':
      return '❕❕';
    case 'low':
      return '!';
    case 'none':
    default:
      return null;
  }
}

const List<String> kTaskRepeatRules = [
  'none',
  'daily',
  'weekly',
  'monthly',
  'custom',
];
