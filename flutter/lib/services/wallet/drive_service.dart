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
      debugPrint('[Drive] Drive: listing app data folder');
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
        debugPrint(
          'Drive: list failed ${response.statusCode} ${response.body}',
        );
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
          debugPrint('[Drive] Drive: backup found (fileId present)');
        }
        return id;
      }
    }
    if (kDebugMode) {
      debugPrint('[Drive] Drive: no backup file found');
    }
    return null;
  }

  Future<String> download(String fileId) async {
    if (kDebugMode) {
      debugPrint('[Drive] Drive: downloading backup');
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
      debugPrint('[Drive] Drive: download OK (${response.body.length} bytes)');
    }
    return response.body;
  }

  Future<void> upload(String content, {String? existingFileId}) async {
    if (kDebugMode) {
      debugPrint('[Drive] Drive: uploading backup');
    }
    final metadata = {
      'name': _fileName,
      'parents': ['appDataFolder'],
    };
    if (existingFileId != null) {
      await _updateFile(existingFileId, content);
      if (kDebugMode) {
        debugPrint('[Drive] Drive: upload OK (updated)');
      }
      return;
    }
    await _createFile(metadata, content);
    if (kDebugMode) {
      debugPrint('[Drive] Drive: upload OK (created)');
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
      final hint = _hintForDrive403(body);
      return '$operation failed: 403 Forbidden. $hint';
    }
    return '$operation failed: $statusCode';
  }

  /// Maps Google Drive API error payloads to user-facing hints. Avoids implying
  /// the Drive API is disabled when the real cause is quota, policy, or scopes.
  static String _hintForDrive403(String body) {
    String? topMessage;
    final reasons = <String>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return _hintForDrive403Unknown();
      }
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        final m = error['message'];
        if (m is String) topMessage = m;
        final errors = error['errors'];
        if (errors is List<dynamic>) {
          for (final e in errors) {
            if (e is Map<String, dynamic>) {
              final r = e['reason'];
              if (r is String) reasons.add(r);
            }
          }
        }
      }
    } catch (_) {
      return _hintForDrive403Unknown();
    }

    bool reasonEquals(String name) =>
        reasons.any((r) => r.toLowerCase() == name.toLowerCase());

    if (reasonEquals('storageQuotaExceeded')) {
      return 'Your Google storage may be full. Free space in Drive, Gmail, or Google Photos, then try again.';
    }
    if (reasonEquals('teamDriveStorageQuotaExceeded')) {
      return 'Shared drive storage limit reached. Free space or ask an administrator, then try again.';
    }
    if (reasonEquals('domainPolicy')) {
      return 'Your organization may block this app from using Google Drive. Contact your administrator.';
    }
    if (reasonEquals('dailyLimitExceeded') ||
        reasonEquals('userRateLimitExceeded') ||
        reasonEquals('rateLimitExceeded')) {
      return 'Google Drive rate limit reached. Wait a few minutes and try again.';
    }
    if (reasonEquals('accessNotConfigured')) {
      return 'Google Drive is not available for this app build. If this keeps happening, contact support.';
    }

    final msg = (topMessage ?? '').toLowerCase();
    if (msg.contains('not been used') ||
        msg.contains('access not configured') ||
        msg.contains('has not been enabled')) {
      return 'Google Drive is not available for this app build. If this keeps happening, contact support.';
    }
    if (msg.contains('insufficient') ||
        msg.contains('permission') ||
        msg.contains('scope') ||
        reasonEquals('insufficientPermissions')) {
      return 'Drive access was not granted. Sign out, sign in again, and accept Google permissions when prompted.';
    }
    if (msg.contains('quota') || msg.contains('storage')) {
      return 'Your Google storage or quota may be exceeded. Free up space or try again later.';
    }

    return _hintForDrive403Unknown();
  }

  static String _hintForDrive403Unknown() {
    return 'Try signing out and signing in again. If your Google storage is full, free some space. '
        'Work or school accounts may restrict Drive access.';
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
