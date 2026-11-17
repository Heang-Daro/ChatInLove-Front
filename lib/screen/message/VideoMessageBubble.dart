import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Messenger-style video message bubble.
///
///  - a placeholder with a play button (no player is created while the
///    message is only scrolled through - a controller per bubble would open
///    a platform player for every visible video)
///  - tapping it loads and plays the video inline
///  - play / pause, a progress bar and the duration
///  - only one video plays at a time
///  - error state with a retry button
class VideoMessageBubble extends StatefulWidget {
  final String videoUrl;
  final bool isMe;
  final double width;
  final double height;

  const VideoMessageBubble({
    super.key,
    required this.videoUrl,
    required this.isMe,
    this.width = 250,
    this.height = 170,
  });

  @override
  State<VideoMessageBubble> createState() => _VideoMessageBubbleState();
}

class _VideoMessageBubbleState extends State<VideoMessageBubble> {
  /// The bubble that currently plays - every other one is stopped.
  static _VideoMessageBubbleState? _playing;

  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _failed = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool get _hasPlayer => _controller?.value.isInitialized ?? false;

  @override
  void dispose() {
    if (_playing == this) _playing = null;
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    controller.removeListener(_onTick);
    unawaited(controller.pause());
    unawaited(controller.dispose());
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final position = controller.value.position;
    final duration = controller.value.duration;
    if (position != _position || duration != _duration) {
      setState(() {
        _position = position;
        _duration = duration;
      });
    }
  }

  /// Loads and starts the video.
  Future<void> _start() async {
    if (_initializing || _hasPlayer) return;

    // Only one video plays at a time.
    final other = _playing;
    if (other != null && other != this) other._stop();

    setState(() {
      _initializing = true;
      _failed = false;
    });

    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = controller;
      controller.addListener(_onTick);
      await controller.initialize();
      if (!mounted) {
        controller.removeListener(_onTick);
        await controller.dispose();
        return;
      }
      await controller.play();
      _playing = this;
      setState(() {
        _initializing = false;
        _position = controller!.value.position;
        _duration = controller.value.duration;
      });
    } catch (_) {
      if (controller != null) {
        controller.removeListener(_onTick);
        await controller.dispose();
      }
      _controller = null;
      if (mounted) {
        setState(() {
          _initializing = false;
          _failed = true;
        });
      }
    }
  }

  /// Stops the playback and goes back to the placeholder.
  void _stop() {
    if (_playing == this) _playing = null;
    _disposeController();
    if (mounted) {
      setState(() {
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }
  }

  Future<void> _togglePlayPause() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      await controller.pause();
      return;
    }
    if (_playing != this) {
      final other = _playing;
      if (other != null && other != this) other._stop();
      _playing = this;
    }
    await controller.play();
  }

  double get _progress {
    if (_duration.inMilliseconds <= 0) return 0;
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return minutes > 0 ? '$minutes:${two(seconds)}' : '${two(seconds)}s';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized = controller?.value.isInitialized ?? false;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (initialized)
              _videoSurface(controller!)
            else
              _placeholder(),
            if (!initialized)
              _centerButton()
            else
              _controls(controller!),
          ],
        ),
      ),
    );
  }

  // ── Placeholder (before the video is loaded) ───────────────────────────────
  Widget _placeholder() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: _initializing
            ? const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _failed ? Icons.error_outline_rounded : Icons.videocam_rounded,
                    color: _failed ? Colors.redAccent : Colors.white70,
                    size: 34,
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      _failed ? 'Tap to retry' : 'Tap to play',
                      style: TextStyle(
                        color: _failed ? Colors.redAccent : Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _centerButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _failed || _initializing ? _start : _start,
      child: Container(
        color: Colors.black.withValues(alpha: 0.25),
        alignment: Alignment.center,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
        ),
      ),
    );
  }

  // ── The video itself ──────────────────────────────────────────────────────
  Widget _videoSurface(VideoPlayerController controller) {
    final size = controller.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return Container(color: Colors.black87);
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  // ── Controls ──────────────────────────────────────────────────────────────
  Widget _controls(VideoPlayerController controller) {
    final isPlaying = controller.value.isPlaying;

    return Stack(
      children: [
        // Tap anywhere on the video to play / pause.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlayPause,
          ),
        ),
        // Progress bar + time.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _togglePlayPause,
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 3,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _duration > Duration.zero
                      ? '${_fmt(_position)} / ${_fmt(_duration)}'
                      : _fmt(_position),
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: _stop,
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
