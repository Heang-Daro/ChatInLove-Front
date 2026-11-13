import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import 'package:love_in_chat/model/emun/MessageType.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';

import 'message/ConversationBody.dart';
import 'message/ConversationHeader.dart';
import 'message/ConversationInput.dart';

import 'package:flutter/foundation.dart'; // for kIsWeb

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
  String? _currentRecordingPath;

  @override
  void initState() {
    super.initState();

    _messageController.addListener(_onTextChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);

      conversationProvider.fetchMessages(authProvider, widget.conversationId);
    });
  }

  void _onTextChanged() {
    final text = _messageController.text;
    final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
    if (text.isNotEmpty) {
      final now = DateTime.now();
      if (_lastTypingEventTime == null ||
          now.difference(_lastTypingEventTime!) > const Duration(seconds: 2)) {
        _lastTypingEventTime = now;
        conversationProvider.sendTyping(widget.conversationId, isTyping: true);
      }
    } else {
      conversationProvider.sendTyping(widget.conversationId, isTyping: false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);

    // Stop typing notification immediately when sending
    conversationProvider.sendTyping(widget.conversationId, isTyping: false);

    await conversationProvider.sendMessage(authProvider, widget.conversationId, text);
  }

  // --- Like Button Action (Messenger Thumbs Up) ---
  void _sendLike() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);

    // Sends a thumbs-up emoji or custom text action
    await conversationProvider.sendMessage(authProvider, widget.conversationId, "👍");
  }

  // --- Web & Mobile Safe Image Picker ---
  Future<void> _handlePickImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      final Uint8List fileBytes = await pickedFile.readAsBytes();
      final String fileName = pickedFile.name;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading image...')),
      );

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final convoProvider = Provider.of<ConversationProvider>(context, listen: false);

      final success = await convoProvider.uploadAndSendMessage(
        authProvider,
        widget.conversationId,
        fileBytes,
        fileName,
        overrideType: MessageType.IMAGE,
      );

      if (!mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload image.')),
        );
      }
    }
  }

  // --- Web & Mobile Safe Video Picker ---
  Future<void> _handlePickVideo() async {
    final XFile? pickedFile = await _picker.pickVideo(
      source: ImageSource.gallery,
    );

    if (pickedFile != null) {
      final Uint8List fileBytes = await pickedFile.readAsBytes();
      final String fileName = pickedFile.name;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading video...')),
      );

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final convoProvider = Provider.of<ConversationProvider>(context, listen: false);

      final success = await convoProvider.uploadAndSendMessage(
        authProvider,
        widget.conversationId,
        fileBytes,
        fileName,
        overrideType: MessageType.VIDEO,
      );

      if (!mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload video.')),
        );
      }
    }
  }

  // --- Camera: take a photo (mobile opens camera; web uses capture input) ---
  Future<void> _handleTakePhoto() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );
      if (pickedFile == null) return;

      final Uint8List fileBytes = await pickedFile.readAsBytes();
      final String fileName = pickedFile.name;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading photo...')),
      );

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final convoProvider = Provider.of<ConversationProvider>(context, listen: false);

      final success = await convoProvider.uploadAndSendMessage(
        authProvider,
        widget.conversationId,
        fileBytes,
        fileName,
        overrideType: MessageType.IMAGE,
      );

      if (!mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload photo.')),
        );
      }
    } catch (e) {
      debugPrint('Camera photo failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the camera.')),
      );
    }
  }

  // --- Camera: record a video (mobile opens camera; web uses capture input) ---
  Future<void> _handleRecordVideoFromCamera() async {
    try {
      final XFile? pickedFile = await _picker.pickVideo(
        source: ImageSource.camera,
      );
      if (pickedFile == null) return;

      final Uint8List fileBytes = await pickedFile.readAsBytes();
      final String fileName = pickedFile.name;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading video...')),
      );

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final convoProvider = Provider.of<ConversationProvider>(context, listen: false);

      final success = await convoProvider.uploadAndSendMessage(
        authProvider,
        widget.conversationId,
        fileBytes,
        fileName,
        overrideType: MessageType.VIDEO,
      );

      if (!mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload video.')),
        );
      }
    } catch (e) {
      debugPrint('Camera video failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the camera.')),
      );
    }
  }

  // --- Voice Recorder Handlers (Click-to-Record Workflow) ---
  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      String? filePath;
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }

      await _audioRecorder.start(
        const RecordConfig(),
        path: filePath ?? '',
      );
      setState(() {
        _isRecording = true;
        _currentRecordingPath = filePath;
      });
    }
  }

  Future<void> _stopAndSendRecording() async {
    final pathOrBlobUrl = await _audioRecorder.stop();
    setState(() => _isRecording = false);

    if (pathOrBlobUrl != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading voice message...')),
      );

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final convoProvider = Provider.of<ConversationProvider>(context, listen: false);

      Uint8List voiceBytes;
      if (kIsWeb) {
        final res = await http.get(Uri.parse(pathOrBlobUrl));
        voiceBytes = res.bodyBytes;
      } else {
        voiceBytes = await File(pathOrBlobUrl).readAsBytes();
      }

      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      final success = await convoProvider.uploadAndSendMessage(
        authProvider,
        widget.conversationId,
        voiceBytes,
        fileName,
        overrideType: MessageType.VOICE,
      );

      if (!mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload voice message.')),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    await _audioRecorder.stop();
    setState(() => _isRecording = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice recording cancelled.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ConversationHeader(
        conversationId: widget.conversationId,
        chatName: widget.chatName,
        avatar: widget.avatar,
        isGroup: widget.isGroup,
      ),
      body: Column(
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
            onSendImage: _handlePickImage,
            onSendCamera: _handleTakePhoto,
            onSendVideo: _handlePickVideo,
            onSendCameraVideo: _handleRecordVideoFromCamera,
          ),
        ],
      ),
    );
  }
}