import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/models/firestore/payment_method/payment_method.dart';
import 'package:pax/models/remote_config/goodcollective_config.dart';

enum ClaimKind { achievement, task, referral }

class ClaimPayoutContext {
  final ClaimKind claimKind;
  final int tokenId;
  final num amount;
  final WithdrawalMethod? selectedWithdrawalMethod;
  final bool isDonation;
  final GoodCollective? selectedGoodCollective;
  final int donationBasisPoints;

  // Identifiers for each claim type
  final String? achievementId;
  final String? taskCompletionId;
  final String? referralId;

  ClaimPayoutContext({
    required this.claimKind,
    required this.tokenId,
    required this.amount,
    this.selectedWithdrawalMethod,
    this.isDonation = false,
    this.selectedGoodCollective,
    this.donationBasisPoints = 1000,
    this.achievementId,
    this.taskCompletionId,
    this.referralId,
  });

  ClaimPayoutContext copyWith({
    ClaimKind? claimKind,
    int? tokenId,
    num? amount,
    WithdrawalMethod? selectedWithdrawalMethod,
    bool? isDonation,
    GoodCollective? selectedGoodCollective,
    int? donationBasisPoints,
    String? achievementId,
    String? taskCompletionId,
    String? referralId,
  }) {
    return ClaimPayoutContext(
      claimKind: claimKind ?? this.claimKind,
      tokenId: tokenId ?? this.tokenId,
      amount: amount ?? this.amount,
      selectedWithdrawalMethod:
          selectedWithdrawalMethod ?? this.selectedWithdrawalMethod,
      isDonation: isDonation ?? this.isDonation,
      selectedGoodCollective:
          selectedGoodCollective ?? this.selectedGoodCollective,
      donationBasisPoints: donationBasisPoints ?? this.donationBasisPoints,
      achievementId: achievementId ?? this.achievementId,
      taskCompletionId: taskCompletionId ?? this.taskCompletionId,
      referralId: referralId ?? this.referralId,
    );
  }
}

class ClaimPayoutContextNotifier extends Notifier<ClaimPayoutContext?> {
  @override
  ClaimPayoutContext? build() => null;

  void setContext(ClaimPayoutContext context) {
    state = context;
  }

  void setSelectedPaymentMethod(WithdrawalMethod? method) {
    if (state == null) return;
    state = ClaimPayoutContext(
      claimKind: state!.claimKind,
      tokenId: state!.tokenId,
      amount: state!.amount,
      selectedWithdrawalMethod: method,
      isDonation: state!.isDonation,
      selectedGoodCollective: state!.selectedGoodCollective,
      donationBasisPoints: state!.donationBasisPoints,
      achievementId: state!.achievementId,
      taskCompletionId: state!.taskCompletionId,
      referralId: state!.referralId,
    );
  }

  void setSelectedGoodCollective(GoodCollective? collective) {
    if (state == null) return;
    state = state!.copyWith(selectedGoodCollective: collective);
  }

  void clear() {
    state = null;
  }
}

final claimPayoutContextProvider =
    NotifierProvider<ClaimPayoutContextNotifier, ClaimPayoutContext?>(
      () => ClaimPayoutContextNotifier(),
    );
