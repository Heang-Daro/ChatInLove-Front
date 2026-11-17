import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Fault-tolerant resumable file downloader.
///
/// Features:
/// 1. Saves partial chunks to a `.part` file.
/// 2. Detects existing file length on restart and sends `Range: bytes=$length-`.
/// 3. Renames `.part` to final file only upon 100% completion.
class ResumableDownloader {
  static final ResumableDownloader _instance = ResumableDownloader._internal();
  factory ResumableDownloader() => _instance;
  ResumableDownloader._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 60),
  ));

  Future<File?> download({
    required String fileUrl,
    required String fileName,
    String? accessToken,
    Function(double progress)? onProgress,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final finalFile = File('${dir.path}/$fileName');
      final partFile = File('${dir.path}/$fileName.part');

      if (await finalFile.exists()) {
        onProgress?.call(1.0);
        return finalFile;
      }

      int existingLength = 0;
      if (await partFile.exists()) {
        existingLength = await partFile.length();
      }

      final headers = <String, dynamic>{
        if (accessToken != null && accessToken.isNotEmpty) 'Authorization': 'Bearer $accessToken',
      };

      if (existingLength > 0) {
        headers['Range'] = 'bytes=$existingLength-';
      }

      final response = await _dio.get<ResponseBody>(
        fileUrl,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
        ),
      );

      final totalHeader = response.headers.value('Content-Length');
      final totalBytes = (totalHeader != null ? int.parse(totalHeader) : 0) + existingLength;

      final sink = partFile.openWrite(mode: FileMode.append);
      int received = existingLength;

      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call((received / totalBytes).clamp(0.0, 1.0));
        }
      }

      await sink.flush();
      await sink.close();

      // Rename upon complete transfer
      await partFile.rename(finalFile.path);
      onProgress?.call(1.0);
      return finalFile;
    } catch (e) {
      debugPrint('[ResumableDownloader] Error: $e');
      return null;
    }
  }
}
