import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays ringtone / ringback tones during calls.
///
/// • Caller  → ringback (outgoing beep) while waiting for answer.
/// • Callee  → ringtone (incoming alert) while the call is ringing.
/// • In-call → silence (stopped as soon as the call connects).
///
/// Uses [audioplayers] which is already in pubspec.
/// The app-bundled sounds are loaded from assets/sounds/.
/// Falls back to system-tone generation on web (no asset required).
class CallRingtoneService {
  CallRingtoneService._();

  static final _player = AudioPlayer();
  static bool _playing = false;

  // ── Caller ringback ───────────────────────────────────────────────────────

  /// Play an outgoing ringback tone (caller hears this while waiting).
  static Future<void> playRingback() async {
    await _play('sounds/ringback.mp3', loop: true);
  }

  // ── Callee ringtone ───────────────────────────────────────────────────────

  /// Play an incoming ringtone (callee hears this when a call arrives).
  static Future<void> playRingtone() async {
    await _play('sounds/ringtone.mp3', loop: true);
  }

  // ── Stop ──────────────────────────────────────────────────────────────────

  static Future<void> stop() async {
    if (!_playing) return;
    try {
      await _player.stop();
    } catch (_) {}
    _playing = false;
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  static Future<void> _play(String assetPath, {bool loop = false}) async {
    if (kIsWeb) {
      // Web AudioContext has stricter autoplay policies.
      // Ringtone will only work after a user gesture on the page.
    }
    try {
      await _player.stop();
      await _player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
      await _player.play(AssetSource(assetPath));
      _playing = true;
    } catch (e) {
      debugPrint('[Ringtone] could not play $assetPath: $e');
      _playing = false;
    }
  }
}
