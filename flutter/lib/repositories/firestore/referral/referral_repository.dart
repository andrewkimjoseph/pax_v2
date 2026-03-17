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
      final snapshot = await _firestore
          .collection(collectionName)
          .where('referredParticipantId', isEqualTo: participantId)
          .orderBy('timeCreated', descending: true)
          .get();

      return snapshot.docs.map(Referral.fromFirestore).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting referrals: $e');
      }
      return [];
    }
  }
}

