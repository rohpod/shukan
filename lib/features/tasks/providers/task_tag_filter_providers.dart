import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../lists/data/list.dart';
import '../../lists/providers/list_providers.dart';
import '../../tags/providers/tag_providers.dart';
import '../data/task.dart';
import 'task_providers.dart';
import 'task_sort_providers.dart';

/// Model representing a group of tasks belonging to a list for a given tag.
class TagTaskListGroup {
  final String listId;
  final String listName;
  final List<Task> tasks;

  const TagTaskListGroup({
    required this.listId,
    required this.listName,
    required this.tasks,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagTaskListGroup &&
          runtimeType == other.runtimeType &&
          listId == other.listId &&
          listName == other.listName &&
          listEquals(tasks, other.tasks);

  @override
  int get hashCode =>
      listId.hashCode ^ listName.hashCode ^ Object.hashAll(tasks);

  @override
  String toString() =>
      'TagTaskListGroup(listId: $listId, listName: $listName, taskCount: ${tasks.length})';
}

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

/// Computes the unique tag set client-side for [listId] from tasks in that list,
/// sorted alphabetically by name with the count of active tasks per tag.
final tagBrowserEntriesForListProvider =
    Provider.family<AsyncValue<List<TagBrowserEntry>>, String>((ref, listId) {
      final tasksAsync = ref.watch(tasksForListProvider(listId));
      final tagsAsync = ref.watch(tagsForCurrentUserProvider);

      if (tasksAsync.isLoading || tagsAsync.isLoading) {
        return const AsyncLoading();
      }

      if (tasksAsync.hasError) {
        return AsyncError(
          tasksAsync.error!,
          tasksAsync.stackTrace ?? StackTrace.current,
        );
      }
      if (tagsAsync.hasError) {
        return AsyncError(
          tagsAsync.error!,
          tagsAsync.stackTrace ?? StackTrace.current,
        );
      }

      final tasks = tasksAsync.value ?? [];
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

      entries.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      return AsyncData(entries);
    });

/// Family stream provider returning incomplete, active tasks for [tagId] across all lists.
final activeTasksForTagProvider = StreamProvider.family<List<Task>, String>((
  ref,
  tagId,
) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Stream.value(const <Task>[]);
  }

  final repository = ref.watch(taskRepositoryProvider);
  return repository.streamTasksForTagIds(
    uid: uid,
    tagIds: [tagId],
    onlyIncomplete: true,
  );
});

/// Family provider returning active tasks carrying [tagId] grouped by list,
/// sorted alphabetically by listName with tasks ordered by createdAt ascending.
final tasksForTagGroupedByListProvider =
    Provider.family<AsyncValue<List<TagTaskListGroup>>, String>((ref, tagId) {
      final tasksAsync = ref.watch(activeTasksForTagProvider(tagId));
      final listsAsync = ref.watch(listsForUserProvider);

      if (tasksAsync.isLoading || listsAsync.isLoading) {
        return const AsyncLoading();
      }

      if (tasksAsync.hasError) {
        return AsyncError(
          tasksAsync.error!,
          tasksAsync.stackTrace ?? StackTrace.current,
        );
      }
      if (listsAsync.hasError) {
        return AsyncError(
          listsAsync.error!,
          listsAsync.stackTrace ?? StackTrace.current,
        );
      }

      final tasks = tasksAsync.value ?? const <Task>[];
      final lists = listsAsync.value ?? const <ListModel>[];
      final listNames = {for (final l in lists) l.listId: l.name};

      final groupedMap = <String, List<Task>>{};
      for (final task in tasks) {
        // Strict active check: completed tasks are NEVER shown
        if (task.isCompleted) continue;
        groupedMap.putIfAbsent(task.listId, () => <Task>[]).add(task);
      }

      final groups = <TagTaskListGroup>[];
      for (final entry in groupedMap.entries) {
        final listId = entry.key;
        final groupTasks = List<Task>.from(entry.value);
        groupTasks.sort((a, b) {
          if (a.createdAt == null && b.createdAt == null) return 0;
          if (a.createdAt == null) return 1;
          if (b.createdAt == null) return -1;
          return a.createdAt!.compareTo(b.createdAt!);
        });

        final listName = listNames[listId] ?? 'Inbox';
        groups.add(
          TagTaskListGroup(
            listId: listId,
            listName: listName,
            tasks: groupTasks,
          ),
        );
      }

      groups.sort(
        (a, b) => a.listName.toLowerCase().compareTo(b.listName.toLowerCase()),
      );

      return AsyncData(groups);
    });

/// Manages collapsed state of a tag chips section, keyed by [contextKey] (e.g. 'home' or listId).
class TagChipsSectionCollapsedNotifier extends Notifier<bool> {
  TagChipsSectionCollapsedNotifier(this.contextKey);

  final String contextKey;

  static String prefKey(String contextKey) =>
      'tag_chips_section_collapsed_$contextKey';

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs?.getBool(prefKey(contextKey)) ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.setBool(prefKey(contextKey), state);
  }

  Future<void> setCollapsed(bool collapsed) async {
    state = collapsed;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.setBool(prefKey(contextKey), state);
  }
}

/// Provider exposing whether a tag chips section is collapsed for a given [contextKey].
final tagChipsSectionCollapsedProvider =
    NotifierProvider.family<TagChipsSectionCollapsedNotifier, bool, String>(
      (arg) => TagChipsSectionCollapsedNotifier(arg),
    );
