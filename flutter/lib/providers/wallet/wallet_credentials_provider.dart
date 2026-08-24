import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web3dart/web3dart.dart';
import 'package:pax/services/wallet/wallet_service.dart';
import 'package:pax/services/wallet/wallet_encryption.dart';
import 'package:pax/services/wallet/drive_service.dart';
import 'package:pax/services/wallet/local_wallet_cache.dart';
import 'package:pax/services/wallet/wallet_backup_reconciliation.dart';
import 'package:pax/utils/secret_constants.dart' as secret_constants;

enum WalletCredentialsStatus { initial, loading, loaded, error }

class WalletCredentialsState {
  final WalletCredentialsStatus status;
  final Credentials? credentials;
  final String? mnemonic;
  final String? eoAddress;
  final String? errorMessage;
  final bool isDebugOverride;

  WalletCredentialsState({
    this.status = WalletCredentialsStatus.initial,
    this.credentials,
    this.mnemonic,
    this.eoAddress,
    this.errorMessage,
    this.isDebugOverride = false,
  });

  factory WalletCredentialsState.initial() {
    return WalletCredentialsState();
  }

  WalletCredentialsState copyWith({
    WalletCredentialsStatus? status,
    Credentials? credentials,
    String? mnemonic,
    String? eoAddress,
    String? errorMessage,
    bool? isDebugOverride,
  }) {
    return WalletCredentialsState(
      status: status ?? this.status,
      credentials: credentials ?? this.credentials,
      mnemonic: mnemonic ?? this.mnemonic,
      eoAddress: eoAddress ?? this.eoAddress,
      errorMessage: errorMessage ?? this.errorMessage,
      isDebugOverride: isDebugOverride ?? this.isDebugOverride,
    );
  }

  bool get isLoaded => status == WalletCredentialsStatus.loaded;
}

class WalletCredentialsNotifier extends Notifier<WalletCredentialsState> {
  @override
  WalletCredentialsState build() {
    return WalletCredentialsState.initial();
  }

  /// Creates a new wallet, encrypts to Drive, and caches locally.
  Future<void> createWallet({
    required String accessToken,
    required String accountId,
  }) async {
    if (kDebugMode) {
      debugPrint('[WalletCredentials] WalletCredentials: creating wallet');
    }
    state = state.copyWith(status: WalletCredentialsStatus.loading);

    final walletService = WalletService();
    final walletEnc = WalletEncryption();
    final drive = DriveService(accessToken: accessToken);
    final localCache = LocalWalletCache();

    try {
      final result = await walletService.createWallet();
      if (kDebugMode) {
        debugPrint('[WalletCredentials] WalletCredentials: wallet created');
      }

      final encrypted = walletEnc.encrypt(result.mnemonic, accountId);
      // Overwrite any existing backup in place instead of creating a duplicate
      // file. Drive allows multiple files with the same name, so without this
      // a retried creation (e.g. after a partial failure) would silently leave
      // an orphaned backup with a different mnemonic behind.
      final existingFileId = await drive.findAppDataFile();
      await drive.upload(encrypted, existingFileId: existingFileId);
      if (kDebugMode) {
        debugPrint('[WalletCredentials] WalletCredentials: uploaded to Drive');
      }

      await localCache.cacheWallet(result.mnemonic, accountId);
      if (kDebugMode) {
        debugPrint('[WalletCredentials] WalletCredentials: cached locally');
      }

      drive.close();

      state = state.copyWith(
        status: WalletCredentialsStatus.loaded,
        credentials: result.credentials,
        mnemonic: result.mnemonic,
        eoAddress: result.credentials.address.with0x,
        errorMessage: null,
        isDebugOverride: false,
      );
    } catch (e) {
      drive.close();
      if (kDebugMode) {
        debugPrint('[WalletCredentials] WalletCredentials: create failed: $e');
      }
      state = state.copyWith(
        status: WalletCredentialsStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Restores wallet from local cache first, then Drive as fallback.
  ///
  /// [expectedEoAddress], when known (e.g. from the Firestore-pinned
  /// `pax_wallets` document), is used to self-heal accounts affected by the
  /// legacy duplicate-Drive-backup bug: if more than one backup file is found,
  /// each candidate is decrypted and compared against [expectedEoAddress] so
  /// the correct one can be restored and the orphaned duplicates cleaned up.
  Future<void> restoreWallet({
    required String accessToken,
    required String accountId,
    String? expectedEoAddress,
  }) async {
    if (kDebugMode) {
      debugPrint('[WalletCredentials] WalletCredentials: restoreWallet start');
    }
    state = state.copyWith(status: WalletCredentialsStatus.loading);

    final walletService = WalletService();
    final localCache = LocalWalletCache();

    try {
      final debugPrivateKeyOverride =
          secret_constants.debugWalletPrivateKeyOverride.trim();
      if (kDebugMode && debugPrivateKeyOverride.isNotEmpty) {
        final normalizedHex = debugPrivateKeyOverride.startsWith('0x')
            ? debugPrivateKeyOverride.substring(2)
            : debugPrivateKeyOverride;
        if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(normalizedHex)) {
          throw ArgumentError(
            'Invalid debugWalletPrivateKeyOverride. Expected 64 hex chars, optionally prefixed with 0x.',
          );
        }
        final credentials = EthPrivateKey.fromHex(debugPrivateKeyOverride);
        if (kDebugMode) {
          debugPrint(
            '[WalletCredentials] WalletCredentials: using debug private key override; skipping cache/Drive restore',
          );
        }
        state = state.copyWith(
          status: WalletCredentialsStatus.loaded,
          credentials: credentials,
          mnemonic: null,
          eoAddress: credentials.address.with0x,
          errorMessage: null,
          isDebugOverride: true,
        );
        return;
      }

      // Try local cache first
      if (kDebugMode) {
        debugPrint('[WalletCredentials] WalletCredentials: trying local cache...');
      }
      final cachedMnemonic = await localCache.getCachedWallet(accountId);
      if (cachedMnemonic != null) {
        if (kDebugMode) {
          debugPrint('[WalletCredentials] WalletCredentials: restored from cache, calling restoreFromMnemonic...');
        }
        final credentials = await walletService.restoreFromMnemonic(
          cachedMnemonic,
          saveToStorage: true,
        );
        if (kDebugMode) {
          debugPrint('[WalletCredentials] WalletCredentials: restoreFromMnemonic done, updating state');
        }
        state = state.copyWith(
          status: WalletCredentialsStatus.loaded,
          credentials: credentials,
          mnemonic: cachedMnemonic,
          eoAddress: credentials.address.with0x,
          errorMessage: null,
          isDebugOverride: false,
        );
        return;
      }

      // Fallback to Drive
      if (kDebugMode) {
        debugPrint('[WalletCredentials] WalletCredentials: cache miss, trying Drive');
      }
      final drive = DriveService(accessToken: accessToken);
      try {
        final candidates = await drive.listAppDataFiles();

        if (candidates.isEmpty) {
          // No backup found during restore — do not create a new wallet here.
          // Wallet creation is handled explicitly by the wallet creation flow.
          drive.close();
          if (kDebugMode) {
            debugPrint(
              '[WalletCredentials] WalletCredentials: no Drive backup found during restore',
            );
          }
          state = state.copyWith(
            status: WalletCredentialsStatus.error,
            errorMessage:
                'Wallet backup not found in Google Drive. '
                'Please sign in with the Google account you used when creating your wallet.',
          );
          return;
        }

        if (candidates.length == 1) {
          final content = await drive.download(candidates.first.id);
          final mnemonic = await compute(_decryptInBackground, [
            content,
            accountId,
          ]);
          final credentials = await walletService.restoreFromMnemonic(
            mnemonic,
            saveToStorage: true,
          );
          await localCache.cacheWallet(mnemonic, accountId);

          drive.close();
          state = state.copyWith(
            status: WalletCredentialsStatus.loaded,
            credentials: credentials,
            mnemonic: mnemonic,
            eoAddress: credentials.address.with0x,
            errorMessage: null,
            isDebugOverride: false,
          );
          return;
        }

        // Multiple backup files found (legacy duplicate-upload bug). Self-heal
        // by decrypting each candidate and matching it against the
        // Firestore-pinned address, then cleaning up the orphan(s).
        await _reconcileMultipleDriveBackups(
          drive: drive,
          localCache: localCache,
          walletService: walletService,
          accountId: accountId,
          candidates: candidates,
          expectedEoAddress: expectedEoAddress,
        );
        return;
      } catch (e) {
        drive.close();
        rethrow;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WalletCredentials] WalletCredentials: restore failed: $e');
      }
      state = state.copyWith(
        status: WalletCredentialsStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Decrypts each of [candidates], compares the derived EO address against
  /// [expectedEoAddress] using the pure [selectBackupWinner] logic, restores
  /// the winning backup, and deletes the orphaned duplicate(s) from Drive.
  Future<void> _reconcileMultipleDriveBackups({
    required DriveService drive,
    required LocalWalletCache localCache,
    required WalletService walletService,
    required String accountId,
    required List<DriveFileInfo> candidates,
    String? expectedEoAddress,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[WalletCredentials] WalletCredentials: ${candidates.length} Drive '
        'backups found, reconciling (expectedEoAddress present: '
        '${(expectedEoAddress?.isNotEmpty ?? false)})',
      );
    }
    final needsEoAddress = normalizeEoAddress(expectedEoAddress).isNotEmpty;

    final mnemonicsByFileId = <String, String>{};
    final credentialsByFileId = <String, Credentials>{};
    final decrypted = <DecryptedBackupCandidate>[];

    for (final candidate in candidates) {
      try {
        final content = await drive.download(candidate.id);
        final mnemonic = await compute(_decryptInBackground, [
          content,
          accountId,
        ]);
        mnemonicsByFileId[candidate.id] = mnemonic;

        if (!needsEoAddress) {
          // No pinned address to reconcile against yet; selectBackupWinner
          // will default to the first (newest) decrypted entry.
          decrypted.add(DecryptedBackupCandidate(fileId: candidate.id));
          continue;
        }

        final credentials = await walletService.restoreFromMnemonic(
          mnemonic,
          saveToStorage: false,
        );
        credentialsByFileId[candidate.id] = credentials;
        decrypted.add(
          DecryptedBackupCandidate(
            fileId: candidate.id,
            eoAddress: credentials.address.with0x,
          ),
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[WalletCredentials] WalletCredentials: candidate '
            '${candidate.id} failed to decrypt/derive: $e',
          );
        }
      }
    }

    final result = selectBackupWinner(
      decrypted: decrypted,
      totalCandidateCount: candidates.length,
      expectedEoAddress: expectedEoAddress,
    );

    if (!result.isSuccess) {
      drive.close();
      if (kDebugMode) {
        debugPrint(
          '[WalletCredentials] WalletCredentials: reconciliation failed: '
          '${result.errorMessage}',
        );
      }
      state = state.copyWith(
        status: WalletCredentialsStatus.error,
        errorMessage: result.errorMessage,
      );
      return;
    }

    final winnerFileId = result.winnerFileId!;
    final winnerMnemonic = mnemonicsByFileId[winnerFileId]!;
    final credentials =
        credentialsByFileId[winnerFileId] ??
        await walletService.restoreFromMnemonic(
          winnerMnemonic,
          saveToStorage: true,
        );
    if (credentialsByFileId.containsKey(winnerFileId)) {
      // Winner was only derived without persisting; persist it now.
      await walletService.restoreFromMnemonic(
        winnerMnemonic,
        saveToStorage: true,
      );
    }
    await localCache.cacheWallet(winnerMnemonic, accountId);

    // Self-heal: remove the orphaned duplicate(s), keeping only the winner.
    for (final candidate in candidates) {
      if (candidate.id == winnerFileId) continue;
      try {
        await drive.deleteFile(candidate.id);
        if (kDebugMode) {
          debugPrint(
            '[WalletCredentials] WalletCredentials: deleted orphaned '
            'Drive backup ${candidate.id}',
          );
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[WalletCredentials] WalletCredentials: failed to delete '
            'orphaned backup ${candidate.id}: $e',
          );
        }
      }
    }

    drive.close();
    state = state.copyWith(
      status: WalletCredentialsStatus.loaded,
      credentials: credentials,
      mnemonic: winnerMnemonic,
      eoAddress: credentials.address.with0x,
      errorMessage: null,
      isDebugOverride: false,
    );
  }

  void clearCredentials() {
    state = WalletCredentialsState.initial();
  }

  /// Sets error state (e.g. when restore is skipped or token is missing).
  void setError(String message) {
    state = state.copyWith(
      status: WalletCredentialsStatus.error,
      errorMessage: message,
      isDebugOverride: false,
    );
  }
}

String _decryptInBackground(List<String> args) {
  return WalletEncryption().decrypt(args[0], args[1]);
}

final walletCredentialsProvider =
    NotifierProvider<WalletCredentialsNotifier, WalletCredentialsState>(() {
      return WalletCredentialsNotifier();
    });
