import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/ui/safe_url.dart';
import '../../data/task.dart';

/// A task's URL. Valid http(s) links open in a new tab; anything else that was
/// stored renders as plain text.
class TaskUrlLink extends StatelessWidget {
  const TaskUrlLink({super.key, required this.task, this.enabled = true});

  final Task task;

  /// False while selecting tasks, so a tap selects instead of opening.
  final bool enabled;

  Future<void> _open(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, webOnlyWindowName: '_blank');
    } catch (_) {}
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open the link.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = parseWebUrl(task.url);
    final key = Key('taskUrl_${task.taskId}');
    if (uri == null) {
      return Text(task.url, key: key);
    }
    final text = Text(
      task.url,
      key: key,
      style: const TextStyle(
        color: Colors.blue,
        decoration: TextDecoration.underline,
      ),
    );
    if (!enabled) return text;
    return InkWell(onTap: () => _open(context, uri), child: text);
  }
}
