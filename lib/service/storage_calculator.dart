import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The categories the app storage is split into.
enum StorageCategory {
  /// .jpg .png .gif .webp ...
  images,

  /// .mp4 .mov .m4a .mp3 ... (videos and voice notes)
  media,

  /// .pdf .doc .zip ... (documents)
  files,

  /// The SQLite database and the cached chat history (json).
  database,

  /// Everything that does not fit into a category above.
  other,
}

/// Human readable name of a category.
extension StorageCategoryLabel on StorageCategory {
  String get title {
    switch (this) {
      case StorageCategory.images:
        return 'Images & Photos';
      case StorageCategory.media:
        return 'Videos & Media';
      case StorageCategory.files:
        return 'Files & Documents';
      case StorageCategory.database:
        return 'Text Messages & Database';
      case StorageCategory.other:
        return 'Other files';
    }
  }
}

/// One file that was found on the device.
class StorageEntry {
  final File file;
  final int bytes;
  final StorageCategory category;

  const StorageEntry({
    required this.file,
    required this.bytes,
    required this.category,
  });

  String get name {
    final parts = file.path.split(Platform.pathSeparator);
    return parts.isEmpty ? file.path : parts.last;
  }
}

/// Everything that was found for one category.
class StorageCategoryUsage {
  final StorageCategory category;
  final int bytes;
  final int fileCount;
  final List<StorageEntry> entries;

  const StorageCategoryUsage({
    required this.category,
    required this.bytes,
    required this.fileCount,
    required this.entries,
  });

  static const empty = StorageCategoryUsage(
    category: StorageCategory.other,
    bytes: 0,
    fileCount: 0,
    entries: [],
  );
}

/// The result of a storage scan.
class StorageReport {
  final Map<StorageCategory, StorageCategoryUsage> categories;

  const StorageReport(this.categories);

  /// Total number of bytes used by the app on this device.
  int get totalBytes =>
      categories.values.fold(0, (sum, usage) => sum + usage.bytes);

  /// Usage of one category (never null).
  StorageCategoryUsage usage(StorageCategory category) =>
      categories[category] ??
      StorageCategoryUsage(
        category: category,
        bytes: 0,
        fileCount: 0,
        entries: const [],
      );

  /// Share of the total in percent (0 - 100).
  double percentage(StorageCategory category) {
    final total = totalBytes;
    if (total <= 0) return 0;
    return (usage(category).bytes / total) * 100;
  }

  /// Categories that actually use space, biggest first.
  List<StorageCategory> get usedCategories {
    final used = categories.values
        .where((u) => u.bytes > 0)
        .map((u) => u.category)
        .toList();
    used.sort((a, b) => usage(b).bytes.compareTo(usage(a).bytes));
    return used;
  }
}

/// Scans the storage of the device and groups everything the app has stored.
///
/// The scan looks at
/// * the temporary directory (`getTemporaryDirectory()`) – picked images,
///   recorded voice notes and other temporary downloads,
/// * the cache directory (`getApplicationCacheDirectory()`) – the Flutter
///   image cache,
/// * the documents directory (`getApplicationDocumentsDirectory()`) – the
///   SQLite database of drift and the json chat cache,
/// * the support directory (`getApplicationSupportDirectory()`) – databases
///   that the platform keeps there.
class StorageCalculator {
  StorageCalculator._();

  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
    '.heif',
    '.svg',
  };

  static const Set<String> _mediaExtensions = {
    '.mp4',
    '.mov',
    '.avi',
    '.mkv',
    '.webm',
    '.3gp',
    '.m4v',
    '.m4a',
    '.mp3',
    '.aac',
    '.wav',
    '.ogg',
    '.opus',
    '.amr',
  };

  static const Set<String> _fileExtensions = {
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.zip',
    '.rar',
    '.7z',
    '.txt',
    '.csv',
    '.json',
  };

  /// Database files (sqlite and its side car files).
  static const Set<String> _databaseExtensions = {
    '.sqlite',
    '.sqlite3',
    '.db',
    '.wal',
    '.shm',
  };

  /// Scans the device and returns the usage per category.
  static Future<StorageReport> scan() async {
    final entries = <StorageEntry>[];

    // Temporary files and the Flutter image cache.
    final temp = await _safeDirectory(getTemporaryDirectory);
    if (temp != null) {
      await _collectDirectory(temp, entries, recursive: true);
    }

    final cache = await _safeDirectory(getApplicationCacheDirectory);
    if (cache != null) {
      await _collectDirectory(cache, entries, recursive: true);
    }

    // The databases and the json chat cache.
    final docs = await _safeDirectory(getApplicationDocumentsDirectory);
    if (docs != null) {
      await _collectDirectory(docs, entries, recursive: false);

      // The json chat cache lives in a sub folder of the documents directory.
      // It is part of the local chat history, so it counts as "database".
      final chatCache = Directory(
        '${docs.path}${Platform.pathSeparator}chat_cache',
      );
      if (await chatCache.exists()) {
        await _collectDirectory(chatCache, entries,
            recursive: true, forceCategory: StorageCategory.database);
      }
    }

    final support = await _safeDirectory(getApplicationSupportDirectory);
    if (support != null) {
      await _collectDirectory(support, entries, recursive: false);
    }

    return _buildReport(entries);
  }

  /// Resolves a directory without failing the whole scan when the platform
  /// does not support it (for example `getApplicationCacheDirectory()` on
  /// the web).
  static Future<Directory?> _safeDirectory(Future<Directory> Function() getter) async {
    try {
      return await getter();
    } catch (e) {
      debugPrint('StorageCalculator: directory not available: $e');
      return null;
    }
  }

  /// Deletes every file of one category.
  ///
  /// Returns the number of bytes that were freed. The database category is
  /// not handled here (the app owns that file, it is cleared through the
  /// repository instead).
  static Future<int> clearCategory(StorageCategory category) async {
    if (category == StorageCategory.database) return 0;

    final report = await scan();
    final usage = report.usage(category);
    var freed = 0;

    for (final entry in usage.entries) {
      try {
        if (await entry.file.exists()) {
          await entry.file.delete();
          freed += entry.bytes;
        }
      } catch (e) {
        debugPrint('StorageCalculator: could not delete ${entry.name}: $e');
      }
    }
    return freed;
  }

  /// Formats a number of bytes as KB / MB / GB.
  static String formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return '0 B';

    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;

    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }

    final text = unit == 0 || value >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(decimals);
    return '$text ${units[unit]}';
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static Future<void> _collectDirectory(
    Directory directory,
    List<StorageEntry> entries, {
    required bool recursive,
    StorageCategory? forceCategory,
  }) async {
    try {
      if (!await directory.exists()) return;

      await for (final entity in directory.list(recursive: recursive)) {
        if (entity is! File) continue;

        int size = 0;
        try {
          size = await entity.length();
        } catch (_) {
          continue;
        }
        if (size <= 0) continue;

        entries.add(StorageEntry(
          file: entity,
          bytes: size,
          category: forceCategory ?? _categorize(entity.path),
        ));
      }
    } catch (e) {
      debugPrint('StorageCalculator: cannot read ${directory.path}: $e');
    }
  }

  /// Decides the category of a file from its extension.
  static StorageCategory _categorize(String path) {
    final lower = path.toLowerCase();
    final dot = lower.lastIndexOf('.');
    final extension = dot == -1 ? '' : lower.substring(dot);

    // SQLite side car files are named "x.sqlite-wal" / "x.sqlite-shm".
    if (lower.contains('.sqlite') || lower.contains('.db')) {
      return StorageCategory.database;
    }
    if (_databaseExtensions.contains(extension)) return StorageCategory.database;
    if (_imageExtensions.contains(extension)) return StorageCategory.images;
    if (_mediaExtensions.contains(extension)) return StorageCategory.media;
    if (_fileExtensions.contains(extension)) return StorageCategory.files;
    return StorageCategory.other;
  }

  static StorageReport _buildReport(List<StorageEntry> entries) {
    final grouped = <StorageCategory, List<StorageEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.category, () => <StorageEntry>[]).add(entry);
    }

    final categories = <StorageCategory, StorageCategoryUsage>{};
    grouped.forEach((category, list) {
      // Biggest file first, the detail sheet shows the top entries.
      list.sort((a, b) => b.bytes.compareTo(a.bytes));
      categories[category] = StorageCategoryUsage(
        category: category,
        bytes: list.fold(0, (sum, entry) => sum + entry.bytes),
        fileCount: list.length,
        entries: list,
      );
    });

    return StorageReport(categories);
  }
}
