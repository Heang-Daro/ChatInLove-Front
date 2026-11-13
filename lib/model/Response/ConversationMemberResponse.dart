class ConversationMemberResponse {
  final String userId;
  final String username;
  final String role; // Can be mapped to an enum if you have a ConversationMemberRole enum defined in Dart
  final DateTime? joinedAt;
  final DateTime? leftAt;

  ConversationMemberResponse({
    required this.userId,
    required this.username,
    required this.role,
    this.joinedAt,
    this.leftAt,
  });

  factory ConversationMemberResponse.fromJson(Map<String, dynamic> json) {
    return ConversationMemberResponse(
      userId: json['userId'] ?? '',
      username: json['username'] ?? '',
      role: json['role'] ?? '',
      joinedAt: json['joinedAt'] != null ? DateTime.parse(json['joinedAt']) : null,
      leftAt: json['leftAt'] != null ? DateTime.parse(json['leftAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'role': role,
      'joinedAt': joinedAt?.toIso8601String(),
      'leftAt': leftAt?.toIso8601String(),
    };
  }
}