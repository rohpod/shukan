import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/web_reminder_scheduler.dart';
import '../../auth/providers/auth_providers.dart';
import '../domain/smart_view_models.dart';
import '../providers/task_providers.dart';
import 'smart_view_detail_screen.dart';
import 'task_list_screen.dart';

/// Connects reminders to navigation: opens the task behind a clicked
/// notification and offers the Today view after missed reminders.
class ReminderNavigationHandler extends ConsumerStatefulWidget {
  final Widget child;

  const ReminderNavigationHandler({super.key, required this.child});

  @override
  ConsumerState<ReminderNavigationHandler> createState() =>
      _ReminderNavigationHandlerState();
}

class _ReminderNavigationHandlerState
    extends ConsumerState<ReminderNavigationHandler> {
  StreamSubscription<String>? _tapSubscription;
  StreamSubscription<int>? _missedSubscription;

  @override
  void initState() {
    super.initState();
    final notifications = ref.read(notificationServiceProvider);
    _tapSubscription = notifications.taskTaps.listen(_openTask);
    _missedSubscription = ref
        .read(webReminderSchedulerProvider)
        .missedReminders
        .listen(_showMissedSummary);
    unawaited(_openLaunchTask(notifications));
  }

  @override
  void dispose() {
    _tapSubscription?.cancel();
    _missedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _openLaunchTask(NotificationService notifications) async {
    final taskId = await notifications.launchTaskId();
    if (taskId != null) await _openTask(taskId);
  }

  Future<void> _openTask(String taskId) async {
    if (taskId == testNotificationTaskId) return;

    // Stream providers pause without a listener, which would leave these
    // futures pending, so hold listeners while waiting on them.
    final authListener = ref.listenManual(authStateChangesProvider, (_, _) {});
    final tasksListener = ref.listenManual(
      allTasksForCurrentUserProvider,
      (_, _) {},
    );
    try {
      final user = await ref.read(authStateChangesProvider.future);
      if (user == null) return;
      final tasks = await ref.read(allTasksForCurrentUserProvider.future);
      final matches = tasks.where((task) => task.taskId == taskId);
      final navigatorContext = rootNavigatorKey.currentContext;
      if (!mounted || navigatorContext == null || !navigatorContext.mounted) {
        return;
      }
      if (matches.isEmpty) {
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('That task is no longer available.')),
        );
        return;
      }
      final task = matches.first;
      await showDialog<void>(
        context: navigatorContext,
        builder: (_) =>
            TaskDialog(uid: task.uid, listId: task.listId, task: task),
      );
    } catch (e) {
      debugPrint('Failed to open task from notification: $e');
    } finally {
      authListener.close();
      tasksListener.close();
    }
  }

  void _showMissedSummary(int count) {
    final message = count == 1
        ? '1 reminder while you were away'
        : '$count reminders while you were away';
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        key: const Key('missedRemindersSnackBar'),
        duration: const Duration(seconds: 10),
        content: Text(message),
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            rootNavigatorKey.currentState?.push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const SmartViewDetailScreen(viewType: SmartViewType.today),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
