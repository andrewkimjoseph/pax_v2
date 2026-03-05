import 'package:flutter_riverpod/flutter_riverpod.dart';

enum WalletCreationStep { info, creating, success, error }

class WalletCreationState {
  final WalletCreationStep step;
  final String? errorMessage;

  WalletCreationState({
    this.step = WalletCreationStep.info,
    this.errorMessage,
  });

  WalletCreationState copyWith({
    WalletCreationStep? step,
    String? errorMessage,
  }) {
    return WalletCreationState(
      step: step ?? this.step,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class WalletCreationNotifier extends Notifier<WalletCreationState> {
  @override
  WalletCreationState build() {
    return WalletCreationState();
  }

  void setStep(WalletCreationStep step) {
    state = state.copyWith(step: step);
  }

  void setError(String message) {
    state = state.copyWith(
      step: WalletCreationStep.error,
      errorMessage: message,
    );
  }

  void reset() {
    state = WalletCreationState();
  }
}

final walletCreationProvider =
    NotifierProvider<WalletCreationNotifier, WalletCreationState>(() {
      return WalletCreationNotifier();
    });
