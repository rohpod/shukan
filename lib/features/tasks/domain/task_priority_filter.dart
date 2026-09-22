/// Filter options for task priority across list and smart views.
enum TaskPriorityFilter {
  all('All'),
  high('High'),
  medium('Medium'),
  low('Low'),
  none('None');

  final String label;
  const TaskPriorityFilter(this.label);

  /// Target priority string in Task/Firestore, or null for 'All' (no filter).
  String? get firestoreValue => this == TaskPriorityFilter.all ? null : name;
}
