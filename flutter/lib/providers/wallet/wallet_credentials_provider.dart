import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web3dart/web3dart.dart';
import 'package:pax/services/wallet/wallet_service.dart';
import 'package:pax/services/wallet/wallet_encryption.dart';
import 'package:pax/services/wallet/drive_service.dart';
import 'package:pax/services/wallet/local_wallet_cache.dart';
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
      await drive.upload(encrypted);
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
  Future<void> restoreWallet({
    required String accessToken,
    required String accountId,
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
        final fileId = await drive.findAppDataFile();
        if (fileId != null) {
          final content = await drive.download(fileId);
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

        // No backup found -- create new wallet
        drive.close();
        if (kDebugMode) {
          debugPrint('[WalletCredentials] WalletCredentials: no Drive backup, creating new wallet');
        }
        await createWallet(accessToken: accessToken, accountId: accountId);
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
