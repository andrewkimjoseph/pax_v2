import 'package:flutter_riverpod/flutter_riverpod.dart';

enum FaceVerificationStep { loading, verifying, success, failed }

class FaceVerificationState {
  final FaceVerificationStep step;
  final String? chain;

  FaceVerificationState({
    this.step = FaceVerificationStep.loading,
    this.chain,
  });

  FaceVerificationState copyWith({
    FaceVerificationStep? step,
    String? chain,
  }) {
    return FaceVerificationState(
      step: step ?? this.step,
      chain: chain ?? this.chain,
    );
  }
}

class FaceVerificationNotifier extends Notifier<FaceVerificationState> {
  @override
  FaceVerificationState build() {
    return FaceVerificationState();
  }

  void setVerifying() {
    state = state.copyWith(step: FaceVerificationStep.verifying);
  }

  void setSuccess(String chain) {
    state = state.copyWith(
      step: FaceVerificationStep.success,
      chain: chain,
    );
  }

  void setFailed() {
    state = state.copyWith(step: FaceVerificationStep.failed);
  }

  void reset() {
    state = FaceVerificationState();
  }
}

final faceVerificationProvider =
    NotifierProvider<FaceVerificationNotifier, FaceVerificationState>(() {
      return FaceVerificationNotifier();
    });
