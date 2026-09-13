import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/task.dart';
import '../providers/task_providers.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  final String? listId;

  const TaskListScreen({super.key, this.listId});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  final _urlController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _createTask(String uid, String listId) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);
    try {
      await ref.read(taskRepositoryProvider).createTask(
            uid: uid,
            listId: listId,
            title: _titleController.text,
            notes: _notesController.text,
            url: _urlController.text,
          );
      _titleController.clear();
      _notesController.clear();
      _urlController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add task: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _showEditDialog(BuildContext context, Task task) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _EditTaskDialog(task: task),
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
      error: (e, _) => Center(
        child: Text('Error loading default list: $e'),
      ),
    );
  }

  Widget _buildContent(BuildContext context, String uid, String listId) {
    final tasksAsync = ref.watch(tasksForListProvider(listId));

    return Column(
      children: [
        // Add task card
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    key: const Key('taskTitleInput'),
                    controller: _titleController,
                    decoration: const InputDecoration(
                      hintText: 'What needs to be done?',
                      isDense: true,
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter a title.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('taskNotesInput'),
                          controller: _notesController,
                          decoration: const InputDecoration(
                            hintText: 'Notes (optional)',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: const Key('taskUrlInput'),
                          controller: _urlController,
                          decoration: const InputDecoration(
                            hintText: 'URL (optional)',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        key: const Key('addTaskButton'),
                        onPressed: _isCreating
                            ? null
                            : () => _createTask(uid, listId),
                        child: _isCreating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Task list
        Expanded(
          child: tasksAsync.when(
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
                          onPressed: () => _showEditDialog(context, task),
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
            error: (e, _) => Center(
              child: Text('Error loading tasks: $e'),
            ),
          ),
        ),
      ],
    );
  }
}

class _EditTaskDialog extends ConsumerStatefulWidget {
  final Task task;

  const _EditTaskDialog({required this.task});

  @override
  ConsumerState<_EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends ConsumerState<_EditTaskDialog> {
  final _editFormKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _urlController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _notesController = TextEditingController(text: widget.task.notes);
    _urlController = TextEditingController(text: widget.task.url);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_editFormKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(taskRepositoryProvider).updateTask(
            widget.task.taskId,
            title: _titleController.text,
            notes: _notesController.text,
            url: _urlController.text,
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Task'),
      content: Form(
        key: _editFormKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('editTaskTitleInput'),
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Title is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('editTaskNotesInput'),
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('editTaskUrlInput'),
                controller: _urlController,
                decoration: const InputDecoration(labelText: 'URL (optional)'),
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
              : const Text('Save'),
        ),
      ],
    );
  }
}
