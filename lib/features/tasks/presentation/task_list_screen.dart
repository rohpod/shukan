import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../tags/providers/tag_providers.dart';
import '../data/task.dart';
import '../domain/task_constants.dart';
import '../providers/task_providers.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  final String? listId;

  const TaskListScreen({super.key, this.listId});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  Future<void> _showTaskDialog(
    BuildContext context,
    String uid,
    String listId, {
    Task? task,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          TaskDialog(uid: uid, listId: listId, task: task),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) {
      return const Center(child: Text('User not signed in.'));
    }

    final targetListId = widget.listId;
    if (targetListId != null) {
      return _buildContent(context, uid, targetListId);
    }

    final defaultListIdAsync = ref.watch(defaultListIdProvider);
    return defaultListIdAsync.when(
      data: (listId) {
        if (listId == null) {
          return const Center(child: Text('No default list found.'));
        }
        return _buildContent(context, uid, listId);
      },
      loading: () => const Center(
        key: Key('defaultListLoadingIndicator'),
        child: CircularProgressIndicator(),
      ),
      error: (e, _) => Center(child: Text('Error loading default list: $e')),
    );
  }

  Widget _buildContent(BuildContext context, String uid, String listId) {
    final tasksAsync = ref.watch(tasksForListProvider(listId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        key: const Key('addTaskButton'),
        tooltip: 'New Task',
        onPressed: () => _showTaskDialog(context, uid, listId),
        child: const Icon(Icons.add),
      ),
      body: tasksAsync.when(
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(
              child: Text(
                'No tasks yet',
                key: Key('noTasksText'),
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.separated(
            key: const Key('tasksListView'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: tasks.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return ListTile(
                key: Key('taskItem_${task.taskId}'),
                leading: Checkbox(
                  key: Key('taskCompleteCheckbox_${task.taskId}'),
                  value: task.isCompleted,
                  onChanged: (val) async {
                    await ref
                        .read(taskRepositoryProvider)
                        .toggleTaskCompleted(
                          task.taskId,
                          isCompleted: val ?? false,
                        );
                  },
                ),
                title: Text(
                  task.title,
                  key: Key('taskTitle_${task.taskId}'),
                  style: TextStyle(
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    color: task.isCompleted ? Colors.grey : null,
                  ),
                ),
                subtitle: (task.notes.isNotEmpty || task.url.isNotEmpty)
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (task.notes.isNotEmpty)
                            Text(
                              task.notes,
                              key: Key('taskNotes_${task.taskId}'),
                              style: TextStyle(
                                color: task.isCompleted
                                    ? Colors.grey
                                    : Colors.grey[700],
                              ),
                            ),
                          if (task.url.isNotEmpty)
                            Text(
                              task.url,
                              key: Key('taskUrl_${task.taskId}'),
                              style: const TextStyle(
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                        ],
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: Key('editTaskButton_${task.taskId}'),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Edit',
                      onPressed: () =>
                          _showTaskDialog(context, uid, listId, task: task),
                    ),
                    IconButton(
                      key: Key('deleteTaskButton_${task.taskId}'),
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.redAccent,
                      ),
                      tooltip: 'Delete',
                      onPressed: () async {
                        await ref
                            .read(taskRepositoryProvider)
                            .softDeleteTask(task.taskId);
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(
          key: Key('tasksLoadingIndicator'),
          child: CircularProgressIndicator(),
        ),
        error: (e, _) => Center(child: Text('Error loading tasks: $e')),
      ),
    );
  }
}

class TaskDialog extends ConsumerStatefulWidget {
  final String uid;
  final String listId;
  final Task? task;

  const TaskDialog({
    super.key,
    required this.uid,
    required this.listId,
    this.task,
  });

  @override
  ConsumerState<TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends ConsumerState<TaskDialog> {
  bool get isEditing => widget.task != null;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _urlController;
  late final TextEditingController _tagInputController;

  late String _priority;
  DateTime? _dueDate;
  String? _dueTime;
  late int _earlyReminderMinutes;
  late String _repeatRule;
  late List<String> _tagIds;

  bool _isSaving = false;

  static const List<int> _defaultReminderOptions = [0, 5, 10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _notesController = TextEditingController(text: widget.task?.notes ?? '');
    _urlController = TextEditingController(text: widget.task?.url ?? '');
    _tagInputController = TextEditingController();

    final p = widget.task?.priority;
    _priority = (p != null && p.isNotEmpty) ? p : 'none';
    if (!kTaskPriorities.contains(_priority)) {
      _priority = 'none';
    }

    _dueDate = widget.task?.dueDate;
    _dueTime = widget.task?.dueTime;
    _earlyReminderMinutes = widget.task?.earlyReminderMinutes ?? 0;

    final r = widget.task?.repeatRule;
    _repeatRule = (r != null && r.isNotEmpty) ? r : 'none';
    if (!kTaskRepeatRules.contains(_repeatRule)) {
      _repeatRule = 'none';
    }

    _tagIds = widget.task != null
        ? List<String>.from(widget.task!.tagIds)
        : <String>[];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _urlController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  Future<void> _addTag(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    try {
      final tagId = await ref
          .read(tagRepositoryProvider)
          .createTag(uid: widget.uid, name: trimmed);
      if (!_tagIds.contains(tagId)) {
        setState(() {
          _tagIds.add(tagId);
        });
      }
      _tagInputController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to add tag: $e')));
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      if (isEditing) {
        await ref
            .read(taskRepositoryProvider)
            .updateTask(
              widget.task!.taskId,
              title: _titleController.text,
              notes: _notesController.text,
              url: _urlController.text,
              priority: _priority,
              tagIds: _tagIds,
              dueDate: _dueDate,
              dueTime: _dueTime,
              earlyReminderMinutes: _earlyReminderMinutes,
              repeatRule: _repeatRule,
              clearDueDate: _dueDate == null,
              clearDueTime: _dueTime == null,
            );
      } else {
        final createdTask = await ref
            .read(taskRepositoryProvider)
            .createTask(
              uid: widget.uid,
              listId: widget.listId,
              title: _titleController.text,
              notes: _notesController.text,
              url: _urlController.text,
            );
        if (_priority != 'none' ||
            _tagIds.isNotEmpty ||
            _dueDate != null ||
            _dueTime != null ||
            _earlyReminderMinutes != 0 ||
            _repeatRule != 'none') {
          await ref
              .read(taskRepositoryProvider)
              .updateTask(
                createdTask.taskId,
                priority: _priority,
                tagIds: _tagIds,
                dueDate: _dueDate,
                dueTime: _dueTime,
                earlyReminderMinutes: _earlyReminderMinutes,
                repeatRule: _repeatRule,
              );
        }
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing
                  ? 'Failed to update task: $e'
                  : 'Failed to add task: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(tagsForUserProvider(widget.uid));
    final tagMap = <String, String>{};
    if (tagsAsync.hasValue) {
      for (final tag in tagsAsync.value!) {
        tagMap[tag.tagId] = tag.name;
      }
    }

    final reminderOptions = {
      ..._defaultReminderOptions,
      _earlyReminderMinutes,
    }.toList()..sort();

    return AlertDialog(
      title: Text(isEditing ? 'Edit Task' : 'New Task'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: Key(isEditing ? 'editTaskTitleInput' : 'taskTitleInput'),
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return isEditing
                        ? 'Title is required.'
                        : 'Please enter a title.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: Key(isEditing ? 'editTaskNotesInput' : 'taskNotesInput'),
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: Key(isEditing ? 'editTaskUrlInput' : 'taskUrlInput'),
                controller: _urlController,
                decoration: const InputDecoration(labelText: 'URL (optional)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('editTaskPriorityInput'),
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: kTaskPriorities.map((p) {
                  return DropdownMenuItem<String>(
                    value: p,
                    child: Text(p[0].toUpperCase() + p.substring(1)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _priority = val);
                  }
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                key: const Key('editTaskDueDateInput'),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dueDate ?? now,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() {
                      _dueDate = picked;
                    });
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Due Date',
                    suffixIcon: _dueDate != null
                        ? IconButton(
                            key: const Key('clearDueDateButton'),
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() {
                                _dueDate = null;
                                _dueTime = null;
                              });
                            },
                          )
                        : const Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(
                    _dueDate != null
                        ? '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}'
                        : 'None',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                key: const Key('editTaskDueTimeInput'),
                onTap: _dueDate == null
                    ? null
                    : () async {
                        TimeOfDay initial = const TimeOfDay(
                          hour: 12,
                          minute: 0,
                        );
                        if (_dueTime != null) {
                          final parts = _dueTime!.split(':');
                          if (parts.length == 2) {
                            final h = int.tryParse(parts[0]);
                            final m = int.tryParse(parts[1]);
                            if (h != null && m != null) {
                              initial = TimeOfDay(hour: h, minute: m);
                            }
                          }
                        }
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: initial,
                        );
                        if (picked != null) {
                          final formatted =
                              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                          setState(() {
                            _dueTime = formatted;
                          });
                        }
                      },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Due Time',
                    enabled: _dueDate != null,
                    suffixIcon: _dueTime != null
                        ? IconButton(
                            key: const Key('clearDueTimeButton'),
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() {
                                _dueTime = null;
                              });
                            },
                          )
                        : const Icon(Icons.access_time, size: 18),
                  ),
                  child: Text(
                    _dueDate == null
                        ? 'Set due date first'
                        : (_dueTime ?? 'None'),
                    style: TextStyle(
                      color: _dueDate == null ? Colors.grey : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: const Key('editTaskEarlyReminderInput'),
                initialValue: _earlyReminderMinutes,
                decoration: const InputDecoration(labelText: 'Early Reminder'),
                items: reminderOptions.map((minutes) {
                  String label;
                  if (minutes == 0) {
                    label = 'None (0 min)';
                  } else if (minutes < 60) {
                    label = '$minutes minutes before';
                  } else {
                    label =
                        '${minutes ~/ 60} hour${minutes >= 120 ? 's' : ''} before';
                  }
                  return DropdownMenuItem<int>(
                    value: minutes,
                    child: Text(label),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _earlyReminderMinutes = val);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('editTaskRepeatRuleInput'),
                initialValue: _repeatRule,
                decoration: const InputDecoration(labelText: 'Repeat Rule'),
                items: kTaskRepeatRules.map((rule) {
                  return DropdownMenuItem<String>(
                    value: rule,
                    child: Text(rule[0].toUpperCase() + rule.substring(1)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _repeatRule = val);
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text('Tags', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (_tagIds.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _tagIds.map((tagId) {
                    final tagName = tagMap[tagId] ?? tagId;
                    return Chip(
                      key: Key('taskTagChip_$tagId'),
                      label: Text(tagName),
                      onDeleted: () {
                        setState(() {
                          _tagIds.remove(tagId);
                        });
                      },
                    );
                  }).toList(),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('editTaskTagInput'),
                      controller: _tagInputController,
                      decoration: const InputDecoration(
                        labelText: 'Add tag',
                        hintText: 'Press enter or + to add',
                        isDense: true,
                      ),
                      onSubmitted: _addTag,
                    ),
                  ),
                  IconButton(
                    key: const Key('addTagIconButton'),
                    icon: const Icon(Icons.add),
                    tooltip: 'Add tag',
                    onPressed: () => _addTag(_tagInputController.text),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('saveTaskButton'),
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
