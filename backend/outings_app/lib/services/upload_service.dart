// lib/services/upload_service.dart
import 'dart:async'; // for TimeoutException
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import 'package:outings_app/config/app_config.dart';

class UploadResult {
  final String url;
  final String? fileName;
  final int? fileSize;
  const UploadResult({required this.url, this.fileName, this.fileSize});
}

class UploadService {
  final String _base = AppConfig.apiBaseUrl;

  /// Uploads a file to the backend: POST /api/uploads (multipart)
  /// Returns a public URL for the uploaded file.
  Future<UploadResult> uploadFile(
    File file, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse('$_base/api/uploads');
    final req = http.MultipartRequest('POST', uri);

    final mime = lookupMimeType(file.path) ?? 'application/octet-stream';
    final length = await file.length();

    final part = await http.MultipartFile.fromPath(
      'file',
      file.path,
      filename: p.basename(file.path),
      contentType: MediaType.parse(mime), // <- use http_parser's MediaType
    );

    req.files.add(part);

    http.StreamedResponse streamed;
    try {
      streamed = await req.send().timeout(timeout);
    } on SocketException catch (e) {
      throw Exception('Upload failed: network error ($e)');
    } on HttpException catch (e) {
      throw Exception('Upload failed: HTTP error ($e)');
    } on TimeoutException {
      throw Exception('Upload failed: request timed out after ${timeout.inSeconds}s');
    }

    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Upload failed (${res.statusCode}): ${res.body}');
    }

    Map<String, dynamic> jsonBody;
    try {
      jsonBody = json.decode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Upload failed: invalid JSON response: ${res.body}');
    }

    final url = (jsonBody['url'] as String?) ?? '';
    if (url.isEmpty) {
      throw Exception('Upload response missing "url": ${res.body}');
    }

    final name = jsonBody['fileName'] as String?;
    final size = (jsonBody['fileSize'] is int)
        ? jsonBody['fileSize'] as int
        : int.tryParse('${jsonBody['fileSize']}');

    return UploadResult(url: url, fileName: name, fileSize: size ?? length);
  }
}
