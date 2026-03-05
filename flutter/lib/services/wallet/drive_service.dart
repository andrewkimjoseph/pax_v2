import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class DriveService {
  static const String _fileName = 'pax_wallet_backup.enc';
  static const String _baseUrl = 'https://www.googleapis.com/drive/v3';
  static const String _uploadUrl =
      'https://www.googleapis.com/upload/drive/v3/files';

  final String accessToken;
  final http.Client _client = http.Client();

  DriveService({required this.accessToken});

  Future<String?> findAppDataFile() async {
    if (kDebugMode) {
      debugPrint('Drive: listing app data folder');
    }
    final uri = Uri.parse('$_baseUrl/files').replace(
      queryParameters: {
        'spaces': 'appDataFolder',
        'fields': 'files(id,name)',
        'pageSize': '10',
      },
    );
    final response = await _client.get(uri, headers: _authHeaders());
    if (response.statusCode != 200) {
      if (kDebugMode) {
        debugPrint('Drive: list failed ${response.statusCode} ${response.body}');
      }
      throw DriveException(
        _messageForStatus(response.statusCode, response.body, 'List'),
        response.statusCode,
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final files = data['files'] as List<dynamic>? ?? [];
    for (final f in files) {
      final map = f as Map<String, dynamic>;
      if (map['name'] == _fileName) {
        final id = map['id'] as String?;
        if (kDebugMode) {
          debugPrint('Drive: backup found (fileId present)');
        }
        return id;
      }
    }
    if (kDebugMode) {
      debugPrint('Drive: no backup file found');
    }
    return null;
  }

  Future<String> download(String fileId) async {
    if (kDebugMode) {
      debugPrint('Drive: downloading backup');
    }
    final uri = Uri.parse(
      '$_baseUrl/files/$fileId',
    ).replace(queryParameters: {'alt': 'media'});
    final response = await _client.get(uri, headers: _authHeaders());
    if (response.statusCode != 200) {
      if (kDebugMode) {
        debugPrint(
          'Drive: download failed ${response.statusCode} ${response.body}',
        );
      }
      throw DriveException(
        _messageForStatus(response.statusCode, response.body, 'Download'),
        response.statusCode,
      );
    }
    if (kDebugMode) {
      debugPrint('Drive: download OK (${response.body.length} bytes)');
    }
    return response.body;
  }

  Future<void> upload(String content, {String? existingFileId}) async {
    if (kDebugMode) {
      debugPrint('Drive: uploading backup');
    }
    final metadata = {
      'name': _fileName,
      'parents': ['appDataFolder'],
    };
    if (existingFileId != null) {
      await _updateFile(existingFileId, content);
      if (kDebugMode) {
        debugPrint('Drive: upload OK (updated)');
      }
      return;
    }
    await _createFile(metadata, content);
    if (kDebugMode) {
      debugPrint('Drive: upload OK (created)');
    }
  }

  Future<void> _createFile(
    Map<String, dynamic> metadata,
    String content,
  ) async {
    const boundary = 'pax_wallet_boundary';
    final body = _multipartBody(boundary, metadata, content);
    final response = await _client.post(
      Uri.parse('$_uploadUrl?uploadType=multipart'),
      headers: {
        ..._authHeaders(),
        'Content-Type': 'multipart/related; boundary=$boundary',
        'Content-Length': body.length.toString(),
      },
      body: body,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      if (kDebugMode) {
        debugPrint(
          'Drive: upload failed ${response.statusCode} ${response.body}',
        );
      }
      throw DriveException(
        _messageForStatus(response.statusCode, response.body, 'Upload'),
        response.statusCode,
      );
    }
  }

  Future<void> _updateFile(String fileId, String content) async {
    final response = await _client.patch(
      Uri.parse('$_uploadUrl/$fileId?uploadType=media'),
      headers: {..._authHeaders(), 'Content-Type': 'application/octet-stream'},
      body: content,
    );
    if (response.statusCode != 200) {
      if (kDebugMode) {
        debugPrint(
          'Drive: update failed ${response.statusCode} ${response.body}',
        );
      }
      throw DriveException(
        _messageForStatus(response.statusCode, response.body, 'Update'),
        response.statusCode,
      );
    }
  }

  List<int> _multipartBody(
    String boundary,
    Map<String, dynamic> metadata,
    String content,
  ) {
    final parts = <List<int>>[];
    parts.add(utf8.encode('--$boundary\r\n'));
    parts.add(
      utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'),
    );
    parts.add(utf8.encode(jsonEncode(metadata)));
    parts.add(utf8.encode('\r\n--$boundary\r\n'));
    parts.add(utf8.encode('Content-Type: application/octet-stream\r\n\r\n'));
    parts.add(utf8.encode(content));
    parts.add(utf8.encode('\r\n--$boundary--\r\n'));
    return parts.expand((e) => e).toList();
  }

  Map<String, String> _authHeaders() => {
    'Authorization': 'Bearer $accessToken',
    'Content-Type': 'application/json',
  };

  static String _messageForStatus(
    int statusCode,
    String body,
    String operation,
  ) {
    if (statusCode == 403) {
      String hint =
          'Enable the Drive API in Google Cloud Console (APIs & Services → Library → Google Drive API), '
          'then sign out and sign in again so the app can access Drive.';
      try {
        final json = jsonDecode(body) as Map<String, dynamic>?;
        final error = json?['error'] as Map<String, dynamic>?;
        final message = error?['message'] as String?;
        if (message != null && message.isNotEmpty) {
          if (message.toLowerCase().contains('not been used') ||
              message.toLowerCase().contains('access not configured')) {
            hint =
                'Drive API is not enabled. In Google Cloud Console go to APIs & Services → Library, '
                'search for "Google Drive API", enable it, then sign out and sign in again.';
          } else if (message.toLowerCase().contains('insufficient') ||
              message.toLowerCase().contains('permission') ||
              message.toLowerCase().contains('scope')) {
            hint =
                'Drive access was not granted. Sign out, then sign in again and accept the requested permissions.';
          }
        }
      } catch (_) {}
      return '$operation failed: 403 Forbidden. $hint';
    }
    return '$operation failed: $statusCode';
  }

  void close() => _client.close();
}

class DriveException implements Exception {
  DriveException(this.message, this.statusCode);
  final String message;
  final int statusCode;
  @override
  String toString() => 'DriveException: $message (statusCode: $statusCode)';
}
