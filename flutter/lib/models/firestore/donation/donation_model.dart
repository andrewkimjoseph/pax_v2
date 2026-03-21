import 'package:cloud_firestore/cloud_firestore.dart';

class Donation {
  final String id;
  final num? amountDonated;
  final String? collectiveDonatedTo;
  final String? participantId;
  final Timestamp? timeDonated;
  final String? txnHash;
  final Timestamp? timeCreated;
  final Timestamp? timeUpdated;

  Donation({
    required this.id,
    this.amountDonated,
    this.collectiveDonatedTo,
    this.participantId,
    this.timeDonated,
    this.txnHash,
    this.timeCreated,
    this.timeUpdated,
  });

  factory Donation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Donation data is null');
    }
    return Donation(
      id: doc.id,
      amountDonated: data['amountDonated'],
      collectiveDonatedTo: data['collectiveDonatedTo'],
      participantId: data['participantId'],
      timeDonated: data['timeDonated'],
      txnHash: data['txnHash'],
      timeCreated: data['timeCreated'],
      timeUpdated: data['timeUpdated'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'amountDonated': amountDonated,
      'collectiveDonatedTo': collectiveDonatedTo,
      'participantId': participantId,
      'timeDonated': timeDonated,
      'txnHash': txnHash,
      'timeCreated': timeCreated,
      'timeUpdated': timeUpdated,
    };
  }
}
