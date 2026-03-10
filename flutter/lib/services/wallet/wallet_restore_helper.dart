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

/// Restores wallet credentials from cache or Drive when the user is V2 and has a Pax wallet.
/// Call on app resume or when entering Miniapps so the wallet is ready when the user opens a miniapp.
/// [silentOnly] if true uses only signInSilently (no UI). Set false to allow interactive sign-in.
/// Returns without doing anything if not authenticated, not V2, no wallet, or credentials already loaded/loading.
Future<void> restoreWalletIfNeeded(
  WidgetRef ref, {
  bool silentOnly = true,
}) async {
  final authState = ref.read(authProvider);
  if (authState.state != AuthState.authenticated) return;

  final paxWalletState = ref.read(paxWalletProvider);
  final hasWallet =
      paxWalletState.state == PaxWalletState.loaded &&
      paxWalletState.wallet != null &&
      paxWalletState.wallet!.eoAddress != null &&
      paxWalletState.wallet!.eoAddress!.isNotEmpty;
  if (!hasWallet) return;

  final credState = ref.read(walletCredentialsProvider);
  if (credState.status == WalletCredentialsStatus.loaded) return;
  if (credState.status == WalletCredentialsStatus.loading) return;

  if (kDebugMode) {
    debugPrint('WalletRestoreHelper: restoreWalletIfNeeded start (silentOnly: $silentOnly)');
  }
  try {
    GoogleSignInAccount? driveAccount =
        await driveSignInForWallet.signInSilently();
    if (!silentOnly && driveAccount == null) {
      driveAccount = await driveSignInForWallet.signIn();
    }
    if (driveAccount == null) {
      if (kDebugMode) {
        debugPrint('WalletRestoreHelper: no Drive account, skipping');
      }
      return;
    }
    if (kDebugMode) {
      debugPrint('WalletRestoreHelper: Drive account ok, calling restoreWallet...');
    }

    final driveAuth = await driveAccount.authentication;
    final accessToken = driveAuth.accessToken;
    if (accessToken == null) {
      ref
          .read(walletCredentialsProvider.notifier)
          .setError('Failed to get Drive access token');
      return;
    }

    await ref
        .read(walletCredentialsProvider.notifier)
        .restoreWallet(accessToken: accessToken, accountId: driveAccount.id);
    if (kDebugMode) {
      debugPrint('WalletRestoreHelper: wallet restored on preload');
    }

    // Backfill smart account address if missing (e.g. partial write or legacy data).
    final credStateAfter = ref.read(walletCredentialsProvider);
    if (credStateAfter.status == WalletCredentialsStatus.loaded &&
        credStateAfter.credentials != null &&
        credStateAfter.eoAddress != null) {
      final paxWalletStateAfter = ref.read(paxWalletProvider);
      final paxAccountStateAfter = ref.read(paxAccountProvider);
      final wallet = paxWalletStateAfter.wallet;
      final account = paxAccountStateAfter.account;
      final missingOnWallet = wallet?.smartAccountAddress == null ||
          (wallet?.smartAccountAddress ?? '').isEmpty;
      final missingOnAccount = account?.smartAccountWalletAddress == null ||
          (account?.smartAccountWalletAddress ?? '').isEmpty;
      if (missingOnWallet || missingOnAccount) {
        try {
          final smartAccountAddress = await SmartAccountService().createSmartAccount(
            credentials: credStateAfter.credentials!,
            sessionKey: driveAccount.id,
          );
          if (wallet?.id != null) {
            await ref.read(paxWalletProvider.notifier).updateSmartAccountAddress(
              walletId: wallet!.id!,
              smartAccountAddress: smartAccountAddress,
            );
          }
          await ref.read(paxAccountProvider.notifier).updateAccount({
            if (credStateAfter.eoAddress != null)
              'eoWalletAddress': credStateAfter.eoAddress!,
            'smartAccountWalletAddress': smartAccountAddress,
          });
          if (kDebugMode) {
            debugPrint('WalletRestoreHelper: backfilled smart account address');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('WalletRestoreHelper: backfill failed (non-blocking): $e');
          }
        }
      }
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('WalletRestoreHelper: preload restore failed: $e');
    }
    ref.read(walletCredentialsProvider.notifier).setError(e.toString());
  }
}
