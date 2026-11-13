import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../model/Request/DeviceLocationRequest.dart';

/// Collects the information about the device that is sent to the backend:
///
/// * the **name** of the device ("Samsung SM-G991B", "Chrome on Windows", ...)
/// * the **type** of the device (ANDROID / IOS / WEB / DESKTOP)
/// * the **location** of the device (latitude, longitude, city, country)
///
/// The location is only requested when the user allows it. The service never
/// throws: when the permission is missing or the position can not be read,
/// `null` is returned and the app works exactly as before.
class DeviceLocationService {
  DeviceLocationService._();

  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// The reverse geocoder of the platform (Android/iOS).
  static final Geocoding _geocoding = Geocoding();

  /// How long the app waits for a position before it gives up.
  static const Duration _positionTimeout = Duration(seconds: 12);

  /// Everything the backend needs to know about the current device.
  static Future<DeviceProfile> currentProfile({
    bool askPermission = true,
    bool includeLocation = true,
  }) async {
    final location = includeLocation
        ? await requestLocation(askPermission: askPermission)
        : null;

    return DeviceProfile(
      deviceName: await deviceName(),
      deviceType: await deviceType(),
      location: location,
    );
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  /// Asks for the permission (the first time) and reads the current position.
  ///
  /// Returns `null` when the permission was denied, the location service is
  /// switched off or the position could not be determined.
  static Future<DeviceLocationRequest?> requestLocation({
    bool askPermission = true,
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('DeviceLocationService: location service is disabled');
        return null;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied && askPermission) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('DeviceLocationService: location permission denied');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: _positionTimeout,
        ),
      );

      // The backend expects latitude in "mapX" and longitude in "mapY".
      final place = await _placemarkOf(position.latitude, position.longitude);

      return DeviceLocationRequest(
        mapX: position.latitude,
        mapY: position.longitude,
        city: place.city,
        country: place.country,
      );
    } catch (e) {
      debugPrint('DeviceLocationService: could not read the position: $e');
      return null;
    }
  }

  /// Reverse geocoding: the city and the country of a position.
  ///
  /// The platform geocoder is asked only once for both values.
  static Future<({String? city, String? country})> _placemarkOf(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await _geocoding.placemarkFromCoordinates(
        latitude,
        longitude,
      );
      if (placemarks.isEmpty) return (city: null, country: null);

      final place = placemarks.first;
      final city = place.locality ??
          place.subAdministrativeArea ??
          place.administrativeArea ??
          place.thoroughfare;

      return (
        city: _clean(city),
        country: _clean(place.country),
      );
    } catch (e) {
      debugPrint('DeviceLocationService: reverse geocoding failed: $e');
      return (city: null, country: null);
    }
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length > 120 ? trimmed.substring(0, 120) : trimmed;
  }

  // ---------------------------------------------------------------------------
  // Device name & type
  // ---------------------------------------------------------------------------

  /// A readable name of the device, e.g. "Samsung SM-G991B".
  static Future<String> deviceName() async {
    try {
      if (kIsWeb) {
        final info = await _deviceInfo.webBrowserInfo;
        final browser = info.browserName.name.toUpperCase();
        final vendor = info.vendor?.trim() ?? '';
        return vendor.isEmpty ? browser : '$vendor $browser';
      }

      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        final model = info.model.trim();
        final manufacturer = info.manufacturer.trim();
        if (model.isEmpty) return 'Android device';
        if (manufacturer.isEmpty ||
            model.toLowerCase().startsWith(manufacturer.toLowerCase())) {
          return model;
        }
        return '$manufacturer $model';
      }

      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        final name = info.name.trim();
        final model = info.model.trim();
        if (name.isEmpty && model.isEmpty) return 'iPhone';
        if (name.isEmpty || name == model) return model;
        return '$name ($model)';
      }

      // Desktop: the name of the computer.
      final host = Platform.localHostname.trim();
      return host.isEmpty ? Platform.operatingSystem : host;
    } catch (e) {
      debugPrint('DeviceLocationService: could not read the device name: $e');
      return 'Unknown device';
    }
  }

  /// The type of the device, mapped to the enum of the backend.
  ///
  /// ANDROID / IOS / WEB / DESKTOP
  static Future<String> deviceType() async {
    try {
      if (kIsWeb) return 'WEB';
      if (Platform.isAndroid) return 'ANDROID';
      if (Platform.isIOS) return 'IOS';
      return 'DESKTOP';
    } catch (_) {
      return 'DESKTOP';
    }
  }
}

/// The profile of the current device, sent to the backend.
class DeviceProfile {
  final String deviceName;
  final String deviceType;
  final DeviceLocationRequest? location;

  const DeviceProfile({
    required this.deviceName,
    required this.deviceType,
    this.location,
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceName': deviceName,
      'deviceType': deviceType,
      if (location != null) 'location': location!.toJson(),
    };
  }
}
