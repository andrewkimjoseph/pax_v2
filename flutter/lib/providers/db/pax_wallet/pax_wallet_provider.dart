import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/models/auth/auth_state_model.dart';
import 'package:pax/models/firestore/pax_wallet/pax_wallet_model.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/withdrawal_method_connection/withdrawal_method_connection_provider.dart';
import 'package:pax/providers/db/withdrawal_method/withdrawal_method_provider.dart';
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
  late final PaxWalletRepository _repository;

  @override
  PaxWalletStateModel build() {
    _repository = ref.watch(paxWalletRepositoryProvider);

    ref.listen(authProvider, (previous, next) {
      if (previous?.state != next.state) {
        if (next.state == AuthState.authenticated) {
          fetchWallet(next.user.uid);
        } else if (next.state == AuthState.unauthenticated) {
          clearWallet();
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
      final wallet =
          await _repository.getWalletByParticipantId(participantId);
      state = state.copyWith(
        wallet: wallet,
        state: PaxWalletState.loaded,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Error fetching pax wallet: $e');
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
        state = state.copyWith(
          wallet: wallet,
          state: PaxWalletState.loaded,
        );
      }

      return wallet;
    } catch (e) {
      if (kDebugMode) debugPrint('Error creating pax wallet doc: $e');
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
      if (kDebugMode) debugPrint('Error updating smart account address: $e');
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
      if (kDebugMode) debugPrint('Error updating wallet log data: $e');
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
      final existing =
          await wmRepo.getPaymentMethodByWalletAddress(wallet.eoAddress!);
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
        debugPrint('Error registering PaxWallet as withdrawal method: $e');
      }
    }
  }

  /// Called when face verification succeeds: ensure payment_methods doc exists (idempotent) and refresh.
  Future<void> registerPaxWalletAfterFaceVerification() async {
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
      final existing =
          await wmRepo.getPaymentMethodByWalletAddress(wallet.eoAddress!);
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

      // Sponsor gas for the wallet (only when face verification completes)
      try {
        await FirebaseFunctions.instance
            .httpsCallable('sponsorWalletGas')
            .call({'eoWalletAddress': wallet.eoAddress});
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Gas sponsorship failed (non-blocking): $e');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error registering PaxWallet after face verification: $e');
      }
    }
  }

  void clearWallet() {
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
