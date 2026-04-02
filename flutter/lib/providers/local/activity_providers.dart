// lib/providers/activity/activity_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/models/local/activity_model.dart';
import 'package:pax/repositories/firestore/reward/reward_repository.dart';
import 'package:pax/repositories/firestore/task_completion/task_completion_repository.dart';
import 'package:pax/repositories/firestore/withdrawal/withdrawal_repository.dart';
import 'package:pax/repositories/firestore/donation/donation_repository.dart';
import 'package:pax/repositories/firestore/referral/referral_repository.dart';
import 'package:pax/repositories/local/activity_repository.dart';
import 'package:pax/providers/db/achievement/achievement_provider.dart';
import 'package:pax/models/firestore/achievement/achievement_model.dart';

import '../auth/auth_provider.dart';

/// Filter for task completion activities, modeled like Achievement filters.
enum CompletionFilter { all, claimed, unclaimed, incomplete, expired }

/// Filter for referral activities.
enum ReferralFilter { all, unclaimed, claimed }

// Provider for repositories
final taskCompletionRepositoryProvider = Provider<TaskCompletionRepository>((
  ref,
) {
  return TaskCompletionRepository();
});

final rewardRepositoryProvider = Provider<RewardRepository>((ref) {
  return RewardRepository();
});

final withdrawalRepositoryProvider = Provider<WithdrawalRepository>((ref) {
  return WithdrawalRepository();
});

final donationRepositoryProvider = Provider<DonationRepository>((ref) {
  return DonationRepository();
});

final referralRepositoryProvider = Provider<ReferralRepository>((ref) {
  return ReferralRepository();
});

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  final taskCompletionRepo = ref.watch(taskCompletionRepositoryProvider);
  final rewardRepo = ref.watch(rewardRepositoryProvider);
  final withdrawalRepo = ref.watch(withdrawalRepositoryProvider);
  final donationRepo = ref.watch(donationRepositoryProvider);

  return ActivityRepository(
    taskCompletionRepository: taskCompletionRepo,
    rewardRepository: rewardRepo,
    withdrawalRepository: withdrawalRepo,
    donationRepository: donationRepo,
  );
});

// Future providers for activities
final allActivitiesProvider = FutureProvider.family<List<Activity>, String>((
  ref,
  userId,
) async {
  final repository = ref.watch(activityRepositoryProvider);
  return repository.getAllActivitiesForParticipant(userId);
});

final taskCompletionActivitiesProvider =
    FutureProvider.family<List<Activity>, String>((ref, userId) async {
      final repository = ref.watch(activityRepositoryProvider);
      return repository.getTaskCompletionActivitiesForParticipant(userId);
    });

final rewardActivitiesProvider = FutureProvider.family<List<Activity>, String>((
  ref,
  userId,
) async {
  final repository = ref.watch(activityRepositoryProvider);
  return repository.getRewardActivitiesForParticipant(userId);
});

// Define a rewards provider that will expose the stream of rewards

final withdrawalActivitiesProvider =
    FutureProvider.family<List<Activity>, String>((ref, userId) async {
      final repository = ref.watch(activityRepositoryProvider);
      return repository.getWithdrawalActivitiesForParticipant(userId);
    });

final donationActivitiesProvider =
    FutureProvider.family<List<Activity>, String>((ref, userId) async {
      final repository = ref.watch(activityRepositoryProvider);
      return repository.getDonationActivitiesForParticipant(userId);
    });

// Activity state class
class ActivityState {
  final List<Activity> activities;
  final bool isLoading;
  final String? errorMessage;
  final ActivityType? filterType;
  final CompletionFilter completionFilter;
  final ReferralFilter referralFilter;

  ActivityState({
    this.activities = const [],
    this.isLoading = false,
    this.errorMessage,
    this.filterType,
    this.completionFilter = CompletionFilter.all,
    this.referralFilter = ReferralFilter.all,
  });

  ActivityState copyWith({
    List<Activity>? activities,
    bool? isLoading,
    String? errorMessage,
    ActivityType? filterType,
    CompletionFilter? completionFilter,
    ReferralFilter? referralFilter,
  }) {
    return ActivityState(
      activities: activities ?? this.activities,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      filterType: filterType ?? this.filterType,
      completionFilter: completionFilter ?? this.completionFilter,
      referralFilter: referralFilter ?? this.referralFilter,
    );
  }
}

// Activity notifier using Riverpod's Notifier
class ActivityNotifier extends Notifier<ActivityState> {
  @override
  ActivityState build() {
    // Initialize with TaskCompletion as the default filter type
    return ActivityState(
      isLoading: false,
      // Set default filter here
      filterType: ActivityType.taskCompletion,
    );
  }

  // Set filter type
  void setFilterType(ActivityType? filterType) {
    state = state.copyWith(filterType: filterType);
  }

  // Set completion filter (used when filterType is taskCompletion)
  void setCompletionFilter(CompletionFilter completionFilter) {
    state = state.copyWith(completionFilter: completionFilter);
  }

  // Set referral filter (used when filterType is referral)
  void setReferralFilter(ReferralFilter referralFilter) {
    state = state.copyWith(referralFilter: referralFilter);
  }

  // Load activities
  Future<void> loadActivities(String userId) async {
    state = state.copyWith(isLoading: true);

    try {
      final repository = ref.read(activityRepositoryProvider);
      final activities = await repository.getAllActivitiesForParticipant(
        userId,
      );

      state = state.copyWith(
        activities: activities,
        isLoading: false,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load activities: $e',
      );
    }
  }

  // Clear activities
  void clearActivities() {
    state = state.copyWith(activities: []);
  }
}

// Provider for ActivityNotifier
final activityNotifierProvider =
    NotifierProvider<ActivityNotifier, ActivityState>(() {
      return ActivityNotifier();
    });

// Provider for total number of Task Completions
final totalTaskCompletionsProvider = Provider<AsyncValue<int>>((ref) {
  final userId = ref.watch(authProvider).user.uid;
  final tasksAsync = ref.watch(taskCompletionActivitiesProvider(userId));

  return tasksAsync.when(
    data: (tasks) => AsyncValue.data(tasks.length),
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});

// Provider for count of unclaimed task completions (complete, valid, no reward yet)
final unclaimedTaskCompletionsCountProvider = Provider<AsyncValue<int>>((ref) {
  final userId = ref.watch(authProvider).user.uid;
  final allActivitiesAsync = ref.watch(allActivitiesProvider(userId));

  return allActivitiesAsync.when(
    data: (allActivities) {
      int count = 0;
      for (final activity in allActivities) {
        if (activity.type != ActivityType.taskCompletion) continue;
        if (!activity.isComplete) continue;
        if (activity.taskCompletion?.isValid == false) continue;
        final isClaimed = allActivities.any(
          (a) =>
              a.reward != null &&
              a.reward?.txnHash != null &&
              a.reward?.taskCompletionId == activity.taskCompletion?.id,
        );
        if (!isClaimed) count++;
      }
      return AsyncValue.data(count);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});

// Provider for count of expired task completions (incomplete and past deadline)
final expiredTaskCompletionsCountProvider = Provider<AsyncValue<int>>((ref) {
  final userId = ref.watch(authProvider).user.uid;
  final allActivitiesAsync = ref.watch(allActivitiesProvider(userId));

  return allActivitiesAsync.when(
    data: (allActivities) {
      final taskCompletions = allActivities
          .where((a) => a.type == ActivityType.taskCompletion)
          .toList();
      final expired =
          filterTaskCompletionActivities(
            taskCompletions,
            allActivities,
            CompletionFilter.expired,
          );
      return AsyncValue.data(expired.length);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});

// Provider for total number of referrals made
final totalReferralsCountProvider = Provider<AsyncValue<int>>((ref) {
  final userId = ref.watch(authProvider).user.uid;
  final allActivitiesAsync = ref.watch(allActivitiesProvider(userId));

  return allActivitiesAsync.when(
    data: (allActivities) {
      final count = allActivities
          .where((activity) => activity.type == ActivityType.referral)
          .length;
      return AsyncValue.data(count);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});

// Provider for count of unclaimed referrals
final unclaimedReferralsCountProvider = Provider<AsyncValue<int>>((ref) {
  final userId = ref.watch(authProvider).user.uid;
  final allActivitiesAsync = ref.watch(allActivitiesProvider(userId));

  return allActivitiesAsync.when(
    data: (allActivities) {
      int count = 0;
      for (final activity in allActivities) {
        if (activity.type != ActivityType.referral) continue;
        final referral = activity.referral;
        if (referral == null) continue;
        final isClaimed = referral.timeRewarded != null ||
            (referral.txnHash != null && referral.txnHash!.isNotEmpty);
        if (!isClaimed) count++;
      }
      return AsyncValue.data(count);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});

/// Sum of G$ from claimed referral rewards (`amountReceived`).
final totalReferralAmountGdProvider = Provider<AsyncValue<double>>((ref) {
  final userId = ref.watch(authProvider).user.uid;
  final allActivitiesAsync = ref.watch(allActivitiesProvider(userId));

  return allActivitiesAsync.when(
    data: (allActivities) {
      double total = 0.0;
      for (final activity in allActivities) {
        if (activity.type != ActivityType.referral) continue;
        final referral = activity.referral;
        if (referral == null || referral.amountReceived == null) continue;
        final isClaimed = referral.timeRewarded != null ||
            (referral.txnHash != null && referral.txnHash!.isNotEmpty);
        if (isClaimed) {
          total += referral.amountReceived!.toDouble();
        }
      }
      return AsyncValue.data(total);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});

// Provider for total G$ tokens earned
final totalGoodDollarTokensEarnedProvider = Provider<AsyncValue<double>>((ref) {
  final userId = ref.watch(authProvider).user.uid;
  final rewardsAsync = ref.watch(rewardActivitiesProvider(userId));
  final allActivitiesAsync = ref.watch(allActivitiesProvider(userId));
  final achievementsAsync = ref.watch(achievementsProvider);

  return rewardsAsync.when(
    data: (rewards) {
      double total = 0.0;
      // Add rewards from reward activities
      for (final activity in rewards) {
        if (activity.type == ActivityType.reward &&
            activity.reward?.rewardCurrencyId == 1 &&
            activity.reward?.amountReceived != null) {
          total += activity.reward!.amountReceived!.toDouble();
        }
      }

      // Add amounts from claimed achievements
      if (achievementsAsync.state == AchievementState.loaded) {
        for (final achievement in achievementsAsync.achievements) {
          if (achievement.status == AchievementStatus.claimed &&
              achievement.amountEarned != null) {
            total += achievement.amountEarned!.toDouble();
          }
        }
      }

      return allActivitiesAsync.when(
        data: (allActivities) {
          // Add amounts from claimed referral rewards
          for (final activity in allActivities) {
            if (activity.type != ActivityType.referral) continue;
            final referral = activity.referral;
            if (referral == null || referral.amountReceived == null) continue;
            final isClaimed = referral.timeRewarded != null ||
                (referral.txnHash != null && referral.txnHash!.isNotEmpty);
            if (isClaimed) {
              total += referral.amountReceived!.toDouble();
            }
          }
          return AsyncValue.data(total);
        },
        loading: () => const AsyncValue.loading(),
        error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
      );
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});

final donationsMadeCountProvider = Provider<AsyncValue<int>>((ref) {
  final userId = ref.watch(authProvider).user.uid;
  final donationsAsync = ref.watch(donationActivitiesProvider(userId));

  return donationsAsync.when(
    data: (donations) => AsyncValue.data(donations.length),
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});

final totalGoodDollarDonatedProvider = Provider<AsyncValue<double>>((ref) {
  final userId = ref.watch(authProvider).user.uid;
  final donationsAsync = ref.watch(donationActivitiesProvider(userId));

  return donationsAsync.when(
    data: (donations) {
      double total = 0;
      for (final donationActivity in donations) {
        if (donationActivity.donation?.amountDonated != null) {
          total += donationActivity.donation!.amountDonated!.toDouble();
        }
      }
      return AsyncValue.data(total);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});

// --- Helper function for filtering activities by type ---
List<Activity> filterActivities(
  List<Activity> activities,
  ActivityType? filterType,
) {
  if (filterType == null) return activities;
  return activities.where((activity) => activity.type == filterType).toList();
}

/// Filters task completion activities by CompletionFilter.
/// Requires allActivities to determine claimed vs unclaimed.
List<Activity> filterTaskCompletionActivities(
  List<Activity> taskCompletionActivities,
  List<Activity> allActivities,
  CompletionFilter filter,
) {
  bool isClaimed(Activity a) =>
      a.taskCompletion != null &&
      allActivities.any(
        (x) =>
            x.reward != null &&
            x.reward?.txnHash != null &&
            x.reward?.taskCompletionId == a.taskCompletion?.id,
      );

  switch (filter) {
    case CompletionFilter.all:
      return taskCompletionActivities;
    case CompletionFilter.claimed:
      return taskCompletionActivities.where(isClaimed).toList();
    case CompletionFilter.unclaimed:
      return taskCompletionActivities
          .where((a) =>
              a.isComplete &&
              a.taskCompletion?.isValid != false &&
              !isClaimed(a))
          .toList();
    case CompletionFilter.incomplete:
      return taskCompletionActivities
          .where((a) => !a.isComplete && !a.isExpired)
          .toList();
    case CompletionFilter.expired:
      return taskCompletionActivities.where((a) => !a.isComplete && a.isExpired).toList();
  }
}

/// Filters referral activities by ReferralFilter.
List<Activity> filterReferralActivities(
  List<Activity> referralActivities,
  ReferralFilter filter,
) {
  switch (filter) {
    case ReferralFilter.all:
      return referralActivities;
    case ReferralFilter.unclaimed:
      return referralActivities
          .where(
            (a) =>
                a.type == ActivityType.referral &&
                a.referral?.timeRewarded == null &&
                (a.referral?.txnHash == null ||
                    a.referral!.txnHash!.isEmpty),
          )
          .toList();
    case ReferralFilter.claimed:
      return referralActivities
          .where(
            (a) =>
                a.type == ActivityType.referral &&
                (a.referral?.timeRewarded != null ||
                    (a.referral?.txnHash != null &&
                        a.referral!.txnHash!.isNotEmpty)),
          )
          .toList();
  }
}

//
// Usage: In your UI, get all activities (e.g., from allActivitiesProvider or ActivityNotifier),
// then call filterActivities(activities, filterType) to get the filtered list.
