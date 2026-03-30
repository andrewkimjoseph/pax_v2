import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/models/firestore/achievement/achievement_model.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/db/achievement/achievement_provider.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';
import 'package:pax/providers/db/withdrawal_method/withdrawal_method_provider.dart';
import 'package:pax/providers/fcm/fcm_provider.dart';
import 'package:pax/providers/wallet/wallet_credentials_provider.dart';
import 'package:pax/providers/withdrawal_method_connection/withdrawal_method_connection_provider.dart';
import 'package:pax/repositories/firestore/achievement/achievement_repository.dart';
import 'package:pax/services/blockchain/blockchain_service.dart';
import 'package:pax/services/notifications/notification_service.dart';
import 'package:pax/services/wallet/smart_account_service.dart';
import 'package:pax/utils/contract_address_constants.dart';
import 'package:pax/utils/error_message_util.dart';
import 'package:pax/utils/token_address_util.dart';
import 'package:pax/services/withdrawal/withdrawal_method_connection_service.dart';

class AchievementStateModel {
  final Map<String, bool> claimingStates;
  final String? errorMessage;
  final String? txnHash;

  const AchievementStateModel({
    this.claimingStates = const {},
    this.errorMessage,
    this.txnHash,
  });

  AchievementStateModel copyWith({
    Map<String, bool>? claimingStates,
    String? errorMessage,
    String? txnHash,
  }) {
    return AchievementStateModel(
      claimingStates: claimingStates ?? this.claimingStates,
      errorMessage: errorMessage,
      txnHash: txnHash ?? this.txnHash,
    );
  }

  bool isClaiming(String achievementId) =>
      claimingStates[achievementId] ?? false;
}

class AchievementNotifier extends Notifier<AchievementStateModel> {
  final AchievementRepository _achievementRepository = AchievementRepository();
  final NotificationService _notificationService = NotificationService();
  late final WithdrawalMethodConnectionService _withdrawalMethodService;

  @override
  AchievementStateModel build() {
    _withdrawalMethodService = ref.watch(withdrawalMethodConnectionProvider);
    return const AchievementStateModel();
  }

  Future<String> claimAchievement({
    required Achievement achievement,
    String? recipientAddress,
    String? donationContractAddress,
    int? donationBasisPoints,
  }) async {
    if (state.isClaiming(achievement.id)) {
      throw Exception('Achievement claim already in progress.');
    }

    if (achievement.status == AchievementStatus.claimed) {
      throw Exception('This achievement has already been claimed.');
    }

    // Set claiming state for this specific achievement
    final updatedClaimingStates = Map<String, bool>.from(state.claimingStates);
    updatedClaimingStates[achievement.id] = true;
    state = state.copyWith(
      claimingStates: updatedClaimingStates,
      errorMessage: null,
      txnHash: null,
    );

    try {
      final auth = ref.read(authProvider);
      final paxAccountPayoutAddress =
          ref.read(paxAccountProvider).account?.payoutWalletAddress;

      if (paxAccountPayoutAddress == null) {
        throw Exception('Pax account not found');
      }

      // Wait for withdrawal methods to load, then check if at least one is GoodDollar verified
      final withdrawalMethodsState = await waitForWithdrawalMethods(ref);
      final withdrawalMethods = withdrawalMethodsState.withdrawalMethods;
      bool hasVerifiedMethod = false;

      for (final withdrawalMethod in withdrawalMethods) {
        final isVerified = await _withdrawalMethodService.isGoodDollarVerified(
          withdrawalMethod.walletAddress,
          true, // checkWhitelist = true
        );
        if (isVerified) {
          hasVerifiedMethod = true;
          break;
        }
      }

      // If no withdrawal method is verified, fail the claim
      if (!hasVerifiedMethod) {
        final finalClaimingStates = Map<String, bool>.from(
          state.claimingStates,
        );
        finalClaimingStates.remove(achievement.id);
        final paxAccount = ref.read(paxAccountProvider).account;
        final isV2 = paxAccount?.isV2 ?? false;
        final faceVerificationMessage =
            isV2
                ? 'You need to complete face verification in PaxWallet.'
                : 'You need to complete face verification in MiniPay or GoodWallet.';
        state = state.copyWith(
          claimingStates: finalClaimingStates,
          errorMessage: faceVerificationMessage,
        );
        throw Exception(faceVerificationMessage);
      }

      // Check CanvassingRewarder has sufficient balance before claiming
      const rewardTokenId = 1; // good_dollar (matches backend REWARD_TOKEN)
      final canvassingRewarderProxyAddress =
          ContractAddressConstants.canvassingRewarderProxyAddress;

      final amount = (achievement.amountEarned ?? 0).toDouble();
      if (amount > 0) {
        final hasBalance = await BlockchainService.hasSufficientBalance(
          canvassingRewarderProxyAddress,
          TokenAddressUtil.getAddressForCurrency(rewardTokenId),
          amount,
          TokenAddressUtil.getDecimalsForCurrency(rewardTokenId),
        );
        if (!hasBalance) {
          final finalClaimingStates = Map<String, bool>.from(
            state.claimingStates,
          );
          finalClaimingStates.remove(achievement.id);
          state = state.copyWith(
            claimingStates: finalClaimingStates,
            errorMessage: 'Rewarder contract has insufficient balance.',
          );
          throw Exception('Rewarder contract has insufficient balance.');
        }
      }

      // Build optional V2 params so the claim is sent from the participant's EOA
      String? eoWalletAddress;
      String? encryptedPrivateKey;
      String? sessionKey;
      final paxAccount = ref.read(paxAccountProvider).account;
      final isV2 = paxAccount?.isV2 ?? false;
      if (isV2) {
        final credState = ref.read(walletCredentialsProvider);
        final credentials = credState.credentials;
        if (credentials == null) {
          final finalClaimingStates = Map<String, bool>.from(
            state.claimingStates,
          );
          finalClaimingStates.remove(achievement.id);
          state = state.copyWith(
            claimingStates: finalClaimingStates,
            errorMessage:
                'Pax Wallet not loaded. Please open Pax Wallet or restore from backup and try again.',
          );
          throw Exception(
            'Pax Wallet not loaded. Please open Pax Wallet or restore from backup and try again.',
          );
        }
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('Not signed in');
        final token = await user.getIdToken(true);
        if (token == null) throw Exception('Failed to get session token');
        final smartAccountService = SmartAccountService();
        final v2Params = smartAccountService.getV2EncryptedParamsForBackend(
          credentials: credentials,
          sessionKey: token,
        );
        eoWalletAddress = v2Params['eoWalletAddress'];
        encryptedPrivateKey = v2Params['encryptedPrivateKey'];
        sessionKey = v2Params['sessionKey'];
      }

      // Call the cloud function (pax account addresses resolved server-side).
      final txnHash = await _achievementRepository.processAchievementClaim(
        achievementId: achievement.id,
        recipientAddress: recipientAddress,
        amountEarned: achievement.amountEarned ?? 0,
        tasksCompleted: achievement.tasksCompleted,
        eoWalletAddress: eoWalletAddress,
        encryptedPrivateKey: encryptedPrivateKey,
        sessionKey: sessionKey,
        donationContractAddress: donationContractAddress,
        donationBasisPoints: donationBasisPoints,
      );

      // Send notification about the claimed achievement
      final fcmToken = await ref.read(fcmTokenProvider.future);
      if (fcmToken != null) {
        await _notificationService.sendAchievementClaimedNotification(
          token: fcmToken,
          achievementData: {
            'achievementName': achievement.name,
            'amountEarned': achievement.amountEarned ?? 0,
            'txnHash': txnHash,
          },
        );
      }

      // Update balances
      await ref.read(paxAccountProvider.notifier).syncBalancesFromBlockchain();

      // Clear claiming state for this achievement
      final finalClaimingStates = Map<String, bool>.from(state.claimingStates);
      finalClaimingStates.remove(achievement.id);
      state = state.copyWith(
        claimingStates: finalClaimingStates,
        txnHash: txnHash,
      );

      // Only fetch achievements if the provider is still mounted
      if (ref.mounted) {
        ref
            .read(achievementsProvider.notifier)
            .fetchAchievements(auth.user.uid);
      }
      return txnHash;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Error] Error claiming achievement: $e');
      }

      String errorMessage = e.toString();
      if (e is FirebaseFunctionsException) {
        if (e.code == 'already-exists') {
          errorMessage = 'This achievement has already been claimed.';
        } else if (e.code == 'failed-precondition') {
          errorMessage = e.message ?? errorMessage;
        } else if (e.message != null && e.message!.isNotEmpty) {
          errorMessage = e.message!;
        }
      }
      errorMessage = ErrorMessageUtil.userFacing(errorMessage);

      // Clear claiming state for this achievement
      final finalClaimingStates = Map<String, bool>.from(state.claimingStates);
      finalClaimingStates.remove(achievement.id);
      state = state.copyWith(
        claimingStates: finalClaimingStates,
        errorMessage: errorMessage,
      );
      rethrow;
    }
  }

  void resetState() {
    state = const AchievementStateModel();
  }
}

final achievementClaimProvider =
    NotifierProvider<AchievementNotifier, AchievementStateModel>(
      () => AchievementNotifier(),
    );
