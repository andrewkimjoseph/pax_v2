import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ClaimRewardContext {
  final String? screeningId;
  final String? taskId;
  final String? taskCompletionId;
  final String? referralId;
  final num? amount;
  final int? tokenId;
  final String? txnHash;
  bool? taskIsCompleted = false;
  final int numberOfCooldownHours;
  final Timestamp? timeCompleted;
  final Timestamp? timeCreated;
  final bool? isValid;
  final bool? isReferral;
  final bool? isAchievement;
  final String? achievementId;

  ClaimRewardContext({
    this.screeningId,
    this.taskId,
    this.taskCompletionId,
    this.referralId,
    this.amount,
    this.tokenId,
    this.txnHash,
    this.taskIsCompleted,
    this.numberOfCooldownHours = 0,
    this.timeCompleted,
    this.timeCreated,
    this.isValid,
    this.isReferral,
    this.isAchievement,
    this.achievementId,
  });

  ClaimRewardContext copyWith({
    String? screeningId,
    String? taskId,
    String? taskCompletionId,
    String? referralId,
    num? amount,
    int? tokenId,
    String? txnHash,
    bool? taskIsCompleted,
    int? numberOfCooldownHours,
    Timestamp? timeCompleted,
    Timestamp? timeCreated,
    bool? isValid,
    bool? isReferral,
    bool? isAchievement,
    String? achievementId,
  }) {
    return ClaimRewardContext(
      screeningId: screeningId ?? this.screeningId,
      taskId: taskId ?? this.taskId,
      taskCompletionId: taskCompletionId ?? this.taskCompletionId,
      referralId: referralId ?? this.referralId,
      amount: amount ?? this.amount,
      tokenId: tokenId ?? this.tokenId,
      txnHash: txnHash ?? this.txnHash,
      taskIsCompleted: taskIsCompleted ?? this.taskIsCompleted,
      numberOfCooldownHours:
          numberOfCooldownHours ?? this.numberOfCooldownHours,
      timeCompleted: timeCompleted ?? this.timeCompleted,
      timeCreated: timeCreated ?? this.timeCreated,
      isValid: isValid ?? this.isValid,
      isReferral: isReferral ?? this.isReferral,
      isAchievement: isAchievement ?? this.isAchievement,
      achievementId: achievementId ?? this.achievementId,
    );
  }
}

class ClaimRewardContextNotifier extends Notifier<ClaimRewardContext?> {
  @override
  ClaimRewardContext? build() {
    return null;
  }

  void setContext({
    String? screeningId,
    String? taskId,
    String? taskCompletionId,
    String? referralId,
    num? amount,
    int? tokenId,
    String? txnHash,
    bool? taskIsCompleted,
    int numberOfCooldownHours = 0,
    Timestamp? timeCompleted,
    Timestamp? timeCreated,
    bool? isValid,
    bool? isReferral,
    bool? isAchievement,
    String? achievementId,
  }) {
    state = ClaimRewardContext(
      screeningId: screeningId,
      taskId: taskId,
      taskCompletionId: taskCompletionId,
      referralId: referralId,
      amount: amount,
      tokenId: tokenId,
      txnHash: txnHash,
      taskIsCompleted: taskIsCompleted,
      numberOfCooldownHours: numberOfCooldownHours,
      timeCompleted: timeCompleted,
      timeCreated: timeCreated,
      isValid: isValid,
      isReferral: isReferral,
      isAchievement: isAchievement,
      achievementId: achievementId,
    );
  }

  void clear() {
    state = null;
  }
}

final claimRewardContextProvider =
    NotifierProvider<ClaimRewardContextNotifier, ClaimRewardContext?>(
      () => ClaimRewardContextNotifier(),
    );
