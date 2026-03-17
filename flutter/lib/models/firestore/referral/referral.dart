import 'package:cloud_firestore/cloud_firestore.dart';

class Referral {
  final String id;
  final String referringParticipantId;
  final String referredParticipantId;
  final String? txnHash;
  final num? amountReceived;
  final Timestamp? timeCreated;
  final Timestamp? timeUpdated;
  final Timestamp? timeRewarded;

  Referral({
    required this.id,
    required this.referringParticipantId,
    required this.referredParticipantId,
    this.txnHash,
    this.amountReceived,
    this.timeCreated,
    this.timeUpdated,
    this.timeRewarded,
  });

  factory Referral.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw Exception('ReferralRecord data is null');
    }

    return Referral(
      id: doc.id,
      referringParticipantId: data['referringParticipantId'] as String,
      referredParticipantId: data['referredParticipantId'] as String,
      txnHash: data['txnHash'] as String?,
      amountReceived: data['amountReceived'] as num?,
      timeCreated: data['timeCreated'] as Timestamp?,
      timeUpdated: data['timeUpdated'] as Timestamp?,
      timeRewarded: data['timeRewarded'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'referringParticipantId': referringParticipantId,
      'referredParticipantId': referredParticipantId,
      'txnHash': txnHash,
      'amountReceived': amountReceived,
      'timeCreated': timeCreated,
      'timeUpdated': timeUpdated,
      'timeRewarded': timeRewarded,
    };
  }
}
