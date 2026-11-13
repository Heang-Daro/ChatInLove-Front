import 'DeviceLocationRequest.dart';

/// Login payload.
///
/// Mirrors the backend DTO:
/// ```java
/// public record LoginRequest(
///         @NotBlank String email,
///         @NotBlank String password,
///         @Valid DeviceLocationRequest location,
///         @Size(max = 120) String deviceName,
///         DeviceType deviceType
/// ) {}
/// ```
class LoginRequest {
  final String email;
  final String password;

  /// Optional location of the device, captured when the app is opened.
  final DeviceLocationRequest? location;

  /// Optional name of the device ("Samsung SM-G991B").
  final String? deviceName;

  /// Optional type of the device (ANDROID / IOS / WEB / DESKTOP).
  final String? deviceType;

  LoginRequest({
    required this.email,
    required this.password,
    this.location,
    this.deviceName,
    this.deviceType,
  });

  factory LoginRequest.fromJson(Map<String, dynamic> json) {
    return LoginRequest(
      email: json['email'] ?? '',
      password: json['password'] ?? '',
      location: json['location'] == null
          ? null
          : DeviceLocationRequest.fromJson(
              Map<String, dynamic>.from(json['location'] as Map)),
      deviceName: json['deviceName'],
      deviceType: json['deviceType'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
      if (location != null) 'location': location!.toJson(),
      if (deviceName != null) 'deviceName': deviceName,
      if (deviceType != null) 'deviceType': deviceType,
    };
  }
}
