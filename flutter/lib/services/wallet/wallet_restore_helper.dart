import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pax/models/auth/auth_state_model.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/providers/wallet/wallet_credentials_provider.dart';
import 'package:pax/services/wallet/smart_account_service.dart';

/// Shared Google Sign-In instance with Drive scopes for wallet backup/restore.
final GoogleSignIn driveSignInForWallet = GoogleSignIn(
  scopes: ['email', 'profile', 'https://www.googleapis.com/auth/drive.appdata'],
);

/// Normalizes an EOA address for comparison (case-insensitive, optional 0x prefix).
String _normalizeEoAddress(String? a) {
  if (a == null || a.isEmpty) return '';
  final s = a.trim().toLowerCase();
  return s.startsWith('0x') ? s.substring(2) : s;
}

bool _eoAddressMatches(String? fromCreds, String? fromFirestore) {
  if (fromCreds == null || fromFirestore == null) return false;
  return _normalizeEoAddress(fromCreds) == _normalizeEoAddress(fromFirestore);
}

/// Restores wallet credentials from cache or Drive when the user has a Pax wallet.
/// Call on app resume or when entering Miniapps so the wallet is ready when the user opens a miniapp.
///
/// Accepts a [ProviderContainer] instead of [WidgetRef] so that all [container.read()]
/// calls after async gaps are safe — [ProviderContainer] is not tied to the widget
/// lifecycle and will not throw "Bad state: Using ref after widget unmounted".
///
/// Obtain the container in your widget BEFORE any await:
///   final container = ProviderScope.containerOf(context);
///   await restoreWalletIfNeeded(container);
///
/// [silentOnly] if true uses only signInSilently (no UI). Set false to allow interactive sign-in.
/// Returns without doing anything if not authenticated, no wallet, or credentials already loaded/loading.
Future<void> restoreWalletIfNeeded(
  ProviderContainer container, {
  bool silentOnly = true,
}) async {
  // --- Snapshot all state & grab notifiers BEFORE any await ---
  final authState = container.read(authProvider);
  if (authState.state != AuthState.authenticated) return;

  final paxWalletState = container.read(paxWalletProvider);
  final hasWallet =
      paxWalletState.state == PaxWalletState.loaded &&
      paxWalletState.wallet != null &&
      paxWalletState.wallet!.eoAddress != null &&
      paxWalletState.wallet!.eoAddress!.isNotEmpty;
  if (!hasWallet) return;

  final credState = container.read(walletCredentialsProvider);
  if (credState.status == WalletCredentialsStatus.loaded) return;
  if (credState.status == WalletCredentialsStatus.loading) return;

  // Capture notifiers now — safe to call methods on these after awaits
  // because notifiers are not tied to the widget lifecycle.
  final walletCredNotifier = container.read(walletCredentialsProvider.notifier);
  final paxWalletNotifier = container.read(paxWalletProvider.notifier);
  final paxAccountNotifier = container.read(paxAccountProvider.notifier);

  if (kDebugMode) {
    debugPrint(
      '[WalletRestoreHelper] restoreWalletIfNeeded start (silentOnly: $silentOnly)',
    );
  }

  try {
    GoogleSignInAccount? driveAccount =
        await driveSignInForWallet.signInSilently();
    if (!silentOnly && driveAccount == null) {
      driveAccount = await driveSignInForWallet.signIn();
    }
    if (driveAccount == null) {
      if (kDebugMode) {
        debugPrint('[WalletRestoreHelper] no Drive account, skipping');
      }
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[WalletRestoreHelper] Drive account ok, calling restoreWallet...',
      );
    }

    final driveAuth = await driveAccount.authentication;
    final accessToken = driveAuth.accessToken;
    if (accessToken == null) {
      walletCredNotifier.setError('Failed to get Drive access token');
      return;
    }

    await walletCredNotifier.restoreWallet(
      accessToken: accessToken,
      accountId: driveAccount.id,
    );
    if (kDebugMode) {
      debugPrint('[WalletRestoreHelper] wallet restored on preload');
    }

    // Validate restored credentials match Firestore wallet.
    // (recovery-first: try interactive restore once before showing error)
    final credAfterRestore = container.read(walletCredentialsProvider);
    final walletAfterRestore = container.read(paxWalletProvider);
    final walletEoAddress = walletAfterRestore.wallet?.eoAddress;
    final credEoAddress = credAfterRestore.eoAddress;

    if (credAfterRestore.status == WalletCredentialsStatus.loaded &&
        walletEoAddress != null &&
        walletEoAddress.isNotEmpty &&
        credEoAddress != null &&
        !_eoAddressMatches(credEoAddress, walletEoAddress)) {
      if (kDebugMode) {
        debugPrint(
          '[WalletRestoreHelper] eoAddress mismatch after restore, '
          'clearing and trying interactive restore once',
        );
      }
      walletCredNotifier.clearCredentials();
      await restoreWalletIfNeeded(container, silentOnly: false);

      final credAfterRetry = container.read(walletCredentialsProvider);
      final walletAfterRetry = container.read(paxWalletProvider);
      final walletEoAfterRetry = walletAfterRetry.wallet?.eoAddress;
      final credEoAfterRetry = credAfterRetry.eoAddress;

      if (credAfterRetry.status != WalletCredentialsStatus.loaded ||
          walletEoAfterRetry == null ||
          credEoAfterRetry == null ||
          !_eoAddressMatches(credEoAfterRetry, walletEoAfterRetry)) {
        walletCredNotifier.setError(
          'Please sign in with the same Google account you used when creating your wallet.',
        );
        return;
      }
    }

    // Backfill smart account address if missing (e.g. partial write or legacy data).
    final credAfterValidation = container.read(walletCredentialsProvider);
    if (credAfterValidation.status == WalletCredentialsStatus.loaded &&
        credAfterValidation.credentials != null &&
        credAfterValidation.eoAddress != null) {
      final walletAfterValidation = container.read(paxWalletProvider);
      final accountAfterValidation = container.read(paxAccountProvider);
      final wallet = walletAfterValidation.wallet;
      final account = accountAfterValidation.account;
      final missingOnWallet =
          wallet?.smartAccountAddress == null ||
          (wallet?.smartAccountAddress ?? '').isEmpty;
      final missingOnAccount =
          account?.smartAccountWalletAddress == null ||
          (account?.smartAccountWalletAddress ?? '').isEmpty;

      if (missingOnWallet || missingOnAccount) {
        try {
          final smartAccountAddress = await SmartAccountService()
              .createSmartAccount(
                credentials: credAfterValidation.credentials!,
                sessionKey: driveAccount.id,
              );
          if (wallet?.id != null) {
            await paxWalletNotifier.updateSmartAccountAddress(
              walletId: wallet!.id!,
              smartAccountAddress: smartAccountAddress,
            );
          }
          await paxAccountNotifier.updateAccount({
            if (credAfterValidation.eoAddress != null)
              'eoWalletAddress': credAfterValidation.eoAddress!,
            'smartAccountWalletAddress': smartAccountAddress,
          });
          if (kDebugMode) {
            debugPrint(
              '[WalletRestoreHelper] backfilled smart account address',
            );
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '[WalletRestoreHelper] backfill failed (non-blocking): $e',
            );
          }
        }
      }
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[WalletRestoreHelper] preload restore failed: $e');
    }
    walletCredNotifier.setError(e.toString());
  }
}
