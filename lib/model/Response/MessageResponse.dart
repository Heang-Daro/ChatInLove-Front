import '../emun/MessageType.dart';
import '../../api/api.dart';

class MessageResponse {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderUsername;
  final MessageType type;
  final String content;
  final bool isRead;
  final DateTime? createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final String? relatedCallId;

  MessageResponse({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderUsername,
    required this.type,
    required this.content,
    required this.isRead,
    this.createdAt,
    this.editedAt,
    this.deletedAt,
    this.relatedCallId,
  });

  /// Human readable preview for chat lists / notifications.
  ///
  /// Media messages (image, voice, video, file) store a file path, never show
  /// that raw path or an `http://...` URL to the user.
  String get previewText {
    switch (type) {
      case MessageType.IMAGE:
        return "Image";
      case MessageType.VIDEO:
        return "Video";
      case MessageType.VOICE:
        return "Voice Note";
      case MessageType.FILE:
        final name = fileNameFromUrl(content);
        return name.isNotEmpty ? name : "Document";
      case MessageType.CALL:
        return "Call";
      case MessageType.SYSTEM:
      case MessageType.TEXT:
        return content;
    }
  }

  /// Absolute URL of the media, always rebuilt from the currently configured
  /// server address so changing the network/domain keeps old media working.
  String get mediaUrl => resolveFileUrl(content);

  factory MessageResponse.fromJson(Map<String, dynamic> json) {
    // Safely parse String type into MessageType enum
    MessageType parsedType = MessageType.TEXT; // Default fallback
    if (json['type'] is String) {
      final typeStr = (json['type'] as String).toLowerCase();
      parsedType = MessageType.values.firstWhere(
            (e) => e.name.toLowerCase() == typeStr,
        orElse: () => MessageType.TEXT,
      );
    }

    return MessageResponse(
      id: json['id'] ?? '',
      conversationId: json['conversationId'] ?? '',
      senderId: json['senderId'] ?? '',
      senderUsername: json['senderUsername'] ?? '',
      type: parsedType,
      content: json['content'] ?? '',
      isRead: json['isRead'] ?? false,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']).toUtc() : null,
      editedAt: json['editedAt'] != null ? DateTime.parse(json['editedAt']).toUtc() : null,
      deletedAt: json['deletedAt'] != null ? DateTime.parse(json['deletedAt']).toUtc() : null,
      relatedCallId: json['relatedCallId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'senderId': senderId,
      'senderUsername': senderUsername,
      'type': type.name, // Convert enum back to string format for serialization
      'content': content,
      'isRead': isRead,
      'createdAt': createdAt?.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'relatedCallId': relatedCallId,
    };
  }
}