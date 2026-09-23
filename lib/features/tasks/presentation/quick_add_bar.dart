import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/task.dart';
import '../domain/quick_add_parser.dart';
import '../providers/smart_view_providers.dart';
import '../providers/task_providers.dart';

class QuickAddBar extends ConsumerStatefulWidget {
  final String uid;
  final String? listId;
  final String? hintText;
  final void Function(String currentText)? onExpand;
  final Key? expandButtonKey;
  final void Function(Task task)? onTaskCreated;

  const QuickAddBar({
    super.key,
    required this.uid,
    required this.listId,
    this.hintText,
    this.onExpand,
    this.expandButtonKey,
    this.onTaskCreated,
  });

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  String? _rawInput;
  String? _strippedTitle;
  DateTime? _parsedDueDate;
  String? _parsedDueTime;

  bool _hasParsed = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _reset() {
    _controller.clear();
    _rawInput = null;
    _strippedTitle = null;
    _parsedDueDate = null;
    _parsedDueTime = null;
    _hasParsed = false;
  }

  Future<void> _handleSubmit() async {
    final currentText = _controller.text.trim();

    if (widget.listId == null) return;

    // If nothing typed and no parsed state, do nothing
    if (currentText.isEmpty &&
        _parsedDueDate == null &&
        _parsedDueTime == null) {
      return;
    }

    // Phase 1: First submit runs the natural-language parser and displays preview chip / hint
    if (!_hasParsed) {
      _rawInput = currentText;
      final now = ref.read(currentDateProvider);
      final parseResult = parseQuickAdd(currentText, now: now);

      if (parseResult.dueDate != null || parseResult.dueTime != null) {
        setState(() {
          _hasParsed = true;
          _parsedDueDate = parseResult.dueDate;
          _parsedDueTime = parseResult.dueTime;
          _strippedTitle = parseResult.strippedTitle;
          _controller.text = parseResult.strippedTitle;
        });
      } else {
        // No date phrase recognized
        setState(() {
          _hasParsed = true;
          _parsedDueDate = null;
          _parsedDueTime = null;
          _strippedTitle = currentText;
        });
      }
      return;
    }

    // Phase 2: Second submit confirms and creates the task
    final titleToCreate = _controller.text.trim().isNotEmpty
        ? _controller.text.trim()
        : (_strippedTitle?.isNotEmpty == true
              ? _strippedTitle!
              : (_rawInput ?? ''));

    if (titleToCreate.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final createdTask = await ref
          .read(taskRepositoryProvider)
          .createTask(
            uid: widget.uid,
            listId: widget.listId!,
            title: titleToCreate,
            dueDate: _parsedDueDate,
            dueTime: _parsedDueTime,
          );
      if (mounted) {
        setState(() {
          _reset();
          _isSaving = false;
        });
        widget.onTaskCreated?.call(createdTask);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to add task: $e')));
      }
    }
  }

  void _onDismissChip() {
    setState(() {
      _parsedDueDate = null;
      _parsedDueTime = null;
      if (_rawInput != null) {
        _controller.text = _rawInput!;
      }
      _hasParsed = true;
    });
  }

  String _formatDueTime12Hour(String dueTime24) {
    final parts = dueTime24.split(':');
    if (parts.length != 2) return dueTime24;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final mStr = m.toString().padLeft(2, '0');
    return '$h12:$mStr $ampm';
  }

  String _formatPreviewDate(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _buildChipLabel() {
    final now = ref.read(currentDateProvider);
    final parts = <String>[];
    if (_parsedDueDate != null) {
      parts.add(_formatPreviewDate(_parsedDueDate!, now));
    }
    if (_parsedDueTime != null) {
      parts.add(_formatDueTime12Hour(_parsedDueTime!));
    }
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDateOrTime = _parsedDueDate != null || _parsedDueTime != null;

    final isEnabled = widget.listId != null;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        8,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasDateOrTime)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Chip(
                key: const Key('quickAddDateChip'),
                avatar: Icon(
                  Icons.event_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                label: Text(
                  _buildChipLabel(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                deleteIcon: const Icon(Icons.close, size: 14),
                deleteButtonTooltipMessage: 'Remove date/time',
                onDeleted: _onDismissChip,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          Row(
            children: [
              IconButton(
                key:
                    widget.expandButtonKey ?? const Key('quickAddExpandButton'),
                icon: const Icon(Icons.open_in_full, size: 18),
                tooltip: 'Full task form',
                onPressed: (!isEnabled || _isSaving)
                    ? null
                    : () {
                        final textToPass = _rawInput ?? _controller.text;
                        widget.onExpand?.call(textToPass);
                      },
              ),
              Expanded(
                child: TextField(
                  key: const Key('quickAddTextInput'),
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: isEnabled && !_isSaving,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: !isEnabled
                        ? 'Loading...'
                        : (widget.hintText ??
                              'Add a task (e.g. Buy milk tomorrow 5pm)...'),
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: theme.hintColor.withValues(alpha: 0.6),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: (val) {
                    // Reset parse status on typing if previously parsed
                    if (_hasParsed) {
                      setState(() {
                        _hasParsed = false;
                        _parsedDueDate = null;
                        _parsedDueTime = null;
                      });
                    }
                  },
                  onSubmitted: isEnabled ? (_) => _handleSubmit() : null,
                ),
              ),
              IconButton(
                key: const Key('quickAddSubmitButton'),
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _hasParsed
                            ? Icons.check_circle_outline
                            : Icons.arrow_upward,
                        size: 20,
                        color: isEnabled
                            ? theme.colorScheme.primary
                            : theme.disabledColor,
                      ),
                tooltip: _hasParsed ? 'Confirm task' : 'Add task',
                onPressed: (!isEnabled || _isSaving) ? null : _handleSubmit,
              ),
            ],
          ),
          if (_hasParsed && !hasDateOrTime)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 2),
              child: Text(
                'No date detected. Press Enter to create.',
                key: const Key('quickAddHintText'),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
