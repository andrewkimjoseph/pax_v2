import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/models/auth/auth_state_model.dart';
import 'package:pax/models/firestore/pax_wallet/pax_wallet_model.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';
import 'package:pax/providers/referral_existence_provider.dart';
import 'package:pax/providers/db/achievement/achievement_provider.dart';
import 'package:pax/providers/fcm/fcm_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/providers/wallet/wallet_credentials_provider.dart';
import 'package:pax/providers/withdrawal_method_connection/withdrawal_method_connection_provider.dart';
import 'package:pax/providers/db/withdrawal_method/withdrawal_method_provider.dart';
import 'package:pax/utils/achievement_constants.dart';
import 'package:pax/utils/branch_param_cleaner.dart';
import 'package:pax/repositories/firestore/pax_wallet/pax_wallet_repository.dart';
import 'package:pax/services/blockchain/blockchain_service.dart';
import 'package:pax/services/wallet/gooddollar_identity_service.dart';
import 'package:pax/services/wallet/wallet_registry_service.dart';
import 'package:pax/utils/remote_config_constants.dart';

enum PaxWalletState { initial, loading, loaded, creating, error }

enum WalletRegistryLogStatus {
  loggedLocally,
  loggedNow,
  alreadyLoggedOnChain,
  missingWalletData,
  failed,
}

enum WalletDocumentBackfillStatus {
  skippedMissingPrerequisites,
  alreadyExists,
  createdNow,
  failed,
}

class PaxWalletStateModel {
  final PaxWallet? wallet;
  final PaxWalletState state;
  final String? errorMessage;
  final double? nativeCeloBalance;

  PaxWalletStateModel({
    this.wallet,
    this.state = PaxWalletState.initial,
    this.errorMessage,
    this.nativeCeloBalance,
  });

  factory PaxWalletStateModel.initial() {
    return PaxWalletStateModel();
  }

  PaxWalletStateModel copyWith({
    PaxWallet? wallet,
    PaxWalletState? state,
    String? errorMessage,
    double? nativeCeloBalance,
    bool clearNativeCeloBalance = false,
  }) {
    return PaxWalletStateModel(
      wallet: wallet ?? this.wallet,
      state: state ?? this.state,
      errorMessage: errorMessage ?? this.errorMessage,
      nativeCeloBalance:
          clearNativeCeloBalance
              ? null
              : (nativeCeloBalance ?? this.nativeCeloBalance),
    );
  }
}

class PaxWalletNotifier extends Notifier<PaxWalletStateModel> {
  PaxWalletRepository get _repository => ref.read(paxWalletRepositoryProvider);
  static const double _defaultAutoTopUpThresholdCelo = 0.028125;
  static const Duration _fetchWalletTimeout = Duration(seconds: 15);
  double _autoTopUpThresholdCelo() {
    final config = ref
        .read(paxWalletConfigProvider)
        .maybeWhen(
          data: (data) => data,
          orElse: () => const <String, dynamic>{},
        );
    final rawThreshold = config[RemoteConfigKeys.autoTopupThreshold];
    if (rawThreshold is num) {
      return rawThreshold.toDouble();
    }
    if (rawThreshold is String) {
      return double.tryParse(rawThreshold) ?? _defaultAutoTopUpThresholdCelo;
    }
    return _defaultAutoTopUpThresholdCelo;
  }

  /// EOA we have already requested gas sponsorship for this session; avoids duplicate sponsorWalletGas calls.
  String? _gasSponsorshipRequestedForEoAddress;
  int _fetchWalletRequestId = 0;
  String? _loadingWalletParticipantId;

  Future<void> _fetchWalletAndEnsureBackfill(String participantId) async {
    if (kDebugMode) {
      debugPrint(
        '[PaxWalletNotifier] _fetchWalletAndEnsureBackfill start '
        '(participantId=$participantId)',
      );
    }
    await fetchWallet(participantId);
    if (kDebugMode) {
      debugPrint(
        '[PaxWalletNotifier] _fetchWalletAndEnsureBackfill end '
        '(participantId=$participantId)',
      );
    }
  }

  @override
  PaxWalletStateModel build() {
    ref.listen(authProvider, (previous, next) {
      if (previous?.state != next.state) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] auth state changed '
            '(from=${previous?.state}, to=${next.state}, uid=${next.user.uid})',
          );
        }
        if (next.state == AuthState.authenticated) {
          if (kDebugMode) {
            debugPrint(
              '[PaxWalletNotifier] auth listener triggering wallet fetch/backfill '
              '(participantId=${next.user.uid})',
            );
          }
          _fetchWalletAndEnsureBackfill(next.user.uid);
        } else if (next.state == AuthState.unauthenticated) {
          if (kDebugMode) {
            debugPrint(
              '[PaxWalletNotifier] auth listener clearing wallet and credentials',
            );
          }
          clearWallet();
          ref.read(walletCredentialsProvider.notifier).clearCredentials();
        }
      }
    });

    ref.listen<WalletCredentialsState>(walletCredentialsProvider, (
      previous,
      next,
    ) {
      final didLoadCredentials =
          previous?.status != WalletCredentialsStatus.loaded &&
          next.status == WalletCredentialsStatus.loaded;
      if (!didLoadCredentials) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] wallet credentials listener ignored '
            '(prev=${previous?.status}, next=${next.status})',
          );
        }
        return;
      }
      if (next.isDebugOverride) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] wallet credentials listener skipped: '
            'debug override credentials loaded (no fetch/backfill)',
          );
        }
        return;
      }

      final authState = ref.read(authProvider);
      final participantId = authState.user.uid;
      if (authState.state != AuthState.authenticated || participantId.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] wallet credentials listener skipped: '
            'auth not ready (authState=${authState.state}, participantId=$participantId)',
          );
        }
        return;
      }
      if (state.wallet?.participantId == participantId &&
          state.wallet != null) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] wallet credentials listener skipped: '
            'wallet already loaded for participantId=$participantId',
          );
        }
        return;
      }
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] wallet credentials listener triggering wallet fetch/backfill '
          '(participantId=$participantId)',
        );
      }
      unawaited(_fetchWalletAndEnsureBackfill(participantId));
    });

    final authState = ref.read(authProvider);
    if (authState.state == AuthState.authenticated) {
      Future.microtask(() => _fetchWalletAndEnsureBackfill(authState.user.uid));
    }

    return PaxWalletStateModel.initial();
  }

  Future<void> fetchWallet(String participantId) async {
    if (participantId.isEmpty) return;
    if (state.state == PaxWalletState.loading &&
        _loadingWalletParticipantId == participantId) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] fetchWallet deduped while loading '
          '(participantId=$participantId, requestId=$_fetchWalletRequestId)',
        );
      }
      return;
    }
    if (state.state == PaxWalletState.loaded &&
        state.wallet?.participantId == participantId) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] fetchWallet skipped (already loaded for participantId=$participantId)',
        );
      }
      return;
    }

    final requestId = ++_fetchWalletRequestId;
    _loadingWalletParticipantId = participantId;
    if (kDebugMode) {
      debugPrint(
        '[PaxWalletNotifier] fetchWallet started '
        '(participantId=$participantId, requestId=$requestId)',
      );
    }

    try {
      state = state.copyWith(state: PaxWalletState.loading);
      final wallet = await _repository
          .getWalletByParticipantId(participantId)
          .timeout(_fetchWalletTimeout);

      final authState = ref.read(authProvider);
      final isCurrentRequest = requestId == _fetchWalletRequestId;
      final isCurrentUser =
          authState.state == AuthState.authenticated &&
          authState.user.uid == participantId;
      if (!isCurrentRequest || !isCurrentUser) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] Ignoring stale fetchWallet result '
            '(participantId=$participantId, requestId=$requestId, '
            'latestRequestId=$_fetchWalletRequestId, authUid=${authState.user.uid}, '
            'authState=${authState.state})',
          );
        }
        return;
      }

      state = state.copyWith(wallet: wallet, state: PaxWalletState.loaded);
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] fetchWallet completed '
          '(participantId=$participantId, requestId=$requestId, hasWallet=${wallet != null})',
        );
      }
      await refreshNativeCeloBalance();

      if (wallet == null) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] fetchWallet found no wallet; attempting backfill '
            '(participantId=$participantId, requestId=$requestId)',
          );
        }
        final backfillStatus = await ensureWalletDocumentExistsForCurrentUser();
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] fetchWallet backfill result '
            '(participantId=$participantId, requestId=$requestId, status=$backfillStatus)',
          );
        }
        if (backfillStatus == WalletDocumentBackfillStatus.createdNow ||
            backfillStatus == WalletDocumentBackfillStatus.alreadyExists) {
          if (kDebugMode) {
            debugPrint(
              '[PaxWalletNotifier] fetchWallet refetching wallet after backfill '
              '(participantId=$participantId, requestId=$requestId)',
            );
          }
          final refetchedWallet = await _repository.getWalletByParticipantId(
            participantId,
          );
          final latestAuthState = ref.read(authProvider);
          final stillCurrentRequest = requestId == _fetchWalletRequestId;
          final stillCurrentUser =
              latestAuthState.state == AuthState.authenticated &&
              latestAuthState.user.uid == participantId;
          if (stillCurrentRequest &&
              stillCurrentUser &&
              refetchedWallet != null) {
            state = state.copyWith(
              wallet: refetchedWallet,
              state: PaxWalletState.loaded,
            );
            await refreshNativeCeloBalance();
            if (kDebugMode) {
              debugPrint(
                '[PaxWalletNotifier] fetchWallet updated state from refetched wallet '
                '(participantId=$participantId, requestId=$requestId, walletId=${refetchedWallet.id})',
              );
            }
          } else if (kDebugMode) {
            debugPrint(
              '[PaxWalletNotifier] fetchWallet skipped applying refetched wallet '
              '(participantId=$participantId, requestId=$requestId, '
              'stillCurrentRequest=$stillCurrentRequest, stillCurrentUser=$stillCurrentUser, '
              'refetchedWalletNull=${refetchedWallet == null})',
            );
          }
        }
      }
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] fetchWallet timed out for participantId=$participantId: $e',
        );
      }
      final isCurrentRequest = requestId == _fetchWalletRequestId;
      if (!isCurrentRequest) return;
      state = state.copyWith(
        state: PaxWalletState.error,
        errorMessage: 'Wallet fetch timed out. Please try again.',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PaxWalletNotifier] Error fetching pax wallet: $e');
      }
      final isCurrentRequest = requestId == _fetchWalletRequestId;
      if (!isCurrentRequest) return;
      state = state.copyWith(
        state: PaxWalletState.error,
        errorMessage: e.toString(),
      );
    } finally {
      if (requestId == _fetchWalletRequestId) {
        _loadingWalletParticipantId = null;
      }
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] fetchWallet finalized '
          '(participantId=$participantId, requestId=$requestId, '
          'latestRequestId=$_fetchWalletRequestId, state=${state.state})',
        );
      }
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
        await refreshNativeCeloBalance();
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

  Future<void> refreshNativeCeloBalance() async {
    final eoAddress = state.wallet?.eoAddress;
    if (eoAddress == null || eoAddress.isEmpty) {
      state = state.copyWith(clearNativeCeloBalance: true);
      return;
    }

    try {
      final celoBalance = await BlockchainService.fetchNativeCeloBalance(
        eoAddress,
      );
      state = state.copyWith(nativeCeloBalance: celoBalance);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PaxWalletNotifier] Failed to refresh native CELO: $e');
      }
      state = state.copyWith(clearNativeCeloBalance: true);
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

  /// Ensures there is a `pax_wallets` record for the authenticated user.
  /// Idempotent and safe for repeated calls in app lifecycle / verification flows.
  Future<WalletDocumentBackfillStatus>
  ensureWalletDocumentExistsForCurrentUser() async {
    final authState = ref.read(authProvider);
    if (authState.state != AuthState.authenticated) {
      return WalletDocumentBackfillStatus.skippedMissingPrerequisites;
    }
    final participantId = authState.user.uid;
    if (participantId.isEmpty) {
      return WalletDocumentBackfillStatus.skippedMissingPrerequisites;
    }

    final credsState = ref.read(walletCredentialsProvider);
    final paxAccountState = ref.read(paxAccountProvider);
    final walletEoAddress = state.wallet?.eoAddress;
    final credsEoAddress = credsState.eoAddress;
    final paxAccountEoAddress = paxAccountState.account?.eoWalletAddress;
    final eoAddress =
        (state.wallet?.eoAddress?.isNotEmpty ?? false)
            ? state.wallet!.eoAddress!
            : ((credsState.eoAddress?.isNotEmpty ?? false)
                ? credsState.eoAddress
                : paxAccountState.account?.eoWalletAddress);
    if (kDebugMode) {
      final source =
          (walletEoAddress?.isNotEmpty ?? false)
              ? 'wallet_state'
              : ((credsEoAddress?.isNotEmpty ?? false)
                  ? 'wallet_credentials'
                  : 'pax_account');
      debugPrint(
        '[PaxWalletNotifier] ensureWalletDocumentExistsForCurrentUser EOA resolution '
        '(participantId=$participantId, source=$source, '
        'walletStateHasEo=${walletEoAddress?.isNotEmpty ?? false}, '
        'credentialsHasEo=${credsEoAddress?.isNotEmpty ?? false}, '
        'paxAccountHasEo=${paxAccountEoAddress?.isNotEmpty ?? false})',
      );
    }
    if (eoAddress == null || eoAddress.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] ensureWalletDocumentExistsForCurrentUser skipped: missing eoAddress',
        );
      }
      return WalletDocumentBackfillStatus.skippedMissingPrerequisites;
    }

    try {
      final existingWallet =
          state.wallet?.participantId == participantId && state.wallet != null
              ? state.wallet
              : await _repository.getWalletByParticipantId(participantId);
      if (existingWallet != null) {
        if (state.wallet?.id != existingWallet.id) {
          state = state.copyWith(
            wallet: existingWallet,
            state: PaxWalletState.loaded,
          );
        }
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] ensureWalletDocumentExistsForCurrentUser: wallet already exists',
          );
        }
        return WalletDocumentBackfillStatus.alreadyExists;
      }

      final createdWallet = await createWalletDocument(
        participantId: participantId,
        eoAddress: eoAddress,
      );

      if (createdWallet == null) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] ensureWalletDocumentExistsForCurrentUser failed: createWalletDocument returned null',
          );
        }
        return WalletDocumentBackfillStatus.failed;
      }

      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] ensureWalletDocumentExistsForCurrentUser: wallet created',
        );
      }
      return WalletDocumentBackfillStatus.createdNow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] ensureWalletDocumentExistsForCurrentUser failed: $e',
        );
      }
      return WalletDocumentBackfillStatus.failed;
    }
  }

  /// Ensures wallet is logged to the on-chain registry.
  /// Idempotent and safe to call from multiple entry points.
  Future<WalletRegistryLogStatus> ensureWalletLoggedToRegistry() async {
    final wallet = state.wallet;
    final eoAddress = wallet?.eoAddress;
    final walletId = wallet?.id;
    final hasLocalLogHash = (wallet?.logTxnHash ?? '').isNotEmpty;

    if (eoAddress == null ||
        eoAddress.isEmpty ||
        walletId == null ||
        walletId.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] ensureWalletLoggedToRegistry skipped: missing wallet data',
        );
      }
      return WalletRegistryLogStatus.missingWalletData;
    }

    try {
      final registryService = WalletRegistryService();
      final onChainLogged = await registryService.isWalletLogged(eoAddress);
      if (onChainLogged) {
        return hasLocalLogHash
            ? WalletRegistryLogStatus.loggedLocally
            : WalletRegistryLogStatus.alreadyLoggedOnChain;
      }

      if (hasLocalLogHash && kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] local log hash exists but on-chain status is false; attempting relog',
        );
      }

      final registryResult = await registryService.logWallet(
        eoWalletAddress: eoAddress,
      );
      final txHash = registryResult.txnHash;

      if (txHash != null && txHash.isNotEmpty) {
        await updateWithLogData(
          walletId: walletId,
          logTxnHash: txHash,
          logTimeCreated: registryResult.logTimeCreated,
        );
        return WalletRegistryLogStatus.loggedNow;
      }

      if (registryResult.alreadyLogged) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] wallet already logged on-chain; local log hash remains empty',
          );
        }
        return WalletRegistryLogStatus.alreadyLoggedOnChain;
      }

      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] ensureWalletLoggedToRegistry failed: missing txHash and alreadyLogged=false',
        );
      }
      return WalletRegistryLogStatus.failed;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] ensureWalletLoggedToRegistry error: $e',
        );
      }
      return WalletRegistryLogStatus.failed;
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
    final walletBackfillStatus =
        await ensureWalletDocumentExistsForCurrentUser();
    if (walletBackfillStatus == WalletDocumentBackfillStatus.failed ||
        walletBackfillStatus ==
            WalletDocumentBackfillStatus.skippedMissingPrerequisites) {
      return;
    }

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

    await _safeCreateReferralRecord(participantId);

    final logStatus = await ensureWalletLoggedToRegistry();
    if (logStatus == WalletRegistryLogStatus.failed ||
        logStatus == WalletRegistryLogStatus.missingWalletData) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] skipping sponsorWalletGas after face verification: wallet not logged',
        );
      }
      return;
    }
    await _safeSponsorGas(wallet.eoAddress!);
  }

  /// Backfill pass for users who already completed face verification earlier.
  /// Runs idempotent/non-blocking post-verification side effects again.
  Future<void> backfillPostVerificationSideEffects() async {
    final walletBackfillStatus =
        await ensureWalletDocumentExistsForCurrentUser();
    if (walletBackfillStatus == WalletDocumentBackfillStatus.failed ||
        walletBackfillStatus ==
            WalletDocumentBackfillStatus.skippedMissingPrerequisites) {
      return;
    }

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
    ]);

    final logStatus = await ensureWalletLoggedToRegistry();
    if (logStatus == WalletRegistryLogStatus.failed ||
        logStatus == WalletRegistryLogStatus.missingWalletData) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] backfill: skipping sponsorWalletGas because wallet logging failed',
        );
      }
      return;
    }
    await _safeSponsorGas(wallet.eoAddress!);
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
          ref.invalidate(referralExistsForReferredParticipantProvider);
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '[PaxWalletNotifier] createReferral failed (non-blocking): $e',
            );
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] skipping referral record creation '
            '(no valid referringParticipantId in Branch params)',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] error while preparing referral record params (non-blocking): $e',
        );
      }
    }
  }

  /// Auto top-up flow for V2 wallet gas.
  /// Calls sponsorWalletGas when native CELO balance is below 0.01875 CELO.
  Future<bool> topUpGasIfNeeded() async {
    try {
      final wallet = state.wallet;
      final eoAddress = wallet?.eoAddress;
      if (eoAddress == null || eoAddress.isEmpty) {
        state = state.copyWith(clearNativeCeloBalance: true);
        return false;
      }

      final logStatus = await ensureWalletLoggedToRegistry();
      if (logStatus == WalletRegistryLogStatus.failed ||
          logStatus == WalletRegistryLogStatus.missingWalletData) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] topUpGasIfNeeded skipped: wallet not logged in registry',
          );
        }
        return false;
      }

      final celoBalance = await BlockchainService.fetchNativeCeloBalance(
        eoAddress,
      );
      state = state.copyWith(nativeCeloBalance: celoBalance);
      if (celoBalance >= _autoTopUpThresholdCelo()) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] topUpGasIfNeeded skipped: CELO balance sufficient '
            '(eoAddress=$eoAddress, celoBalance=$celoBalance)',
          );
        }
        return false;
      }

      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] topUpGasIfNeeded triggering sponsorWalletGas '
          '(eoAddress=$eoAddress, celoBalance=$celoBalance)',
        );
      }

      final result = await FirebaseFunctions.instance
          .httpsCallable('sponsorWalletGas')
          .call({'eoWalletAddress': eoAddress});

      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] topUpGasIfNeeded sponsorWalletGas result '
          '(eoAddress=$eoAddress): ${result.data}',
        );
      }
      await refreshNativeCeloBalance();
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PaxWalletNotifier] topUpGasIfNeeded failed: $e');
      }
      return false;
    }
  }

  /// Sponsor gas at most once per wallet per app session; errors are swallowed.
  Future<void> _safeSponsorGas(String eoAddress) async {
    try {
      final logStatus = await ensureWalletLoggedToRegistry();
      if (logStatus == WalletRegistryLogStatus.failed ||
          logStatus == WalletRegistryLogStatus.missingWalletData) {
        if (kDebugMode) {
          debugPrint(
            '[PaxWalletNotifier] _safeSponsorGas skipped: wallet not logged in registry',
          );
        }
        return;
      }

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
          debugPrint(
            '[PaxWalletNotifier] Gas sponsorship failed (non-blocking): $e',
          );
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
    final eoAddress = state.wallet?.eoAddress;
    if (eoAddress == null || eoAddress.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] skipping Verified Human create: missing wallet eoAddress '
          '(participantId=$participantId)',
        );
      }
      return;
    }

    final isWhitelisted = await GoodDollarIdentityService.isWhitelisted(
      eoAddress,
    );
    if (!isWhitelisted) {
      if (kDebugMode) {
        debugPrint(
          '[PaxWalletNotifier] skipping Verified Human create: user not face-verified/whitelisted '
          '(participantId=$participantId, eoAddress=$eoAddress)',
        );
      }
      return;
    }

    final achievementAmounts = ref
        .read(achievementAmountsProvider)
        .maybeWhen(
          data: (data) => data,
          orElse: () => AchievementConstants.defaultAchievementAmounts,
        );
    final verifiedHumanAmount = AchievementConstants.getAmountForAchievement(
      AchievementConstants.verifiedHuman,
      achievementAmounts,
    );

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
      amountEarned: verifiedHumanAmount,
    );

    ref.read(analyticsProvider).achievementCreated({
      'achievementName': AchievementConstants.verifiedHuman,
      'amountEarned': verifiedHumanAmount,
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
                'amountEarned': verifiedHumanAmount,
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
    final previousRequestId = _fetchWalletRequestId;
    final previousParticipantId = state.wallet?.participantId;
    _fetchWalletRequestId++;
    _loadingWalletParticipantId = null;
    _gasSponsorshipRequestedForEoAddress = null;
    state = PaxWalletStateModel.initial().copyWith(
      clearNativeCeloBalance: true,
    );
    if (kDebugMode) {
      debugPrint(
        '[PaxWalletNotifier] clearWallet '
        '(previousParticipantId=$previousParticipantId, '
        'previousRequestId=$previousRequestId, '
        'newRequestId=$_fetchWalletRequestId)',
      );
    }
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
