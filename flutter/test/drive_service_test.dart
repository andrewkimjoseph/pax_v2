import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pax/services/wallet/drive_service.dart';

http.Response _filesListResponse(List<Map<String, String>> files) {
  return http.Response(jsonEncode({'files': files}), 200);
}

void main() {
  group('DriveService.listAppDataFiles', () {
    test('requests createdTime desc ordering and only appDataFolder', () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return _filesListResponse([]);
      });

      final drive = DriveService(accessToken: 'token', client: client);
      await drive.listAppDataFiles();

      expect(capturedUri, isNotNull);
      expect(capturedUri!.queryParameters['spaces'], 'appDataFolder');
      expect(capturedUri!.queryParameters['orderBy'], 'createdTime desc');
    });

    test('filters out files that do not match the backup file name', () async {
      final client = MockClient(
        (request) async => _filesListResponse([
          {'id': 'other-1', 'name': 'not_a_backup.txt', 'createdTime': '2024-01-01T00:00:00.000Z'},
          {'id': 'backup-1', 'name': 'pax_wallet_backup.enc', 'createdTime': '2024-01-02T00:00:00.000Z'},
        ]),
      );

      final drive = DriveService(accessToken: 'token', client: client);
      final files = await drive.listAppDataFiles();

      expect(files.map((f) => f.id), ['backup-1']);
    });

    test('preserves the order returned by the API (newest first)', () async {
      final client = MockClient(
        (request) async => _filesListResponse([
          {'id': 'newest', 'name': 'pax_wallet_backup.enc', 'createdTime': '2024-03-01T00:00:00.000Z'},
          {'id': 'middle', 'name': 'pax_wallet_backup.enc', 'createdTime': '2024-02-01T00:00:00.000Z'},
          {'id': 'oldest', 'name': 'pax_wallet_backup.enc', 'createdTime': '2024-01-01T00:00:00.000Z'},
        ]),
      );

      final drive = DriveService(accessToken: 'token', client: client);
      final files = await drive.listAppDataFiles();

      expect(files.map((f) => f.id).toList(), ['newest', 'middle', 'oldest']);
      expect(files.first.createdTime!.isAfter(files.last.createdTime!), isTrue);
    });

    test('throws DriveException on non-200 response', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({'error': {'message': 'boom', 'errors': []}}),
          500,
        ),
      );

      final drive = DriveService(accessToken: 'token', client: client);

      expect(drive.listAppDataFiles(), throwsA(isA<DriveException>()));
    });
  });

  group('DriveService.findAppDataFile', () {
    test('returns null when no backup files exist', () async {
      final client = MockClient((request) async => _filesListResponse([]));
      final drive = DriveService(accessToken: 'token', client: client);

      expect(await drive.findAppDataFile(), isNull);
    });

    test('returns the newest file id when duplicates exist', () async {
      final client = MockClient(
        (request) async => _filesListResponse([
          {'id': 'newest', 'name': 'pax_wallet_backup.enc', 'createdTime': '2024-03-01T00:00:00.000Z'},
          {'id': 'oldest', 'name': 'pax_wallet_backup.enc', 'createdTime': '2024-01-01T00:00:00.000Z'},
        ]),
      );
      final drive = DriveService(accessToken: 'token', client: client);

      expect(await drive.findAppDataFile(), 'newest');
    });
  });

  group('DriveService.upload', () {
    test('creates a new file when no existingFileId is given', () async {
      String? method;
      final client = MockClient((request) async {
        method = request.method;
        return http.Response('{}', 200);
      });
      final drive = DriveService(accessToken: 'token', client: client);

      await drive.upload('encrypted-content');

      expect(method, 'POST');
    });

    test('updates the existing file in place when existingFileId is given', () async {
      String? method;
      Uri? url;
      final client = MockClient((request) async {
        method = request.method;
        url = request.url;
        return http.Response('{}', 200);
      });
      final drive = DriveService(accessToken: 'token', client: client);

      await drive.upload('encrypted-content', existingFileId: 'file-123');

      expect(method, 'PATCH');
      expect(url!.path, contains('file-123'));
    });
  });

  group('DriveService.deleteFile', () {
    test('issues a DELETE request for the given file id', () async {
      String? method;
      Uri? url;
      final client = MockClient((request) async {
        method = request.method;
        url = request.url;
        return http.Response('', 204);
      });
      final drive = DriveService(accessToken: 'token', client: client);

      await drive.deleteFile('file-456');

      expect(method, 'DELETE');
      expect(url!.path, contains('file-456'));
    });

    test('throws DriveException on failure', () async {
      final client = MockClient((request) async => http.Response('nope', 403));
      final drive = DriveService(accessToken: 'token', client: client);

      expect(drive.deleteFile('file-456'), throwsA(isA<DriveException>()));
    });
  });
}
