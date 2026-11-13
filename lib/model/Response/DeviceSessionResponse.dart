/// A device session (an active login) of the current account.
///
/// Mirrors the backend record `DeviceSessionResponse`:
/// ```java
/// @Builder
/// public record DeviceSessionResponse(
///         String id,
///         String deviceName,
///         DeviceType deviceType,
///         String ipAddress,
///         Double mapX,
///         Double mapY,
///         String city,
///         String country,
///         LocalDateTime locationUpdatedAt,
///         LocalDateTime lastActiveAt,
///         LocalDateTime expiresAt,
///         boolean revoked,
///         boolean currentDevice   // <- is this the device of the request?
/// ) {}
/// ```
class DeviceSessionResponse {
  final String id;
  final String deviceName;
  final String deviceType; // Can be mapped to an enum if needed
  final String ipAddress;

  /// Latitude of the device (null when the device did not report a position).
  final double? mapX;

  /// Longitude of the device.
  final double? mapY;

  /// City of the last known position.
  final String? city;

  /// Country of the last known position.
  final String? country;

  /// When the position was refreshed the last time.
  final DateTime? locationUpdatedAt;

  final DateTime? lastActiveAt;
  final DateTime? expiresAt;
  final bool revoked;

  /// True when this session is the one that sent the request, in other words
  /// the device the user is currently using.
  final bool currentDevice;

  DeviceSessionResponse({
    required this.id,
    required this.deviceName,
    required this.deviceType,
    required this.ipAddress,
    this.mapX,
    this.mapY,
    this.city,
    this.country,
    this.locationUpdatedAt,
    this.lastActiveAt,
    this.expiresAt,
    required this.revoked,
    this.currentDevice = false,
  });

  factory DeviceSessionResponse.fromJson(Map<String, dynamic> json) {
    return DeviceSessionResponse(
      id: json['id'] ?? '',
      deviceName: json['deviceName'] ?? '',
      deviceType: json['deviceType'] ?? '',
      ipAddress: json['ipAddress'] ?? '',
      mapX: _parseDouble(json['mapX']),
      mapY: _parseDouble(json['mapY']),
      city: json['city'],
      country: json['country'],
      locationUpdatedAt: _parseDate(json['locationUpdatedAt']),
      lastActiveAt: _parseDate(json['lastActiveAt']),
      expiresAt: _parseDate(json['expiresAt']),
      revoked: json['revoked'] ?? false,
      currentDevice: json['currentDevice'] ?? false,
    );
  }

  /// True when the device reported a position that can be shown on a map.
  bool get hasLocation => mapX != null && mapY != null;

  /// "Phnom Penh, Cambodia" (falls back to the coordinates or a placeholder).
  String get locationLabel {
    final parts = <String>[
      if (city != null && city!.trim().isNotEmpty) city!.trim(),
      if (country != null && country!.trim().isNotEmpty) country!.trim(),
    ];
    if (parts.isEmpty) {
      return hasLocation
          ? '${mapX!.toStringAsFixed(4)}, ${mapY!.toStringAsFixed(4)}'
          : 'Location unknown';
    }
    return parts.join(', ');
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Accepts both ISO-8601 strings and Jackson's "timestamps" arrays
  /// (`[2026, 11, 10, 8, 30, 0]`), so it works no matter how the backend
  /// serializes `LocalDateTime`.
  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    if (value is List && value.length >= 3) {
      List<int> parts = value.map((e) => (e as num).toInt()).toList();
      while (parts.length < 6) {
        parts.add(0);
      }
      return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceName': deviceName,
      'deviceType': deviceType,
      'ipAddress': ipAddress,
      'mapX': mapX,
      'mapY': mapY,
      'city': city,
      'country': country,
      'locationUpdatedAt': locationUpdatedAt?.toIso8601String(),
      'lastActiveAt': lastActiveAt?.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'revoked': revoked,
      'currentDevice': currentDevice,
    };
  }
}
