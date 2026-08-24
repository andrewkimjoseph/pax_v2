/// Pure logic for choosing which Google Drive wallet backup is correct when
/// more than one `pax_wallet_backup.enc` file exists for the same account.
///
/// This is deliberately free of I/O (no Drive/network/storage calls) so the
/// decision logic can be unit tested without mocking encryption, HTTP, or
/// platform channels. Callers are responsible for decrypting each candidate
/// and deriving its EO address before calling [selectBackupWinner].
library;

/// Normalizes an EOA address for comparison (case-insensitive, optional 0x prefix).
String normalizeEoAddress(String? address) {
  if (address == null || address.isEmpty) return '';
  final s = address.trim().toLowerCase();
  return s.startsWith('0x') ? s.substring(2) : s;
}

/// A backup candidate whose content was successfully decrypted, paired with
/// the EO address derived from its mnemonic.
///
/// When the caller has no pinned address to reconcile against yet,
/// [eoAddress] may be left empty — [selectBackupWinner] falls back to
/// treating the first entry in the (newest-first) list as the winner.
class DecryptedBackupCandidate {
  const DecryptedBackupCandidate({required this.fileId, this.eoAddress = ''});

  final String fileId;
  final String eoAddress;
}

/// Outcome of reconciling multiple Drive wallet backups.
class BackupReconciliation {
  const BackupReconciliation.matched(String fileId)
    : winnerFileId = fileId,
      errorMessage = null;

  const BackupReconciliation.failed(String message)
    : winnerFileId = null,
      errorMessage = message;

  /// The file id to restore from, or null if reconciliation failed.
  final String? winnerFileId;

  /// A user-facing diagnostic message, set only when reconciliation failed.
  final String? errorMessage;

  bool get isSuccess => winnerFileId != null;
}

/// Selects which of several duplicate Drive wallet backups is correct.
///
/// [decrypted] should contain one entry per candidate that was successfully
/// downloaded and decrypted (candidates that failed to decrypt are simply
/// omitted — they count toward [totalCandidateCount] but not [decrypted]).
///
/// [totalCandidateCount] is the total number of backup files found in Drive,
/// including any that failed to decrypt/derive. It is only used to produce a
/// clear diagnostic message when reconciliation fails.
///
/// Behavior:
/// - If [expectedEoAddress] is known (a Firestore-pinned wallet already
///   exists), exactly one decrypted candidate must match it. Zero or
///   multiple matches are treated as a failure requiring manual support,
///   since guessing could silently restore the wrong wallet.
/// - If [expectedEoAddress] is not known (no Firestore wallet document
///   exists yet, e.g. during wallet creation), the first entry in
///   [decrypted] wins. Callers must pass candidates newest-first so this
///   default is deterministic.
BackupReconciliation selectBackupWinner({
  required List<DecryptedBackupCandidate> decrypted,
  required int totalCandidateCount,
  String? expectedEoAddress,
}) {
  final normalizedExpected = normalizeEoAddress(expectedEoAddress);

  if (normalizedExpected.isEmpty) {
    if (decrypted.isEmpty) {
      return BackupReconciliation.failed(
        'Unable to restore any of the $totalCandidateCount wallet backups '
        'found in Google Drive. Please contact support.',
      );
    }
    return BackupReconciliation.matched(decrypted.first.fileId);
  }

  final matches = decrypted
      .where((c) => normalizeEoAddress(c.eoAddress) == normalizedExpected)
      .toList();

  if (matches.length != 1) {
    return BackupReconciliation.failed(
      matches.isEmpty
          ? 'We found $totalCandidateCount wallet backups in Google Drive, '
                'but none match your wallet address. Please contact support.'
          : 'We found $totalCandidateCount wallet backups in Google Drive, '
                'and ${matches.length} match your wallet address. Please contact support.',
    );
  }

  return BackupReconciliation.matched(matches.first.fileId);
}
