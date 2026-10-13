// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('AudioContext')
extension type _AudioContext._(JSObject _) implements JSObject {
  external _AudioContext();
  external String get state;
  external JSPromise resume();
  external double get currentTime;
  external _AudioDestinationNode get destination;
  external _OscillatorNode createOscillator();
  external _GainNode createGain();
}

@JS('webkitAudioContext')
extension type _WebkitAudioContext._(JSObject _) implements JSObject {
  external _WebkitAudioContext();
}

@JS('AudioDestinationNode')
extension type _AudioDestinationNode._(JSObject _) implements JSObject {}

@JS('AudioParam')
extension type _AudioParam._(JSObject _) implements JSObject {
  external void setValueAtTime(double value, double startTime);
  external void linearRampToValueAtTime(double value, double endTime);
}

@JS('GainNode')
extension type _GainNode._(JSObject _) implements JSObject {
  external _AudioParam get gain;
  external void connect(JSObject destination);
}

@JS('OscillatorNode')
extension type _OscillatorNode._(JSObject _) implements JSObject {
  external _AudioParam get frequency;
  external void connect(JSObject destination);
  external void start([double when]);
  external void stop([double when]);
}

_AudioContext? _audioContext;

/// Synchronously creates the AudioContext (including the webkit prefix fallback)
/// if needed and resumes it if suspended.
void prepareChime() {
  try {
    if (_audioContext == null) {
      if (globalContext.hasProperty('AudioContext'.toJS).toDart) {
        _audioContext = _AudioContext();
      } else if (globalContext.hasProperty('webkitAudioContext'.toJS).toDart) {
        _audioContext = _AudioContext._(_WebkitAudioContext() as JSObject);
      }
    }
    if (_audioContext != null && _audioContext!.state == 'suspended') {
      _audioContext!.resume();
    }
  } catch (_) {
    // Synchronous try/catch as specified.
  }
}

/// Plays a short two-tone chime (~0.4s, 587 Hz then 880 Hz oscillators with soft attack and decay).
/// Returns true if the sound was played, false otherwise.
bool playChime() {
  try {
    prepareChime();
    final ctx = _audioContext;
    if (ctx == null || ctx.state != 'running') {
      return false;
    }

    final double now = ctx.currentTime;

    // Tone 1: 587 Hz for ~0.2s
    final osc1 = ctx.createOscillator();
    final gain1 = ctx.createGain();
    osc1.frequency.setValueAtTime(587.0, now);
    osc1.connect(gain1);
    gain1.connect(ctx.destination);

    gain1.gain.setValueAtTime(0.0001, now);
    gain1.gain.linearRampToValueAtTime(0.2, now + 0.03);
    gain1.gain.linearRampToValueAtTime(0.0001, now + 0.18);
    gain1.gain.setValueAtTime(0.0, now + 0.2);

    osc1.start(now);
    osc1.stop(now + 0.2);

    // Tone 2: 880 Hz for ~0.2s
    final osc2 = ctx.createOscillator();
    final gain2 = ctx.createGain();
    osc2.frequency.setValueAtTime(880.0, now + 0.2);
    osc2.connect(gain2);
    gain2.connect(ctx.destination);

    gain2.gain.setValueAtTime(0.0001, now + 0.2);
    gain2.gain.linearRampToValueAtTime(0.25, now + 0.23);
    gain2.gain.linearRampToValueAtTime(0.0001, now + 0.38);
    gain2.gain.setValueAtTime(0.0, now + 0.4);

    osc2.start(now + 0.2);
    osc2.stop(now + 0.4);

    return true;
  } catch (_) {
    return false;
  }
}
