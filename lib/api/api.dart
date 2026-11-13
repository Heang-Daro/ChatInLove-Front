import 'package:flutter/foundation.dart';

// Set your computer's local Wi-Fi IP address here when testing on a real physical device:
const String SERVER_IP = "10.1.68.109";

String get defaultHost {
  if (kIsWeb) return SERVER_IP;
  if (SERVER_IP.isNotEmpty) return SERVER_IP;
  if (defaultTargetPlatform == TargetPlatform.android) return "10.0.2.2";
  return SERVER_IP;
}

final String HOST = defaultHost;
const String PORT = "2026";
const String PROTOCOL = "http";
const String PROTOCOL_SOCKET = "ws";
final String REST_URL = "$PROTOCOL://$HOST:$PORT";
final String SOCKET_URL = "$PROTOCOL_SOCKET://$HOST:$PORT";

/// Turns the content of a media/file message into a loadable URL.
///
/// Messages must store only the path returned by the server
/// (e.g. `/files/voice_123.m4a`), never a full `http://host:port/...` address,
/// otherwise every media message breaks as soon as the network IP or the
/// domain name changes. This helper always resolves the path against the
/// [REST_URL] that is configured right now.
///
/// Absolute URLs written by older versions of the app are re-pointed to the
/// current server origin (path + query are kept), so media sent before the
/// domain change keeps working too.
String resolveFileUrl(String content) {
  if (content.isEmpty) return content;

  final value = content.trim();
  if (value.isEmpty) return content;

  // ប្រសិនបើវាជា Supabase URL រួចស្រេចហើយ គឺទាញយកទៅប្រើប្រាស់ផ្ទាល់តែម្ដង មិនបាច់ប្រែប្រួលទេ!
  if (value.contains('supabase.co')) {
    return value;
  }

  // Relative path សម្រាប់ Server ចាស់ (ប្រសិនបើមាន)
  if (value.startsWith('/')) return '$REST_URL$value';

  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return value;

  final path = uri.path.isEmpty ? '/' : uri.path;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return '$REST_URL$path$query';
}

/// File name shown for a FILE message (works with relative paths and with
/// absolute URLs that still carry a `?query`).
String fileNameFromUrl(String content) {
  final value = content.trim();
  if (value.isEmpty) return value;

  final segments = Uri.tryParse(value)?.pathSegments ?? const <String>[];
  for (var i = segments.length - 1; i >= 0; i--) { // FIXED: Added missing minus '-' operator
    final segment = segments[i];
    if (segment.isNotEmpty) return segment;
  }
  return value;
}