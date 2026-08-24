import 'package:flutter_test/flutter_test.dart';
import 'package:pax/services/wallet/wallet_backup_reconciliation.dart';

void main() {
  group('normalizeEoAddress', () {
    test('lowercases and strips 0x prefix', () {
      expect(normalizeEoAddress('0xABCDEF'), 'abcdef');
    });

    test('handles missing 0x prefix', () {
      expect(normalizeEoAddress('ABCDEF'), 'abcdef');
    });

    test('returns empty string for null or empty input', () {
      expect(normalizeEoAddress(null), '');
      expect(normalizeEoAddress(''), '');
    });
  });

  group('selectBackupWinner with a known expectedEoAddress', () {
    test('picks the single matching candidate', () {
      final result = selectBackupWinner(
        decrypted: [
          const DecryptedBackupCandidate(fileId: 'a', eoAddress: '0x111'),
          const DecryptedBackupCandidate(fileId: 'b', eoAddress: '0x222'),
        ],
        totalCandidateCount: 2,
        expectedEoAddress: '0x222',
      );

      expect(result.isSuccess, isTrue);
      expect(result.winnerFileId, 'b');
      expect(result.errorMessage, isNull);
    });

    test('matches case-insensitively and ignores 0x prefix differences', () {
      final result = selectBackupWinner(
        decrypted: [
          const DecryptedBackupCandidate(fileId: 'a', eoAddress: 'ABCDEF'),
        ],
        totalCandidateCount: 1,
        expectedEoAddress: '0xabcdef',
      );

      expect(result.isSuccess, isTrue);
      expect(result.winnerFileId, 'a');
    });

    test('fails with a diagnostic message when no candidate matches', () {
      final result = selectBackupWinner(
        decrypted: [
          const DecryptedBackupCandidate(fileId: 'a', eoAddress: '0x111'),
          const DecryptedBackupCandidate(fileId: 'b', eoAddress: '0x222'),
        ],
        totalCandidateCount: 2,
        expectedEoAddress: '0x333',
      );

      expect(result.isSuccess, isFalse);
      expect(result.winnerFileId, isNull);
      expect(result.errorMessage, contains('none match'));
      expect(result.errorMessage, contains('2 wallet backups'));
    });

    test('fails with a diagnostic message when multiple candidates match', () {
      final result = selectBackupWinner(
        decrypted: [
          const DecryptedBackupCandidate(fileId: 'a', eoAddress: '0x111'),
          const DecryptedBackupCandidate(fileId: 'b', eoAddress: '0x111'),
        ],
        totalCandidateCount: 2,
        expectedEoAddress: '0x111',
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('2 match'));
    });

    test('counts candidates that failed to decrypt in the diagnostic message', () {
      // Only 1 of 3 total Drive files could be decrypted/derived; the other
      // 2 are omitted from `decrypted` entirely (as the real caller would do
      // for candidates that threw during decrypt).
      final result = selectBackupWinner(
        decrypted: [
          const DecryptedBackupCandidate(fileId: 'a', eoAddress: '0x111'),
        ],
        totalCandidateCount: 3,
        expectedEoAddress: '0x999',
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('3 wallet backups'));
    });
  });

  group('selectBackupWinner with no expectedEoAddress (no Firestore pin yet)', () {
    test('defaults to the first (newest) decrypted candidate', () {
      final result = selectBackupWinner(
        decrypted: [
          const DecryptedBackupCandidate(fileId: 'newest'),
          const DecryptedBackupCandidate(fileId: 'oldest'),
        ],
        totalCandidateCount: 2,
      );

      expect(result.isSuccess, isTrue);
      expect(result.winnerFileId, 'newest');
    });

    test('fails when every candidate failed to decrypt', () {
      final result = selectBackupWinner(
        decrypted: const [],
        totalCandidateCount: 2,
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Unable to restore'));
      expect(result.errorMessage, contains('2 wallet backups'));
    });
  });
}
