import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pax/models/local/donation_state_model.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/db/achievement/achievement_provider.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';
import 'package:pax/providers/fcm/fcm_provider.dart';
import 'package:pax/providers/local/activity_providers.dart';
import 'package:pax/providers/local/donation_service_provider.dart';
import 'package:pax/providers/wallet/wallet_credentials_provider.dart';
import 'package:pax/services/donation/donation_service.dart';
import 'package:pax/services/wallet/smart_account_service.dart';
import 'package:pax/utils/achievement_constants.dart';
import 'package:pax/utils/error_message_util.dart';

class DonationNotifier extends Notifier<DonationStateModel> {
  late final DonationService _donationService;

  @override
  DonationStateModel build() {
    _donationService = ref.watch(donationServiceProvider);
    return DonationStateModel();
  }

  Future<void> donateToGoodCollective({
    required double amountToDonate,
    required int tokenId,
    required String currencyAddress,
    required String donationContract,
    required int donationMethodId,
    int decimals = 18,
  }) async {
    if (state.isSubmitting) return;

    state = state.copyWith(
      state: DonationState.submitting,
      isSubmitting: true,
      errorMessage: null,
    );

    try {
      final auth = ref.read(authProvider);
      final userId = auth.user.uid;
      final paxAccount = ref.read(paxAccountProvider).account;
      if (paxAccount == null) {
        throw Exception('Pax account not loaded.');
      }

      Map<String, String>? v2EncryptedParams;
      if (paxAccount.isV2) {
        final credState = ref.read(walletCredentialsProvider);
        final credentials = credState.credentials;
        if (credentials == null) {
          throw Exception(
            'Pax Wallet not loaded. Please open Pax Wallet and try again.',
          );
        }
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('Not signed in');
        final sessionKey = await user.getIdToken(true);
        if (sessionKey == null) throw Exception('Failed to get session token');
        final smartAccountService = SmartAccountService();
        v2EncryptedParams = smartAccountService.getV2EncryptedParamsForBackend(
          credentials: credentials,
          sessionKey: sessionKey,
        );
      }

      final result = await _donationService.donateToGoodCollective(
        userId: userId,
        amountToDonate: amountToDonate,
        tokenId: tokenId,
        currencyAddress: currencyAddress,
        donationContract: donationContract,
        donationMethodId: donationMethodId,
        v2EncryptedParams: v2EncryptedParams,
        decimals: decimals,
      );

      state = state.copyWith(
        state: DonationState.success,
        isSubmitting: false,
        txnHash: result['txnHash']?.toString(),
        donationId: result['donationId']?.toString(),
      );

      await _handleGoodImpactAchievement(userId, amountToDonate);
      ref.invalidate(activityRepositoryProvider);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error donating: $e');
      }
      state = state.copyWith(
        state: DonationState.error,
        isSubmitting: false,
        errorMessage: ErrorMessageUtil.userFacing(e.toString()),
      );
    }
  }

  void resetState() {
    state = DonationStateModel();
  }

  Future<void> _handleGoodImpactAchievement(
    String participantId,
    double amountToDonate,
  ) async {
    if (amountToDonate < 500) {
      return;
    }

    await ref
        .read(achievementsProvider.notifier)
        .fetchAchievements(participantId);
    final achievements = ref.read(achievementsProvider).achievements;
    final matching =
        achievements
            .where((a) => a.name == AchievementConstants.goodImpact)
            .toList();
    final goodImpact = matching.isNotEmpty ? matching.first : null;

    if (goodImpact == null) {
      await ref
          .read(achievementsProvider.notifier)
          .createAchievement(
            timeCreated: Timestamp.now(),
            participantId: participantId,
            name: AchievementConstants.goodImpact,
            tasksNeededForCompletion:
                AchievementConstants.goodImpactTasksNeeded,
            tasksCompleted: 1,
            amountEarned: AchievementConstants.goodImpactAmount,
          );
      return;
    }

    if (goodImpact.timeCompleted != null ||
        goodImpact.tasksCompleted >= goodImpact.tasksNeededForCompletion) {
      return;
    }

    final newTasksCompleted = goodImpact.tasksCompleted + 1;
    final updateData = <String, dynamic>{'tasksCompleted': newTasksCompleted};
    if (newTasksCompleted >= goodImpact.tasksNeededForCompletion) {
      updateData['timeCompleted'] = Timestamp.now();
      updateData['timeUpdated'] = Timestamp.now();
    }

    await ref
        .read(achievementsProvider.notifier)
        .updateAchievement(goodImpact.id, updateData);

    if (newTasksCompleted >= goodImpact.tasksNeededForCompletion) {
      final fcmToken = await ref.read(fcmTokenProvider.future);
      if (fcmToken != null) {
        await ref
            .read(notificationServiceProvider)
            .sendAchievementEarnedNotification(
              token: fcmToken,
              achievementData: {
                'achievementName': AchievementConstants.goodImpact,
                'amountEarned': AchievementConstants.goodImpactAmount,
              },
            );
      }
    }
  }
}

final donationProvider = NotifierProvider<DonationNotifier, DonationStateModel>(
  DonationNotifier.new,
);
