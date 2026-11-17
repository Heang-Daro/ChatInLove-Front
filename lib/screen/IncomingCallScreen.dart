import 'dart:async';
import 'package:flutter/material.dart';

import 'package:love_in_chat/service/CallKitService.dart';
import 'package:love_in_chat/service/CallRingtoneService.dart';
import 'package:love_in_chat/service/CallSignalingService.dart';
import 'CallScreen.dart';

/// Ringing / incoming-call overlay shown to the callee (foreground fallback).
///
/// Pass [cancelStream] so the screen closes automatically if the caller hangs
/// up before the callee answers. Wire it from wherever you handle the
/// "call cancelled / hangup" signal, e.g. a StreamController you feed from
/// your STOMP listener:
///
///   IncomingCallScreen(
///     offer: offer,
///     callerName: name,
///     signalingService: signaling,
///     cancelStream: cancelController.stream,
///   )
class IncomingCallScreen extends StatefulWidget {
  final Map<String, dynamic> offer;
  final String callerName;
  final CallSignalingService signalingService;

  /// Emits an event when the caller cancels. Optional.
  final Stream<void>? cancelStream;

  const IncomingCallScreen({
    super.key,
    required this.offer,
    required this.callerName,
    required this.signalingService,
    this.cancelStream,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  bool _handled = false;
  StreamSubscription<void>? _cancelSub;

  bool get _isVideo =>
      widget.offer['callType']?.toString().toUpperCase() == 'VIDEO';

  String get _sessionId =>
      widget.offer['callSessionId']?.toString() ??
          widget.offer['callId']?.toString() ??
          '';

  @override
  void initState() {
    super.initState();
    CallRingtoneService.playRingtone();

    _cancelSub = widget.cancelStream?.listen((_) {
      if (_handled || !mounted) return;
      _handled = true;
      CallRingtoneService.stop();
      Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _cancelSub?.cancel();
    CallRingtoneService.stop();
    super.dispose();
  }

  void _decline() {
    if (_handled) return;
    _handled = true;
    CallRingtoneService.stop();

    // Capture before popping; don't touch widget/context afterwards.
    final offer = widget.offer;
    final signaling = widget.signalingService;
    final sessionId = _sessionId;

    if (mounted) Navigator.of(context).pop();

    // Same endpoint CallKit uses; fall back to signaling only if REST fails.
    unawaited(() async {
      final ok = await CallKitService.postCallAction('reject', sessionId);
      if (!ok) signaling.rejectCall(offer);
    }());
  }

  void _accept() {
    if (_handled) return;
    _handled = true;
    CallRingtoneService.stop();

    // Tell the server immediately so the caller stops ringing,
    // without blocking navigation on the network.
    unawaited(CallKitService.postCallAction('accept', _sessionId));

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          remoteUserId: widget.offer['fromUserId']?.toString() ?? '',
          remoteName: widget.callerName,
          conversationId: widget.offer['conversationId']?.toString() ?? '',
          isVideo: _isVideo,
          incomingOffer: widget.offer,
          signalingService: widget.signalingService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // System back = decline, so the caller isn't left ringing.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _decline();
      },
      child: Scaffold(
        backgroundColor: Colors.black87,
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 48),
              Column(children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.pinkAccent.withValues(alpha: 0.2),
                  child: Text(
                    widget.callerName.isNotEmpty
                        ? widget.callerName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        fontSize: 48,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 20),
                Text(widget.callerName,
                    style: const TextStyle(
                        fontSize: 26,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_isVideo ? Icons.videocam : Icons.call,
                      color: Colors.white60, size: 18),
                  const SizedBox(width: 6),
                  Text(
                      _isVideo ? 'Incoming video call' : 'Incoming voice call',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 15)),
                ]),
              ]),
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallButton(
                      icon: Icons.call_end,
                      label: 'Decline',
                      color: Colors.redAccent,
                      onTap: _decline,
                    ),
                    _CallButton(
                      icon: _isVideo ? Icons.videocam : Icons.call,
                      label: 'Accept',
                      color: Colors.pinkAccent,
                      onTap: _accept,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    ),
  );
}