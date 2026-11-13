import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Messenger-style voice message bubble:
///  - waveform (tap or drag to seek) instead of a slider
///  - play / pause / resume (no restart after pause)
///  - only one voice message plays at a time
///  - playback speed chip (1x → 1.5x → 2x)
///  - error + retry state
class VoiceMessageBubble extends StatefulWidget {
  final String audioUrl;
  final bool isMe;

  /// Optional: known duration (e.g. from your backend) so it shows before play.
  final Duration? initialDuration;

  /// Optional: real waveform samples 0..1. If null, a stable pseudo waveform
  /// is generated from the audio URL.
  final List<double>? waveform;

  final Color accentColor;
  final double waveformWidth;

  const VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    required this.isMe,
    this.initialDuration,
    this.waveform,
    this.accentColor = Colors.pinkAccent,
    this.waveformWidth = 150,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  static _VoiceMessageBubbleState? _current; // currently playing bubble
  static const int _barCount = 34;
  static const List<double> _speeds = [1.0, 1.5, 2.0];

  late final AudioPlayer _player;
  final List<StreamSubscription> _subs = [];

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _hasError = false;
  bool _started = false; // source loaded and not finished
  double _speed = 1.0;
  double? _dragFraction;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  late List<double> _bars;

  @override
  void initState() {
    super.initState();
    _duration = widget.initialDuration ?? Duration.zero;
    _bars = _buildBars();

    _player = AudioPlayer();
    _subs.addAll([
      _player.onPlayerStateChanged.listen((s) {
        if (!mounted) return;
        setState(() {
          _isPlaying = s == PlayerState.playing;
          if (s == PlayerState.playing) _isLoading = false;
        });
      }),
      _player.onDurationChanged.listen((d) {
        if (mounted && d > Duration.zero) setState(() => _duration = d);
      }),
      _player.onPositionChanged.listen((p) {
        if (mounted && _dragFraction == null) setState(() => _position = p);
      }),
      _player.onPlayerComplete.listen((_) {
        if (!mounted) return;
        if (_current == this) _current = null;
        setState(() {
          _isPlaying = false;
          _started = false;
          _position = Duration.zero;
        });
      }),
    ]);
  }

  @override
  void didUpdateWidget(covariant VoiceMessageBubble old) {
    super.didUpdateWidget(old);
    if (old.audioUrl != widget.audioUrl || old.waveform != widget.waveform) {
      _bars = _buildBars();
    }
  }

  @override
  void dispose() {
    if (_current == this) _current = null;
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  List<double> _buildBars() {
    final src = widget.waveform;
    if (src != null && src.isNotEmpty) {
      // resample to _barCount
      return List.generate(_barCount, (i) {
        final idx = (i * src.length / _barCount).floor().clamp(0, src.length - 1);
        return src[idx].clamp(0.12, 1.0).toDouble();
      });
    }
    final rnd = Random(widget.audioUrl.hashCode);
    return List.generate(_barCount, (_) => 0.2 + rnd.nextDouble() * 0.8);
  }

  // ───────────── Playback ─────────────

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }
    if (_isLoading) return;

    // Stop any other bubble that is playing
    final other = _current;
    if (other != null && other != this) {
      await other._player.pause();
    }
    _current = this;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      await _player.setPlaybackRate(_speed);
      if (_started) {
        await _player.resume(); // continue where it was paused
      } else {
        await _player.play(UrlSource(widget.audioUrl));
        _started = true;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _started = false;
        });
      }
    }
  }

  Future<void> _cycleSpeed() async {
    final next = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
    setState(() => _speed = next);
    try {
      await _player.setPlaybackRate(next);
    } catch (_) {}
  }

  double get _progress {
    if (_dragFraction != null) return _dragFraction!;
    if (_duration.inMilliseconds <= 0) return 0;
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
  }

  Future<void> _seekTo(double fraction) async {
    if (_duration.inMilliseconds <= 0 || !_started) {
      setState(() => _dragFraction = null);
      return;
    }
    final target =
    Duration(milliseconds: (fraction * _duration.inMilliseconds).round());
    setState(() {
      _position = target;
      _dragFraction = null;
    });
    try {
      await _player.seek(target);
    } catch (_) {}
  }

  double _fractionOf(double dx) =>
      (dx / widget.waveformWidth).clamp(0.0, 1.0).toDouble();

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    final isMe = widget.isMe;
    final active = isMe ? Colors.white : widget.accentColor;
    final inactive = isMe ? Colors.white38 : widget.accentColor.withAlpha(70);
    final buttonBg = isMe ? Colors.white24 : widget.accentColor.withAlpha(35);
    final textColor = isMe ? Colors.white70 : Colors.grey.shade600;

    final showPosition = _isPlaying || _position > Duration.zero;
    final label = showPosition
        ? _fmt(_dragFraction != null
        ? Duration(
        milliseconds: (_dragFraction! * _duration.inMilliseconds).round())
        : _position)
        : (_duration > Duration.zero ? _fmt(_duration) : '0:00');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _togglePlayPause,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: buttonBg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: _isLoading
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: active),
            )
                : Icon(
              _hasError
                  ? Icons.refresh_rounded
                  : (_isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded),
              color: _hasError ? Colors.redAccent : active,
              size: 26,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _seekTo(_fractionOf(d.localPosition.dx)),
              onHorizontalDragStart: (d) =>
                  setState(() => _dragFraction = _fractionOf(d.localPosition.dx)),
              onHorizontalDragUpdate: (d) =>
                  setState(() => _dragFraction = _fractionOf(d.localPosition.dx)),
              onHorizontalDragEnd: (_) => _seekTo(_dragFraction ?? _progress),
              onHorizontalDragCancel: () => setState(() => _dragFraction = null),
              child: SizedBox(
                width: widget.waveformWidth,
                height: 30,
                child: CustomPaint(
                  painter: _WaveformPainter(
                    bars: _bars,
                    progress: _progress,
                    activeColor: active,
                    inactiveColor: inactive,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: widget.waveformWidth,
              child: Row(
                children: [
                  Text(
                    _hasError ? 'Tap to retry' : label,
                    style: TextStyle(
                      fontSize: 11,
                      color: _hasError ? Colors.redAccent : textColor,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  if (_isPlaying || _speed != 1.0)
                    GestureDetector(
                      onTap: _cycleSpeed,
                      child: Container(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: buttonBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_speed == _speed.roundToDouble() ? _speed.toInt() : _speed}x',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: active,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    final step = size.width / bars.length;
    final midY = size.height / 2;

    for (var i = 0; i < bars.length; i++) {
      final h = max(4.0, bars[i] * size.height);
      final x = step * i + step / 2;
      paint.color = (i + 0.5) / bars.length <= progress ? activeColor : inactiveColor;
      canvas.drawLine(Offset(x, midY - h / 2), Offset(x, midY + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress ||
          old.bars != bars ||
          old.activeColor != activeColor ||
          old.inactiveColor != inactiveColor;
}