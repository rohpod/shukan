import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A dialog with a single list-name field.
///
/// It owns its [TextEditingController], so the controller is disposed only
/// once the dialog has left the tree. Disposing right after `await showDialog`
/// crashes, because the field is still mounted during the exit animation.
///
/// [onConfirm] runs once the name is valid and is responsible for closing the
/// dialog (via `Navigator.pop` on the given context) when it succeeds.
class ListNameDialog extends StatefulWidget {
  const ListNameDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.inputKey,
    required this.confirmKey,
    required this.emptyMessage,
    required this.onConfirm,
    this.cancelKey,
    this.labelText = 'List Name',
    this.hintText,
    this.initialName = '',
  });

  final String title;
  final String confirmLabel;
  final Key inputKey;
  final Key confirmKey;
  final Key? cancelKey;
  final String labelText;
  final String? hintText;
  final String initialName;
  final String emptyMessage;
  final Future<void> Function(BuildContext dialogContext, String name)
  onConfirm;

  @override
  State<ListNameDialog> createState() => _ListNameDialogState();
}

class _ListNameDialogState extends State<ListNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.onConfirm(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: widget.inputKey,
          controller: _controller,
          inputFormatters: [LengthLimitingTextInputFormatter(100)],
          autofocus: true,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) return widget.emptyMessage;
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          key: widget.cancelKey,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: widget.confirmKey,
          onPressed: _confirm,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
