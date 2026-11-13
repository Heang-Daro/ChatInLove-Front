import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:love_in_chat/api/api.dart';
import 'package:love_in_chat/model/Response/DeviceSessionResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/util/AnimatedComponents.dart';
import 'package:love_in_chat/util/AppBarStyle.dart';
import 'package:love_in_chat/util/browser_launcher.dart';

// -----------------------------------------------------------------------------
// Design tokens
// -----------------------------------------------------------------------------

/// The pink of the brand. It looks the same in the light and in the dark
/// theme, so it can stay a constant.
const Color _brand = Colors.pinkAccent;

const double _radius = 18;

/// The colors of the screen, resolved from the theme of the app.
///
/// The screen follows the theme of the app (light / dark / system), so no
/// color is hardcoded: every value is read from the [Theme] of the context.
class _Palette {
  const _Palette(this.context);

  final BuildContext context;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  /// Background of the page.
  Color get pageBg =>
      _isDark ? const Color(0xFF111318) : const Color(0xFFFAE7EE);

  /// Background of a card, a dialog or a sheet.
  Color get surface => _isDark ? const Color(0xFF1B1E26) : Colors.white;

  /// Background of a soft area (empty state, chip background).
  Color get muted => _isDark ? const Color(0xFF232733) : const Color(0xFFEFEFF4);

  /// The main text.
  Color get textPrimary =>
      _isDark ? const Color(0xFFF1F3F8) : const Color(0xFF1F2330);

  /// Secondary text (labels, subtitles).
  Color get textSecondary =>
      _isDark ? const Color(0xFF9CA2B2) : const Color(0xFF6B7080);

  /// Very quiet text (timestamps).
  Color get textHint =>
      _isDark ? const Color(0xFF6F7688) : const Color(0xFF9A9EAD);

  /// Lines and borders.
  Color get border => _isDark ? const Color(0xFF2B303C) : const Color(0xFFE8E8EE);

  /// Destructive actions.
  Color get danger => _isDark ? const Color(0xFFFF6B6E) : const Color(0xFFE5484D);

  /// Disabled icons.
  Color get disabled => _isDark ? const Color(0xFF5A6070) : Colors.grey;
}

/// ---------------------------------------------------------------------------
/// Entry tile used by SettingScreen.
/// ---------------------------------------------------------------------------
class DeviceSecurityTile extends StatelessWidget {
  const DeviceSecurityTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.computer_outlined, color: _brand),
      title: const Text("Device Security"),
      subtitle: const Text("See and terminate the sessions using your account"),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        Navigator.push(
          context,
          AnimatedPageRoute(page: const DeviceSessionScreen()),
        );
      },
    );
  }
}

/// ---------------------------------------------------------------------------
/// Device sessions screen.
///
///   GET    /api/auth/devices          -> list active sessions
///   DELETE /api/auth/devices/{id}     -> terminate one session
/// ---------------------------------------------------------------------------
class DeviceSessionScreen extends StatefulWidget {
  const DeviceSessionScreen({super.key});

  @override
  State<DeviceSessionScreen> createState() => _DeviceSessionScreenState();
}

class _DeviceSessionScreenState extends State<DeviceSessionScreen> {
  static const Duration _timeout = Duration(seconds: 15);

  String get _baseUrl => "$REST_URL/api/auth";

  List<DeviceSessionResponse> _devices = [];
  bool _isLoading = true;
  bool _isWorking = false;
  String? _errorMessage;
  DeviceSessionResponse? _selectedDevice;

  AuthProvider get _auth => Provider.of<AuthProvider>(context, listen: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDevices());
  }

  Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  bool _isCurrent(DeviceSessionResponse d) {
    final id = _auth.currentSessionId;
    return d.currentDevice || (id != null && d.id == id);
  }

  // ---------------------------------------------------------------------------
  // Ordering & selection
  // ---------------------------------------------------------------------------

  /// Current device first, then the others by last activity (newest first).
  List<DeviceSessionResponse> _sortDevices(List<DeviceSessionResponse> devices) {
    final sorted = List<DeviceSessionResponse>.from(devices);
    sorted.sort((a, b) {
      final aCurrent = _isCurrent(a);
      final bCurrent = _isCurrent(b);
      if (aCurrent != bCurrent) return aCurrent ? -1 : 1;

      final aTime = a.lastActiveAt ?? DateTime(1970);
      final bTime = b.lastActiveAt ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    return sorted;
  }

  DeviceSessionResponse? _resolveSelection(
    DeviceSessionResponse? selected,
    List<DeviceSessionResponse> devices,
  ) {
    if (devices.isEmpty) return null;
    if (selected != null) {
      for (final device in devices) {
        if (device.id == selected.id) return device;
      }
    }
    return devices.first;
  }

  // ---------------------------------------------------------------------------
  // Backend calls
  // ---------------------------------------------------------------------------

  Future<void> _refreshAll() async {
    await _auth.syncCurrentDevice();
    await _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _auth
          .authorizedRequest(
            (token) => http.get(
          Uri.parse('$_baseUrl/devices'),
          headers: _headers(token),
        ),
      )
          .timeout(_timeout);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        final loaded = data
            .map((e) => DeviceSessionResponse.fromJson(e as Map<String, dynamic>))
            .toList();

        setState(() {
          _devices = _sortDevices(loaded);
          _selectedDevice = _resolveSelection(_selectedDevice, _devices);
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to load devices (${response.statusCode})";
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = "Connection error. Please try again.";
      });
    }
  }

  Future<void> _revokeDevice(DeviceSessionResponse device) async {
    if (_isCurrent(device)) {
      _toast("You can not sign out this device from here");
      return;
    }

    final confirmed = await _confirm(
      title: "Terminate this session?",
      message: "${_nameOf(device)} will be signed out of your account.",
      confirmLabel: "Terminate",
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isWorking = true);

    try {
      final response = await _auth
          .authorizedRequest(
            (token) => http.delete(
          Uri.parse('$_baseUrl/devices/${device.id}'),
          headers: _headers(token),
        ),
      )
          .timeout(_timeout);

      if (!mounted) return;

      if (response.statusCode == 204 || response.statusCode == 200) {
        setState(() {
          _devices.removeWhere((d) => d.id == device.id);
          _selectedDevice = _resolveSelection(_selectedDevice, _devices);
        });
        _toast("Session terminated");
      } else {
        _toast("Could not terminate this session (${response.statusCode})");
      }
    } catch (_) {
      _toast("Connection error. Please try again.");
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _logoutOtherDevices() async {
    final others = _devices.where((d) => !_isCurrent(d)).toList();

    if (others.isEmpty) {
      _toast("There is no other device signed in");
      return;
    }

    final confirmed = await _confirm(
      title: "Sign out other devices?",
      message: others.length == 1
          ? "${_nameOf(others.first)} will be signed out. "
          "You stay signed in on this device."
          : "${others.length} devices will be signed out. "
          "You stay signed in on this device.",
      confirmLabel: "Sign out others",
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isWorking = true);

    var terminated = 0;
    final removedIds = <String>{};
    for (final device in others) {
      try {
        final response = await _auth
            .authorizedRequest(
              (token) => http.delete(
            Uri.parse('$_baseUrl/devices/${device.id}'),
            headers: _headers(token),
          ),
        )
            .timeout(_timeout);

        if (response.statusCode == 204 || response.statusCode == 200) {
          terminated++;
          removedIds.add(device.id);
        }
      } catch (_) {
        // Keep going with the other devices.
      }
    }

    if (!mounted) return;

    setState(() {
      _devices.removeWhere((d) => removedIds.contains(d.id));
      _selectedDevice = _resolveSelection(_selectedDevice, _devices);
      _isWorking = false;
    });

    _toast(terminated == 0
        ? "Could not sign out the other devices"
        : "$terminated device(s) signed out");
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    final palette = _Palette(context);

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: palette.textPrimary,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              "Cancel",
              style: TextStyle(color: palette.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: palette.danger),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }

  /// Opens a position in Google Maps (new tab on web, app/browser on mobile).
  void _openInGoogleMaps(double latitude, double longitude) {
    final coordinates = '$latitude,$longitude';
    final webUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$coordinates',
    );

    if (kIsWeb) {
      // No await before this call: the browser needs the user gesture.
      final opened = openInNewTab(webUri.toString());
      if (!opened) {
        unawaited(launchUrl(webUri));
      }
      return;
    }

    unawaited(_launchNative(webUri, coordinates));
  }

  Future<void> _launchNative(Uri webUri, String coordinates) async {
    final appUri = Uri.parse('comgooglemaps://?center=$coordinates&zoom=15');

    try {
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri);
        return;
      }
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        return;
      }
      _toast("Could not open Google Maps");
    } catch (e) {
      debugPrint('DeviceSessionScreen: could not open Google Maps: $e');
      _toast("Could not open Google Maps");
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(context);

    return Scaffold(
      backgroundColor: palette.pageBg,
      appBar: AppBarStyle.build(
        title: "Device Security",
      ),
      body: _buildBody(),
    );
  }

  /// Wraps a non-scrollable message so the user can still pull down to reload.
  Widget _pullToRefresh(Widget child) {
    return RefreshIndicator(
      color: _brand,
      onRefresh: _refreshAll,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: constraints.maxHeight, child: child),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final palette = _Palette(context);

    if (_isLoading && _devices.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _brand));
    }

    if (_errorMessage != null && _devices.isEmpty) {
      return _pullToRefresh(
        _StateMessage(
          icon: Icons.wifi_off_rounded,
          title: "Something went wrong",
          message: "$_errorMessage\nPull down to try again.",
          actionLabel: "Try again",
          onAction: _loadDevices,
        ),
      );
    }

    if (_devices.isEmpty) {
      return _pullToRefresh(
        const _StateMessage(
          icon: Icons.devices_other_rounded,
          title: "No active sessions",
          message: "Sessions signed in to your account will show up here.\n"
              "Pull down to refresh.",
        ),
      );
    }

    final selected = _selectedDevice ?? _devices.first;
    final others = _devices.where((d) => !_isCurrent(d)).toList();

    return Stack(
      children: [
        RefreshIndicator(
          color: _brand,
          onRefresh: _refreshAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(4)),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: _brand,
                      backgroundColor: palette.border,
                    ),
                  ),
                ),

              // Device selector
              _DeviceChips(
                devices: _devices,
                selectedId: selected.id,
                isCurrent: _isCurrent,
                onSelected: (d) => setState(() => _selectedDevice = d),
              ),
              const SizedBox(height: 14),

              // Map hero
              _LocationHero(
                device: selected,
                isCurrent: _isCurrent(selected),
                onOpenMaps: selected.hasLocation
                    ? () => _openInGoogleMaps(selected.mapX!, selected.mapY!)
                    : null,
              ),
              const SizedBox(height: 14),

              // Details
              _DeviceDetails(
                device: selected,
                onOpenMaps: selected.hasLocation
                    ? () => _openInGoogleMaps(selected.mapX!, selected.mapY!)
                    : null,
              ),
              const SizedBox(height: 26),

              // Sessions list
              _SectionHeader(
                title: "Sessions",
                trailing: "${_devices.length} active",
              ),
              const SizedBox(height: 4),
              Text(
                "Terminate any device you no longer use. "
                "Sessions expire automatically after 7 days.",
                style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
              ),
              const SizedBox(height: 12),
              ..._devices.map(
                    (device) => _SessionTile(
                  device: device,
                  isCurrent: _isCurrent(device),
                  isSelected: device.id == selected.id,
                  enabled: !_isWorking,
                  onTap: () => setState(() => _selectedDevice = device),
                  onRevoke: () => _revokeDevice(device),
                ),
              ),

              // Danger zone
              if (others.isNotEmpty) ...[
                const SizedBox(height: 20),
                _DangerZone(
                  count: others.length,
                  enabled: !_isWorking,
                  onPressed: _logoutOtherDevices,
                ),
              ],
            ],
          ),
        ),
        if (_isWorking)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator(color: _brand)),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Widgets
// =============================================================================

/// Horizontal, scrollable device picker.
class _DeviceChips extends StatelessWidget {
  final List<DeviceSessionResponse> devices;
  final String selectedId;
  final bool Function(DeviceSessionResponse) isCurrent;
  final ValueChanged<DeviceSessionResponse> onSelected;

  const _DeviceChips({
    required this.devices,
    required this.selectedId,
    required this.isCurrent,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(context);

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: devices.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final device = devices[index];
          final selected = device.id == selectedId;
          final current = isCurrent(device);

          return Material(
            color: selected ? _brand : palette.surface,
            shape: StadiumBorder(
              side: BorderSide(color: selected ? _brand : palette.border),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => onSelected(device),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _iconFor(device.deviceType),
                      size: 18,
                      color: selected ? Colors.white : palette.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        current ? "This device" : _nameOf(device),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : palette.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Map with overlays: device name on top, location label at the bottom.
class _LocationHero extends StatelessWidget {
  final DeviceSessionResponse device;
  final bool isCurrent;
  final VoidCallback? onOpenMaps;

  const _LocationHero({
    required this.device,
    required this.isCurrent,
    required this.onOpenMaps,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: SizedBox(
        height: 250,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            device.hasLocation ? _buildMap() : _buildNoLocation(context),

            // Bottom gradient + label
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xB3000000)],
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          device.hasLocation
                              ? device.locationLabel
                              : "Location not reported yet",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Top-left: device pill
            Positioned(
              left: 12,
              top: 12,
              child: _GlassPill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_iconFor(device.deviceType), size: 16, color: _brand),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: Text(
                        _nameOf(device),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      const _Badge(label: "This device"),
                    ],
                  ],
                ),
              ),
            ),

            // Top-right: open in maps
            if (onOpenMaps != null)
              Positioned(
                right: 12,
                top: 12,
                child: Material(
                  color: Colors.white.withOpacity(0.95),
                  shape: const CircleBorder(),
                  elevation: 1,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onOpenMaps,
                    child: const Padding(
                      padding: EdgeInsets.all(9),
                      child: Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: _brand,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final point = LatLng(device.mapX!, device.mapY!);

    return FlutterMap(
      // New key per position so the camera re-centers when selection changes.
      key: ValueKey('${device.id}-${device.mapX}-${device.mapY}'),
      options: MapOptions(
        initialCenter: point,
        initialZoom: 13,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.love_in_chat',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: point,
              width: 48,
              height: 48,
              child: const _MapPin(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNoLocation(BuildContext context) {
    final palette = _Palette(context);

    return Container(
      color: palette.muted,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 40,
              color: palette.disabled,
            ),
            const SizedBox(height: 8),
            Text(
              "No location available",
              style: TextStyle(
                color: palette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Info card for the selected device.
class _DeviceDetails extends StatelessWidget {
  final DeviceSessionResponse device;
  final VoidCallback? onOpenMaps;

  const _DeviceDetails({required this.device, required this.onOpenMaps});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.place_outlined,
            label: "Location",
            value: device.hasLocation ? device.locationLabel : "Unknown",
          ),
          if (device.hasLocation)
            _InfoRow(
              icon: Icons.my_location_rounded,
              label: "Coordinates",
              value: '${device.mapX!.toStringAsFixed(5)}, '
                  '${device.mapY!.toStringAsFixed(5)}',
            ),
          _InfoRow(
            icon: Icons.lan_outlined,
            label: "IP address",
            value: device.ipAddress,
          ),
          _InfoRow(
            icon: Icons.schedule_rounded,
            label: "Last active",
            value: _timeAgo(device.lastActiveAt),
          ),
          _InfoRow(
            icon: Icons.update_rounded,
            label: "Location updated",
            value: _timeAgo(device.locationUpdatedAt, never: "Never"),
            isLast: onOpenMaps == null,
          ),
          if (onOpenMaps != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onOpenMaps,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brand,
                  side: const BorderSide(color: _brand),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text(
                  "Open in Google Maps",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: palette.textSecondary),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontSize: 13.5, color: palette.textSecondary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One session in the list.
class _SessionTile extends StatelessWidget {
  final DeviceSessionResponse device;
  final bool isCurrent;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onRevoke;

  const _SessionTile({
    required this.device,
    required this.isCurrent,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? _brand : palette.border,
                width: isSelected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isCurrent ? _brand : _brand.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconFor(device.deviceType),
                    color: isCurrent ? Colors.white : _brand,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _nameOf(device),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 8),
                            const _Badge(label: "This device"),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        device.hasLocation
                            ? device.locationLabel
                            : device.ipAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: palette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _timeAgo(device.lastActiveAt, prefix: "Active "),
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: palette.disabled,
                    ),
                  )
                else
                  IconButton(
                    tooltip: "Terminate session",
                    onPressed: enabled ? onRevoke : null,
                    icon: Icon(
                      Icons.logout_rounded,
                      size: 20,
                      color: enabled ? palette.danger : palette.disabled,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  final int count;
  final bool enabled;
  final VoidCallback onPressed;

  const _DangerZone({
    required this.count,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.danger.withOpacity(0.06),
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: palette.danger.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Don't recognize a device?",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Sign out $count other ${count == 1 ? 'device' : 'devices'} "
                "and stay signed in here.",
            style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: enabled ? onPressed : null,
              style: FilledButton.styleFrom(
                backgroundColor: palette.danger,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text(
                "Sign out other devices",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Small building blocks
// -----------------------------------------------------------------------------

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(context);

    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: palette.textPrimary,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: _brand.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              trailing!,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _brand,
              ),
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;

  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _brand,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  final Widget child;

  const _GlassPill({required this.child});

  @override
  Widget build(BuildContext context) {
    // The pill always floats over the map, so it stays light in both themes.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _brand,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 22),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: _brand.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: _brand),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: _brand,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

String _nameOf(DeviceSessionResponse d) =>
    d.deviceName.isEmpty ? "Unknown device" : d.deviceName;

IconData _iconFor(String deviceType) {
  switch (deviceType.toUpperCase()) {
    case 'ANDROID':
      return Icons.android;
    case 'IOS':
      return Icons.phone_iphone;
    case 'DESKTOP':
      return Icons.computer;
    case 'WEB':
    default:
      return Icons.language;
  }
}

/// "just now", "5 min ago", "3 h ago", "2 d ago" or a dd/mm/yyyy date.
String _timeAgo(DateTime? time, {String prefix = "", String never = "Unknown"}) {
  if (time == null) return never;

  final local = time.toLocal();
  final diff = DateTime.now().difference(local);

  if (diff.inMinutes < 1) return "${prefix}just now";
  if (diff.inMinutes < 60) return "$prefix${diff.inMinutes} min ago";
  if (diff.inHours < 24) return "$prefix${diff.inHours} h ago";
  if (diff.inDays < 7) return "$prefix${diff.inDays} d ago";

  String two(int v) => v.toString().padLeft(2, '0');
  return "$prefix${two(local.day)}/${two(local.month)}/${local.year} "
      "${two(local.hour)}:${two(local.minute)}";
}
