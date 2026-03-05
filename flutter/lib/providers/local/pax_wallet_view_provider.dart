import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/services/blockchain/blockchain_service.dart';

enum PaxWalletViewState { initial, loading, loaded, error }

class PaxWalletViewStateModel {
  final PaxWalletViewState state;
  final double gdBalance;
  final double cusdBalance;
  final String? errorMessage;

  PaxWalletViewStateModel({
    this.state = PaxWalletViewState.initial,
    this.gdBalance = 0.0,
    this.cusdBalance = 0.0,
    this.errorMessage,
  });

  PaxWalletViewStateModel copyWith({
    PaxWalletViewState? state,
    double? gdBalance,
    double? cusdBalance,
    String? errorMessage,
  }) {
    return PaxWalletViewStateModel(
      state: state ?? this.state,
      gdBalance: gdBalance ?? this.gdBalance,
      cusdBalance: cusdBalance ?? this.cusdBalance,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class PaxWalletViewNotifier extends Notifier<PaxWalletViewStateModel> {
  @override
  PaxWalletViewStateModel build() {
    return PaxWalletViewStateModel();
  }

  Future<void> fetchBalance(String eoAddress) async {
    state = state.copyWith(state: PaxWalletViewState.loading);
    try {
      final balances = await BlockchainService.fetchAllTokenBalances(eoAddress);
      final gdBalance = balances[1] ?? 0.0;
      final cusdBalance = balances[2] ?? 0.0;
      state = state.copyWith(
        state: PaxWalletViewState.loaded,
        gdBalance: gdBalance,
        cusdBalance: cusdBalance,
      );
    } catch (e) {
      if (kDebugMode) print('Error fetching PaxWallet balance: $e');
      state = state.copyWith(
        state: PaxWalletViewState.error,
        errorMessage: e.toString(),
      );
    }
  }
}

final paxWalletViewProvider =
    NotifierProvider<PaxWalletViewNotifier, PaxWalletViewStateModel>(() {
      return PaxWalletViewNotifier();
    });
