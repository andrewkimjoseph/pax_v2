// This service manages the reward distribution process:
// - Handles participant rewards through Firebase Functions
// - Manages reward state through Riverpod providers
// - Provides error handling and state management for the reward process
// - Returns detailed reward results including transaction hashes

// lib/services/reward_service.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';
import 'package:pax/providers/local/activity_providers.dart';
import 'package:pax/providers/local/reward_state_provider.dart';
import 'package:pax/providers/fcm/fcm_provider.dart';
import 'package:pax/providers/wallet/wallet_credentials_provider.dart';
import 'package:pax/services/wallet/smart_account_service.dart';
import 'package:pax/utils/currency_symbol.dart';
import 'package:pax/utils/error_message_util.dart';
import 'package:pax/services/notifications/notification_service.dart';

class RewardService {
  final Ref ref;
  final NotificationService _notificationService;

  RewardService(this.ref) : _notificationService = NotificationService();

  Future<RewardResult> rewardParticipant({
    required String taskCompletionId,
  }) async {
    try {
      // Update state to processing
      ref.read(rewardStateProvider.notifier).startRewarding();

      final paxAccount = ref.read(paxAccountProvider).account;
      final isV2 = paxAccount?.isV2 ?? false;

      final payload = <String, dynamic>{'taskCompletionId': taskCompletionId};
      if (isV2) {
        final credState = ref.read(walletCredentialsProvider);
        final credentials = credState.credentials;
        if (credentials == null) {
          throw Exception(
            'Pax Wallet not loaded. Please open Pax Wallet or restore from backup and try again.',
          );
        }
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('Not signed in');
        final sessionKey = await user.getIdToken(true);
        if (sessionKey == null) throw Exception('Failed to get session token');
        final smartAccountService = SmartAccountService();
        final v2Params = smartAccountService.getV2EncryptedParamsForBackend(
          credentials: credentials,
          sessionKey: sessionKey,
        );
        payload['encryptedPrivateKey'] = v2Params['encryptedPrivateKey'];
        payload['sessionKey'] = v2Params['sessionKey'];
        payload['eoWalletAddress'] = v2Params['eoWalletAddress'];
      }

      // Call the Firebase function
      final httpsCallable = FirebaseFunctions.instance.httpsCallable(
        'rewardParticipantProxy',
      );
      final result = await httpsCallable.call(payload);

      // Extract data from the result
      final data = result.data as Map<String, dynamic>;

      // Create RewardResult object
      final rewardResult = RewardResult.fromMap(data);

      // Update state to complete with the result
      ref.read(rewardStateProvider.notifier).completeRewarding(rewardResult);

      ref.read(analyticsProvider).rewardingComplete({
        "taskId": rewardResult.taskId,
        "taskCompletionId": rewardResult.taskCompletionId,
        "rewardId": rewardResult.rewardId,
        "amount": rewardResult.amount,
        "currency": rewardResult.rewardCurrencyId,
      });

      // Send notification about the reward
      final fcmToken = await ref.read(fcmTokenProvider.future);
      if (fcmToken != null) {
        final currencyName = CurrencySymbolUtil.getNameForCurrency(
          rewardResult.rewardCurrencyId,
        );
        final currencySymbol = CurrencySymbolUtil.getSymbolForCurrency(
          currencyName,
        );

        await _notificationService.sendRewardNotification(
          token: fcmToken,
          rewardData: {
            'amount': rewardResult.amount,
            'currencySymbol': currencySymbol,
            'rewardId': rewardResult.rewardId.toString(),
            'taskId': rewardResult.taskId.toString(),
            'taskCompletionId': rewardResult.taskCompletionId.toString(),
            'currency': rewardResult.rewardCurrencyId.toString(),
          },
        );
      }

      ref.invalidate(activityRepositoryProvider);

      await ref.read(paxAccountProvider.notifier).syncBalancesFromBlockchain();

      return rewardResult;
    } catch (e) {
      // Update state to error with error message
      ref
          .read(rewardStateProvider.notifier)
          .setError(
            ErrorMessageUtil.userFacing(
              e is FirebaseFunctionsException
                  ? e.message ?? e.toString()
                  : e.toString(),
            ),
          );

      // Log the error
      if (kDebugMode) {
        print('Reward process error: $e');
      }

      rethrow;
    }
  }
}

final rewardServiceProvider = Provider<RewardService>((ref) {
  return RewardService(ref);
});
