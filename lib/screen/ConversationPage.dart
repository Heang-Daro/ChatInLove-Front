import 'dart:async';
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
import 'message/message_shortcuts.dart';

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
  // Use ShortcutTextController so valid #keys are highlighted while typing.
  final ShortcutTextController _messageController = ShortcutTextController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _isRecording = false;
  DateTime? _lastTypingEventTime;

  // Live amplitude stream for the waveform in the input bar.
  StreamController<double>? _amplitudeController;
  Timer? _amplitudeTicker;

  // ── #loop macro state ─────────────────────────────────────────────────────
  bool _loopRunning   = false;
  bool _loopCancelled = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onTextChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final provider = context.read<ConversationProvider>();
      provider.fetchMessages(auth, widget.conversationId);
    });
  }

  void _onScroll() {
    // When scrolling near the top of the reverse ListView (which is maxScrollExtent)
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final auth = context.read<AuthProvider>();
      context.read<ConversationProvider>().loadMoreMessages(auth, widget.conversationId);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0, // In reverse list, 0.0 is the latest message!
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onTextChanged() {
    final conversations = context.read<ConversationProvider>();
    if (_messageController.text.isEmpty) {
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
    _scrollController.dispose();
    _audioRecorder.dispose();
    _amplitudeTicker?.cancel();
    _amplitudeController?.close();
    super.dispose();
  }

  // ── Send message — full if/else chain ─────────────────────────────────────
  Future<void> _sendMessage() async {
    final raw = _messageController.text.trim();
    if (raw.isEmpty) return;

    // ── Branch 1: #loop macro ─────────────────────────────────────────────
    final loopMatch = RegExp(
      r'^#loop\s+(?:(\d+)\s+)?(.+)$',
      caseSensitive: false,
    ).firstMatch(raw);

    if (loopMatch != null) {
      _messageController.clear();

      if (_loopRunning) {
        // A loop is already running — cancel it instead of starting a new one.
        _loopCancelled = true;
        return;
      }

      final requestedCount = int.tryParse(loopMatch.group(1) ?? '') ?? 100;
      final count   = requestedCount.clamp(1, 100);
      // Apply any nested #shortcuts inside the loop message before repeating.
      final message = MessageShortcuts.apply(loopMatch.group(2)!.trim());

      if (message.isEmpty) return;

      _loopRunning   = true;
      _loopCancelled = false;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: StatefulBuilder(
            builder: (ctx, _) => Row(children: [
              Expanded(
                child: Text('Sending "$message" × $count…',
                    overflow: TextOverflow.ellipsis),
              ),
              TextButton(
                onPressed: () {
                  _loopCancelled = true;
                  ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
                },
                child: const Text('Cancel', style: TextStyle(color: Colors.white)),
              ),
            ]),
          ),
          duration: Duration(seconds: count * 2),
          backgroundColor: Colors.pinkAccent,
        ));
      }

      _runLoop(message, count);

    // ── Branch 2: other #shortcuts (bold, italic, code, upper, lower …) ──
    } else if (raw.contains('#') && MessageShortcuts.apply(raw) != raw) {
      // The text contains at least one valid #key{} shortcut.
      final converted = MessageShortcuts.apply(raw);
      _messageController.clear();
      _scrollToBottom();
      await context.read<ConversationProvider>().sendMessage(
        context.read<AuthProvider>(),
        widget.conversationId,
        converted,
      );

    // ── Branch 3: plain text (most common path) ───────────────────────────
    } else {
      _messageController.clear();
      _scrollToBottom();
      context.read<ConversationProvider>().sendTyping(widget.conversationId, isTyping: false);
      await context.read<ConversationProvider>().sendMessage(
        context.read<AuthProvider>(),
        widget.conversationId,
        raw,
      );
    }
  }

  // ── Loop runner ───────────────────────────────────────────────────────────
  Future<void> _runLoop(String message, int count) async {
    final auth   = context.read<AuthProvider>();
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
      ..showSnackBar(SnackBar(
        content: Text('Sent "$message" $sent time${sent == 1 ? '' : 's'}.'),
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.pinkAccent,
      ));
  }

  // ── Like button ───────────────────────────────────────────────────────────
  Future<void> _sendLike() => context.read<ConversationProvider>().sendMessage(
        context.read<AuthProvider>(),
        widget.conversationId,
        '👍',
      );

  // ── Media helpers ─────────────────────────────────────────────────────────
  Future<void> _pickMedia({
    required ImageSource source,
    required MessageType type,
  }) async {
    final file = type == MessageType.IMAGE
        ? await _picker.pickImage(source: source, imageQuality: 80)
        : await _picker.pickVideo(source: source);
    if (file == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(type == MessageType.IMAGE ? 'Uploading image…' : 'Uploading video…')),
    );

    bool success;
    if (type == MessageType.IMAGE || kIsWeb) {
      final bytes = await file.readAsBytes();
      success = await context.read<ConversationProvider>().uploadAndSendMessage(
            context.read<AuthProvider>(),
            widget.conversationId,
            bytes,
            file.name,
            overrideType: type,
          );
    } else {
      success = await context.read<ConversationProvider>().uploadResumableMedia(
            context.read<AuthProvider>(),
            widget.conversationId,
            File(file.path),
            overrideType: type,
          );
    }

    if (!mounted || success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to upload ${type == MessageType.IMAGE ? 'image' : 'video'}.')),
    );
  }

  // ── Voice recording ───────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    if (!await _audioRecorder.hasPermission()) return;

    String? path;
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }
    await _audioRecorder.start(const RecordConfig(), path: path ?? '');

    // Stream amplitude values for the live waveform.
    _amplitudeController = StreamController<double>.broadcast();
    _amplitudeTicker = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      try {
        final amp = await _audioRecorder.getAmplitude();
        if (!(_amplitudeController?.isClosed ?? true)) {
          // Normalize dBFS (-160…0) → 0…1
          final norm = ((amp.current + 160) / 160).clamp(0.0, 1.0);
          _amplitudeController?.add(norm);
        }
      } catch (_) {}
    });

    if (mounted) setState(() => _isRecording = true);
  }

  Future<void> _stopAndSendRecording() async {
    _amplitudeTicker?.cancel();
    _amplitudeController?.close();
    _amplitudeController = null;

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
    _amplitudeTicker?.cancel();
    _amplitudeController?.close();
    _amplitudeController = null;
    await _audioRecorder.stop();
    if (mounted) setState(() => _isRecording = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────
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
              ConversationBody(scrollController: _scrollController),
              ConversationInput(
                controller: _messageController,
                onSend: _sendMessage,
                onLikePressed: _sendLike,
                isRecording: _isRecording,
                amplitudeStream: _amplitudeController?.stream,
                onStartRecording: _startRecording,
                onStopAndSendRecording: _stopAndSendRecording,
                onCancelRecording: _cancelRecording,
                onSendImage: () => _pickMedia(
                    source: ImageSource.gallery, type: MessageType.IMAGE),
                onSendCamera: () => _pickMedia(
                    source: ImageSource.camera, type: MessageType.IMAGE),
                onSendVideo: () => _pickMedia(
                    source: ImageSource.gallery, type: MessageType.VIDEO),
                onSendCameraVideo: () => _pickMedia(
                    source: ImageSource.camera, type: MessageType.VIDEO),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
