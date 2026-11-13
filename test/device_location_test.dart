import 'package:flutter_test/flutter_test.dart';
import 'package:love_in_chat/model/Request/DeviceLocationRequest.dart';
import 'package:love_in_chat/model/Request/LoginRequest.dart';

void main() {
  group('DeviceLocationRequest', () {
    test('is serialized for the backend', () {
      const location = DeviceLocationRequest(
        mapX: 11.5564,
        mapY: 104.9282,
        city: 'Phnom Penh',
        country: 'Cambodia',
      );

      expect(location.toJson(), {
        'mapX': 11.5564,
        'mapY': 104.9282,
        'city': 'Phnom Penh',
        'country': 'Cambodia',
      });
      expect(location.hasPosition, isTrue);
    });

    test('accepts a missing position', () {
      const location = DeviceLocationRequest(city: 'Phnom Penh');
      expect(location.hasPosition, isFalse);
      expect(location.toJson()['mapX'], isNull);
    });

    test('reads the backend answer', () {
      final location = DeviceLocationRequest.fromJson({
        'mapX': 11.5,
        'mapY': 104.9,
        'city': 'Phnom Penh',
        'country': 'Cambodia',
      });

      expect(location.mapX, 11.5);
      expect(location.mapY, 104.9);
      expect(location.city, 'Phnom Penh');
    });
  });

  group('LoginRequest', () {
    test('only sends the fields that are set', () {
      final request = LoginRequest(email: 'a@b.c', password: 'secret');
      expect(request.toJson(), {
        'email': 'a@b.c',
        'password': 'secret',
      });
    });

    test('sends the location and the device name', () {
      final request = LoginRequest(
        email: 'a@b.c',
        password: 'secret',
        location: const DeviceLocationRequest(mapX: 1, mapY: 2),
        deviceName: 'Samsung SM-G991B',
        deviceType: 'ANDROID',
      );

      final json = request.toJson();
      expect(json['location'], isNotNull);
      expect((json['location'] as Map)['mapX'], 1.0);
      expect(json['deviceName'], 'Samsung SM-G991B');
      expect(json['deviceType'], 'ANDROID');
    });
  });
}
