import 'package:flutter_test/flutter_test.dart';
import 'package:love_in_chat/model/Response/DeviceSessionResponse.dart';

void main() {
  group('DeviceSessionResponse.fromJson', () {
    test('reads the location fields', () {
      final device = DeviceSessionResponse.fromJson({
        'id': 's1',
        'deviceName': 'Anna iPhone',
        'deviceType': 'IOS',
        'ipAddress': '203.0.113.7',
        'mapX': 11.5564,
        'mapY': 104.9282,
        'city': 'Phnom Penh',
        'country': 'Cambodia',
        'locationUpdatedAt': '2026-11-12T08:30:00',
        'lastActiveAt': '2026-11-12T09:00:00',
        'expiresAt': '2026-11-19T09:00:00',
        'revoked': false,
        'currentDevice': true,
      });

      expect(device.id, 's1');
      expect(device.mapX, 11.5564);
      expect(device.mapY, 104.9282);
      expect(device.city, 'Phnom Penh');
      expect(device.country, 'Cambodia');
      expect(device.hasLocation, isTrue);
      expect(device.currentDevice, isTrue);
      expect(device.locationLabel, 'Phnom Penh, Cambodia');
    });

    test('accepts integers and strings for the coordinates', () {
      final device = DeviceSessionResponse.fromJson({
        'id': 's2',
        'deviceName': 'Chrome',
        'deviceType': 'WEB',
        'ipAddress': '10.0.0.2',
        'mapX': 12,
        'mapY': '104.5',
        'revoked': false,
      });

      expect(device.mapX, 12.0);
      expect(device.mapY, 104.5);
    });

    test('survives a device without any location', () {
      final device = DeviceSessionResponse.fromJson({
        'id': 's3',
        'deviceName': 'Unknown',
        'deviceType': 'DESKTOP',
        'ipAddress': '10.0.0.3',
        'revoked': false,
      });

      expect(device.hasLocation, isFalse);
      expect(device.locationLabel, 'Location unknown');
      expect(device.currentDevice, isFalse);
    });

    test('parses Jackson timestamp arrays', () {
      final device = DeviceSessionResponse.fromJson({
        'id': 's4',
        'deviceName': 'Old client',
        'deviceType': 'ANDROID',
        'ipAddress': '10.0.0.4',
        'lastActiveAt': [2026, 11, 10, 8, 30, 0],
        'revoked': false,
      });

      expect(device.lastActiveAt, DateTime(2026, 11, 10, 8, 30));
    });
  });
}
