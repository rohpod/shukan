import 'package:flutter/material.dart';

import 'friendly_error.dart';

/// Shows a standardized feedback [SnackBar] through [messenger].
///
/// Always clears existing snackbars first.
/// If [actionLabel] and [onAction] are provided, displays an action button
/// with 5-second auto-dismissal, [DismissDirection.startToEnd] swipe dismissal,
/// and catches errors thrown by [onAction] to display a follow-up error snackbar
/// prefixed by [actionErrorPrefix].
///
/// If no action is provided, displays a standard duration message snackbar.
void showFeedbackSnackBar(
  ScaffoldMessengerState messenger,
  String message, {
  String? actionLabel,
  Key? actionKey,
  Future<void> Function()? onAction,
  String actionErrorPrefix = 'Failed to undo',
}) {
  messenger.clearSnackBars();

  if (actionLabel != null && onAction != null) {
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        persist: false,
        dismissDirection: DismissDirection.startToEnd,
        content: Text(message),
        action: SnackBarAction(
          key: actionKey,
          label: actionLabel,
          onPressed: () async {
            try {
              await onAction();
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text('$actionErrorPrefix: ${friendlyError(e)}'),
                ),
              );
            }
          },
        ),
      ),
    );
  } else {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Runs [action], showing [failureMessage] through [messenger] if it throws.
Future<void> runWithFeedback(
  ScaffoldMessengerState messenger,
  String failureMessage,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    debugPrint('$failureMessage: $e');
    messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
  }
}
