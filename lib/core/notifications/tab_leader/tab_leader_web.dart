import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Calls [onLeader] once this tab holds the reminder lock.
///
/// The lock stays held until the tab closes, then the browser hands it to the
/// next waiting tab, so only one tab fires reminders. Browsers without the Web
/// Locks API treat every tab as the leader.
void whenReminderLeader(void Function() onLeader) {
  try {
    final navigator = globalContext.getProperty<JSObject>('navigator'.toJS);
    if (!navigator.hasProperty('locks'.toJS).toDart) {
      onLeader();
      return;
    }

    JSPromise<JSAny?> holdLock(JSAny? _) {
      onLeader();
      return Completer<JSAny?>().future.toJS;
    }

    navigator
        .getProperty<JSObject>('locks'.toJS)
        .callMethod<JSAny?>(
          'request'.toJS,
          'shukan-reminder-leader'.toJS,
          holdLock.toJS,
        );
  } catch (_) {
    onLeader();
  }
}
