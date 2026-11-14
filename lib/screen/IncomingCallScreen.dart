import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/emun/MessageType.dart' as app_msg;
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/service/CallSignalingService.dart';
import 'CallScreen.dart';

/// Ringing / incoming-call overlay shown to the callee.
class IncomingCallScreen extends StatelessWidget {
  final Map<String, dynamic> offer;
  final String callerName;
  final CallSignalingService signalingService;

  const IncomingCallScreen({
    super.key,
    required this.offer,
    required this.callerName,
    required this.signalingService,
  });

  bool get _isVideo => offer['callType']?.toString().toUpperCase() == 'VIDEO';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ── Caller info ───────────────────────────────────────────────
            const SizedBox(height: 48),
            Column(children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: Colors.pinkAccent.withValues(alpha: 0.2),
                child: Text(
                  callerName.isNotEmpty ? callerName[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 48, color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),
              Text(callerName,
                  style: const TextStyle(fontSize: 26, color: Colors.white,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_isVideo ? Icons.videocam : Icons.call,
                    color: Colors.white60, size: 18),
                const SizedBox(width: 6),
                Text(_isVideo ? 'Incoming video call' : 'Incoming voice call',
                    style: const TextStyle(color: Colors.white60, fontSize: 15)),
              ]),
            ]),

            // ── Accept / Decline buttons ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline
                  _CallButton(
                    icon: Icons.call_end,
                    label: 'Decline',
                    color: Colors.redAccent,
                    onTap: () async {
                      signalingService.rejectCall(offer);
                      // Send a "missed call" message into the conversation.
                      final convId = offer['conversationId']?.toString() ?? '';
                      if (convId.isNotEmpty) {
                        try {
                          final auth = context.read<AuthProvider>();
                          final convos = context.read<ConversationProvider>();
                          final kind = _isVideo ? 'VIDEO' : 'AUDIO';
                          await convos.sendMessage(
                            auth, convId, '$kind:MISSED',
                            type: app_msg.MessageType.CALL,
                          );
                        } catch (_) {}
                      }
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                  // Accept
                  _CallButton(
                    icon: Icons.call,
                    label: 'Accept',
                    color: Colors.green,
                    onTap: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => CallScreen(
                            remoteUserId:   offer['fromUserId']?.toString() ?? '',
                            remoteName:     callerName,
                            conversationId: offer['conversationId']?.toString() ?? '',
                            isVideo:        _isVideo,
                            incomingOffer:  offer,
                            signalingService: signalingService,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
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

  const _CallButton(
      {required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
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
      );
}
