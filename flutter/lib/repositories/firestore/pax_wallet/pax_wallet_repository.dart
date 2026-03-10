import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:pax/models/firestore/pax_wallet/pax_wallet_model.dart';

class PaxWalletRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String collectionName = 'pax_wallets';

  Future<bool> walletExistsForParticipant(String participantId) async {
    try {
      final querySnapshot = await _firestore
          .collection(collectionName)
          .where('participantId', isEqualTo: participantId)
          .limit(1)
          .get();
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking if wallet exists: $e');
      }
      rethrow;
    }
  }

  Future<PaxWallet?> getWalletByParticipantId(String participantId) async {
    try {
      final querySnapshot = await _firestore
          .collection(collectionName)
          .where('participantId', isEqualTo: participantId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return PaxWallet.fromMap(doc.data(), id: doc.id);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting wallet: $e');
      }
      rethrow;
    }
  }

  Future<PaxWallet?> getWallet(String walletId) async {
    try {
      final docSnapshot =
          await _firestore.collection(collectionName).doc(walletId).get();
      if (docSnapshot.exists) {
        return PaxWallet.fromMap(docSnapshot.data()!, id: docSnapshot.id);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting wallet by id: $e');
      }
      rethrow;
    }
  }

  /// Creates a new wallet document. Returns null if one already exists for this participant.
  Future<PaxWallet?> createWallet({
    required String participantId,
    required String eoAddress,
  }) async {
    try {
      final exists = await walletExistsForParticipant(participantId);
      if (exists) {
        if (kDebugMode) {
          debugPrint('Wallet already exists for participant $participantId');
        }
        return await getWalletByParticipantId(participantId);
      }

      final now = Timestamp.now();
      final docRef = _firestore.collection(collectionName).doc();

      final wallet = PaxWallet(
        id: docRef.id,
        participantId: participantId,
        eoAddress: eoAddress,
        timeCreated: now,
        timeUpdated: now,
      );

      await docRef.set(wallet.toMap());
      return wallet;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error creating wallet: $e');
      }
      rethrow;
    }
  }

  Future<PaxWallet> updateSmartAccountAddress({
    required String walletId,
    required String smartAccountAddress,
  }) async {
    try {
      await _firestore.collection(collectionName).doc(walletId).update({
        'smartAccountAddress': smartAccountAddress,
        'timeUpdated': Timestamp.now(),
      });

      final updatedDoc =
          await _firestore.collection(collectionName).doc(walletId).get();
      return PaxWallet.fromMap(updatedDoc.data()!, id: updatedDoc.id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error updating smart account address: $e');
      }
      rethrow;
    }
  }

  Future<PaxWallet> updateWalletWithLogData({
    required String walletId,
    required String logTxnHash,
    required Timestamp logTimeCreated,
  }) async {
    try {
      await _firestore.collection(collectionName).doc(walletId).update({
        'logTxnHash': logTxnHash,
        'logTimeCreated': logTimeCreated,
        'timeUpdated': Timestamp.now(),
      });

      final updatedDoc =
          await _firestore.collection(collectionName).doc(walletId).get();
      return PaxWallet.fromMap(updatedDoc.data()!, id: updatedDoc.id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error updating wallet with log data: $e');
      }
      rethrow;
    }
  }
}
