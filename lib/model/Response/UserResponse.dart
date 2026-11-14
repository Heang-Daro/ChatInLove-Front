class UserResponse {
  final String id;
  final String username;
  final String email;
  final String? profileImageUrl;
  final String? foregroundImageUrl;

  const UserResponse({
    required this.id,
    required this.username,
    required this.email,
    this.profileImageUrl,
    this.foregroundImageUrl,
  });

  factory UserResponse.fromJson(Map<String, dynamic> json) {
    return UserResponse(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      profileImageUrl: json['profileImageUrl']?.toString(),
      foregroundImageUrl: json['foregroundImageUrl']?.toString(),
    );
  }

  UserResponse copyWith({
    String? id,
    String? username,
    String? email,
    String? profileImageUrl,
    String? foregroundImageUrl,
  }) => UserResponse(
        id: id ?? this.id,
        username: username ?? this.username,
        email: email ?? this.email,
        profileImageUrl: profileImageUrl ?? this.profileImageUrl,
        foregroundImageUrl: foregroundImageUrl ?? this.foregroundImageUrl,
      );
}
