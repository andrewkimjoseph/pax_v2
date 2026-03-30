import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/services/blockchain/blockchain_service.dart';
import 'package:pax/utils/local_db_helper.dart';

enum PaxWalletViewState { initial, loading, loaded, error }

class PaxWalletViewStateModel {
  final PaxWalletViewState state;
  final double gdBalance;
  final double cusdBalance;
  final double usdtBalance;
  final String? errorMessage;
  final String? networkLabel;

  PaxWalletViewStateModel({
    this.state = PaxWalletViewState.initial,
    this.gdBalance = 0.0,
    this.cusdBalance = 0.0,
    this.usdtBalance = 0.0,
    this.errorMessage,
    this.networkLabel,
  });

  PaxWalletViewStateModel copyWith({
    PaxWalletViewState? state,
    double? gdBalance,
    double? cusdBalance,
    double? usdtBalance,
    String? errorMessage,
    String? networkLabel,
    bool clearNetworkLabel = false,
  }) {
    return PaxWalletViewStateModel(
      state: state ?? this.state,
      gdBalance: gdBalance ?? this.gdBalance,
      cusdBalance: cusdBalance ?? this.cusdBalance,
      usdtBalance: usdtBalance ?? this.usdtBalance,
      errorMessage: errorMessage ?? this.errorMessage,
      networkLabel: clearNetworkLabel ? null : (networkLabel ?? this.networkLabel),
    );
  }
}

class PaxWalletViewNotifier extends Notifier<PaxWalletViewStateModel> {
  @override
  PaxWalletViewStateModel build() {
    return PaxWalletViewStateModel();
  }

  Future<void> fetchBalance(String eoAddress, {bool silent = false, bool forceRefresh = false}) async {
    final participantId = ref.read(participantProvider).participant?.id;

    // On load: show cached EOA balances from DB immediately to avoid empty/loading state
    if (participantId != null) {
      try {
        final cached =
            await LocalDBHelper().getPaxWalletEoaBalances(participantId);
        if (cached.isNotEmpty) {
          state = state.copyWith(
            state: PaxWalletViewState.loaded,
            gdBalance: (cached[1] ?? 0).toDouble(),
            cusdBalance: (cached[2] ?? 0).toDouble(),
            usdtBalance: (cached[3] ?? 0).toDouble(),
          );
        }
      } catch (_) {
        // Ignore DB read errors; we'll show loading and fetch from chain
      }
    }

    // When user explicitly taps refresh, always fetch from blockchain and sync to DB.
    // Otherwise throttle: if we refreshed recently, reuse cached values.
    if (!forceRefresh && participantId != null) {
      try {
        final info =
            await LocalDBHelper().getRefreshments(participantId);
        final lastMillis = info['walletRefreshTime'];
        if (lastMillis != null) {
          final last =
              DateTime.fromMillisecondsSinceEpoch(lastMillis);
          if (DateTime.now().difference(last) <
              const Duration(seconds: 30)) {
            // Not stale: keep current state (which may already reflect cached DB values).
            return;
          }
        }
      } catch (_) {
        // If refreshments lookup fails, fall back to normal fetch.
      }
    }

    final alreadyLoaded = state.state == PaxWalletViewState.loaded;
    if (!silent || !alreadyLoaded) {
      state = state.copyWith(state: PaxWalletViewState.loading);
    }
    try {
      final balancesFuture = BlockchainService.fetchAllTokenBalances(eoAddress);
      final networkLabelFuture = BlockchainService.getNetworkLabel();
      final balances = await balancesFuture;
      final networkLabel = await networkLabelFuture;
      final gdBalance = balances[1] ?? 0.0;
      final cusdBalance = balances[2] ?? 0.0;
      final usdtBalance = balances[3] ?? 0.0;
      state = state.copyWith(
        state: PaxWalletViewState.loaded,
        gdBalance: gdBalance,
        cusdBalance: cusdBalance,
        usdtBalance: usdtBalance,
        networkLabel: networkLabel,
      );
      // Sync EOA balances to dedicated table so wallet card shows wallet, not account
      if (participantId != null) {
        final dbBalances = <int, num>{
          1: gdBalance,
          2: cusdBalance,
          3: usdtBalance,
          4: balances[4] ?? 0.0,
        };
        await LocalDBHelper().setPaxWalletEoaBalances(participantId, dbBalances);
        await LocalDBHelper().upsertRefreshments(
          participantId: participantId,
          walletRefreshTime: DateTime.now().millisecondsSinceEpoch,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Error] Error fetching PaxWallet balance: $e');
      state = state.copyWith(
        state: PaxWalletViewState.error,
        errorMessage: e.toString(),
        clearNetworkLabel: true,
      );
    }
  }
}

final paxWalletViewProvider =
    NotifierProvider<PaxWalletViewNotifier, PaxWalletViewStateModel>(() {
      return PaxWalletViewNotifier();
    });
