import 'package:pax/models/firestore/achievement/achievement_model.dart';

// Achievement names and amounts constants
class AchievementConstants {
  // Achievement Names
  static const String taskStarter = "Task Starter";
  static const String taskExpert = "Task Expert";
  static const String profilePerfectionist = "Profile Perfectionist";
  static const String payoutConnector = "Payout Connector";
  static const String doublePayoutConnector = "Double Payout Connector";
  static const String triplePayoutConnector = "Triple Payout Connector";
  static const String goodImpact = "Good Impact";

  static const String verifiedHuman = "Verified Human";

  // Achievement Amounts
  static const int taskStarterAmount = 100;
  static const int taskExpertAmount = 200;
  static const int profilePerfectionistAmount = 100;
  static const int payoutConnectorAmount = 100;
  static const int doublePayoutConnectorAmount = 50;
  static const int triplePayoutConnectorAmount = 50;
  static const int verifiedHumanAmount = 200;
  static const int goodImpactAmount = 200;

  // Remote config keys for achievement amounts
  static const String taskStarterAmountKey = 'taskStarterAmount';
  static const String taskExpertAmountKey = 'taskExpertAmount';
  static const String profilePerfectionistAmountKey =
      'profilePerfectionistAmount';
  static const String payoutConnectorAmountKey = 'payoutConnectorAmount';
  static const String doublePayoutConnectorAmountKey =
      'doublePayoutConnectorAmount';
  static const String triplePayoutConnectorAmountKey =
      'triplePayoutConnectorAmount';
  static const String verifiedHumanAmountKey = 'verifiedHumanAmount';
  static const String goodImpactAmountKey = 'goodImpactAmount';

  // Achievement Tasks Needed
  static const int taskStarterTasksNeeded = 1;
  static const int taskExpertTasksNeeded = 10;
  static const int profilePerfectionistTasksNeeded = 1;
  static const int payoutConnectorTasksNeeded = 1;
  static const int doublePayoutConnectorTasksNeeded = 1;
  static const int triplePayoutConnectorTasksNeeded = 1;
  static const int verifiedHumanTasksNeeded = 1;
  static const int goodImpactTasksNeeded = 5000;

  static const Map<String, int> defaultAchievementAmounts = {
    taskStarterAmountKey: taskStarterAmount,
    taskExpertAmountKey: taskExpertAmount,
    profilePerfectionistAmountKey: profilePerfectionistAmount,
    payoutConnectorAmountKey: payoutConnectorAmount,
    doublePayoutConnectorAmountKey: doublePayoutConnectorAmount,
    triplePayoutConnectorAmountKey: triplePayoutConnectorAmount,
    verifiedHumanAmountKey: verifiedHumanAmount,
    goodImpactAmountKey: goodImpactAmount,
  };

  /// Maps an achievement name to its remote-config amount key.
  static String? amountKeyForAchievementName(String achievementName) {
    switch (achievementName) {
      case taskStarter:
        return taskStarterAmountKey;
      case taskExpert:
        return taskExpertAmountKey;
      case profilePerfectionist:
        return profilePerfectionistAmountKey;
      case payoutConnector:
        return payoutConnectorAmountKey;
      case doublePayoutConnector:
        return doublePayoutConnectorAmountKey;
      case triplePayoutConnector:
        return triplePayoutConnectorAmountKey;
      case verifiedHuman:
        return verifiedHumanAmountKey;
      case goodImpact:
        return goodImpactAmountKey;
      default:
        return null;
    }
  }

  /// Returns the effective amount for a given remote-config amount key.
  static int getAmountByKey(
    String amountKey, [
    Map<String, int>? remoteAmounts,
  ]) {
    return remoteAmounts?[amountKey] ??
        defaultAchievementAmounts[amountKey] ??
        0;
  }

  /// Returns the effective amount for a given achievement name.
  static int getAmountForAchievement(
    String achievementName, [
    Map<String, int>? remoteAmounts,
  ]) {
    final amountKey = amountKeyForAchievementName(achievementName);
    if (amountKey == null) return 0;
    return getAmountByKey(amountKey, remoteAmounts);
  }

  // Helper method to get amount for achievement
  // static int getAmountForAchievement(String achievementName) {
  //   switch (achievementName) {
  //     case taskStarter:
  //       return taskStarterAmount;
  //     case taskExpert:
  //       return taskExpertAmount;
  //     case profilePerfectionist:
  //       return profilePerfectionistAmount;
  //     case payoutConnector:
  //       return payoutConnectorAmount;
  //     case verifiedHuman:
  //       return verifiedHumanAmount;
  //     default:
  //       return 0;
  //   }
  // }

  // Helper method to get tasks needed for achievement
  // static int getTasksNeededForAchievement(String achievementName) {
  //   switch (achievementName) {
  //     case taskStarter:
  //       return taskStarterTasksNeeded;
  //     case taskExpert:
  //       return taskExpertTasksNeeded;
  //     case profilePerfectionist:
  //       return profilePerfectionistTasksNeeded;
  //     case payoutConnector:
  //       return payoutConnectorTasksNeeded;
  //     case verifiedHuman:
  //       return verifiedHumanTasksNeeded;
  //     default:
  //       return 1;
  //   }
  // }
}

/// Utility to get the string name of an AchievementStatus enum value
///
/// Example:
///   achievementStatusName(AchievementStatus.earned) // returns 'earned'
String achievementStatusName(AchievementStatus status) {
  return status.toString().split('.').last;
}

/// String constants for AchievementStatus values.
///
/// Use these to avoid typos when comparing or displaying status names.
/// Example:
///   if (achievementStatusName(a.status) == AchievementStatusNames.earned) { ... }
class AchievementStatusNames {
  /// Status for achievements that are in progress (not yet earned)
  static const inProgress = 'inProgress';

  /// Status for achievements that have been earned but not yet claimed
  static const earned = 'earned';

  /// Status for achievements that have been claimed
  static const claimed = 'claimed';
}
