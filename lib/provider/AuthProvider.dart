import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_in_chat/api/api.dart';
import 'package:love_in_chat/model/Request/LoginRequest.dart';
import 'package:love_in_chat/model/Request/RegisterRequest.dart';
import 'package:love_in_chat/model/Response/AuthResponse.dart';
import '../model/Response/UserResponse.dart';
import '../service/CacheService.dart';
import '../service/DeviceLocationService.dart';

class AuthProvider extends ChangeNotifier {
  final String baseUrl = "${REST_URL}/api/auth";

  UserResponse? _currentUser;
  UserResponse? get currentUser => _currentUser;

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _timeout = Duration(seconds: 15);

  String? _accessToken;
  String? _refreshToken;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;

  // Ensures only one refresh runs at a time (parallel requests share it).
  Completer<bool>? _refreshing;

  String? get accessToken => _accessToken;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized; // show a splash until true
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _accessToken != null;

  // Single, robust getter for currentUserId using the JWT payload
  String? get currentUserId {
    final payload = _jwtPayload;
    if (payload == null) return null;

    // Return 'sub', 'userId', or 'id' depending on what your Spring Security JWT contains
    final value = payload['sub'] ?? payload['userId'] ?? payload['id'];
    return value is String ? value : value?.toString();
  }

  /// Device session id (`sid` claim) of the token the app is using right now.
  /// Used by the Device Security screen to highlight the current device.
  String? get currentSessionId {
    final payload = _jwtPayload;
    if (payload == null) return null;

    final value = payload['sid'] ?? payload['sessionId'];
    return value is String ? value : value?.toString();
  }

  /// Decoded JWT payload of the current access token, or null.
  Map<String, dynamic>? get _jwtPayload {
    final token = _accessToken;
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      return json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  AuthProvider() {
    _init();
  }

  // ---------------------------------------------------------------------------
  // Startup: load saved tokens, refresh if expired, and fetch user profile
  // ---------------------------------------------------------------------------
  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessKey);
    _refreshToken = prefs.getString(_refreshKey);

    final needsRefresh =
        _accessToken == null || _isExpired(_accessToken!);
    if (needsRefresh) {
      if (_refreshToken != null) {
        final success = await refreshAccessToken();
        if (success && _accessToken != null) {
          await _fetchUserProfile(_accessToken!);
        }
      } else {
        await logout();
      }
    } else if (_accessToken != null) {
      // Fetch user profile on successful startup if token is valid
      await _fetchUserProfile(_accessToken!);
    }

    _isInitialized = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Fetch User Principal Profile
  // ---------------------------------------------------------------------------
  Future<void> _fetchUserProfile(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/principal'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        _currentUser = UserResponse.fromJson(json.decode(response.body));
        notifyListeners();
      }
    } catch (_) {
      // Fail silently or handle network error for profile fetch
    }
  }

  // ---------------------------------------------------------------------------
  // JWT helpers
  // ---------------------------------------------------------------------------
  /// True if the JWT's `exp` is in the past (30s leeway). If the token can't be
  /// parsed, returns false and lets the server decide.
  bool _isExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! num) return false;
      final expiry =
      DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      return DateTime.now()
          .isAfter(expiry.subtract(const Duration(seconds: 30)));
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Token storage
  // ---------------------------------------------------------------------------
  Future<void> _saveTokens(String access, String? refresh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, access);
    _accessToken = access;
    if (refresh != null) {
      await prefs.setString(_refreshKey, refresh);
      _refreshToken = refresh;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Refresh
  // ---------------------------------------------------------------------------
  /// Returns true if a new access token is now available.
  Future<bool> refreshAccessToken() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight.future;

    final completer = _refreshing = Completer<bool>();
    _doRefresh().then(completer.complete).whenComplete(() => _refreshing = null);
    return completer.future;
  }

  Future<bool> _doRefresh() async {
    final rt = _refreshToken;
    // Check if rt is null OR empty
    if (rt == null || rt.trim().isEmpty) {
      await logout();
      return false;
    }
    try {
      final response = await http
          .post(
        Uri.parse('$baseUrl/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refreshToken': rt}),
      )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final auth = AuthResponse.fromJson(json.decode(response.body));
        await _saveTokens(auth.accessToken, auth.refreshToken.isNotEmpty ? auth.refreshToken : rt);
        await _fetchUserProfile(auth.accessToken);
        return true;
      }

      _errorMessage = "Session expired. Please log in again.";
      await logout();
      return false;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Authorized request wrapper: refresh before/after expiry, retry once,
  // log out if the session can't be recovered.
  // ---------------------------------------------------------------------------
  Future<http.Response> authorizedRequest(
      Future<http.Response> Function(String token) send,
      ) async {
    var token = _accessToken;
    if (token == null) {
      await logout();
      throw StateError('Not authenticated');
    }

    // Proactive check if expired locally using JWT 'exp' claim
    if (_isExpired(token)) {
      if (!await refreshAccessToken()) {
        await logout();
        throw StateError('Session expired');
      }
      token = _accessToken!;
    }

    var response = await send(token).timeout(_timeout);

    // If backend rejects with 401/403, attempt a reactive token refresh once
    if (response.statusCode == 401 || response.statusCode == 403) {
      if (await refreshAccessToken()) {
        response = await send(_accessToken!).timeout(_timeout);
        // If it still fails with 401/403 after refreshing, terminate session
        if (response.statusCode == 401 || response.statusCode == 403) {
          await logout();
          throw StateError('Unauthorized access');
        }
      } else {
        await logout();
        throw StateError('Session refresh failed');
      }
    }

    return response;
  }

  // ---------------------------------------------------------------------------
  // Login / Register / Logout
  // ---------------------------------------------------------------------------
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // The device profile (name, type and the location the user allowed)
      // travels with the login so the session list can show it right away.
      final profile = await DeviceLocationService.currentProfile();

      final request = LoginRequest(
        email: email,
        password: password,
        location: profile.location,
        deviceName: profile.deviceName,
        deviceType: profile.deviceType,
      );

      final response = await http
          .post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(request.toJson()),
      )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final auth = AuthResponse.fromJson(json.decode(response.body));

        // 1. Save tokens
        await _saveTokens(auth.accessToken, auth.refreshToken);

        // 2. Fetch user profile from /principal endpoint using the new token
        await _fetchUserProfile(auth.accessToken);

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = "Invalid email or password";
      }
    } on TimeoutException {
      _errorMessage = "Connection timed out. Please try again.";
    } catch (e) {
      _errorMessage = "Network error: $e";
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> register(String email, String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final request =
      RegisterRequest(email: email, username: username, password: password);
      final response = await http
          .post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(request.toJson()),
      )
          .timeout(_timeout);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final auth = AuthResponse.fromJson(json.decode(response.body));

        // 1. Save tokens
        await _saveTokens(auth.accessToken, auth.refreshToken);

        // 2. Fetch user profile from /principal endpoint
        await _fetchUserProfile(auth.accessToken);

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = "Registration failed";
      }
    } on TimeoutException {
      _errorMessage = "Connection timed out. Please try again.";
    } catch (e) {
      _errorMessage = "Network error: $e";
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Sends the device name, the device type and the location of the device to
  /// the backend for the session that is currently used.
  ///
  /// This is called when the app is opened, so the "Device Security" screen
  /// always shows an up to date position of every device. Failures are
  /// ignored: the app works without a position.
  Future<bool> syncCurrentDevice({bool askPermission = true}) async {
    final token = _accessToken;
    if (token == null || token.isEmpty) return false;

    try {
      final profile = await DeviceLocationService.currentProfile(
        askPermission: askPermission,
      );

      final response = await http
          .put(
            Uri.parse('$baseUrl/devices/current'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode(profile.toJson()),
          )
          .timeout(_timeout);

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('AuthProvider: could not sync the device: $e');
      return false;
    }
  }

  Future<void> logout() async {
    // Remember the account id before the token is dropped, the local chat
    // cache of that account is removed as well.
    final userId = currentUserId;

    // Best effort: revoke this device session on the server (POST /api/auth/logout).
    // Failures are ignored so signing out always works offline too.
    final token = _accessToken;
    if (token != null && token.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse('$baseUrl/logout'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Ignore: local sign-out must never be blocked by the network.
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    // Drop the cached chats of this account so the next user starts clean.
    if (userId != null && userId.isNotEmpty) {
      await CacheService.clearUser(userId);
    }
    notifyListeners(); // UI watching isAuthenticated switches to the login page
  }
}