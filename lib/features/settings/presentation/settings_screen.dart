import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/web_reminder_scheduler.dart';
import '../../../core/ui/feedback_snackbar.dart';
import '../../auth/providers/auth_providers.dart';
import '../../export/export_service.dart';
import '../../tasks/data/task.dart';
import '../../tasks/providers/task_sort_providers.dart';

/// Notice shown wherever reminders are configured on web.
const reminderTabNotice =
    'Reminders only fire while a shukan tab is open. Anything missed while it '
    'is closed is summarised when you come back.';

class SettingsScreen extends ConsumerStatefulWidget {
  /// Replaces the browser download in tests.
  final void Function(String content, String filename)? downloadTrigger;

  const SettingsScreen({super.key, this.downloadTrigger});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isSendingTest = false;
  bool _isExporting = false;

  Future<void> _enableNotifications() async {
    ref.read(chimePreparerProvider)();
    await ref.read(notificationServiceProvider).requestWebPermissionIfNeeded();
    if (mounted) setState(() {});
  }

  Future<void> _sendTestNotification() async {
    if (_isSendingTest) return;
    setState(() => _isSendingTest = true);

    try {
      ref.read(chimePreparerProvider)();

      final notifService = ref.read(notificationServiceProvider);
      final permResult = await notifService.requestWebPermissionIfNeeded();
      ref.read(chimePlayerProvider)();

      if (permResult == WebPermissionResult.granted) {
        final testTask = Task(
          taskId: testNotificationTaskId,
          uid: ref.read(currentUidProvider) ?? 'test-uid',
          listId: 'test-list',
          title: 'Test notification',
          notes: 'If you can see and hear this, notifications are working.',
        );
        await notifService.showWebReminder(
          WebReminder(
            task: testTask,
            kind: WebReminderKind.due,
            fireTime: DateTime.now(),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingTest = false);
    }
  }

  Future<void> _exportData(String uid) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isExporting = true);
    await runWithFeedback(messenger, "Couldn't export your data.", () async {
      await ref
          .read(exportServiceProvider)
          .exportAccount(uid: uid, downloadTrigger: widget.downloadTrigger);
      showFeedbackSnackBar(messenger, 'Exported your data');
    });
    if (mounted) setState(() => _isExporting = false);
  }

  Future<void> _confirmDeleteAccount() async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (deleted != true || !mounted) return;

    await ref.read(sharedPreferencesProvider)?.clear();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  String _statusText(WebNotificationStatus status) {
    switch (status) {
      case WebNotificationStatus.granted:
        return 'Notifications are on.';
      case WebNotificationStatus.notAsked:
        return "Notifications aren't turned on yet. Until they are, reminders "
            'appear inside the app.';
      case WebNotificationStatus.blocked:
        return 'Notifications are blocked. To turn them on, allow notifications '
            'for this site in your browser settings, then reload the page.';
      case WebNotificationStatus.unsupported:
        return "This browser doesn't support notifications, so reminders "
            'appear inside the app.';
    }
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<Widget> _notificationSection(BuildContext context) {
    final status = ref.read(notificationServiceProvider).webNotificationStatus;
    return [
      _sectionTitle(context, 'Reminders'),
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text(reminderTabNotice, key: Key('reminderTabNotice')),
      ),
      ListTile(
        leading: const Icon(Icons.notifications_outlined),
        title: Text(_statusText(status), key: const Key('notificationStatus')),
      ),
      if (status == WebNotificationStatus.notAsked)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const Key('enableNotificationsButton'),
              onPressed: _enableNotifications,
              child: const Text('Turn on notifications'),
            ),
          ),
        ),
      if (status == WebNotificationStatus.granted)
        ListTile(
          key: const Key('testNotificationButton'),
          leading: const Icon(Icons.campaign_outlined),
          title: const Text('Send a test notification'),
          enabled: !_isSendingTest,
          onTap: _sendTestNotification,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isWeb = ref.watch(isWebPlatformProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            children: [
              if (isWeb) ..._notificationSection(context),
              _sectionTitle(context, 'Your data'),
              ListTile(
                key: const Key('exportDataButton'),
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export my data'),
                subtitle: const Text(
                  'Download all your lists, tags and tasks as JSON.',
                ),
                enabled: user != null && !_isExporting,
                onTap: user == null ? null : () => _exportData(user.uid),
              ),
              _sectionTitle(context, 'Account'),
              if (user?.email != null)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(user!.email!),
                ),
              ListTile(
                key: const Key('deleteAccountButton'),
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Delete account',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: user == null ? null : _confirmDeleteAccount,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the password, then deletes the account. Pops `true` on success.
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _passwordController = TextEditingController();
  bool _isDeleting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_passwordController.text.isEmpty) {
      setState(() => _error = 'Enter your password to confirm.');
      return;
    }
    setState(() {
      _isDeleting = true;
      _error = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .deleteAccount(password: _passwordController.text);
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
        _error = e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? 'Incorrect password.'
            : "Couldn't delete your account. Please try again.";
      });
    } catch (e) {
      debugPrint('Failed to delete account: $e');
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
        _error = "Couldn't delete your account. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes your account and all your lists, tags '
            'and tasks. It cannot be undone.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('deleteAccountPasswordInput'),
            controller: _passwordController,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('cancelDeleteAccountButton'),
          onPressed: _isDeleting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('confirmDeleteAccountButton'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
          onPressed: _isDeleting ? null : _delete,
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}
