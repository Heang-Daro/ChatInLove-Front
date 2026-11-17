import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:love_in_chat/api/api.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import '../../util/AnimatedComponents.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

const List<double> _kSpeeds = [0.75, 1.0, 1.25, 1.5, 2.0];

/// Creates a network controller that sends the JWT in the request headers.
/// (`Range` requests are added by the platform player itself - `Accept-Ranges`
/// is a *response* header and must not be sent.)
VideoPlayerController _createAuthedController(BuildContext context, String url) {
  final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
  return VideoPlayerController.networkUrl(
    Uri.parse(resolveFileUrl(url)),
    httpHeaders: <String, String>{
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    },
  );
}

double _nextSpeed(double current) {
  final index = _kSpeeds.indexOf(current);
  if (index < 0) return 1.0;
  return _kSpeeds[(index + 1) % _kSpeeds.length];
}

String _speedLabel(double s) => '${s == s.roundToDouble() ? s.toInt() : s}x';

String _formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '$minutes:${two(seconds)}';
}

bool _isFinished(VideoPlayerValue v) =>
    v.isInitialized && v.duration > Duration.zero && v.position >= v.duration;

Future<void> _seekBy(VideoPlayerController controller, Duration delta) async {
  if (!controller.value.isInitialized) return;
  final total = controller.value.duration;
  var target = controller.value.position + delta;
  if (target < Duration.zero) target = Duration.zero;
  if (target > total) target = total;
  await controller.seekTo(target);
}

/// Small icon button with a comfortable hit area.
class _TapIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final EdgeInsets padding;

  const _TapIcon({
    required this.icon,
    required this.onTap,
    this.size = 20,
    this.padding = const EdgeInsets.all(4),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline bubble
// ─────────────────────────────────────────────────────────────────────────────

/// Messenger-style video message bubble.
///
///  - Placeholder with play button until tapped (no player is created while
///    the message is only scrolled past)
///  - Play / pause, replay, rewind / forward 10s, draggable progress bar
///  - Playback speed (0.75x - 2x), buffering indicator
///  - Fullscreen viewer that re-uses the same controller (no second download,
///    position and speed stay in sync)
///  - JWT auth header, only one inline video plays at a time
///  - Pauses when the app goes to the background
///  - Error state with retry
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

class _VideoMessageBubbleState extends State<VideoMessageBubble>
    with WidgetsBindingObserver {
  /// The bubble that currently plays - every other one is stopped.
  static _VideoMessageBubbleState? _playing;

  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _failed = false;
  bool _isPlaying = false;
  bool _buffering = false;
  double _playbackSpeed = 1.0;
  double? _scrubFraction; // 0..1 while the user drags the progress bar

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool get _hasPlayer => _controller?.value.isInitialized ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant VideoMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The bubble was reused for another message: drop the old player.
    // (No setState needed - a rebuild follows.)
    if (oldWidget.videoUrl != widget.videoUrl) {
      _release(clearError: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      final controller = _controller;
      if (controller != null && controller.value.isPlaying) {
        unawaited(controller.pause());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release();
    super.dispose();
  }

  // ── Lifecycle helpers ──────────────────────────────────────────────────────

  /// Detaches and disposes the current controller (safe to call repeatedly).
  void _disposeController() {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    controller.removeListener(_onTick);
    unawaited(controller.dispose());
  }

  /// Drops the player and resets the state fields. Does NOT call setState.
  void _release({bool clearError = false}) {
    if (_playing == this) _playing = null;
    _disposeController();
    _initializing = false;
    _isPlaying = false;
    _buffering = false;
    _scrubFraction = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    if (clearError) _failed = false;
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;

    // Playback error after initialization.
    if (value.hasError) {
      _release();
      setState(() => _failed = true);
      return;
    }

    if (value.position != _position ||
        value.duration != _duration ||
        value.isPlaying != _isPlaying ||
        value.isBuffering != _buffering) {
      setState(() {
        _position = value.position;
        _duration = value.duration;
        _isPlaying = value.isPlaying;
        _buffering = value.isBuffering;
      });
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Loads and starts the video.
  Future<void> _start() async {
    if (_initializing || _hasPlayer) return;

    // Only one video plays at a time.
    final other = _playing;
    if (other != null && other != this) other._stop();

    final VideoPlayerController controller;
    try {
      controller = _createAuthedController(context, widget.videoUrl);
    } catch (_) {
      // e.g. malformed URL
      setState(() => _failed = true);
      return;
    }

    final speed = _playbackSpeed;
    setState(() {
      _initializing = true;
      _failed = false;
    });
    _controller = controller;
    controller.addListener(_onTick);

    try {
      await controller.initialize();

      // Disposed or stopped while loading: dispose()/_stop() already released
      // this controller, so just bail out.
      if (!mounted || !identical(_controller, controller)) return;

      // Claim the "currently playing" slot before awaiting play(), so a
      // second bubble cannot slip in between.
      final current = _playing;
      if (current != null && current != this) current._stop();
      _playing = this;

      await controller.setPlaybackSpeed(speed);
      await controller.play();
      if (!mounted || !identical(_controller, controller)) return;

      setState(() {
        _initializing = false;
        _isPlaying = controller.value.isPlaying;
        _position = controller.value.position;
        _duration = controller.value.duration;
      });
    } catch (_) {
      // Only clean up if this controller is still the active one;
      // otherwise _stop()/dispose() already did.
      if (identical(_controller, controller)) {
        _release();
        if (mounted) setState(() => _failed = true);
      }
    }
  }

  /// Stops the playback and goes back to the placeholder.
  void _stop() {
    if (!mounted) {
      _release();
      return;
    }
    setState(_release);
  }

  Future<void> _togglePlayPause() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      await controller.pause();
      return;
    }

    final other = _playing;
    if (other != null && other != this) other._stop();
    _playing = this;

    // Finished videos: start again from the beginning.
    if (_isFinished(controller.value)) {
      await controller.seekTo(Duration.zero);
    }
    if (!identical(_controller, controller)) return;
    await controller.play();
  }

  Future<void> _cyclePlaybackSpeed() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final next = _nextSpeed(_playbackSpeed);
    setState(() => _playbackSpeed = next);
    await controller.setPlaybackSpeed(next);
  }

  Future<void> _seekToFraction(double fraction) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final totalMs = controller.value.duration.inMilliseconds;
    if (totalMs <= 0) return;
    await controller.seekTo(
      Duration(milliseconds: (fraction.clamp(0.0, 1.0) * totalMs).round()),
    );
  }

  void _openFullScreen() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    AnimatedDialog.show(
      context: context,
      builder: (_) => FullScreenVideoViewer(
        videoUrl: widget.videoUrl,
        // Share the already loaded controller - no second download, and the
        // inline bubble continues exactly where fullscreen leaves off.
        controller: controller,
        onSpeedChanged: (speed) {
          if (mounted) setState(() => _playbackSpeed = speed);
        },
      ),
    );
  }

  double get _progress {
    if (_duration.inMilliseconds <= 0) return 0;
    return (_position.inMilliseconds / _duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

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

  Widget _placeholder() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: _initializing
            ? const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        )
            : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _failed
                  ? Icons.error_outline_rounded
                  : Icons.videocam_rounded,
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
    // While loading, the spinner is the only thing shown.
    if (_initializing) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _start,
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
          child: Icon(
            _failed ? Icons.refresh_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
      ),
    );
  }

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

  Widget _controls(VideoPlayerController controller) {
    final finished = _isFinished(controller.value) && !_isPlaying;

    return Stack(
      children: [
        // Tap anywhere on the video to play / pause.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlayPause,
          ),
        ),

        // Buffering indicator.
        if (_buffering)
          const IgnorePointer(
            child: Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          ),

        // Top bar: speed + fullscreen.
        Positioned(
          top: 6,
          left: 6,
          right: 6,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _cyclePlaybackSpeed,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _speedLabel(_playbackSpeed),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openFullScreen,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fullscreen_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Bottom bar.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 12, 6, 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
            ),
            child: Row(
              children: [
                _TapIcon(
                  icon: Icons.replay_10_rounded,
                  size: 18,
                  onTap: () => _seekBy(controller, const Duration(seconds: -10)),
                ),
                _TapIcon(
                  icon: finished
                      ? Icons.replay_rounded
                      : (_isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                  size: 22,
                  onTap: _togglePlayPause,
                ),
                _TapIcon(
                  icon: Icons.forward_10_rounded,
                  size: 18,
                  onTap: () => _seekBy(controller, const Duration(seconds: 10)),
                ),
                const SizedBox(width: 4),
                _progressBar(),
                const SizedBox(width: 6),
                Text(
                  _duration > Duration.zero
                      ? '${_formatDuration(_position)} / ${_formatDuration(_duration)}'
                      : _formatDuration(_position),
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                _TapIcon(
                  icon: Icons.close_rounded,
                  size: 16,
                  onTap: _stop,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Progress bar that can be tapped or dragged to seek.
  Widget _progressBar() {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          double fractionAt(double dx) =>
              width <= 0 ? 0.0 : (dx / width).clamp(0.0, 1.0);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _seekToFraction(fractionAt(d.localPosition.dx)),
            onHorizontalDragStart: (d) => setState(
                  () => _scrubFraction = fractionAt(d.localPosition.dx),
            ),
            onHorizontalDragUpdate: (d) => setState(
                  () => _scrubFraction = fractionAt(d.localPosition.dx),
            ),
            onHorizontalDragEnd: (_) {
              final fraction = _scrubFraction;
              setState(() => _scrubFraction = null);
              if (fraction != null) _seekToFraction(fraction);
            },
            onHorizontalDragCancel: () => setState(() => _scrubFraction = null),
            child: SizedBox(
              height: 24, // taller than the visible bar: easier to hit
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _scrubFraction ?? _progress,
                    minHeight: 3,
                    backgroundColor: Colors.white24,
                    valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fullscreen viewer
// ─────────────────────────────────────────────────────────────────────────────

/// Fullscreen video viewer with seek slider, speed, skip back / forward,
/// replay and auto-hiding controls.
///
/// If [controller] is given (the inline bubble passes its own), it is shared
/// and NOT disposed here. Otherwise the viewer creates and owns its controller
/// from [videoUrl].
class FullScreenVideoViewer extends StatefulWidget {
  final String videoUrl;
  final VideoPlayerController? controller;
  final Duration initialPosition; // only used when the viewer owns the player
  final double initialSpeed; // only used when the viewer owns the player
  final ValueChanged<double>? onSpeedChanged;

  const FullScreenVideoViewer({
    super.key,
    required this.videoUrl,
    this.controller,
    this.initialPosition = Duration.zero,
    this.initialSpeed = 1.0,
    this.onSpeedChanged,
  });

  @override
  State<FullScreenVideoViewer> createState() => _FullScreenVideoViewerState();
}

class _FullScreenVideoViewerState extends State<FullScreenVideoViewer> {
  VideoPlayerController? _controller;
  bool _ownsController = false;
  bool _initializing = true;
  bool _failed = false;
  bool _showControls = true;
  double? _dragValue; // milliseconds while the slider is dragged
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    final shared = widget.controller;
    if (shared != null && shared.value.isInitialized) {
      _controller = shared;
      _initializing = false;
      _startHideTimer();
    } else {
      _ownsController = true;
      _initVideo();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _disposeOwned();
    super.dispose();
  }

  void _disposeOwned() {
    final controller = _controller;
    _controller = null;
    if (_ownsController && controller != null) {
      unawaited(controller.dispose());
    }
  }

  void _retry() {
    setState(() {
      _initializing = true;
      _failed = false;
    });
    _initVideo();
  }

  Future<void> _initVideo() async {
    _disposeOwned();

    final VideoPlayerController controller;
    try {
      controller = _createAuthedController(context, widget.videoUrl);
    } catch (_) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _failed = true;
        });
      }
      return;
    }
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted || !identical(_controller, controller)) return;

      await controller.setPlaybackSpeed(widget.initialSpeed);
      if (widget.initialPosition > Duration.zero) {
        await controller.seekTo(widget.initialPosition);
      }
      await controller.play();
      if (!mounted || !identical(_controller, controller)) return;

      setState(() => _initializing = false);
      _startHideTimer();
    } catch (_) {
      if (mounted && identical(_controller, controller)) {
        _disposeOwned();
        setState(() {
          _initializing = false;
          _failed = true;
        });
      }
    }
  }

  // ── Controls visibility ────────────────────────────────────────────────────

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _togglePlayPause(VideoPlayerController controller) async {
    if (controller.value.isPlaying) {
      _hideTimer?.cancel();
      await controller.pause();
      return;
    }
    if (_isFinished(controller.value)) {
      await controller.seekTo(Duration.zero);
    }
    await controller.play();
    _startHideTimer();
  }

  Future<void> _skip(VideoPlayerController controller, Duration delta) async {
    await _seekBy(controller, delta);
    _startHideTimer();
  }

  Future<void> _cycleSpeed(VideoPlayerController controller) async {
    final next = _nextSpeed(controller.value.playbackSpeed);
    await controller.setPlaybackSpeed(next);
    widget.onSpeedChanged?.call(next);
    _startHideTimer();
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _backButton() {
    return Positioned(
      top: 4,
      left: 4,
      child: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _errorView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 48),
              const SizedBox(height: 8),
              const Text(
                'Failed to load video',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pinkAccent,
                ),
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                label: const Text('Retry',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
        _backButton(),
      ],
    );
  }

  Widget _buildBody() {
    final controller = _controller;

    if (_failed) return _errorView();
    if (_initializing || controller == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const Center(child: CircularProgressIndicator(color: Colors.white)),
          _backButton(),
        ],
      );
    }

    // Everything that depends on playback state rebuilds from the controller
    // itself - no manual listener / setState needed.
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.hasError) return _errorView();

        final aspect = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;

        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(controller),
              ),
            ),

            // Tap to show / hide the controls.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
              ),
            ),

            if (value.isBuffering)
              const IgnorePointer(
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),

            if (_showControls) ...[
              _topBar(controller, value),
              _centerControls(controller, value),
              _bottomBar(controller, value),
            ],
          ],
        );
      },
    );
  }

  Widget _topBar(VideoPlayerController controller, VideoPlayerValue value) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const Text(
              'Video Player',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: Colors.white24,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => _cycleSpeed(controller),
              icon: const Icon(Icons.speed_rounded,
                  color: Colors.white, size: 18),
              label: Text(
                _speedLabel(value.playbackSpeed),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _centerControls(
      VideoPlayerController controller,
      VideoPlayerValue value,
      ) {
    final finished = _isFinished(value) && !value.isPlaying;

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 42,
            icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
            onPressed: () => _skip(controller, const Duration(seconds: -10)),
          ),
          const SizedBox(width: 24),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              iconSize: 56,
              icon: Icon(
                finished
                    ? Icons.replay_rounded
                    : (value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded),
                color: Colors.white,
              ),
              onPressed: () => _togglePlayPause(controller),
            ),
          ),
          const SizedBox(width: 24),
          IconButton(
            iconSize: 42,
            icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
            onPressed: () => _skip(controller, const Duration(seconds: 10)),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(VideoPlayerController controller, VideoPlayerValue value) {
    final totalMs = value.duration.inMilliseconds.toDouble();
    final max = totalMs > 0 ? totalMs : 1.0;
    final current =
    (_dragValue ?? value.position.inMilliseconds.toDouble()).clamp(0.0, max);
    final shownPosition = Duration(milliseconds: current.round());

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.85),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 6),
                activeTrackColor: Colors.pinkAccent,
                inactiveTrackColor: Colors.white30,
                thumbColor: Colors.pinkAccent,
              ),
              child: Slider(
                value: current,
                max: max,
                // Only seek when the finger is lifted: seeking on every
                // drag update floods the player and stutters.
                onChangeStart: (_) => _hideTimer?.cancel(),
                onChanged: (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) async {
                  await controller.seekTo(Duration(milliseconds: v.round()));
                  if (mounted) setState(() => _dragValue = null);
                  _startHideTimer();
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_formatDuration(shownPosition)} / ${_formatDuration(value.duration)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen_exit_rounded,
                      color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}