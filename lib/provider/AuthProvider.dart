import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
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
  Completer<bool>? _refreshing;

  String? get accessToken => _accessToken;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _accessToken != null;

  String? get currentUserId {
    final payload = _jwtPayload;
    if (payload == null) return null;
    final value = payload['sub'] ?? payload['userId'] ?? payload['id'];
    return value is String ? value : value?.toString();
  }

  String? get currentSessionId {
    final payload = _jwtPayload;
    if (payload == null) return null;
    final value = payload['sid'] ?? payload['sessionId'];
    return value is String ? value : value?.toString();
  }

  Map<String, dynamic>? get _jwtPayload {
    final token = _accessToken;
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      return json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  AuthProvider() { _init(); }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessKey);
    _refreshToken = prefs.getString(_refreshKey);
    final needsRefresh = _accessToken == null || _isExpired(_accessToken!);
    if (needsRefresh) {
      if (_refreshToken != null) {
        final success = await refreshAccessToken();
        if (success && _accessToken != null) await _fetchUserProfile(_accessToken!);
      } else {
        await logout();
      }
    } else if (_accessToken != null) {
      await _fetchUserProfile(_accessToken!);
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _fetchUserProfile(String token) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/principal'), headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      }).timeout(_timeout);
      if (response.statusCode == 200) {
        _currentUser = UserResponse.fromJson(json.decode(response.body));
        notifyListeners();
      }
    } catch (_) {}
  }

  bool _isExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! num) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      return DateTime.now().isAfter(expiry.subtract(const Duration(seconds: 30)));
    } catch (_) { return false; }
  }

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

  Future<bool> refreshAccessToken() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight.future;
    final completer = _refreshing = Completer<bool>();
    _doRefresh().then(completer.complete).whenComplete(() => _refreshing = null);
    return completer.future;
  }

  Future<bool> _doRefresh() async {
    final rt = _refreshToken;
    if (rt == null || rt.trim().isEmpty) { await logout(); return false; }
    try {
      final response = await http.post(Uri.parse('$baseUrl/refresh'),
          headers: {'Content-Type': 'application/json'}, body: json.encode({'refreshToken': rt})).timeout(_timeout);
      if (response.statusCode == 200) {
        final auth = AuthResponse.fromJson(json.decode(response.body));
        await _saveTokens(auth.accessToken, auth.refreshToken.isNotEmpty ? auth.refreshToken : rt);
        await _fetchUserProfile(auth.accessToken);
        return true;
      }
      _errorMessage = 'Session expired. Please log in again.';
      await logout();
      return false;
    } catch (_) { return false; }
  }

  Future<http.Response> authorizedRequest(Future<http.Response> Function(String token) send) async {
    var token = _accessToken;
    if (token == null) { await logout(); throw StateError('Not authenticated'); }
    if (_isExpired(token)) {
      if (!await refreshAccessToken()) { await logout(); throw StateError('Session expired'); }
      token = _accessToken!;
    }
    var response = await send(token).timeout(_timeout);
    if (response.statusCode == 401 || response.statusCode == 403) {
      if (await refreshAccessToken()) {
        response = await send(_accessToken!).timeout(_timeout);
        if (response.statusCode == 401 || response.statusCode == 403) { await logout(); throw StateError('Unauthorized access'); }
      } else { await logout(); throw StateError('Session refresh failed'); }
    }
    return response;
  }

  Future<String?> updateProfile({required String username, required String email}) async {
    try {
      final response = await authorizedRequest((token) => http.put(Uri.parse('$baseUrl/profile'), headers: {
        'Content-Type': 'application/json', 'Authorization': 'Bearer $token',
      }, body: json.encode({'username': username.trim(), 'email': email.trim()})));
      if (response.statusCode == 200) {
        _currentUser = UserResponse.fromJson(json.decode(response.body));
        notifyListeners();
        return null;
      }
      return _responseMessage(response, 'Could not update your profile.');
    } catch (error) { return _friendlyError(error); }
  }

  /// Uploads a profile avatar or foreground image using the authenticated
  /// multipart API. Returns null on success, otherwise a displayable error.
  Future<String?> uploadUserImage(XFile image, {required bool foreground}) async {
    // Use a longer timeout for file uploads (cold-start servers can be slow).
    const uploadTimeout = Duration(seconds: 60);
    try {
      final bytes = await image.readAsBytes();
      final endpoint = foreground ? 'profile/foreground' : 'profile/image';

      // Build and send the multipart request directly so we can apply our own
      // timeout — authorizedRequest's 15-second timeout is too short for uploads.
      var token = _accessToken;
      if (token == null) return 'Not authenticated. Please log in again.';
      if (_isExpired(token)) {
        if (!await refreshAccessToken()) return 'Session expired. Please log in again.';
        token = _accessToken!;
      }

      Future<http.Response> doUpload(String tkn) async {
        final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/$endpoint'));
        request.headers['Authorization'] = 'Bearer $tkn';
        request.files.add(http.MultipartFile.fromBytes(
          'file', bytes,
          filename: image.name.isNotEmpty ? image.name : 'profile-image.jpg',
        ));
        final streamed = await request.send().timeout(uploadTimeout);
        return http.Response.fromStream(streamed).timeout(uploadTimeout);
      }

      var response = await doUpload(token);

      // Transparent token refresh on 401/403.
      if (response.statusCode == 401 || response.statusCode == 403) {
        if (await refreshAccessToken()) {
          response = await doUpload(_accessToken!);
        } else {
          await logout();
          return 'Session expired. Please log in again.';
        }
      }

      if (response.statusCode == 200) {
        _currentUser = UserResponse.fromJson(json.decode(response.body));
        notifyListeners();
        return null;
      }
      debugPrint('[uploadUserImage] HTTP ${response.statusCode}: ${response.body}');
      return _responseMessage(response, 'Could not upload the image (HTTP ${response.statusCode}).');
    } on TimeoutException {
      return 'Upload timed out. The server may be starting up — please try again in a moment.';
    } catch (error) {
      debugPrint('[uploadUserImage] Error: $error');
      return _friendlyError(error);
    }
  }

  Future<String?> changePassword({required String currentPassword, required String newPassword}) async {
    try {
      final response = await authorizedRequest((token) => http.put(Uri.parse('$baseUrl/change-password'), headers: {
        'Content-Type': 'application/json', 'Authorization': 'Bearer $token',
      }, body: json.encode({'currentPassword': currentPassword, 'newPassword': newPassword})));
      if (response.statusCode == 204 || response.statusCode == 200) return null;
      return _responseMessage(response, 'Could not change your password.');
    } catch (error) { return _friendlyError(error); }
  }

  String _responseMessage(http.Response response, String fallback) {
    try {
      final body = json.decode(response.body);
      if (body is Map<String, dynamic> && body['message'] is String) return body['message'] as String;
    } catch (_) {}
    return fallback;
  }

  String _friendlyError(Object error) {
    if (error is TimeoutException) return 'Request timed out. Please try again.';
    if (error is StateError) return error.message;
    return 'Connection error. Please try again.';
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true; _errorMessage = null; notifyListeners();
    try {
      final profile = await DeviceLocationService.currentProfile();
      final request = LoginRequest(email: email, password: password, location: profile.location,
          deviceName: profile.deviceName, deviceType: profile.deviceType);
      final response = await http.post(Uri.parse('$baseUrl/login'), headers: {'Content-Type': 'application/json'},
          body: json.encode(request.toJson())).timeout(_timeout);
      if (response.statusCode == 200) {
        final auth = AuthResponse.fromJson(json.decode(response.body));
        await _saveTokens(auth.accessToken, auth.refreshToken);
        await _fetchUserProfile(auth.accessToken);
        _isLoading = false; notifyListeners(); return true;
      }
      _errorMessage = 'Invalid email or password';
    } on TimeoutException { _errorMessage = 'Connection timed out. Please try again.'; }
    catch (e) { _errorMessage = 'Network error: $e'; }
    _isLoading = false; notifyListeners(); return false;
  }

  Future<bool> register(String email, String username, String password) async {
    _isLoading = true; _errorMessage = null; notifyListeners();
    try {
      final request = RegisterRequest(email: email, username: username, password: password);
      final response = await http.post(Uri.parse('$baseUrl/register'), headers: {'Content-Type': 'application/json'},
          body: json.encode(request.toJson())).timeout(_timeout);
      if (response.statusCode == 201 || response.statusCode == 200) {
        final auth = AuthResponse.fromJson(json.decode(response.body));
        await _saveTokens(auth.accessToken, auth.refreshToken);
        await _fetchUserProfile(auth.accessToken);
        _isLoading = false; notifyListeners(); return true;
      }
      _errorMessage = 'Registration failed';
    } on TimeoutException { _errorMessage = 'Connection timed out. Please try again.'; }
    catch (e) { _errorMessage = 'Network error: $e'; }
    _isLoading = false; notifyListeners(); return false;
  }

  Future<bool> syncCurrentDevice({bool askPermission = true}) async {
    final token = _accessToken;
    if (token == null || token.isEmpty) return false;
    try {
      final profile = await DeviceLocationService.currentProfile(askPermission: askPermission);
      final response = await http.put(Uri.parse('$baseUrl/devices/current'), headers: {
        'Content-Type': 'application/json', 'Authorization': 'Bearer $token',
      }, body: json.encode(profile.toJson())).timeout(_timeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) { debugPrint('AuthProvider: could not sync the device: $e'); return false; }
  }

  Future<void> logout() async {
    final userId = currentUserId;
    final token = _accessToken;
    if (token != null && token.isNotEmpty) {
      try {
        await http.post(Uri.parse('$baseUrl/logout'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey); await prefs.remove(_refreshKey);
    _accessToken = null; _refreshToken = null; _currentUser = null;
    if (userId != null && userId.isNotEmpty) await CacheService.clearUser(userId);
    notifyListeners();
  }
}
