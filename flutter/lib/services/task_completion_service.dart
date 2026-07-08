// This service manages the task completion workflow:
// - Handles marking tasks as complete through Firebase Functions
// - Manages task completion state through Riverpod providers
// - Updates activity feed after task completion
// - Provides error handling and state management for the completion process

// lib/services/task_completion_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/db/achievement/achievement_provider.dart';
import 'package:pax/providers/fcm/fcm_provider.dart';
import 'package:pax/providers/local/activity_providers.dart';
import 'package:pax/providers/local/task_completion_state_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/services/notifications/notification_service.dart';
import 'package:pax/utils/achievement_constants.dart';

class TaskCompletionService {
  final Ref ref;

  TaskCompletionService(this.ref);

  Future<void> markTaskAsComplete({
    required String? screeningId,
    required String taskId,
  }) async {
    try {
      ref.read(taskCompletionProvider.notifier).startCompletion();

      if (screeningId == null) {
        throw Exception('Screening ID is required');
      }

      final httpsCallable = FirebaseFunctions.instance.httpsCallable(
        'markTaskCompletionAsComplete',
      );
      final result = await httpsCallable.call({
        'screeningId': screeningId,
        'taskId': taskId,
      });

      final data = result.data as Map<String, dynamic>;

      await onTaskRecordedComplete(
        screeningId: screeningId,
        taskId: taskId,
        taskCompletionId: data['taskCompletionId'] as String,
      );
    } catch (e) {
      ref.read(taskCompletionProvider.notifier).setError(e.toString());

      if (kDebugMode) {
        debugPrint('[Task] Task completion error: $e');
      }

      rethrow;
    }
  }

  /// Runs post-completion side effects after a task is already marked complete
  /// in Firestore (e.g. via [markTaskCompletionAsComplete] or [submitPollResponse]).
  Future<void> onTaskRecordedComplete({
    required String screeningId,
    required String taskId,
    required String taskCompletionId,
  }) async {
    final taskCompletionResult = TaskCompletionResult(
      taskCompletionId: taskCompletionId,
      taskId: taskId,
      screeningId: screeningId,
      completedAt: DateTime.now(),
    );

    await NotificationService().onTaskCompleted();

    final authState = ref.read(authProvider);

    final achievements = ref.read(achievementsProvider).achievements;
    final achievementAmounts = ref
        .read(achievementAmountsProvider)
        .maybeWhen(
          data: (data) => data,
          orElse: () => AchievementConstants.defaultAchievementAmounts,
        );
    final taskStarterAmount = AchievementConstants.getAmountForAchievement(
      AchievementConstants.taskStarter,
      achievementAmounts,
    );
    final taskExpertAmount = AchievementConstants.getAmountForAchievement(
      AchievementConstants.taskExpert,
      achievementAmounts,
    );
    final hasTaskStarter = achievements.any(
      (a) =>
          a.name == AchievementConstants.taskStarter &&
          a.timeCompleted != null,
    );
    final taskExpert =
        achievements
            .where((a) => a.name == AchievementConstants.taskExpert)
            .firstOrNull;

    if (!hasTaskStarter) {
      await ref
          .read(achievementsProvider.notifier)
          .createAchievement(
            timeCreated: Timestamp.now(),
            participantId: authState.user.uid,
            name: AchievementConstants.taskStarter,
            tasksNeededForCompletion:
                AchievementConstants.taskStarterTasksNeeded,
            tasksCompleted: 1,
            timeCompleted: Timestamp.now(),
            amountEarned: taskStarterAmount,
          );
      ref.read(analyticsProvider).achievementCreated({
        'achievementName': AchievementConstants.taskStarter,
        'amountEarned': taskStarterAmount,
      });
      final fcmToken = await ref.read(fcmTokenProvider.future);

      if (fcmToken != null) {
        ref
            .read(notificationServiceProvider)
            .sendAchievementEarnedNotification(
              token: fcmToken,
              achievementData: {
                'achievementName': AchievementConstants.taskStarter,
                'amountEarned': taskStarterAmount,
              },
            );
      }
    }

    if (taskExpert == null) {
      await ref
          .read(achievementsProvider.notifier)
          .createAchievement(
            timeCreated: Timestamp.now(),
            participantId: authState.user.uid,
            name: AchievementConstants.taskExpert,
            tasksNeededForCompletion:
                AchievementConstants.taskExpertTasksNeeded,
            tasksCompleted: 1,
            amountEarned: taskExpertAmount,
          );
      ref.read(analyticsProvider).achievementCreated({
        'achievementName': AchievementConstants.taskExpert,
        'amountEarned': taskExpertAmount,
      });
    } else if (taskExpert.tasksCompleted <
        taskExpert.tasksNeededForCompletion) {
      final newTasksCompleted = taskExpert.tasksCompleted + 1;
      final Map<String, dynamic> updateData = {
        'tasksCompleted': newTasksCompleted,
      };

      if (newTasksCompleted >= taskExpert.tasksNeededForCompletion) {
        updateData['timeCompleted'] = Timestamp.now();
        updateData['timeUpdated'] = Timestamp.now();

        ref.read(analyticsProvider).achievementComplete({
          'achievementName': AchievementConstants.taskExpert,
          'tasksCompleted': newTasksCompleted,
          'tasksNeededForCompletion': taskExpert.tasksNeededForCompletion,
        });

        final fcmToken = await ref.read(fcmTokenProvider.future);

        if (fcmToken != null) {
          ref
              .read(notificationServiceProvider)
              .sendAchievementEarnedNotification(
                token: fcmToken,
                achievementData: {
                  'achievementName': AchievementConstants.taskExpert,
                  'amountEarned': taskExpertAmount,
                },
              );
        }
      }

      await ref
          .read(achievementsProvider.notifier)
          .updateAchievement(taskExpert.id, updateData);
      ref.read(analyticsProvider).achievementUpdated({
        'achievementName': AchievementConstants.taskExpert,
        'tasksCompleted': newTasksCompleted,
        'tasksNeededForCompletion': taskExpert.tasksNeededForCompletion,
      });
    }

    await ref
        .read(achievementsProvider.notifier)
        .fetchAchievements(authState.user.uid);

    ref.invalidate(activityRepositoryProvider);

    ref
        .read(taskCompletionProvider.notifier)
        .completeTask(taskCompletionResult);
  }
}

final taskCompletionServiceProvider = Provider<TaskCompletionService>((ref) {
  return TaskCompletionService(ref);
});
