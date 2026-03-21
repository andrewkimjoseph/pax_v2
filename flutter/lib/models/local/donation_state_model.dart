enum DonationState { initial, submitting, success, error }

class DonationStateModel {
  final DonationState state;
  final String? errorMessage;
  final bool isSubmitting;
  final String? txnHash;
  final String? donationId;

  DonationStateModel({
    this.state = DonationState.initial,
    this.errorMessage,
    this.isSubmitting = false,
    this.txnHash,
    this.donationId,
  });

  DonationStateModel copyWith({
    DonationState? state,
    String? errorMessage,
    bool? isSubmitting,
    String? txnHash,
    String? donationId,
  }) {
    return DonationStateModel(
      state: state ?? this.state,
      errorMessage: errorMessage,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      txnHash: txnHash ?? this.txnHash,
      donationId: donationId ?? this.donationId,
    );
  }
}
