import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:pax/models/firestore/donation/donation_model.dart';

class DonationRepository {
  final FirebaseFirestore _firestore;
  final String collectionName = 'donations';

  DonationRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<Donation> createDonation({
    required String participantId,
    required double amountDonated,
    required String collectiveDonatedTo,
    required String txnHash,
  }) async {
    try {
      final existing =
          await _firestore
              .collection(collectionName)
              .where('participantId', isEqualTo: participantId)
              .where('txnHash', isEqualTo: txnHash)
              .limit(1)
              .get();
      if (existing.docs.isNotEmpty) {
        return Donation.fromFirestore(existing.docs.first);
      }

      final now = FieldValue.serverTimestamp();
      final docRef = _firestore.collection(collectionName).doc();
      await docRef.set({
        'id': docRef.id,
        'participantId': participantId,
        'amountDonated': amountDonated,
        'collectiveDonatedTo': collectiveDonatedTo,
        'txnHash': txnHash,
        'timeDonated': now,
        'timeCreated': now,
        'timeUpdated': now,
      });

      final created = await docRef.get();
      return Donation.fromFirestore(created);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error creating donation: $e');
      }
      rethrow;
    }
  }

  Future<List<Donation>> getDonationsForParticipant(String participantId) async {
    try {
      final snapshot = await _firestore
          .collection(collectionName)
          .where('participantId', isEqualTo: participantId)
          .orderBy('timeCreated', descending: true)
          .get();

      return snapshot.docs.map((doc) => Donation.fromFirestore(doc)).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting donations: $e');
      }
      return [];
    }
  }

  Stream<List<Donation>> streamDonationsForParticipant(String? participantId) {
    if (participantId == null) {
      return Stream.value([]);
    }

    try {
      return _firestore
          .collection(collectionName)
          .where('participantId', isEqualTo: participantId)
          .orderBy('timeCreated', descending: true)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map((doc) => Donation.fromFirestore(doc)).toList(),
          );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error streaming donations: $e');
      }
      return Stream.value([]);
    }
  }
}
