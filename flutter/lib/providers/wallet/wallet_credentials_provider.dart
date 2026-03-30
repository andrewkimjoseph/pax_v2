import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web3dart/web3dart.dart';
import 'package:pax/services/wallet/wallet_service.dart';
import 'package:pax/services/wallet/wallet_encryption.dart';
import 'package:pax/services/wallet/drive_service.dart';
import 'package:pax/services/wallet/local_wallet_cache.dart';

enum WalletCredentialsStatus { initial, loading, loaded, error }

class WalletCredentialsState {
  final WalletCredentialsStatus status;
  final Credentials? credentials;
  final String? mnemonic;
  final String? eoAddress;
  final String? errorMessage;

  WalletCredentialsState({
    this.status = WalletCredentialsStatus.initial,
    this.credentials,
    this.mnemonic,
    this.eoAddress,
    this.errorMessage,
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
  }) {
    return WalletCredentialsState(
      status: status ?? this.status,
      credentials: credentials ?? this.credentials,
      mnemonic: mnemonic ?? this.mnemonic,
      eoAddress: eoAddress ?? this.eoAddress,
      errorMessage: errorMessage ?? this.errorMessage,
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
