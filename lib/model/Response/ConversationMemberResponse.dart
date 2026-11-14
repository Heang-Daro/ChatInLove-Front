class ConversationMemberResponse {
  final String userId;
  final String username;
  final String role;
  final DateTime? joinedAt;
  final DateTime? leftAt;
  final String? profileImageUrl;

  ConversationMemberResponse({
    required this.userId,
    required this.username,
    required this.role,
    this.joinedAt,
    this.leftAt,
    this.profileImageUrl,
  });

  factory ConversationMemberResponse.fromJson(Map<String, dynamic> json) {
    return ConversationMemberResponse(
      userId: json['userId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      joinedAt: json['joinedAt'] != null ? DateTime.parse(json['joinedAt']) : null,
      leftAt: json['leftAt'] != null ? DateTime.parse(json['leftAt']) : null,
      profileImageUrl: json['profileImageUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'role': role,
      'joinedAt': joinedAt?.toIso8601String(),
      'leftAt': leftAt?.toIso8601String(),
      'profileImageUrl': profileImageUrl,
    };
  }
}
