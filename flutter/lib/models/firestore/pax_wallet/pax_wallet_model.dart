import 'package:cloud_firestore/cloud_firestore.dart';

class PaxWallet {
  final String? id;
  final String? participantId;
  final String? eoAddress;
  final Timestamp? timeCreated;
  final Timestamp? timeUpdated;
  final String? smartAccountAddress;
  final String? logTxnHash;
  final Timestamp? logTimeCreated;

  PaxWallet({
    this.id,
    this.participantId,
    this.eoAddress,
    this.smartAccountAddress,
    this.timeCreated,
    this.timeUpdated,
    this.logTxnHash,
    this.logTimeCreated,
  });

  PaxWallet copyWith({
    String? id,
    String? participantId,
    String? eoAddress,
    String? smartAccountAddress,
    Timestamp? timeCreated,
    Timestamp? timeUpdated,
    String? logTxnHash,
    Timestamp? logTimeCreated,
  }) {
    return PaxWallet(
      id: id ?? this.id,
      participantId: participantId ?? this.participantId,
      eoAddress: eoAddress ?? this.eoAddress,
      smartAccountAddress: smartAccountAddress ?? this.smartAccountAddress,
      timeCreated: timeCreated ?? this.timeCreated,
      timeUpdated: timeUpdated ?? this.timeUpdated,
      logTxnHash: logTxnHash ?? this.logTxnHash,
      logTimeCreated: logTimeCreated ?? this.logTimeCreated,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'participantId': participantId,
      'eoAddress': eoAddress,
      'smartAccountAddress': smartAccountAddress,
      'timeCreated': timeCreated,
      'timeUpdated': timeUpdated,
      'logTxnHash': logTxnHash,
      'logTimeCreated': logTimeCreated,
    };
  }

  factory PaxWallet.fromMap(Map<String, dynamic> map, {required String id}) {
    return PaxWallet(
      id: id,
      participantId: map['participantId'],
      eoAddress: map['eoAddress'],
      smartAccountAddress: map['smartAccountAddress'],
      timeCreated: map['timeCreated'],
      timeUpdated: map['timeUpdated'],
      logTxnHash: map['logTxnHash'],
      logTimeCreated: map['logTimeCreated'],
    );
  }

  factory PaxWallet.empty() {
    return PaxWallet();
  }

  bool get isEmpty => id == null || id!.isEmpty;
  bool get isNotEmpty => !isEmpty;
}
