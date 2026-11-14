import '../emun/ConversationStatus.dart';
import '../emun/ConversationType.dart';
import 'ConversationMemberResponse.dart';
import 'MessageResponse.dart';

class ConversationResponse {
  final String id;
  final ConversationType type;
  final String? name;
  final String? description;
  final DateTime? createdAt;
  final DateTime? lastMessageAt;
  final List<ConversationMemberResponse> members;
  final MessageResponse? lastMessage;
  final ConversationStatus status;
  final String? requesterId;

  ConversationResponse({
    required this.id,
    required this.type,
    this.name,
    this.description,
    this.createdAt,
    this.lastMessageAt,
    required this.members,
    this.lastMessage,
    this.status = ConversationStatus.ACCEPTED,
    this.requesterId,
  });

  factory ConversationResponse.fromJson(Map<String, dynamic> json) {
    return ConversationResponse(
      id: json['id'] ?? '',
      type: json['type'] is String
          ? ConversationType.values.firstWhere(
              (e) => e.name.toUpperCase() == (json['type'] as String).toUpperCase(),
              orElse: () => ConversationType.PRIVATE,
            )
          : ConversationType.GROUP,
      name: json['name'],
      description: json['description'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']).toUtc() : null,
      lastMessageAt: json['lastMessageAt'] != null ? DateTime.parse(json['lastMessageAt']).toUtc() : null,
      members: json['members'] != null
          ? (json['members'] as List)
              .map((e) => ConversationMemberResponse.fromJson(e))
              .toList()
          : [],
      lastMessage: json['lastMessage'] != null
          ? MessageResponse.fromJson(json['lastMessage'])
          : null,
      status: ConversationStatus.fromJson(json['status']),
      requesterId: json['requesterId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'name': name,
      'description': description,
      'createdAt': createdAt?.toIso8601String(),
      'lastMessageAt': lastMessageAt?.toIso8601String(),
      'members': members.map((e) => e.toJson()).toList(),
      'lastMessage': lastMessage?.toJson(),
      'status': status.name,
      'requesterId': requesterId,
    };
  }
}
