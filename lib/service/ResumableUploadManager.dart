import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_in_chat/api/api.dart';
import 'package:love_in_chat/model/emun/MessageType.dart';
import 'package:love_in_chat/service/StompService.dart';

/// Progress information for an active or queued upload.
class UploadProgressInfo {
  final String uploadId;
  final String fileName;
  final double progress; // 0.0 to 1.0
  final bool isCompleted;
  final bool isFailed;
  final String? errorMessage;
  final String? remoteUrl;

  const UploadProgressInfo({
    required this.uploadId,
    required this.fileName,
    required this.progress,
    this.isCompleted = false,
    this.isFailed = false,
    this.errorMessage,
    this.remoteUrl,
  });
}

/// Fault-tolerant resumable chunked upload manager.
///
/// Features:
/// 1. Slices files using RandomAccessFile in 2MB chunks without loading full file into RAM.
/// 2. Persists upload task state in local storage to resume after app restart or network drop.
/// 3. Inquires HEAD /api/media/uploads/{id} on reconnect to resume from exact server byte offset.
/// 4. Exponential backoff retry logic.
/// 5. Automatically dispatches the STOMP message when upload completes and is verified.
class ResumableUploadManager {
  static final ResumableUploadManager _instance = ResumableUploadManager._internal();
  factory ResumableUploadManager() => _instance;
  ResumableUploadManager._internal();

  static const int chunkSize = 2 * 1024 * 1024; // 2MB chunk
  static const String _storagePrefix = 'resumable_upload_task_';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 25),
    sendTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 30),
  ));

  final Map<String, StreamController<UploadProgressInfo>> _progressControllers = {};

  Stream<UploadProgressInfo> watchUpload(String uploadId) {
    _progressControllers.putIfAbsent(uploadId, () => StreamController<UploadProgressInfo>.broadcast());
    return _progressControllers[uploadId]!.stream;
  }

  void _emitProgress(UploadProgressInfo info) {
    final controller = _progressControllers[info.uploadId];
    if (controller != null && !controller.isClosed) {
      controller.add(info);
    }
  }

  /// Streaming SHA-256 calculation to keep memory flat even for 2GB+ files.
  Future<String> computeSha256(File file) async {
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }

  /// Starts or resumes an upload.
  Future<String?> uploadFile({
    required File file,
    required String conversationId,
    required MessageType messageType,
    required String accessToken,
    String? customMimeType,
    Function(double progress)? onProgress,
  }) async {
    final totalSize = await file.length();
    final fileName = file.uri.pathSegments.last;
    final mimeType = customMimeType ?? _detectMimeType(fileName, messageType);

    final prefs = await SharedPreferences.getInstance();
    final storageKey = '$_storagePrefix${file.path.hashCode}';

    String? uploadId;
    int currentOffset = 0;

    // Check if there is an active session recorded locally
    final savedJson = prefs.getString(storageKey);
    if (savedJson != null) {
      try {
        final data = json.decode(savedJson);
        final candidateId = data['uploadId'] as String;
        // Verify with backend via HEAD request
        final remoteOffset = await checkRemoteOffset(candidateId, accessToken);
        if (remoteOffset >= 0) {
          uploadId = candidateId;
          currentOffset = remoteOffset;
          debugPrint('[ResumableUpload] Resuming upload $uploadId from offset $currentOffset');
        }
      } catch (e) {
        debugPrint('[ResumableUpload] Failed to recover previous task: $e');
      }
    }

    // Initialize new session if not resumed
    if (uploadId == null) {
      final sha256Hash = await computeSha256(file);
      final initResult = await _initSession(
        fileName: fileName,
        mimeType: mimeType,
        totalSize: totalSize,
        fileHash: sha256Hash,
        accessToken: accessToken,
      );
      if (initResult == null) {
        _emitProgress(UploadProgressInfo(
          uploadId: 'failed',
          fileName: fileName,
          progress: 0.0,
          isFailed: true,
          errorMessage: 'Could not initialize upload session on server',
        ));
        return null;
      }
      uploadId = initResult;
      currentOffset = 0;

      // Persist to local storage
      await prefs.setString(storageKey, json.encode({
        'uploadId': uploadId,
        'filePath': file.path,
        'conversationId': conversationId,
        'totalSize': totalSize,
      }));
    }

    _progressControllers.putIfAbsent(uploadId, () => StreamController<UploadProgressInfo>.broadcast());

    // Execute chunk streaming loop
    final remoteUrl = await _chunkUploadLoop(
      file: file,
      uploadId: uploadId,
      totalSize: totalSize,
      startOffset: currentOffset,
      accessToken: accessToken,
      onProgress: onProgress,
    );

    if (remoteUrl != null) {
      await prefs.remove(storageKey);
      _emitProgress(UploadProgressInfo(
        uploadId: uploadId,
        fileName: fileName,
        progress: 1.0,
        isCompleted: true,
        remoteUrl: remoteUrl,
      ));

      // Dispatch STOMP message
      StompService().sendMessage(conversationId, remoteUrl);
      return remoteUrl;
    } else {
      _emitProgress(UploadProgressInfo(
        uploadId: uploadId,
        fileName: fileName,
        progress: (currentOffset / totalSize).clamp(0.0, 1.0),
        isFailed: true,
        errorMessage: 'Upload interrupted. Will resume automatically.',
      ));
      return null;
    }
  }

  Future<String?> _initSession({
    required String fileName,
    required String mimeType,
    required int totalSize,
    required String fileHash,
    required String accessToken,
  }) async {
    try {
      final response = await _dio.post(
        '$REST_URL/api/media/uploads',
        options: Options(headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        }),
        data: {
          'fileName': fileName,
          'mimeType': mimeType,
          'totalSize': totalSize,
          'fileHash': fileHash,
        },
      );
      if (response.statusCode == 201 && response.data != null) {
        return response.data['uploadId'] as String;
      }
    } catch (e) {
      debugPrint('[ResumableUpload] Init session error: $e');
    }
    return null;
  }

  Future<int> checkRemoteOffset(String uploadId, String accessToken) async {
    try {
      final response = await _dio.head(
        '$REST_URL/api/media/uploads/$uploadId',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final offsetHeader = response.headers.value('Upload-Offset');
      if (offsetHeader != null) {
        return int.parse(offsetHeader);
      }
    } catch (e) {
      debugPrint('[ResumableUpload] Check offset error: $e');
    }
    return -1;
  }

  Future<String?> _chunkUploadLoop({
    required File file,
    required String uploadId,
    required int totalSize,
    required int startOffset,
    required String accessToken,
    Function(double progress)? onProgress,
  }) async {
    int currentOffset = startOffset;
    final raf = await file.open(mode: FileMode.read);

    try {
      while (currentOffset < totalSize) {
        final remaining = totalSize - currentOffset;
        final bytesToRead = min(chunkSize, remaining);

        await raf.setPosition(currentOffset);
        final chunkData = await raf.read(bytesToRead);

        bool chunkUploaded = false;
        int attempts = 0;
        const maxAttempts = 5;

        while (!chunkUploaded && attempts < maxAttempts) {
          try {
            final response = await _dio.patch(
              '$REST_URL/api/media/uploads/$uploadId',
              data: Stream.fromIterable([chunkData]),
              options: Options(
                headers: {
                  'Authorization': 'Bearer $accessToken',
                  'Upload-Offset': currentOffset.toString(),
                  'Content-Type': 'application/octet-stream',
                  'Content-Length': chunkData.length.toString(),
                },
              ),
            );

            if (response.statusCode == 200 || response.statusCode == 204) {
              currentOffset += chunkData.length;
              final p = (currentOffset / totalSize).clamp(0.0, 1.0);
              onProgress?.call(p);
              _emitProgress(UploadProgressInfo(
                uploadId: uploadId,
                fileName: file.uri.pathSegments.last,
                progress: p,
              ));

              chunkUploaded = true;

              if (response.statusCode == 200 && response.data != null) {
                return response.data['fileUrl'] as String?;
              }
            }
          } catch (e) {
            attempts++;
            debugPrint('[ResumableUpload] Chunk at $currentOffset failed (attempt $attempts): $e');
            await Future.delayed(Duration(milliseconds: 400 * pow(2, attempts).toInt()));

            // Synchronize with server offset on error
            final syncedOffset = await checkRemoteOffset(uploadId, accessToken);
            if (syncedOffset >= 0) {
              currentOffset = syncedOffset;
            }
          }
        }

        if (!chunkUploaded) {
          debugPrint('[ResumableUpload] Failed chunk at offset $currentOffset after $maxAttempts attempts.');
          return null;
        }
      }
    } finally {
      await raf.close();
    }
    return null;
  }

  String _detectMimeType(String fileName, MessageType type) {
    final lower = fileName.toLowerCase();
    if (type == MessageType.VIDEO || lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.mkv')) {
      return 'video/mp4';
    }
    if (type == MessageType.VOICE || lower.endsWith('.m4a') || lower.endsWith('.mp3') || lower.endsWith('.wav')) {
      return 'audio/m4a';
    }
    if (type == MessageType.IMAGE || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }
}
