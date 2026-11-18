import 'package:flutter/material.dart';
import '../screen/CallScreen.dart';
import 'CallKitService.dart';
import 'CallSignalingService.dart';

class CallOverlayController {
  static OverlayEntry? _callEntry;
  static bool isMinimized = false;
  static bool isShowing = false;

  static void showCall({
    BuildContext? context,
    required String remoteUserId,
    required String remoteName,
    required String conversationId,
    required bool isVideo,
    required CallSignalingService signalingService,
    Map<String, dynamic>? incomingOffer,
  }) {
    if (isShowing) return;

    final overlayState = navigatorKey.currentState?.overlay ??
        (context != null ? Overlay.of(context, rootOverlay: true) : null);

    if (overlayState == null) {
      debugPrint('[CallOverlay] OverlayState is null, cannot show call.');
      return;
    }

    isShowing = true;
    isMinimized = false;

    _callEntry = OverlayEntry(
      builder: (ctx) => CallScreen(
        remoteUserId: remoteUserId,
        remoteName: remoteName,
        conversationId: conversationId,
        isVideo: isVideo,
        signalingService: signalingService,
        incomingOffer: incomingOffer,
      ),
    );

    overlayState.insert(_callEntry!);
  }

  static void closeCall() {
    isShowing = false;
    isMinimized = false;
    _callEntry?.remove();
    _callEntry = null;
  }
}