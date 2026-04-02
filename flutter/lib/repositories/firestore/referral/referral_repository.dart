import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:pax/models/firestore/referral/referral.dart';

class ReferralRepository {
  final FirebaseFirestore _firestore;
  final String collectionName = 'referrals';

  ReferralRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<List<Referral>> getReferralsForReferredParticipant(
    String participantId,
  ) async {
    try {
      final snapshot =
          await _firestore
              .collection(collectionName)
              .where('referringParticipantId', isEqualTo: participantId)
              .orderBy('timeCreated', descending: true)
              .get();

      return snapshot.docs.map(Referral.fromFirestore).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Error] Error getting referrals: $e');
      }
      return [];
    }
  }

  /// True if this participant is the referred party on at least one referral doc.
  Future<bool> referralExistsForReferredParticipant(String participantId) async {
    try {
      final snapshot =
          await _firestore
              .collection(collectionName)
              .where('referredParticipantId', isEqualTo: participantId)
              .limit(1)
              .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Error] Error checking referral existence for referred: $e');
      }
      return false;
    }
  }
}
