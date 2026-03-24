import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:pax/models/firestore/achievement/achievement_model.dart';

class AchievementRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final String collectionName = 'achievements';

  String _stableAchievementId(String participantId, String name) {
    final normalizedName = name.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    return '${participantId}_$normalizedName';
  }

  // Create a new achievement
  Future<Achievement> createAchievement({
    required String participantId,
    required String name,
    required num tasksNeededForCompletion,
    required num tasksCompleted,
    Timestamp? timeCreated,
    Timestamp? timeCompleted,
    num? amountEarned,
  }) async {
    try {
      final stableId = _stableAchievementId(participantId, name);

      // Backward-compatible guard: if legacy docs already exist for this
      // participant+achievement, reuse one rather than creating another.
      final existingAchievements =
          await _firestore
              .collection(collectionName)
              .where('participantId', isEqualTo: participantId)
              .where('name', isEqualTo: name)
              .get();
      if (existingAchievements.docs.isNotEmpty) {
        existingAchievements.docs.sort((a, b) {
          final aIsStable = a.id == stableId ? 1 : 0;
          final bIsStable = b.id == stableId ? 1 : 0;
          if (aIsStable != bIsStable) return bIsStable.compareTo(aIsStable);
          final aCreated = a.data()['timeCreated'] as Timestamp?;
          final bCreated = b.data()['timeCreated'] as Timestamp?;
          final aMicros = aCreated?.microsecondsSinceEpoch ?? 0;
          final bMicros = bCreated?.microsecondsSinceEpoch ?? 0;
          return aMicros.compareTo(bMicros);
        });
        return Achievement.fromFirestore(existingAchievements.docs.first);
      }

      final achievement = Achievement(
        id: stableId,
        participantId: participantId,
        name: name,
        tasksNeededForCompletion: tasksNeededForCompletion,
        tasksCompleted: tasksCompleted,
        timeCreated: timeCreated,
        timeCompleted: timeCompleted,
        amountEarned: amountEarned,
      );

      await _firestore.runTransaction((transaction) async {
        final stableRef = _firestore.collection(collectionName).doc(stableId);
        final snapshot = await transaction.get(stableRef);
        if (!snapshot.exists) {
          transaction.set(stableRef, achievement.toMap());
        }
      });

      final savedDoc =
          await _firestore.collection(collectionName).doc(stableId).get();
      if (savedDoc.exists) {
        return Achievement.fromFirestore(savedDoc);
      }

      return achievement;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error creating achievement: $e');
      }
      rethrow;
    }
  }

  /// Returns duplicate achievement doc IDs keyed by achievement name.
  Future<Map<String, List<String>>> findDuplicateAchievementIdsForParticipant(
    String participantId,
  ) async {
    final querySnapshot =
        await _firestore
            .collection(collectionName)
            .where('participantId', isEqualTo: participantId)
            .get();

    final grouped = <String, List<String>>{};
    for (final doc in querySnapshot.docs) {
      final data = doc.data();
      final name = (data['name'] as String?) ?? '';
      if (name.isEmpty) continue;
      grouped.putIfAbsent(name, () => <String>[]).add(doc.id);
    }

    grouped.removeWhere((_, ids) => ids.length <= 1);
    return grouped;
  }

  // Get achievements for a participant
  Future<List<Achievement>> getAchievementsForParticipant(
    String participantId,
  ) async {
    try {
      final querySnapshot =
          await _firestore
              .collection(collectionName)
              .where('participantId', isEqualTo: participantId)
              .get();
      if (kDebugMode) {
        debugPrint(
          'Achievements fetched: ${querySnapshot.docs.length} for participant: $participantId',
        );
      }
      return querySnapshot.docs
          .map((doc) => Achievement.fromFirestore(doc))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting achievements: $e');
      }
      rethrow;
    }
  }

  // Update an achievement
  Future<Achievement> updateAchievement(
    String achievementId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _firestore
          .collection(collectionName)
          .doc(achievementId)
          .update(data);

      final doc =
          await _firestore.collection(collectionName).doc(achievementId).get();

      return Achievement.fromFirestore(doc);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error updating achievement: $e');
      }
      rethrow;
    }
  }

  /// Processes an achievement claim by calling the cloud function (CanvassingRewarder).
  ///
  /// For V2 users, pass [eoWalletAddress], [encryptedPrivateKey], and [sessionKey]
  /// so the claim is sent from the participant's EOA.
  Future<String> processAchievementClaim({
    required String achievementId,
    required String paxAccountContractAddress,
    required num amountEarned,
    required num tasksCompleted,
    String? recipientAddress,
    String? eoWalletAddress,
    String? encryptedPrivateKey,
    String? sessionKey,
    String? donationContractAddress,
    int? donationBasisPoints,
  }) async {
    try {
      final payload = <String, dynamic>{
        'achievementId': achievementId,
        'paxAccountContractAddress': paxAccountContractAddress,
        'amountEarned': amountEarned,
        'tasksCompleted': tasksCompleted,
        if (recipientAddress != null && recipientAddress.isNotEmpty)
          'recipientAddress': recipientAddress,
        if (donationContractAddress != null && donationContractAddress.isNotEmpty)
          'donationContractAddress': donationContractAddress,
        if (donationBasisPoints != null && donationBasisPoints > 0)
          'donationBasisPoints': donationBasisPoints,
      };
      if (eoWalletAddress != null && encryptedPrivateKey != null && sessionKey != null) {
        payload['eoWalletAddress'] = eoWalletAddress;
        payload['encryptedPrivateKey'] = encryptedPrivateKey;
        payload['sessionKey'] = sessionKey;
      }
      final result = await _functions
          .httpsCallable('processAchievementClaim')
          .call(payload);

      final txnHash = result.data['txnHash'] as String;

      return txnHash;
    } catch (e) {
      throw Exception('Failed to process achievement claim: $e');
    }
  }
}
