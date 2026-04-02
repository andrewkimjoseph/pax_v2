import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/models/auth/auth_state_model.dart';
import 'package:pax/models/firestore/pax_wallet/pax_wallet_model.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/referral_existence_provider.dart';
import 'package:pax/providers/db/achievement/achievement_provider.dart';
import 'package:pax/providers/fcm/fcm_provider.dart';
import 'package:pax/providers/wallet/wallet_credentials_provider.dart';
import 'package:pax/providers/withdrawal_method_connection/withdrawal_method_connection_provider.dart';
import 'package:pax/providers/db/withdrawal_method/withdrawal_method_provider.dart';
import 'package:pax/utils/achievement_constants.dart';
import 'package:pax/utils/branch_param_cleaner.dart';
import 'package:pax/repositories/firestore/pax_wallet/pax_wallet_repository.dart';
import 'package:pax/services/wallet/gooddollar_identity_service.dart';

enum PaxWalletState { initial, loading, loaded, creating, error }

class PaxWalletStateModel {
  final PaxWallet? wallet;
  final PaxWalletState state;
  final String? errorMessage;

  PaxWalletStateModel({
    this.wallet,
    this.state = PaxWalletState.initial,
    this.errorMessage,
  });

  factory PaxWalletStateModel.initial() {
    return PaxWalletStateModel();
  }

  PaxWalletStateModel copyWith({
    PaxWallet? wallet,
    PaxWalletState? state,
    String? errorMessage,
  }) {
    return PaxWalletStateModel(
      wallet: wallet ?? this.wallet,
      state: state ?? this.state,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class PaxWalletNotifier extends Notifier<PaxWalletStateModel> {
  PaxWalletRepository get _repository => ref.read(paxWalletRepositoryProvider);

  /// EOA we have already requested gas sponsorship for this session; avoids duplicate sponsorWalletGas calls.
  String? _gasSponsorshipRequestedForEoAddress;

  @override
  PaxWalletStateModel build() {
    ref.listen(authProvider, (previous, next) {
      if (previous?.state != next.state) {
        if (next.state == AuthState.authenticated) {
          fetchWallet(next.user.uid);
        } else if (next.state == AuthState.unauthenticated) {
          clearWallet();
          ref.read(walletCredentialsProvider.notifier).clearCredentials();
        }
      }
    });

    final authState = ref.read(authProvider);
    if (authState.state == AuthState.authenticated) {
      Future.microtask(() => fetchWallet(authState.user.uid));
    }

    return PaxWalletStateModel.initial();
  }

  Future<void> fetchWallet(String participantId) async {
    try {
      state = state.copyWith(state: PaxWalletState.loading);
      final wallet = await _repository.getWalletByParticipantId(participantId);
      state = state.copyWith(wallet: wallet, state: PaxWalletState.loaded);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PaxWalletNotifier] Error fetching pax wallet: $e');
      }
      state = state.copyWith(
        state: PaxWalletState.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<PaxWallet?> createWalletDocument({
    required String participantId,
    required String eoAddress,
  }) async {
    try {
      state = state.copyWith(state: PaxWalletState.creating);

      final wallet = await _repository.createWallet(
        participantId: participantId,
        eoAddress: eoAddress,
      );

      if (wallet != null) {
        state = state.copyWith(wallet: wallet, state: PaxWalletState.loaded);
      }

      return wallet;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PaxWalletNotifier] Error creating pax wallet doc: $e');
      }
      state = state.copyWith(
        state: PaxWalletState.error,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  Future<void> updateSmartAccountAddress({
    required String walletId,
    required String smartAccountAddress,
  }) async {
    try {
      final updated = await _repository.updateSmartAccountAddress(
        walletId: walletId,
        smartAccountAddress: smartAccountAddress,
      );
      state = state.copyWith(wallet: updated, state: PaxWalletState.loaded);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] Error updating smart account address: $e',
        );
      }
      state = state.copyWith(
        state: PaxWalletState.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> updateWithLogData({
    required String walletId,
    required String logTxnHash,
    required Timestamp logTimeCreated,
  }) async {
    try {
      final updated = await _repository.updateWalletWithLogData(
        walletId: walletId,
        logTxnHash: logTxnHash,
        logTimeCreated: logTimeCreated,
      );
      state = state.copyWith(wallet: updated, state: PaxWalletState.loaded);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PaxWalletNotifier] Error updating wallet log data: $e');
      }
      state = state.copyWith(
        state: PaxWalletState.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Registers the Pax Wallet as a withdrawal method (creates payment_methods doc if missing).
  /// Call after wallet is successfully backed up, before face verification.
  Future<void> registerPaxWalletAsWithdrawalMethod() async {
    final wallet = state.wallet;
    final participantId = ref.read(authProvider).user.uid;
    if (wallet == null ||
        wallet.eoAddress == null ||
        wallet.id == null ||
        participantId.isEmpty) {
      return;
    }

    try {
      await ref
          .read(withdrawalMethodsProvider.notifier)
          .fetchPaymentMethods(participantId);
      final currentCount =
          ref.read(withdrawalMethodsProvider).withdrawalMethods.length;
      final predefinedId = currentCount + 1;

      final wmRepo = ref.read(withdrawalMethodRepositoryProvider);
      final existing = await wmRepo.getPaymentMethodByWalletAddress(
        wallet.eoAddress!,
      );
      if (existing == null) {
        await wmRepo.createWithdrawalMethod(
          participantId: participantId,
          paxAccountId: participantId,
          walletAddress: wallet.eoAddress!,
          name: 'PaxWallet',
          predefinedId: predefinedId,
        );
      }

      await ref
          .read(withdrawalMethodsProvider.notifier)
          .fetchPaymentMethods(participantId);

      if (existing == null) {
        await ref
            .read(withdrawalConnectionProvider.notifier)
            .createPayoutConnectorAchievementForNthMethod(
              participantId,
              predefinedId,
            );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] Error registering PaxWallet as withdrawal method: $e',
        );
      }
    }
  }

  /// Called when face verification succeeds: withdrawal method (idempotent),
  /// Verified Human achievement, referral record, and gas sponsorship.
  /// Individual steps swallow errors so this method does not throw.
  Future<void> registerPaxWalletAfterFaceVerification() async {
    final wallet = state.wallet;
    final participantId = ref.read(authProvider).user.uid;
    if (wallet == null ||
        wallet.eoAddress == null ||
        wallet.id == null ||
        participantId.isEmpty) {
      return;
    }

    await registerPaxWalletAsWithdrawalMethod();

    await _safeCreateVerifiedHumanAfterV2FaceVerification(participantId);

    await Future.wait([
      _safeCreateReferralRecord(participantId),
      _safeSponsorGas(wallet.eoAddress!),
    ]);
  }

  /// Backfill pass for users who already completed face verification earlier.
  /// Runs idempotent/non-blocking post-verification side effects again.
  Future<void> backfillPostVerificationSideEffects() async {
    final wallet = state.wallet;
    final participantId = ref.read(authProvider).user.uid;
    if (wallet == null ||
        wallet.eoAddress == null ||
        wallet.id == null ||
        participantId.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] backfillPostVerificationSideEffects skipped (preconditions). '
          'walletNull=${wallet == null}, eoAddressNull=${wallet?.eoAddress == null}, '
          'walletIdNull=${wallet?.id == null}, participantIdEmpty=${participantId.isEmpty}',
        );
      }
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[PaxWalletNotifier] backfillPostVerificationSideEffects start '
        '(participantId=$participantId, eoAddress=${wallet.eoAddress})',
      );
    }

    final isWhitelisted = await GoodDollarIdentityService.isWhitelisted(
      wallet.eoAddress!,
    );
    if (!isWhitelisted) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] backfillPostVerificationSideEffects skipped (not whitelisted) '
          '(participantId=$participantId, eoAddress=${wallet.eoAddress})',
        );
      }
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[PaxWalletNotifier] backfillPostVerificationSideEffects running side effects in parallel '
        '(participantId=$participantId)',
      );
    }

    await Future.wait([
      _safeCreateVerifiedHumanAfterV2FaceVerification(participantId),
      _safeCreateReferralRecord(participantId),
      _safeSponsorGas(wallet.eoAddress!),
    ]);
  }

  Future<void> _safeCreateVerifiedHumanAfterV2FaceVerification(
    String participantId,
  ) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _createVerifiedHumanAfterV2FaceVerification(participantId);
        return;
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] Verified Human creation attempt '
            '$attempt/$maxAttempts failed (non-blocking): $e',
          );
        }
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
    }
  }

  /// Non-blocking referral record creation based on Branch params.
  Future<void> _safeCreateReferralRecord(String participantId) async {
    try {
      final mergedParams =
          await BranchParamCleaner.mergeWithBranchFirstReferringParams({});
      final referringParticipantId =
          mergedParams['referringParticipantId'] as String?;

      if (referringParticipantId != null &&
          referringParticipantId.isNotEmpty &&
          referringParticipantId != participantId) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] creating referral record for '
            'referringParticipantId=$referringParticipantId, '
            'referredParticipantId=$participantId',
          );
        }

        try {
          await FirebaseFunctions.instance
              .httpsCallable('createReferral')
              .call(<String, dynamic>{
                'referringParticipantId': referringParticipantId,
                'referredParticipantId': participantId,
              });
          ref.read(analyticsProvider).v2ReferralRecordCreatedAttempt({
            'referringParticipantId_present': true,
            'referredParticipantId': participantId,
            'status': 'success',
          });
          ref.invalidate(referralExistsForReferredParticipantProvider);
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '[PaxWalletNotifier] createReferral failed (non-blocking): $e',
            );
          }
          ref.read(analyticsProvider).v2ReferralRecordCreatedAttempt({
            'referringParticipantId_present': true,
            'referredParticipantId': participantId,
            'status': 'error',
            'error': e.toString(),
          });
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] skipping referral record creation '
            '(no valid referringParticipantId in Branch params)',
          );
        }
        ref.read(analyticsProvider).v2ReferralRecordCreatedAttempt({
          'referringParticipantId_present': false,
          'referredParticipantId': participantId,
          'status': 'skipped',
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] error while preparing referral record params (non-blocking): $e',
        );
      }
      ref.read(analyticsProvider).v2ReferralRecordCreatedAttempt({
        'failure_phase': 'merge_branch_params',
        'referredParticipantId': participantId,
        'status': 'error_branch_merge',
        'error': e.toString(),
      });
    }
  }

  /// Sponsor gas at most once per wallet per app session; errors are swallowed.
  Future<void> _safeSponsorGas(String eoAddress) async {
    try {
      if (_gasSponsorshipRequestedForEoAddress == eoAddress) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] skipping sponsorWalletGas (already requested for eoAddress)',
          );
        }
        return;
      }
      _gasSponsorshipRequestedForEoAddress = eoAddress;

      if (kDebugMode) {
        debugPrint(
            '[PaxWalletNotifier] calling sponsorWalletGas for eoAddress=$eoAddress',
        );
      }
      try {
        final result = await FirebaseFunctions.instance
            .httpsCallable('sponsorWalletGas')
            .call({'eoWalletAddress': eoAddress});
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] sponsorWalletGas result (eoAddress=$eoAddress): '
            '${result.data}',
          );
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[PaxWalletNotifier] Gas sponsorship failed (non-blocking): $e');
        }
        _gasSponsorshipRequestedForEoAddress = null;
      }
    } catch (e) {
      if (kDebugMode) {
          debugPrint('[PaxWalletNotifier] _safeSponsorGas unexpected error: $e');
      }
    }
  }

  /// Idempotent; only invoked after successful V2 face verification.
  ///
  /// Uses [AchievementRepository.createAchievement] directly so Firestore
  /// failures propagate. The achievement notifier swallows errors from
  /// [AchievementNotifier.createAchievement], which previously made this
  /// path appear to succeed when the document was never written.
  Future<void> _createVerifiedHumanAfterV2FaceVerification(
    String participantId,
  ) async {
    if (kDebugMode) {
      debugPrint(
        '[PaxWalletNotifier] _createVerifiedHumanAfterV2FaceVerification start '
        '(participantId=$participantId)',
      );
    }
    final repo = ref.read(achievementsRepositoryProvider);
    final already = await repo.getAchievementsForParticipant(participantId);
    if (already.any((a) => a.name == AchievementConstants.verifiedHuman)) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] Verified Human already exists for participantId=$participantId; skipping create',
        );
      }
      await ref
          .read(achievementsProvider.notifier)
          .fetchAchievements(participantId);
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[PaxWalletNotifier] creating Verified Human achievement for participantId=$participantId',
      );
    }

    await repo.createAchievement(
      participantId: participantId,
      name: AchievementConstants.verifiedHuman,
      tasksNeededForCompletion: AchievementConstants.verifiedHumanTasksNeeded,
      tasksCompleted: 1,
      timeCreated: Timestamp.now(),
      timeCompleted: Timestamp.now(),
      amountEarned: AchievementConstants.verifiedHumanAmount,
    );

    ref.read(analyticsProvider).achievementCreated({
      'achievementName': AchievementConstants.verifiedHuman,
      'amountEarned': AchievementConstants.verifiedHumanAmount,
    });

    try {
      final fcmToken = await ref.read(fcmTokenProvider.future);
      if (fcmToken != null) {
        await ref
            .read(notificationServiceProvider)
            .sendAchievementEarnedNotification(
              token: fcmToken,
              achievementData: {
                'achievementName': AchievementConstants.verifiedHuman,
                'amountEarned': AchievementConstants.verifiedHumanAmount,
              },
            );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] Verified Human notification failed (non-blocking): $e',
        );
      }
    }

    await ref
        .read(achievementsProvider.notifier)
        .fetchAchievements(participantId);
  }

  void clearWallet() {
    _gasSponsorshipRequestedForEoAddress = null;
    state = PaxWalletStateModel.initial();
  }
}

final paxWalletRepositoryProvider = Provider<PaxWalletRepository>((ref) {
  return PaxWalletRepository();
});

final paxWalletProvider =
    NotifierProvider<PaxWalletNotifier, PaxWalletStateModel>(() {
      return PaxWalletNotifier();
    });

/// True if user has a PaxWallet whose EOA is not yet whitelisted in GoodDollar Identity.
/// When wallet/EOA is missing, returns true (needs verification) so miniapps are not shown.
final paxWalletNeedsVerificationProvider = FutureProvider<bool>((ref) async {
  final state = ref.watch(paxWalletProvider);
  final eoAddress = state.wallet?.eoAddress;
  if (eoAddress == null || eoAddress.isEmpty) return true;
  final whitelisted = await GoodDollarIdentityService.isWhitelisted(eoAddress);
  return !whitelisted;
});
