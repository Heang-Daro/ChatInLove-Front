import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single saved account stored on the device.
class SavedAccount {
  final String userId;
  final String email;
  final String username;
  final String? profileImageUrl;
  /// The refresh token is stored so the session can be restored without
  /// asking for the password again.
  final String refreshToken;

  const SavedAccount({
    required this.userId,
    required this.email,
    required this.username,
    this.profileImageUrl,
    required this.refreshToken,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'email': email,
        'username': username,
        'profileImageUrl': profileImageUrl,
        'refreshToken': refreshToken,
      };

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
        userId: j['userId']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        profileImageUrl: j['profileImageUrl']?.toString(),
        refreshToken: j['refreshToken']?.toString() ?? '',
      );

  SavedAccount copyWith({
    String? username,
    String? profileImageUrl,
    String? refreshToken,
  }) =>
      SavedAccount(
        userId: userId,
        email: email,
        username: username ?? this.username,
        profileImageUrl: profileImageUrl ?? this.profileImageUrl,
        refreshToken: refreshToken ?? this.refreshToken,
      );
}

/// Manages a list of saved accounts on this device.
///
/// • When a user logs in successfully, call [saveAccount] to persist them.
/// • When a user logs out of only the current account, call [removeAccount].
/// • To switch, call [getAccount] to get the refresh token, restore the
///   session in [AuthProvider], and call [setActiveUserId].
class AccountManager {
  AccountManager._();

  static const _listKey = 'saved_accounts_v1';
  static const _activeKey = 'active_account_id';

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  static Future<List<SavedAccount>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_listKey);
      if (raw == null || raw.isEmpty) return [];
      final list = json.decode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(SavedAccount.fromJson)
          .toList();
    } catch (e) {
      debugPrint('AccountManager.getAll error: $e');
      return [];
    }
  }

  static Future<String?> getActiveUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey);
  }

  static Future<SavedAccount?> getAccount(String userId) async {
    final all = await getAll();
    try {
      return all.firstWhere((a) => a.userId == userId);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Adds or updates a saved account and marks it as active.
  static Future<void> saveAccount(SavedAccount account) async {
    try {
      final all = await getAll();
      final idx = all.indexWhere((a) => a.userId == account.userId);
      if (idx >= 0) {
        all[idx] = account;
      } else {
        all.add(account);
      }
      await _persist(all);
      await setActiveUserId(account.userId);
    } catch (e) {
      debugPrint('AccountManager.saveAccount error: $e');
    }
  }

  static Future<void> setActiveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, userId);
  }

  /// Updates only the mutable fields (profile picture, username, token)
  /// without replacing the whole record.
  static Future<void> updateAccount({
    required String userId,
    String? username,
    String? profileImageUrl,
    String? refreshToken,
  }) async {
    final all = await getAll();
    final idx = all.indexWhere((a) => a.userId == userId);
    if (idx < 0) return;
    all[idx] = all[idx].copyWith(
      username: username,
      profileImageUrl: profileImageUrl,
      refreshToken: refreshToken,
    );
    await _persist(all);
  }

  /// Removes a saved account. Does NOT touch the active-account pointer —
  /// the caller must handle switching to another account.
  static Future<void> removeAccount(String userId) async {
    final all = await getAll();
    all.removeWhere((a) => a.userId == userId);
    await _persist(all);
  }

  static Future<void> _persist(List<SavedAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _listKey,
      json.encode(accounts.map((a) => a.toJson()).toList()),
    );
  }
}
