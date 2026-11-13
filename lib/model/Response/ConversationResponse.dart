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

  ConversationResponse({
    required this.id,
    required this.type,
    this.name,
    this.description,
    this.createdAt,
    this.lastMessageAt,
    required this.members,
    this.lastMessage,
  });

  factory ConversationResponse.fromJson(Map<String, dynamic> json) {
    return ConversationResponse(
      id: json['id'] ?? '',
      // Safely parse the String type from JSON into the ConversationType enum
      type: json['type'] is String
          ? ConversationType.values.firstWhere(
            (e) => e.name.toUpperCase() == (json['type'] as String).toUpperCase(),
        orElse: () => ConversationType.PRIVATE, // Adjust fallback name if needed (e.g. PRIVATE)
      )
          : json['type'] ?? ConversationType.GROUP,
      name: json['name'],
      description: json['description'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      lastMessageAt: json['lastMessageAt'] != null ? DateTime.parse(json['lastMessageAt']) : null,
      members: json['members'] != null
          ? (json['members'] as List)
          .map((e) => ConversationMemberResponse.fromJson(e))
          .toList()
          : [],
      lastMessage: json['lastMessage'] != null
          ? MessageResponse.fromJson(json['lastMessage'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name, // Serialize enum name cleanly back to string
      'name': name,
      'description': description,
      'createdAt': createdAt?.toIso8601String(),
      'lastMessageAt': lastMessageAt?.toIso8601String(),
      'members': members.map((e) => e.toJson()).toList(),
      'lastMessage': lastMessage?.toJson(),
    };
  }
}