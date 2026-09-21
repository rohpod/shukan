import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../tags/providers/tag_providers.dart';
import '../data/task.dart';
import '../domain/task_priority_filter.dart';
import 'task_providers.dart';
import 'task_sort_providers.dart';

/// Model representing a distinct tag with active task count for the tag browser.
class TagBrowserEntry {
  final String tagId;
  final String name;
  final int taskCount;

  const TagBrowserEntry({
    required this.tagId,
    required this.name,
    required this.taskCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagBrowserEntry &&
          runtimeType == other.runtimeType &&
          tagId == other.tagId &&
          name == other.name &&
          taskCount == other.taskCount;

  @override
  int get hashCode => tagId.hashCode ^ name.hashCode ^ taskCount.hashCode;

  @override
  String toString() =>
      'TagBrowserEntry(tagId: $tagId, name: $name, count: $taskCount)';
}

/// Per-view tag filter notifier, keyed by `viewKey` (e.g. `listId`, smart view name, or `tag_<tagId>`).
///
/// Persists the selected tag IDs to SharedPreferences under `task_tag_filter_<viewKey>`.
/// Enforces Firestore's maximum limit of 30 items for `arrayContainsAny`.
class TaskTagFilterNotifier extends Notifier<Set<String>> {
  TaskTagFilterNotifier(this.viewKey, {this.initialTagId});

  final String viewKey;
  final String? initialTagId;

  static const int maxTagLimit = 30;

  @override
  Set<String> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final savedList = prefs?.getStringList('task_tag_filter_$viewKey');
    if (savedList != null) {
      return savedList.toSet();
    }
    if (initialTagId != null) {
      return {initialTagId!};
    }
    if (viewKey.startsWith('tag_')) {
      final tagIdPart = viewKey.substring(4);
      if (tagIdPart.isNotEmpty) {
        return {tagIdPart};
      }
    }
    return const <String>{};
  }

  /// Toggles selection of [tagId]. Returns `false` if the maximum 30-tag limit
  /// was reached and the tag could not be added, `true` otherwise.
  Future<bool> toggleTag(String tagId) async {
    final current = Set<String>.from(state);
    if (current.contains(tagId)) {
      current.remove(tagId);
      state = current;
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs?.setStringList('task_tag_filter_$viewKey', current.toList());
      return true;
    } else {
      if (current.length >= maxTagLimit) {
        return false;
      }
      current.add(tagId);
      state = current;
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs?.setStringList('task_tag_filter_$viewKey', current.toList());
      return true;
    }
  }

  /// Clears all selected tags.
  Future<void> clearAll() async {
    state = const <String>{};
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.remove('task_tag_filter_$viewKey');
  }

  /// Sets the selected tags directly, capped at [maxTagLimit].
  Future<void> setSelectedTags(Set<String> tags) async {
    final capped = tags.take(maxTagLimit).toSet();
    state = capped;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.setStringList('task_tag_filter_$viewKey', capped.toList());
  }
}

/// Provider exposing the independent tag filter selection for each view.
final taskTagFilterProvider =
    NotifierProvider.family<TaskTagFilterNotifier, Set<String>, String>(
      (arg) => TaskTagFilterNotifier(arg),
    );

/// Streams all active (non-soft-deleted) tasks belonging to the current user.
final allActiveTasksProvider = StreamProvider<List<Task>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Stream.value(const <Task>[]);
  }
  final repository = ref.watch(taskRepositoryProvider);
  return repository.streamAllActiveTasks(uid);
});

/// Computes the unique tag set client-side from active tasks, sorted alphabetically by name
/// with the count of active tasks per tag.
final tagBrowserEntriesProvider = Provider<AsyncValue<List<TagBrowserEntry>>>((
  ref,
) {
  final activeTasksAsync = ref.watch(allActiveTasksProvider);
  final tagsAsync = ref.watch(tagsForCurrentUserProvider);

  if (activeTasksAsync.isLoading || tagsAsync.isLoading) {
    return const AsyncLoading();
  }

  if (activeTasksAsync.hasError) {
    return AsyncError(
      activeTasksAsync.error!,
      activeTasksAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (tagsAsync.hasError) {
    return AsyncError(
      tagsAsync.error!,
      tagsAsync.stackTrace ?? StackTrace.current,
    );
  }

  final tasks = activeTasksAsync.value ?? [];
  final tags = tagsAsync.value ?? [];

  final tagMap = <String, String>{};
  for (final tag in tags) {
    tagMap[tag.tagId] = tag.name;
  }

  final counts = <String, int>{};
  for (final task in tasks) {
    for (final tagId in task.tagIds) {
      counts[tagId] = (counts[tagId] ?? 0) + 1;
    }
  }

  final entries = <TagBrowserEntry>[];
  for (final entry in counts.entries) {
    final tagId = entry.key;
    final count = entry.value;
    if (count > 0) {
      final tagName = tagMap[tagId] ?? tagId;
      entries.add(
        TagBrowserEntry(tagId: tagId, name: tagName, taskCount: count),
      );
    }
  }

  entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return AsyncData(entries);
});

/// Family provider that streams tasks for TagDetailScreen matching the active tag filter.
final tasksForTagDetailProvider = StreamProvider.family<List<Task>, String>((
  ref,
  viewKey,
) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Stream.value(const <Task>[]);
  }

  final selectedTags = ref.watch(taskTagFilterProvider(viewKey));
  final showCompleted = ref.watch(showCompletedTasksProvider(viewKey));
  final priorityFilter = ref.watch(taskPriorityFilterProvider(viewKey));
  final repository = ref.watch(taskRepositoryProvider);

  if (selectedTags.isEmpty) {
    return Stream.value(const <Task>[]);
  }

  final baseStream = repository.streamTasksForTagIds(
    uid: uid,
    tagIds: selectedTags.toList(),
    onlyIncomplete: !showCompleted,
    priority: priorityFilter.firestoreValue,
  );

  return baseStream.map((tasks) {
    return tasks.where((t) {
      if (!showCompleted && t.isCompleted) return false;
      if (priorityFilter != TaskPriorityFilter.all &&
          t.priority != priorityFilter.firestoreValue) {
        return false;
      }
      return true;
    }).toList();
  });
});
