import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/api.dart';

/// Tracks online/offline status of users received via STOMP /topic/presence
/// broadcasts and the REST GET /api/users/{id}/presence endpoint.
class UserPresence {
  final String userId;
  final bool online;
  final DateTime? lastSeen; // null when online

  const UserPresence({
    required this.userId,
    required this.online,
    this.lastSeen,
  });

  factory UserPresence.fromJson(Map<String, dynamic> j) {
    final lastSeenMs = j['lastSeen'] as int? ?? 0;
    return UserPresence(
      userId:   j['userId']?.toString() ?? '',
      online:   j['online'] == true,
      lastSeen: lastSeenMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastSeenMs, isUtc: true).toLocal()
          : null,
    );
  }
}

/// App-level presence service.
///
/// Usage:
///   1. Call [updateFromStompFrame] from ConversationProvider whenever a
///      /topic/presence frame arrives.
///   2. Call [fetchPresence] to hydrate a single user's status on demand.
///   3. Listen to [onChange] to rebuild widgets showing online badges.
class PresenceService extends ChangeNotifier {
  final Map<String, UserPresence> _presence = {};

  /// Fires whenever any user's presence changes.
  Stream<UserPresence> get onChange => _controller.stream;
  final _controller = StreamController<UserPresence>.broadcast();

  // ── Update from STOMP broadcast ───────────────────────────────────────────

  void updateFromMap(Map<String, dynamic> data) {
    final p = UserPresence.fromJson(data);
    if (p.userId.isEmpty) return;
    _presence[p.userId] = p;
    _controller.add(p);
    notifyListeners();
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  bool isOnline(String userId) => _presence[userId]?.online ?? false;

  UserPresence? get(String userId) => _presence[userId];

  String lastSeenLabel(String userId) {
    final p = _presence[userId];
    if (p == null) return '';
    if (p.online) return 'Online';
    final ls = p.lastSeen;
    if (ls == null) return 'Offline';
    final diff = DateTime.now().difference(ls);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ── REST fetch ────────────────────────────────────────────────────────────

  Future<UserPresence?> fetchPresence(String userId, String token) async {
    try {
      final resp = await http.get(
        Uri.parse('$REST_URL/api/users/$userId/presence'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final p = UserPresence.fromJson(json.decode(resp.body));
        _presence[p.userId] = p;
        notifyListeners();
        return p;
      }
    } catch (e) {
      debugPrint('[Presence] fetchPresence error: $e');
    }
    return null;
  }

  void dispose() {
    _controller.close();
    super.dispose();
  }
}
