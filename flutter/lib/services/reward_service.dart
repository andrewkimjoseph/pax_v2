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
      ref.read(rewardStateProvider.notifier).startRewarding();

      final paxAccount = ref.read(paxAccountProvider).account;
      final isV2 = paxAccount?.isV2 ?? false;

      final Map<String, dynamic> payload = {
        'taskCompletionId': taskCompletionId,
      };

      if (isV2) {
        final credState = ref.read(walletCredentialsProvider);
        final credentials = credState.credentials;
        if (credentials == null) {
          throw Exception(
            'Pax Wallet not loaded. Open Pax Wallet or restore from backup to claim rewards.',
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
      } else {
        final serverWalletId = paxAccount?.serverWalletId;
        if (serverWalletId == null || serverWalletId.isEmpty) {
          throw Exception(
            'Account is missing server wallet. Contact support or complete wallet setup.',
          );
        }
        payload['serverWalletId'] = serverWalletId;
      }

      final httpsCallable = FirebaseFunctions.instance.httpsCallable(
        'rewardParticipantProxy',
      );
      final result = await httpsCallable.call(payload);

      final data = result.data as Map<String, dynamic>;
      final rewardResult = RewardResult.fromMap(data);

      ref.read(rewardStateProvider.notifier).completeRewarding(rewardResult);

      ref.read(analyticsProvider).rewardingComplete({
        "taskId": rewardResult.taskId,
        "taskCompletionId": rewardResult.taskCompletionId,
        "rewardId": rewardResult.rewardId,
        "amount": rewardResult.amount,
        "currency": rewardResult.rewardCurrencyId,
      });

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
      ref
          .read(rewardStateProvider.notifier)
          .setError(
            ErrorMessageUtil.userFacing(
              e is FirebaseFunctionsException
                  ? e.message ?? e.toString()
                  : e.toString(),
            ),
          );

      if (kDebugMode) {
        debugPrint('Reward process error: $e');
      }

      rethrow;
    }
  }

  Future<void> claimReferralReward({
    required String referralId,
  }) async {
    try {
      final paxAccount = ref.read(paxAccountProvider).account;
      final isV2 = paxAccount?.isV2 ?? false;

      final Map<String, dynamic> payload = {
        'referralId': referralId,
      };

      if (isV2) {
        final credState = ref.read(walletCredentialsProvider);
        final credentials = credState.credentials;
        if (credentials == null) {
          throw Exception(
            'Pax Wallet not loaded. Open Pax Wallet or restore from backup to claim rewards.',
          );
        }
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('Not signed in');
        final sessionKey = await user.getIdToken(true);
        if (sessionKey == null) {
          throw Exception('Failed to get session token');
        }
        final smartAccountService = SmartAccountService();
        final v2Params = smartAccountService.getV2EncryptedParamsForBackend(
          credentials: credentials,
          sessionKey: sessionKey,
        );
        payload['encryptedPrivateKey'] = v2Params['encryptedPrivateKey'];
        payload['sessionKey'] = v2Params['sessionKey'];
        payload['eoWalletAddress'] = v2Params['eoWalletAddress'];
      } else {
        final serverWalletId = paxAccount?.serverWalletId;
        if (serverWalletId == null || serverWalletId.isEmpty) {
          throw Exception(
            'Account is missing server wallet. Contact support or complete wallet setup.',
          );
        }
        payload['serverWalletId'] = serverWalletId;
      }

      final httpsCallable = FirebaseFunctions.instance.httpsCallable(
        'processReferralClaim',
      );
      await httpsCallable.call(payload);

      ref.invalidate(activityRepositoryProvider);
      await ref.read(paxAccountProvider.notifier).syncBalancesFromBlockchain();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Referral reward process error: $e');
      }
      throw Exception(
        ErrorMessageUtil.userFacing(
          e is FirebaseFunctionsException
              ? e.message ?? e.toString()
              : e.toString(),
        ),
      );
    }
  }
}

final rewardServiceProvider = Provider<RewardService>((ref) {
  return RewardService(ref);
});
