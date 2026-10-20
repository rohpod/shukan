import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/web_reminder_scheduler.dart';
import '../../lists/data/list.dart';
import '../../lists/presentation/list_detail_screen.dart';
import '../../tasks/domain/quick_add_parser.dart';
import '../../tasks/providers/smart_view_providers.dart';
import '../../tasks/providers/task_providers.dart';
import '../providers/search_providers.dart';

mixin SearchLogicMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  late final TextEditingController searchController;
  Timer? _debounceTimer;
  bool isCreatingTask = false;

  bool hasParsedAdd = false;
  String? rawAddText;
  String? parsedTitle;
  DateTime? parsedAddDueDate;
  String? parsedAddDueTime;

  void initSearchLogic({String? initialQuery}) {
    searchController = TextEditingController(
      text: initialQuery ?? ref.read(searchQueryProvider),
    );
  }

  void disposeSearchLogic() {
    _debounceTimer?.cancel();
    searchController.dispose();
  }

  void resetParseAddState() {
    hasParsedAdd = false;
    rawAddText = null;
    parsedTitle = null;
    parsedAddDueDate = null;
    parsedAddDueTime = null;
  }

  void dismissAddChip() {
    setState(() {
      resetParseAddState();
    });
  }

  void onSearchQueryChanged(String value) {
    if (hasParsedAdd) {
      resetParseAddState();
    }
    setState(() {});
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        ref.read(searchQueryProvider.notifier).setQuery(value.trim());
      }
    });
  }

  void clearSearchQuery() {
    searchController.clear();
    resetParseAddState();
    _debounceTimer?.cancel();
    ref.read(searchQueryProvider.notifier).setQuery('');
    setState(() {});
  }

  Future<void> handleAddTaskAction({
    required String uid,
    required ListModel list,
    required String trimmedQuery,
    VoidCallback? onCollapse,
  }) async {
    if (isCreatingTask) return;

    if (!hasParsedAdd) {
      final now = ref.read(currentDateProvider);
      final parseResult = parseQuickAdd(trimmedQuery, now: now);

      if (parseResult.dueDate != null || parseResult.dueTime != null) {
        setState(() {
          hasParsedAdd = true;
          rawAddText = trimmedQuery;
          parsedTitle = parseResult.strippedTitle;
          parsedAddDueDate = parseResult.dueDate;
          parsedAddDueTime = parseResult.dueTime;
        });
        return;
      } else {
        // No date phrase recognized: create task immediately in single step
        await createTaskAndNotify(
          uid: uid,
          list: list,
          title: trimmedQuery,
          dueDate: null,
          dueTime: null,
          onCollapse: onCollapse,
        );
        return;
      }
    }

    // Phase 2: Confirm and create task with parsed values
    final titleToCreate = (parsedTitle != null && parsedTitle!.isNotEmpty)
        ? parsedTitle!
        : (rawAddText ?? trimmedQuery);

    if (titleToCreate.isEmpty) return;

    await createTaskAndNotify(
      uid: uid,
      list: list,
      title: titleToCreate,
      dueDate: parsedAddDueDate,
      dueTime: parsedAddDueTime,
      onCollapse: onCollapse,
    );
  }

  Future<void> createTaskAndNotify({
    required String uid,
    required ListModel list,
    required String title,
    DateTime? dueDate,
    String? dueTime,
    VoidCallback? onCollapse,
  }) async {
    if (isCreatingTask) return;
    setState(() {
      isCreatingTask = true;
    });

    _debounceTimer?.cancel();
    ref.read(searchQueryProvider.notifier).setQuery(title);

    if (dueDate != null) {
      requestWebPermissionOnSave(ref: ref, context: context, mounted: mounted);
    }

    try {
      await ref
          .read(taskRepositoryProvider)
          .createTask(
            uid: uid,
            listId: list.listId,
            title: title,
            dueDate: dueDate,
            dueTime: dueTime,
          );

      if (mounted) {
        setState(() {
          resetParseAddState();
        });
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Added to ${list.name}'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                messenger.hideCurrentSnackBar();
                onCollapse?.call();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ListDetailScreen(list: list),
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to add task: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          isCreatingTask = false;
        });
      } else {
        isCreatingTask = false;
      }
    }
  }
}
