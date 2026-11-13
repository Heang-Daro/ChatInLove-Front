import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/data/repositories/chat_repository.dart';
import 'package:love_in_chat/service/CacheService.dart';
import 'package:love_in_chat/service/storage_calculator.dart';
import 'package:love_in_chat/util/AppBarStyle.dart';

import 'CacheScreen.dart';

/// Color of every category in the pie chart.
const Map<StorageCategory, Color> _categoryColors = {
  StorageCategory.images: Color(0xFFFF6B9D),
  StorageCategory.media: Color(0xFF9C6BFF),
  StorageCategory.files: Color(0xFFFFA14A),
  StorageCategory.database: Color(0xFF3D8BFF),
  StorageCategory.other: Color(0xFF9E9E9E),
};

/// Icon of a category (the utility itself stays free of UI code).
IconData _iconFor(StorageCategory category) {
  switch (category) {
    case StorageCategory.images:
      return Icons.image_outlined;
    case StorageCategory.media:
      return Icons.videocam_outlined;
    case StorageCategory.files:
      return Icons.insert_drive_file_outlined;
    case StorageCategory.database:
      return Icons.storage_outlined;
    case StorageCategory.other:
      return Icons.folder_outlined;
  }
}

/// Telegram style "Data & Storage" screen.
///
/// Shows how much space the app uses on the device, split into categories,
/// and allows clearing every category on its own.
class DataStorageScreen extends StatefulWidget {
  const DataStorageScreen({super.key});

  @override
  State<DataStorageScreen> createState() => _DataStorageScreenState();
}

class _DataStorageScreenState extends State<DataStorageScreen> {
  StorageReport? _report;
  bool _loading = true;
  bool _clearing = false;

  static const Map<StorageCategory, Color> _colors = _categoryColors;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    final report = await StorageCalculator.scan();
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Clearing
  // ---------------------------------------------------------------------------

  Future<void> _openCategory(StorageCategory category) async {
    final report = _report;
    if (report == null) return;

    final usage = report.usage(category);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => _CategorySheet(
        category: category,
        usage: usage,
        percentage: report.percentage(category),
        onClear: () async {
          Navigator.pop(sheetContext);
          await _clearCategory(category);
        },
      ),
    );
  }

  Future<void> _clearCategory(StorageCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear ${category.title}?'),
        content: Text(
          category == StorageCategory.database
              ? 'The local chat history on this device will be removed. '
                  'Nothing is deleted on the server, the messages are '
                  'downloaded again the next time you open a chat.'
              : 'All cached ${category.title.toLowerCase()} will be removed '
                  'from this device. They are downloaded again when needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.pinkAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _clearing = true);

    if (category == StorageCategory.database) {
      // The app owns the database, so the history is cleared through the
      // repository (drift rows) and the json cache service.
      try {
        final repository = context.read<ChatRepository>();
        await repository.clearLocalData();
      } catch (_) {
        // The repository is optional, the json cache is cleared anyway.
      }
      await CacheService.clearAll();
    } else {
      await StorageCalculator.clearCategory(category);
    }

    await _scan();

    if (!mounted) return;
    setState(() => _clearing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${category.title} cleared'),
        backgroundColor: Colors.pinkAccent,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarStyle.build(
        title: 'Data & Storage',
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.pinkAccent),
            )
          : RefreshIndicator(
              color: Colors.pinkAccent,
              onRefresh: _scan,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _buildChartCard(),
                  const SizedBox(height: 18),
                  _buildSectionTitle('Cache breakdown'),
                  const SizedBox(height: 8),
                  ..._buildCategoryTiles(),
                  const SizedBox(height: 18),
                  _buildSectionTitle('More'),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.sd_storage_outlined,
                          color: Colors.pinkAccent),
                      title: const Text('Cached chats (per chat)'),
                      subtitle: const Text(
                          'See the cached messages and file links of every chat'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CacheScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.grey.shade700,
        fontWeight: FontWeight.bold,
        fontSize: 15,
      ),
    );
  }

  /// Section 1: circular graphic + total size + breakdown percentages.
  Widget _buildChartCard() {
    final report = _report!;
    final used = report.usedCategories;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            SizedBox(
              height: 210,
              child: used.isEmpty
                  ? Center(
                      child: Text(
                        'No data stored yet',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            sectionsSpace: 3,
                            centerSpaceRadius: 62,
                            startDegreeOffset: -90,
                            sections: used.map((category) {
                              final usage = report.usage(category);
                              final percentage = report.percentage(category);
                              return PieChartSectionData(
                                value: usage.bytes.toDouble(),
                                color: _colors[category],
                                radius: 34,
                                cornerRadius: 4,
                                showTitle: percentage >= 8,
                                title: '${percentage.toStringAsFixed(0)}%',
                                titleStyle: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                titlePositionPercentageOffset: 0.55,
                              );
                            }).toList(),
                          ),
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                        ),
                        // Total size in the middle of the circle.
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              StorageCalculator.formatBytes(report.totalBytes),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.pinkAccent,
                              ),
                            ),
                            const Text(
                              'total used',
                              style: TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            // Breakdown with the percentage of every category.
            ...used.map((category) {
              final usage = report.usage(category);
              final percentage = report.percentage(category);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _colors[category],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        category.title,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      StorageCalculator.formatBytes(usage.bytes),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (used.isEmpty)
              Text(
                'Nothing is stored on this device yet',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }

  /// Section 2: the categorized list.
  List<Widget> _buildCategoryTiles() {
    final report = _report!;

    return StorageCategory.values.map((category) {
      final usage = report.usage(category);
      final percentage = report.percentage(category);
      final canClear = usage.bytes > 0;

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: (_colors[category] ?? Colors.grey).withOpacity(0.15),
              child: Icon(
                _iconFor(category),
                color: _colors[category] ?? Colors.grey,
              ),
            ),
            title: Text(
              category.title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            subtitle: Text(
              canClear
                  ? '${StorageCalculator.formatBytes(usage.bytes)} • '
                      '${usage.fileCount} file(s) • ${percentage.toStringAsFixed(1)}%'
                  : 'Nothing cached',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            trailing: _clearing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.pinkAccent,
                    ),
                  )
                : const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: canClear ? () => _openCategory(category) : null,
          ),
        ),
      );
    }).toList();
  }
}

/// Detail sheet of one category: size, percentage and the biggest files.
class _CategorySheet extends StatelessWidget {
  final StorageCategory category;
  final StorageCategoryUsage usage;
  final double percentage;
  final Future<void> Function() onClear;

  const _CategorySheet({
    required this.category,
    required this.usage,
    required this.percentage,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final entries = usage.entries.take(50).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: 45,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text(
              category.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 4),
            Text(
              '${StorageCalculator.formatBytes(usage.bytes)} • '
              '${percentage.toStringAsFixed(1)}% of the app storage • '
              '${usage.fileCount} file(s)',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text(
                'Nothing stored in this category',
                style: TextStyle(color: Colors.grey.shade600),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _iconFor(category),
                        size: 20,
                        color: Colors.pinkAccent,
                      ),
                      title: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        entry.file.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 10,
                        ),
                      ),
                      trailing: Text(
                        StorageCalculator.formatBytes(entry.bytes),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onClear,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.pinkAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.delete_sweep, color: Colors.white),
                label: Text(
                  'Clear ${category.title}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
