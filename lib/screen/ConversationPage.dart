import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import 'package:love_in_chat/model/emun/MessageType.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import '../service/ChatAppearanceService.dart';
import 'message/ConversationBody.dart';
import 'message/ConversationHeader.dart';
import 'message/ConversationInput.dart';

class ConversationPage extends StatefulWidget {
  final String conversationId;
  final String chatName;
  final IconData avatar;
  final bool isGroup;

  const ConversationPage({
    super.key,
    required this.conversationId,
    required this.chatName,
    required this.avatar,
    this.isGroup = false,
  });

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _isRecording = false;
  DateTime? _lastTypingEventTime;

  // ── #loop macro state ─────────────────────────────────────────────────────
  bool _loopRunning = false;
  bool _loopCancelled = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      context.read<ConversationProvider>().fetchMessages(auth, widget.conversationId);
    });
  }

  void _onTextChanged() {
    final conversations = context.read<ConversationProvider>();
    if (_messageController.text.isEmpty) {
      conversations.sendTyping(widget.conversationId, isTyping: false);
      return;
    }

    final now = DateTime.now();
    if (_lastTypingEventTime == null ||
        now.difference(_lastTypingEventTime!) > const Duration(seconds: 2)) {
      _lastTypingEventTime = now;
      conversations.sendTyping(widget.conversationId, isTyping: true);
    }
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    // ── #loop macro interception ──────────────────────────────────────────
    // Syntax: #loop [count] <message>
    //   #loop Hello               → sends "Hello" 100 times
    //   #loop 50 Hello            → sends "Hello" 50 times
    //   #loop 200 Hello           → capped to 100, sends "Hello" 100 times
    final loopMatch = RegExp(
      r'^#loop\s+(?:(\d+)\s+)?(.+)$',
      caseSensitive: false,
    ).firstMatch(text);

    if (loopMatch != null) {
      _messageController.clear(); // remove #loop from input immediately

      if (_loopRunning) {
        // A loop is already in progress — cancel it.
        _loopCancelled = true;
        return;
      }

      final requestedCount = int.tryParse(loopMatch.group(1) ?? '') ?? 100;
      final count   = requestedCount.clamp(1, 100);
      final message = loopMatch.group(2)!.trim();

      if (message.isEmpty) return;

      _loopRunning   = true;
      _loopCancelled = false;

      // Show a persistent snackbar so the user can cancel.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: StatefulBuilder(
              builder: (ctx, setSnack) => Row(children: [
                Expanded(
                  child: Text(
                    'Sending "$message" × $count…',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _loopCancelled = true;
                    ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
                  },
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white)),
                ),
              ]),
            ),
            duration: Duration(seconds: count * 2), // generous upper bound
            backgroundColor: Colors.pinkAccent,
          ),
        );
      }

      _runLoop(message, count);
      return;
    }
    // ── Normal send ───────────────────────────────────────────────────────
    _messageController.clear();
    final conversations = context.read<ConversationProvider>();
    conversations.sendTyping(widget.conversationId, isTyping: false);
    await conversations.sendMessage(
      context.read<AuthProvider>(),
      widget.conversationId,
      text,
    );
  }

  /// Sends [message] up to [count] times with a 150 ms gap.
  /// Runs entirely in the background — the UI stays responsive.
  Future<void> _runLoop(String message, int count) async {
    final auth  = context.read<AuthProvider>();
    final convos = context.read<ConversationProvider>();
    int sent = 0;

    for (var i = 0; i < count; i++) {
      if (_loopCancelled || !mounted) break;
      await convos.sendMessage(auth, widget.conversationId, message);
      sent++;
      await Future.delayed(const Duration(milliseconds: 150));
    }

    if (!mounted) return;
    _loopRunning   = false;
    _loopCancelled = false;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Sent "$message" $sent time${sent == 1 ? '' : 's'}.'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.pinkAccent,
        ),
      );
  }

  Future<void> _sendLike() => context.read<ConversationProvider>().sendMessage(
        context.read<AuthProvider>(),
        widget.conversationId,
        '👍',
      );

  Future<void> _pickMedia({
    required ImageSource source,
    required MessageType type,
  }) async {
    final file = type == MessageType.IMAGE
        ? await _picker.pickImage(source: source, imageQuality: 80)
        : await _picker.pickVideo(source: source);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(type == MessageType.IMAGE ? 'Uploading image…' : 'Uploading video…')),
    );

    final success = await context.read<ConversationProvider>().uploadAndSendMessage(
          context.read<AuthProvider>(),
          widget.conversationId,
          bytes,
          file.name,
          overrideType: type,
        );
    if (!mounted || success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to upload ${type == MessageType.IMAGE ? 'image' : 'video'}.')),
    );
  }

  Future<void> _startRecording() async {
    if (!await _audioRecorder.hasPermission()) return;
    String? path;
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }
    await _audioRecorder.start(const RecordConfig(), path: path ?? '');
    if (mounted) setState(() => _isRecording = true);
  }

  Future<void> _stopAndSendRecording() async {
    final path = await _audioRecorder.stop();
    if (mounted) setState(() => _isRecording = false);
    if (path == null) return;

    final Uint8List bytes;
    if (kIsWeb) {
      final response = await http.get(Uri.parse(path));
      bytes = response.bodyBytes;
    } else {
      bytes = await File(path).readAsBytes();
    }

    if (!mounted) return;
    final success = await context.read<ConversationProvider>().uploadAndSendMessage(
          context.read<AuthProvider>(),
          widget.conversationId,
          bytes,
          'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
          overrideType: MessageType.VOICE,
        );
    if (!mounted || success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to upload voice message.')),
    );
  }

  Future<void> _cancelRecording() async {
    await _audioRecorder.stop();
    if (mounted) setState(() => _isRecording = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: ChatAppearanceService.backgroundColor,
      builder: (context, backgroundColor, _) => Scaffold(
        backgroundColor: backgroundColor,
        appBar: ConversationHeader(
          conversationId: widget.conversationId,
          chatName: widget.chatName,
          avatar: widget.avatar,
          isGroup: widget.isGroup,
        ),
        body: ColoredBox(
          color: backgroundColor,
          child: Column(
            children: [
              const ConversationBody(),
              ConversationInput(
                controller: _messageController,
                onSend: _sendMessage,
                onLikePressed: _sendLike,
                isRecording: _isRecording,
                onStartRecording: _startRecording,
                onStopAndSendRecording: _stopAndSendRecording,
                onCancelRecording: _cancelRecording,
                onSendImage: () => _pickMedia(source: ImageSource.gallery, type: MessageType.IMAGE),
                onSendCamera: () => _pickMedia(source: ImageSource.camera, type: MessageType.IMAGE),
                onSendVideo: () => _pickMedia(source: ImageSource.gallery, type: MessageType.VIDEO),
                onSendCameraVideo: () => _pickMedia(source: ImageSource.camera, type: MessageType.VIDEO),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
