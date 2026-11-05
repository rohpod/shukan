import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/tasks/data/task.dart';
import '../../features/tasks/providers/task_providers.dart';
import '../../features/tasks/providers/task_sort_providers.dart';
import 'chime/chime.dart';
import 'notification_service.dart';
import 'tab_leader/tab_leader.dart';

/// Global messenger key for displaying reminder SnackBars anywhere in the app.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Global navigator key for opening screens from outside the widget tree.
final rootNavigatorKey = GlobalKey<NavigatorState>();

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

/// Provider supplying how this tab waits to become the one firing reminders.
final reminderLeaderProvider = Provider<void Function(void Function())>(
  (ref) => whenReminderLeader,
);

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
      if (!mounted) {
        await showWebNotificationsDeniedSnackBar(prefs: prefs, context: null);
        return;
      }
      await showWebNotificationsDeniedSnackBar(
        prefs: prefs,
        context: context.mounted ? context : null,
      );
    }
  });
}

/// The message displayed when web notifications are blocked/denied.
const webNotificationsDeniedMessage =
    "Notifications are blocked in your browser. You won't get task reminders from this tab.";

/// SharedPreferences key tracking whether the denied permission SnackBar has been shown.
const webNotificationsDeniedFlagKey = 'web_notifications_denied_snack_shown';

/// Shows a SnackBar when web notifications are denied, respecting the one-time display flag.
Future<void> showWebNotificationsDeniedSnackBar({
  required SharedPreferences? prefs,
  BuildContext? context,
}) async {
  final alreadyShown = prefs?.getBool(webNotificationsDeniedFlagKey) ?? false;
  if (!alreadyShown) {
    await prefs?.setBool(webNotificationsDeniedFlagKey, true);
    const snackBar = SnackBar(content: Text(webNotificationsDeniedMessage));
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } else {
      rootScaffoldMessengerKey.currentState?.showSnackBar(snackBar);
    }
  }
}

/// Scheduler that periodically evaluates upcoming/due tasks on web.
class WebReminderScheduler with WidgetsBindingObserver {
  /// How far back reminders are recovered. Older ones are covered by the
  /// overdue banner, and fired keys are only kept this long.
  static const catchUpWindow = Duration(hours: 24);

  static const _caughtUpAtKey = 'web_reminders_caught_up_at';

  final Ref? ref;
  final bool isWeb;

  Timer? _timer;
  List<Task> _latestTasks = const [];
  final Set<String> _firedKeys = {};
  final _missedReminders = StreamController<int>.broadcast();
  bool _isEvaluating = false;
  bool _isLeader = false;
  bool isTabVisible = true;

  /// Emits the number of tasks with reminders missed while no tab was running.
  Stream<int> get missedReminders => _missedReminders.stream;

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

    ref!.read(reminderLeaderProvider)(_becomeLeader);
  }

  Future<void> _becomeLeader() async {
    // Another tab may have fired reminders since this one started.
    try {
      await ref!.read(sharedPreferencesProvider)?.reload();
      _loadFiredKeys();
    } catch (_) {}
    _isLeader = true;
    await evaluate();
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
    if (!isWeb ||
        !_isLeader ||
        _isEvaluating ||
        _latestTasks.isEmpty ||
        ref == null) {
      return;
    }
    _isEvaluating = true;

    try {
      final clock = ref!.read(reminderClockProvider);
      final now = clock();

      _pruneFiredKeys(now);
      _catchUp(now);

      final due = dueWebReminders(_latestTasks, now, _firedKeys);
      if (due.isEmpty) return;

      final notifService = ref!.read(notificationServiceProvider);
      final playChimeFn = ref!.read(chimePlayerProvider);

      for (final r in due) {
        final shown = await notifService.showWebReminder(r);
        final chimePlayed = playChimeFn();

        final permissionGranted = notifService.webNotificationsGranted;
        final chimeFailedWhileVisible = !chimePlayed && isTabVisible;

        var delivered = shown;
        if (!shown || !permissionGranted || chimeFailedWhileVisible) {
          final message = r.kind == WebReminderKind.due
              ? 'Reminder: ${r.task.title}'
              : 'Upcoming: ${r.task.title}';
          final messenger = rootScaffoldMessengerKey.currentState;
          messenger?.showSnackBar(SnackBar(content: Text(message)));
          delivered = delivered || messenger != null;
        }

        // Left unmarked, a failed reminder retries until it leaves the grace
        // window, and then counts as missed.
        if (delivered) {
          _firedKeys.add(r.key);
          _persistFiredKeys();
        }
      }
    } finally {
      _isEvaluating = false;
    }
  }

  /// Reports reminders that came due while no tab was running.
  ///
  /// Waits for the tab to be visible, so the summary is actually seen, and
  /// reports them once as a count rather than as a burst of notifications.
  void _catchUp(DateTime now) {
    if (!isTabVisible) return;

    final prefs = ref!.read(sharedPreferencesProvider);
    final caughtUpAt = prefs?.getInt(_caughtUpAtKey);
    unawaited(prefs?.setInt(_caughtUpAtKey, now.millisecondsSinceEpoch));
    if (caughtUpAt == null) return;

    final windowStart = now.subtract(catchUpWindow);
    final lastCaughtUp = DateTime.fromMillisecondsSinceEpoch(caughtUpAt);
    final missed = missedWebReminders(
      _latestTasks,
      lastCaughtUp.isAfter(windowStart) ? lastCaughtUp : windowStart,
      now,
      _firedKeys,
    );
    if (missed.isEmpty) return;

    _firedKeys.addAll(missed.map((r) => r.key));
    _persistFiredKeys();
    _missedReminders.add(missed.map((r) => r.task.taskId).toSet().length);
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
    final cutoff = now.subtract(catchUpWindow).millisecondsSinceEpoch;
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
    _missedReminders.close();
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
