import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pax/utils/achievement_constants.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

enum AchievementStatus { inProgress, earned, claimed }

class Achievement {
  final String id;
  final String? participantId;
  final String? name;
  final num tasksCompleted;
  final num tasksNeededForCompletion;
  final Timestamp? timeCreated;
  final Timestamp? timeCompleted;
  final Timestamp? timeClaimed;
  final num? amountEarned;
  final String? txnHash;

  Achievement({
    required this.id,
    this.participantId,
    this.name,
    required this.tasksCompleted,
    required this.tasksNeededForCompletion,
    this.timeCreated,
    this.timeCompleted,
    this.timeClaimed,
    this.amountEarned,
    this.txnHash,
  });

  // Computed properties
  AchievementStatus get status {
    if (txnHash != null) return AchievementStatus.claimed;
    if (amountEarned != null && timeCompleted != null) {
      return AchievementStatus.earned;
    }
    return AchievementStatus.inProgress;
  }

  String get goal {
    final isCompleted =
        status == AchievementStatus.earned ||
        status == AchievementStatus.claimed;
    switch (name) {
      case AchievementConstants.payoutConnector:
        return isCompleted
            ? 'Connected a payment method'
            : 'Connect a payment method';
      case AchievementConstants.verifiedHuman:
        return isCompleted
            ? 'Verified humanness on your connected payment method'
            : 'Verify humanness on your connected payment method';
      case AchievementConstants.profilePerfectionist:
        return isCompleted
            ? 'Filled in your country, gender, and date of birth'
            : 'Fill in your country, gender, and date of birth';
      case AchievementConstants.taskStarter:
        return isCompleted
            ? 'Completed $tasksNeededForCompletion task${tasksNeededForCompletion == 1 ? '' : 's'}'
            : 'Complete $tasksNeededForCompletion task${tasksNeededForCompletion == 1 ? '' : 's'}';
      case AchievementConstants.taskExpert:
        final taskExpertLabel = AchievementConstants.taskExpertTasksNeeded;
        return isCompleted
            ? 'Completed $taskExpertLabel tasks'
            : 'Complete $taskExpertLabel tasks';
      case AchievementConstants.doublePayoutConnector:
        return isCompleted
            ? 'Connected two payment methods'
            : 'Connect two payment methods';
      case AchievementConstants.triplePayoutConnector:
        return isCompleted
            ? 'Connected three payment methods'
            : 'Connect three payment methods';
      case AchievementConstants.goodImpact:
        final targetDonationLabel = NumberFormat(
          '#,###',
        ).format(AchievementConstants.goodImpactTasksNeeded);
        return isCompleted
            ? 'Donated $targetDonationLabel G\$'
            : 'Donate a total of $targetDonationLabel G\$';
      default:
        return '';
    }
  }

  String get svgAssetName {
    switch (name) {
      case AchievementConstants.payoutConnector:
        return 'payout_connector';
      case AchievementConstants.verifiedHuman:
        return 'verified_human';
      case AchievementConstants.profilePerfectionist:
        return 'profile_perfectionist';
      case AchievementConstants.taskStarter:
        return 'task_starter';
      case AchievementConstants.taskExpert:
        return 'task_expert';
      case AchievementConstants.doublePayoutConnector:
        return 'payout_connector';
      case AchievementConstants.triplePayoutConnector:
        return 'payout_connector';
      case AchievementConstants.goodImpact:
        return 'task_expert';
      default:
        return 'task_expert';
    }
  }

  IconData get icon {
    switch (name) {
      case AchievementConstants.payoutConnector:
      case AchievementConstants.doublePayoutConnector:
      case AchievementConstants.triplePayoutConnector:
        return FontAwesomeIcons.wallet;
      case AchievementConstants.verifiedHuman:
        return FontAwesomeIcons.solidCircleCheck;
      case AchievementConstants.profilePerfectionist:
        return FontAwesomeIcons.solidAddressCard;
      case AchievementConstants.taskStarter:
        return FontAwesomeIcons.listCheck;
      case AchievementConstants.taskExpert:
        return FontAwesomeIcons.trophy;
      case AchievementConstants.goodImpact:
        return FontAwesomeIcons.handHoldingHeart;
      default:
        return FontAwesomeIcons.trophy;
    }
  }

  int? get connectorLevelBadge {
    switch (name) {
      case AchievementConstants.payoutConnector:
        return 1;
      case AchievementConstants.doublePayoutConnector:
        return 2;
      case AchievementConstants.triplePayoutConnector:
        return 3;
      default:
        return null;
    }
  }

  String get completionMessage {
    if (name == AchievementConstants.goodImpact) {
      return '$tasksCompleted G\$ / $tasksNeededForCompletion G\$';
    }
    if (status == AchievementStatus.earned ||
        status == AchievementStatus.claimed) {
      return 'Earned on ${timeCompleted?.toDate().toString()}';
    }
    return '$tasksCompleted/$tasksNeededForCompletion';
  }

  // Factory method to create an Achievement from Firestore document
  factory Achievement.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      return Achievement(
        id: doc.id,
        tasksCompleted: 0,
        tasksNeededForCompletion: 1,
      );
    }

    return Achievement(
      id: doc.id,
      participantId: data['participantId'],
      name: data['name'],
      tasksCompleted: data['tasksCompleted'] ?? 0,
      tasksNeededForCompletion: data['tasksNeededForCompletion'] ?? 1,
      timeCreated: data['timeCreated'],
      timeCompleted: data['timeCompleted'],
      timeClaimed: data['timeClaimed'],
      amountEarned: data['amountEarned'],
      txnHash: data['txnHash'],
    );
  }

  // Convert Achievement to a Map
  Map<String, dynamic> toMap() {
    return {
      'participantId': participantId,
      'name': name,
      'tasksCompleted': tasksCompleted,
      'tasksNeededForCompletion': tasksNeededForCompletion,
      'timeCreated': timeCreated,
      'timeCompleted': timeCompleted,
      'timeClaimed': timeClaimed,
      'amountEarned': amountEarned,
      'txnHash': txnHash,
    };
  }

  // Create a copy with updated values
  Achievement copyWith({
    String? id,
    String? participantId,
    String? name,
    num? tasksCompleted,
    num? tasksNeededForCompletion,
    Timestamp? timeCreated,
    Timestamp? timeCompleted,
    Timestamp? timeClaimed,
    num? amountEarned,
    String? txnHash,
  }) {
    return Achievement(
      id: id ?? this.id,
      participantId: participantId ?? this.participantId,
      name: name ?? this.name,
      tasksCompleted: tasksCompleted ?? this.tasksCompleted,
      tasksNeededForCompletion:
          tasksNeededForCompletion ?? this.tasksNeededForCompletion,
      timeCreated: timeCreated ?? this.timeCreated,
      timeCompleted: timeCompleted ?? this.timeCompleted,
      timeClaimed: timeClaimed ?? this.timeClaimed,
      amountEarned: amountEarned ?? this.amountEarned,
      txnHash: txnHash ?? this.txnHash,
    );
  }

  // Create an empty achievement
  factory Achievement.empty() {
    return Achievement(id: '', tasksCompleted: 0, tasksNeededForCompletion: 1);
  }

  bool get isEmpty => id.isEmpty;
  bool get isNotEmpty => !isEmpty;
}
