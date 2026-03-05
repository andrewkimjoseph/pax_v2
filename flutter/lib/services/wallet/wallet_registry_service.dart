import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class WalletRegistryResult {
  final String txnHash;
  final Timestamp logTimeCreated;

  WalletRegistryResult({
    required this.txnHash,
    required this.logTimeCreated,
  });
}

class WalletRegistryService {
  final FirebaseFunctions _functions;

  WalletRegistryService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  /// Calls the `logWalletToRegistry` Cloud Function which sends the
  /// `logWallet` transaction on behalf of the contract owner.
  Future<WalletRegistryResult> logWallet({
    required String eoWalletAddress,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint(
          'WalletRegistryService: logging wallet $eoWalletAddress',
        );
      }

      final callable = _functions.httpsCallable(
        'logWalletToRegistry',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 60),
        ),
      );

      final result = await callable.call({
        'eoWalletAddress': eoWalletAddress,
      });

      final data = result.data as Map<String, dynamic>;
      final txnHash = data['txnHash'] as String;
      final timestampStr = data['timestamp'] as String;
      final dt = DateTime.parse(timestampStr);

      if (kDebugMode) {
        debugPrint('WalletRegistryService: wallet logged, txHash=$txnHash');
      }

      return WalletRegistryResult(
        txnHash: txnHash,
        logTimeCreated: Timestamp.fromDate(dt),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WalletRegistryService: error logging wallet: $e');
      }
      rethrow;
    }
  }
}
