import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/models/firestore/achievement/achievement_model.dart';
import 'package:pax/repositories/firestore/achievement/achievement_repository.dart';

// Provider for the achievement repository
final achievementsRepositoryProvider = Provider<AchievementRepository>((ref) {
  return AchievementRepository();
});

// State enum for achievements
enum AchievementState { initial, loading, loaded, error }

// State model for achievements
class AchievementStateModel {
  final List<Achievement> achievements;
  final AchievementState state;
  final String? errorMessage;

  AchievementStateModel({
    this.achievements = const [],
    this.state = AchievementState.initial,
    this.errorMessage,
  });

  // Copy with method
  AchievementStateModel copyWith({
    List<Achievement>? achievements,
    AchievementState? state,
    String? errorMessage,
  }) {
    return AchievementStateModel(
      achievements: achievements ?? this.achievements,
      state: state ?? this.state,
      errorMessage: errorMessage,
    );
  }
}

// Notifier for achievement state
class AchievementNotifier extends Notifier<AchievementStateModel> {
  AchievementRepository get _repository => ref.read(achievementsRepositoryProvider);

  @override
  AchievementStateModel build() {
    return AchievementStateModel();
  }

  // Create a new achievement
  Future<void> createAchievement({
    required String participantId,
    required String name,
    required num tasksNeededForCompletion,
    required num tasksCompleted,
    Timestamp? timeCreated,
    Timestamp? timeCompleted,
    num? amountEarned,
  }) async {
    try {
      // Set loading state
      state = state.copyWith(state: AchievementState.loading);

      // Create achievement in repository
      final createdAchievement = await _repository.createAchievement(
        participantId: participantId,
        name: name,
        tasksNeededForCompletion: tasksNeededForCompletion,
        tasksCompleted: tasksCompleted,
        timeCreated: timeCreated,
        timeCompleted: timeCompleted,
        amountEarned: amountEarned,
      );

      final existingIndex = state.achievements.indexWhere(
        (a) => a.id == createdAchievement.id,
      );
      final updatedAchievements = [...state.achievements];
      if (existingIndex >= 0) {
        updatedAchievements[existingIndex] = createdAchievement;
      } else {
        updatedAchievements.add(createdAchievement);
      }

      state = state.copyWith(
        achievements: updatedAchievements,
        state: AchievementState.loaded,
      );
    } catch (e) {
      state = state.copyWith(
        state: AchievementState.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Fetch achievements for a participant
  Future<void> fetchAchievements(String participantId) async {
    try {
      // Set loading state
      state = state.copyWith(state: AchievementState.loading);

      // Get achievements from repository
      final achievements = await _repository.getAchievementsForParticipant(
        participantId,
      );

      // Update state with fetched achievements
      state = state.copyWith(
        achievements: achievements,
        state: AchievementState.loaded,
      );
    } catch (e) {
      state = state.copyWith(
        state: AchievementState.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Update an achievement
  Future<void> updateAchievement(
    String achievementId,
    Map<String, dynamic> data,
  ) async {
    try {
      // Set loading state
      state = state.copyWith(state: AchievementState.loading);

      // Update achievement in repository
      await _repository.updateAchievement(achievementId, data);

      // Refresh achievements
      if (state.achievements.isNotEmpty) {
        await fetchAchievements(state.achievements.first.participantId!);
      }
    } catch (e) {
      state = state.copyWith(
        state: AchievementState.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<Map<String, List<String>>> findDuplicateAchievementsForParticipant(
    String participantId,
  ) async {
    try {
      final duplicates = await _repository
          .findDuplicateAchievementIdsForParticipant(participantId);
      if (kDebugMode && duplicates.isNotEmpty) {
        debugPrint(
          'Duplicate achievements detected for participant $participantId: $duplicates',
        );
      }
      return duplicates;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking duplicate achievements: $e');
      }
      return {};
    }
  }
}

// Provider for achievement state
final achievementsProvider =
    NotifierProvider<AchievementNotifier, AchievementStateModel>(
      () => AchievementNotifier(),
    );
