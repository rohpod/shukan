import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tasks/data/task.dart';
import '../../features/tasks/providers/task_providers.dart';
import '../../features/tasks/providers/task_sort_providers.dart';
import 'chime/chime.dart';
import 'notification_service.dart';

/// Global messenger key for displaying reminder SnackBars anywhere in the app.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Provider indicating whether the app is running on the web platform.
final isWebPlatformProvider = Provider<bool>((ref) => kIsWeb);

/// Provider supplying the clock function used to evaluate reminders.
final reminderClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Provider supplying the function to play a reminder chime.
final chimePlayerProvider = Provider<bool Function()>((ref) => playChime);

/// Provider supplying the function to prepare the audio context for chimes.
final chimePreparerProvider = Provider<void Function()>((ref) => prepareChime);

/// Helper to synchronously trigger audio unlock and permission request on task save.
void requestWebPermissionOnSave({
  required WidgetRef ref,
  required BuildContext context,
  required bool mounted,
}) {
  final preparer = ref.read(chimePreparerProvider);
  preparer();

  final prefs = ref.read(sharedPreferencesProvider);
  const promptShownKey = 'web_notifications_prompt_shown';
  final alreadyPrompted = prefs?.getBool(promptShownKey) ?? false;
  if (alreadyPrompted) {
    return;
  }

  final permFuture = ref
      .read(notificationServiceProvider)
      .requestWebPermissionIfNeeded();

  unawaited(prefs?.setBool(promptShownKey, true));

  permFuture.then((result) async {
    if (result == WebPermissionResult.denied) {
      const flagKey = 'web_notifications_denied_snack_shown';
      final alreadyShown = prefs?.getBool(flagKey) ?? false;
      if (!alreadyShown) {
        await prefs?.setBool(flagKey, true);
        const snackBar = SnackBar(
          content: Text(
            "Notifications are blocked in your browser. You won't get task reminders from this tab.",
          ),
        );
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        } else {
          rootScaffoldMessengerKey.currentState?.showSnackBar(snackBar);
        }
      }
    }
  });
}

/// Scheduler that periodically evaluates upcoming/due tasks on web.
class WebReminderScheduler with WidgetsBindingObserver {
  final Ref? ref;
  final bool isWeb;

  Timer? _timer;
  List<Task> _latestTasks = const [];
  final Set<String> _firedKeys = {};
  bool _isEvaluating = false;
  bool isTabVisible = true;

  List<Task> get latestTasks => _latestTasks;
  Set<String> get firedKeys => Set.unmodifiable(_firedKeys);
  Timer? get activeTimer => _timer;

  WebReminderScheduler(this.ref, {required this.isWeb}) {
    if (!isWeb || ref == null) return;

    _loadFiredKeys();
    final clock = ref!.read(reminderClockProvider);
    _pruneFiredKeys(clock());

    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  factory WebReminderScheduler.noop() {
    return _NoopWebReminderScheduler();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    isTabVisible = (state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      evaluate();
    }
  }

  void updateTasks(List<Task> tasks) {
    if (!isWeb) return;

    _latestTasks = tasks;
    if (tasks.isEmpty) {
      _timer?.cancel();
      _timer = null;
      _firedKeys.clear();
      return;
    }

    _ensureTimer();
    evaluate();
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 20), (_) {
      evaluate();
    });
  }

  Future<void> evaluate() async {
    if (!isWeb || _isEvaluating || _latestTasks.isEmpty || ref == null) return;
    _isEvaluating = true;

    try {
      final clock = ref!.read(reminderClockProvider);
      final now = clock();

      _pruneFiredKeys(now);

      final due = dueWebReminders(_latestTasks, now, _firedKeys);
      if (due.isEmpty) return;

      final notifService = ref!.read(notificationServiceProvider);
      final playChimeFn = ref!.read(chimePlayerProvider);

      for (final r in due) {
        _firedKeys.add(r.key);
        _persistFiredKeys();

        await notifService.showWebReminder(r);
        final chimePlayed = playChimeFn();

        final permissionGranted = notifService.webNotificationsGranted;
        final chimeFailedWhileVisible = !chimePlayed && isTabVisible;

        if (!permissionGranted || chimeFailedWhileVisible) {
          final message = r.kind == WebReminderKind.due
              ? 'Reminder: ${r.task.title}'
              : 'Upcoming: ${r.task.title}';
          rootScaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      }
    } finally {
      _isEvaluating = false;
    }
  }

  void _loadFiredKeys() {
    if (ref == null) return;
    try {
      final prefs = ref!.read(sharedPreferencesProvider);
      final stored = prefs?.getStringList('web_fired_reminders') ?? const [];
      _firedKeys.addAll(stored);
    } catch (_) {}
  }

  void _persistFiredKeys() {
    if (ref == null) return;
    try {
      final prefs = ref!.read(sharedPreferencesProvider);
      prefs?.setStringList('web_fired_reminders', _firedKeys.toList());
    } catch (_) {}
  }

  void _pruneFiredKeys(DateTime now) {
    final cutoff = now
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    bool changed = false;
    _firedKeys.removeWhere((key) {
      final lastColon = key.lastIndexOf(':');
      if (lastColon != -1) {
        final ms = int.tryParse(key.substring(lastColon + 1));
        if (ms != null && ms < cutoff) {
          changed = true;
          return true;
        }
      }
      return false;
    });

    if (changed) {
      _persistFiredKeys();
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
  }
}

class _NoopWebReminderScheduler extends WebReminderScheduler {
  _NoopWebReminderScheduler() : super(null, isWeb: false);

  @override
  void updateTasks(List<Task> tasks) {}

  @override
  Future<void> evaluate() async {}

  @override
  void dispose() {}
}

/// Non-autoDispose provider for the web reminder scheduler.
final webReminderSchedulerProvider = Provider<WebReminderScheduler>((ref) {
  final isWeb = ref.watch(isWebPlatformProvider);
  if (!isWeb) {
    return WebReminderScheduler.noop();
  }

  final scheduler = WebReminderScheduler(ref, isWeb: isWeb);
  ref.onDispose(scheduler.dispose);

  ref.listen<AsyncValue<List<Task>>>(allTasksForCurrentUserProvider, (
    previous,
    next,
  ) {
    next.whenData((tasks) {
      scheduler.updateTasks(tasks);
    });
  }, fireImmediately: true);

  return scheduler;
});

/// Host widget that keeps the reminder scheduler alive for the tab lifetime
/// and unlocks Web Audio on the user's first pointer interaction on web.
class WebReminderHost extends ConsumerWidget {
  final Widget child;

  const WebReminderHost({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(webReminderSchedulerProvider);
    final isWeb = ref.watch(isWebPlatformProvider);
    if (!isWeb) {
      return child;
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        final preparer = ref.read(chimePreparerProvider);
        preparer();
      },
      child: child,
    );
  }
}
