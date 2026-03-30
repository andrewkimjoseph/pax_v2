import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:pax/repositories/firestore/pax_account/pax_account_repository.dart';

class DonationService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final PaxAccountRepository _paxAccountRepository;

  DonationService({required PaxAccountRepository paxAccountRepository})
      : _paxAccountRepository = paxAccountRepository;

  Future<Map<String, dynamic>> donateToGoodCollective({
    required String userId,
    required double amountToDonate,
    required int tokenId,
    required String currencyAddress,
    required String donationContract,
    required int donationMethodId,
    Map<String, String>? v2EncryptedParams,
    int decimals = 18,
  }) async {
    try {
      final paxAccount = await _paxAccountRepository.getAccount(userId);
      if (paxAccount == null) {
        throw Exception('PaxAccount not found');
      }

      final paxAccountAddress = paxAccount.payoutWalletAddress;
      if (paxAccountAddress == null || paxAccountAddress.isEmpty) {
        throw Exception('Pax account wallet address not found');
      }

      final callable = _functions.httpsCallable(
        'donateToGoodCollective',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 300)),
      );

      final payload = <String, dynamic>{
        'paxAccountAddress': paxAccountAddress,
        'amountDonated': amountToDonate.toString(),
        'currency': currencyAddress,
        'decimals': decimals,
        'tokenId': tokenId,
        'donationContract': donationContract,
        'donationMethodId': donationMethodId,
      };
      if (paxAccount.isV2) {
        payload['encryptedPrivateKey'] = v2EncryptedParams?['encryptedPrivateKey'];
        payload['sessionKey'] = v2EncryptedParams?['sessionKey'];
        payload['eoWalletAddress'] = v2EncryptedParams?['eoWalletAddress'];
      } else {
        payload['serverWalletId'] = paxAccount.serverWalletId;
      }

      final result = await callable.call(payload);
      if (result.data == null) {
        throw Exception('Donation failed - empty response');
      }

      final data = result.data as Map<String, dynamic>;
      return {
        'success': true,
        'txnHash': data['txnHash'] ?? data['bundleTxnHash'],
        'donationId': data['donationId'],
        'details': data['details'],
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Error] Error donating tokens: $e');
      }
      throw Exception('Failed to donate tokens: ${e.toString()}');
    }
  }
}
