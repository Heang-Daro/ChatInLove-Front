import 'package:flutter_test/flutter_test.dart';
import 'package:love_in_chat/service/storage_calculator.dart';

void main() {
  group('StorageCalculator.formatBytes', () {
    test('formats bytes', () {
      expect(StorageCalculator.formatBytes(0), '0 B');
      expect(StorageCalculator.formatBytes(512), '512 B');
    });

    test('formats kilobytes', () {
      expect(StorageCalculator.formatBytes(1024), '1.0 KB');
      expect(StorageCalculator.formatBytes(1536), '1.5 KB');
      expect(StorageCalculator.formatBytes(1024 * 1024), '1.0 MB');
    });

    test('formats megabytes and gigabytes', () {
      expect(StorageCalculator.formatBytes(120 * 1024 * 1024), '120 MB');
      expect(StorageCalculator.formatBytes(450 * 1024 * 1024), '450 MB');
      expect(StorageCalculator.formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
    });
  });

  group('StorageCategory', () {
    test('every category has a title', () {
      for (final category in StorageCategory.values) {
        expect(category.title, isNotEmpty);
      }
    });
  });
}
