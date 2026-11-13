import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Chat input bar.
///  - Voice note : tap the mic to START recording, tap the send button (or the
///                 mic again) to STOP and send, tap the bin to cancel.
///                 Click-based so it works on web as well as on mobile
///                 (hold-to-record does not work with a mouse).
///  - Attach     : Telegram-style grid sheet + location sheet
///                 (current / live / pick on map).
class ConversationInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onLikePressed;

  /// Optional. UI state is handled internally; if the parent sets this back
  /// to false while recording (e.g. recorder error), the UI resets.
  final bool isRecording;

  /// Optional 0..1 amplitude stream from your recorder for a real waveform.
  /// If null, a simulated waveform is shown.
  final Stream<double>? amplitudeStream;

  // Voice recording callbacks
  final Future<void> Function()? onStartRecording;
  final Future<void> Function()? onStopAndSendRecording;
  final Future<void> Function()? onCancelRecording;

  // Media attachment callbacks
  final VoidCallback? onSendImage; // Photo from gallery
  final VoidCallback? onSendCamera; // Take photo with the camera
  final VoidCallback? onSendVideo; // Video from gallery
  final VoidCallback? onSendCameraVideo; // Record video with the camera
  final VoidCallback? onSendFile;

  // Location callbacks (Telegram style)
  final VoidCallback? onSendLocation; // send current location
  final ValueChanged<Duration>? onSendLiveLocation; // 15m / 1h / 8h
  final VoidCallback? onPickLocationOnMap;

  /// Main accent color.
  final Color accentColor;

  const ConversationInput({
    super.key,
    required this.controller,
    required this.onSend,
    this.onLikePressed,
    this.isRecording = false,
    this.amplitudeStream,
    this.onStartRecording,
    this.onStopAndSendRecording,
    this.onCancelRecording,
    this.onSendImage,
    this.onSendCamera,
    this.onSendVideo,
    this.onSendCameraVideo,
    this.onSendFile,
    this.onSendLocation,
    this.onSendLiveLocation,
    this.onPickLocationOnMap,
    this.accentColor = Colors.pinkAccent,
  });

  @override
  State<ConversationInput> createState() => _ConversationInputState();
}

class _ConversationInputState extends State<ConversationInput>
    with SingleTickerProviderStateMixin {
  static const Duration _minDuration = Duration(seconds: 1);

  bool _hasText = false;

  // Recording state (click based: tap mic to start, tap stop to send)
  bool _recording = false;
  final Stopwatch _stopwatch = Stopwatch();
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);
  Timer? _ticker;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  Color _a(Color c, double opacity) => c.withAlpha((opacity * 255).round());

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _hasText = widget.controller.text.trim().isNotEmpty;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.3, end: 1.0).animate(_pulseController);
  }

  @override
  void didUpdateWidget(covariant ConversationInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    // Parent stopped recording externally (error, permission denied...)
    if (oldWidget.isRecording && !widget.isRecording && _recording) {
      _resetRecordingState();
    }
  }

  @override
  void dispose() {
    if (_recording) widget.onCancelRecording?.call();
    widget.controller.removeListener(_onTextChanged);
    _ticker?.cancel();
    _elapsed.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasTextNow = widget.controller.text.trim().isNotEmpty;
    if (hasTextNow != _hasText) setState(() => _hasText = hasTextNow);
  }

  // ───────────────────────── Voice recording (click to record) ───────────────

  Future<void> _beginRecording() async {
    HapticFeedback.mediumImpact();
    _stopwatch
      ..reset()
      ..start();
    _elapsed.value = Duration.zero;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _elapsed.value = _stopwatch.elapsed;
    });
    setState(() => _recording = true);
    try {
      await widget.onStartRecording?.call();
    } catch (_) {
      _resetRecordingState();
    }
  }

  void _resetRecordingState() {
    _ticker?.cancel();
    _stopwatch.stop();
    if (!mounted) return;
    setState(() => _recording = false);
  }

  Future<void> _finishRecording({required bool send}) async {
    if (!_recording) return;
    final elapsed = _stopwatch.elapsed;
    _resetRecordingState();

    if (send && elapsed >= _minDuration) {
      HapticFeedback.lightImpact();
      await widget.onStopAndSendRecording?.call();
    } else {
      if (send && mounted) {
        // Too short – discard and show a hint
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('Recording is too short — record at least 1 second'),
            duration: Duration(seconds: 1),
          ));
      }
      await widget.onCancelRecording?.call();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ───────────────────────── Attachments (Telegram) ─────────────────────────

  Future<void> _showSheet(BuildContext context, Widget Function(BuildContext) b) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: b,
    );
  }

  void _showAttachmentOptions(BuildContext context) {
    final items = <_AttachItem>[
      _AttachItem(Icons.photo_library_rounded, 'Gallery', const Color(0xFF2E9CEB),
          widget.onSendImage),
      _AttachItem(Icons.camera_alt_rounded, 'Camera', const Color(0xFFE5483D),
          widget.onSendCamera == null && widget.onSendCameraVideo == null
              ? null
              : () => _showCameraOptions(context)),
      _AttachItem(Icons.videocam_rounded, 'Video', const Color(0xFF8E5BD9),
          widget.onSendVideo),
      _AttachItem(Icons.insert_drive_file_rounded, 'File', const Color(0xFFF59E0B),
          widget.onSendFile),
      _AttachItem(Icons.location_on_rounded, 'Location', const Color(0xFF34B35E),
          widget.onSendLocation == null &&
              widget.onSendLiveLocation == null &&
              widget.onPickLocationOnMap == null
              ? null
              : () => _showLocationOptions(context)),
    ];

    _showSheet(context, (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 18,
            childAspectRatio: 1.05,
            children: [
              for (final it in items)
                _buildAttachmentTile(
                  item: it,
                  onTap: () {
                    Navigator.pop(ctx);
                    it.onTap?.call();
                  },
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildAttachmentTile({
    required _AttachItem item,
    required VoidCallback onTap,
  }) {
    final enabled = item.onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: item.color,
              child: Icon(item.icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            Text(item.label,
                style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  /// "Camera" opens a small sheet so the user picks photo or video capture.
  void _showCameraOptions(BuildContext context) {
    _showSheet(context, (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Camera',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            if (widget.onSendCamera != null)
              _locationTile(
                icon: Icons.photo_camera_rounded,
                color: const Color(0xFFE5483D),
                title: 'Take photo',
                subtitle: 'Capture a picture with the camera',
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onSendCamera?.call();
                },
              ),
            if (widget.onSendCameraVideo != null)
              _locationTile(
                icon: Icons.videocam_rounded,
                color: const Color(0xFF8E5BD9),
                title: 'Record video',
                subtitle: 'Capture a video with the camera',
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onSendCameraVideo?.call();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    });
  }

  void _showLocationOptions(BuildContext context) {
    final hasExtras =
        widget.onSendLiveLocation != null || widget.onPickLocationOnMap != null;
    if (!hasExtras) {
      widget.onSendLocation?.call();
      return;
    }

    _showSheet(context, (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onPickLocationOnMap != null)
              _locationTile(
                icon: Icons.map_rounded,
                color: const Color(0xFF2E9CEB),
                title: 'Pick location on map',
                subtitle: 'Search or drop a pin',
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onPickLocationOnMap?.call();
                },
              ),
            if (widget.onSendLocation != null)
              _locationTile(
                icon: Icons.my_location_rounded,
                color: const Color(0xFF34B35E),
                title: 'Send my current location',
                subtitle: 'Share where you are right now',
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onSendLocation?.call();
                },
              ),
            if (widget.onSendLiveLocation != null)
              _locationTile(
                icon: Icons.share_location_rounded,
                color: const Color(0xFFE5483D),
                title: 'Share live location',
                subtitle: 'Updates while you move',
                onTap: () {
                  Navigator.pop(ctx);
                  _showLiveDurations(context);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    });
  }

  Widget _locationTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        child: Icon(icon, color: Colors.white),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }

  void _showLiveDurations(BuildContext context) {
    const options = <MapEntry<String, Duration>>[
      MapEntry('for 15 minutes', Duration(minutes: 15)),
      MapEntry('for 1 hour', Duration(hours: 1)),
      MapEntry('for 8 hours', Duration(hours: 8)),
    ];
    _showSheet(context, (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Share live location',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final o in options)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(o.key),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onSendLiveLocation?.call(o.value);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    });
  }

  // ───────────────────────── Build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accentColor;

    return Container(
      color: Theme.of(context).cardColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: _recording
                ? _buildRecordingBar(accent)
                : _buildMainRow(isDark, accent),
          ),
        ),
      ),
    );
  }

  Widget _buildMainRow(bool isDark, Color accent) {
    return Row(
      key: const ValueKey('mainRow'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          icon: Icon(Icons.add_circle_rounded, color: accent, size: 28),
          onPressed: () => _showAttachmentOptions(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: widget.controller,
            maxLines: 4,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Aa',
              hintStyle: TextStyle(
                  color: isDark ? Colors.grey[500] : Colors.grey),
              filled: true,
              fillColor: _a(Colors.pink, isDark ? 0.1 : 0.05),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => widget.onSend(),
          ),
        ),
        const SizedBox(width: 8),

        // Mic (tap to record) – shown when there is no text
        if (!_hasText) _buildMicButton(accent),

        if (!_hasText) const SizedBox(width: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: _hasText
              ? IconButton(
            key: const ValueKey('sendButton'),
            icon: Icon(Icons.send_rounded, color: accent, size: 22),
            onPressed: widget.onSend,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          )
              : IconButton(
            key: const ValueKey('likeButton'),
            icon: Icon(Icons.thumb_up, color: accent, size: 22),
            onPressed: widget.onLikePressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
      ],
    );
  }

  /// "🗑  ● 00:03  ▂▅▇▃▅▂   [➤]" – shown while recording (click based:
  /// tap the bin to cancel, tap the send button to stop & send).
  Widget _buildRecordingBar(Color accent) {
    return Container(
      key: const ValueKey('recordingBar'),
      height: 48,
      padding: const EdgeInsets.only(left: 4, right: 4),
      decoration: BoxDecoration(
        color: _a(accent, 0.08),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            tooltip: 'Cancel',
            onPressed: () {
              HapticFeedback.mediumImpact();
              _finishRecording(send: false);
            },
          ),
          FadeTransition(
            opacity: _pulseAnimation,
            child: const Icon(Icons.fiber_manual_record,
                color: Colors.red, size: 12),
          ),
          const SizedBox(width: 6),
          ValueListenableBuilder<Duration>(
            valueListenable: _elapsed,
            builder: (_, d, _) => Text(
              _fmt(d),
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _LiveWaveform(
              color: accent,
              amplitude: widget.amplitudeStream,
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: accent,
            shape: const CircleBorder(),
            child: Tooltip(
              message: 'Stop & send',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _finishRecording(send: true),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Mic button: TAP to start recording, tap again (or the send button in
  /// the recording bar) to stop & send. Click-based so it works on web.
  Widget _buildMicButton(Color accent) {
    return Tooltip(
      message: 'Tap to record voice',
      child: GestureDetector(
        key: const ValueKey('mic'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_recording) {
            _finishRecording(send: true);
          } else {
            _beginRecording();
          }
        },
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          scale: _recording ? 1.2 : 1.0,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _recording ? accent : Colors.transparent,
            ),
            child: Icon(
              _recording ? Icons.stop_rounded : Icons.mic,
              size: _recording ? 24 : 26,
              color: _recording ? Colors.white : accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _AttachItem(this.icon, this.label, this.color, this.onTap);
}

// ───────────────────────── Waveform ─────────────────────────

class _LiveWaveform extends StatefulWidget {
  final Color color;
  final Stream<double>? amplitude;
  const _LiveWaveform({required this.color, this.amplitude});

  @override
  State<_LiveWaveform> createState() => _LiveWaveformState();
}

class _LiveWaveformState extends State<_LiveWaveform> {
  static const int _maxBars = 40;
  final List<double> _bars = List.filled(_maxBars, 0.05, growable: true);
  final Random _rnd = Random();
  StreamSubscription<double>? _sub;
  Timer? _fake;

  @override
  void initState() {
    super.initState();
    if (widget.amplitude != null) {
      _sub = widget.amplitude!.listen(_push);
    } else {
      _fake = Timer.periodic(const Duration(milliseconds: 90),
              (_) => _push(0.15 + _rnd.nextDouble() * 0.85));
    }
  }

  void _push(double v) {
    if (!mounted) return;
    setState(() {
      _bars.removeAt(0);
      _bars.add(v.clamp(0.05, 1.0));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _fake?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: CustomPaint(
        size: Size.infinite,
        painter: _WavePainter(List.of(_bars), widget.color),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final List<double> bars;
  final Color color;
  _WavePainter(this.bars, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    final step = size.width / bars.length;
    final midY = size.height / 2;
    for (var i = 0; i < bars.length; i++) {
      final h = max(3.0, bars[i] * size.height);
      final x = step * i + step / 2;
      canvas.drawLine(Offset(x, midY - h / 2), Offset(x, midY + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}