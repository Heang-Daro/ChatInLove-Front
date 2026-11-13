/// The location reported by a device.
///
/// Mirrors the backend DTO:
/// ```java
/// public record DeviceLocationRequest(
///         @DecimalMin("-90.0")  @DecimalMax("90.0")  Double mapX,
///         @DecimalMin("-180.0") @DecimalMax("180.0") Double mapY,
///         @Size(max = 120) String city,
///         @Size(max = 120) String country
/// ) {}
/// ```
/// `mapX` is the latitude and `mapY` the longitude (the convention of the
/// legacy `sessions` table with its `mapx` / `mapy` columns).
class DeviceLocationRequest {
  final double? mapX;
  final double? mapY;
  final String? city;
  final String? country;

  const DeviceLocationRequest({
    this.mapX,
    this.mapY,
    this.city,
    this.country,
  });

  factory DeviceLocationRequest.fromJson(Map<String, dynamic> json) {
    return DeviceLocationRequest(
      mapX: _parseDouble(json['mapX']),
      mapY: _parseDouble(json['mapY']),
      city: json['city'],
      country: json['country'],
    );
  }

  /// True when the position can be shown on a map.
  bool get hasPosition => mapX != null && mapY != null;

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'mapX': mapX,
      'mapY': mapY,
      'city': city,
      'country': country,
    };
  }
}
