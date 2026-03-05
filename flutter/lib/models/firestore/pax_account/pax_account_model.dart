import 'package:cloud_firestore/cloud_firestore.dart';

class PaxAccount {
  final String id; // Same as participant ID
  final String? contractAddress;
  final String? contractCreationTxnHash;
  final Timestamp? timeCreated;
  final Timestamp? timeUpdated;
  final String? serverWalletId;
  final String? serverWalletAddress;
  final String? smartAccountWalletAddress;
  final String? eoWalletAddress;

  PaxAccount({
    required this.id,
    this.contractAddress,
    this.contractCreationTxnHash,
    this.timeCreated,
    this.timeUpdated,
    this.serverWalletId,
    this.serverWalletAddress,
    this.smartAccountWalletAddress,
    this.eoWalletAddress,
  });

  bool get isV1 => contractAddress != null;
  bool get isV2 => contractAddress == null && eoWalletAddress != null;

  /// Payout address: V1 = proxy contract; V2 = smart account contract. Both are contracts.
  String? get payoutWalletAddress =>
      isV1 ? contractAddress : smartAccountWalletAddress;

  PaxAccount copyWith({
    String? contractAddress,
    String? contractCreationTxnHash,
    Timestamp? timeUpdated,
    String? serverWalletId,
    String? serverWalletAddress,
    String? smartAccountWalletAddress,
    String? eoWalletAddress,
  }) {
    return PaxAccount(
      id: id,
      contractAddress: contractAddress ?? this.contractAddress,
      contractCreationTxnHash:
          contractCreationTxnHash ?? this.contractCreationTxnHash,
      timeCreated: timeCreated,
      timeUpdated: timeUpdated ?? this.timeUpdated,
      serverWalletId: serverWalletId ?? this.serverWalletId,
      serverWalletAddress: serverWalletAddress ?? this.serverWalletAddress,
      smartAccountWalletAddress:
          smartAccountWalletAddress ?? this.smartAccountWalletAddress,
      eoWalletAddress: eoWalletAddress ?? this.eoWalletAddress,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contractAddress': contractAddress,
      'contractCreationTxnHash': contractCreationTxnHash,
      'timeCreated': timeCreated,
      'timeUpdated': timeUpdated,
      'serverWalletId': serverWalletId,
      'serverWalletAddress': serverWalletAddress,
      'smartAccountWalletAddress': smartAccountWalletAddress,
      'eoWalletAddress': eoWalletAddress,
    };
  }

  factory PaxAccount.fromMap(Map<String, dynamic> map, {required String id}) {
    return PaxAccount(
      id: id,
      contractAddress: map['contractAddress'],
      contractCreationTxnHash: map['contractCreationTxnHash'],
      timeCreated: map['timeCreated'],
      timeUpdated: map['timeUpdated'],
      serverWalletId: map['serverWalletId'],
      serverWalletAddress: map['serverWalletAddress'],
      smartAccountWalletAddress: map['smartAccountWalletAddress'],
      eoWalletAddress: map['eoWalletAddress'],
    );
  }

  factory PaxAccount.empty() {
    return PaxAccount(id: '');
  }

  bool get isEmpty => id.isEmpty;
  bool get isNotEmpty => !isEmpty;
}
