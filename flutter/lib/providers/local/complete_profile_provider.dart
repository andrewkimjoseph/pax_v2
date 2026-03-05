import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CompleteProfileStep { editing, saving, completed, error }

class CompleteProfileState {
  final CompleteProfileStep step;
  final String? errorMessage;

  CompleteProfileState({
    this.step = CompleteProfileStep.editing,
    this.errorMessage,
  });

  CompleteProfileState copyWith({
    CompleteProfileStep? step,
    String? errorMessage,
  }) {
    return CompleteProfileState(
      step: step ?? this.step,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class CompleteProfileNotifier extends Notifier<CompleteProfileState> {
  @override
  CompleteProfileState build() {
    return CompleteProfileState();
  }

  void setSaving() {
    state = state.copyWith(step: CompleteProfileStep.saving);
  }

  void setCompleted() {
    state = state.copyWith(step: CompleteProfileStep.completed);
  }

  void setError(String message) {
    state = state.copyWith(
      step: CompleteProfileStep.error,
      errorMessage: message,
    );
  }

  void reset() {
    state = CompleteProfileState();
  }
}

final completeProfileProvider =
    NotifierProvider<CompleteProfileNotifier, CompleteProfileState>(() {
      return CompleteProfileNotifier();
    });
