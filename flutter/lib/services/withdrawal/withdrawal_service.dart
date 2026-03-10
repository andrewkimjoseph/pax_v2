// Note: This service manages withdrawals to payment methods. While the UI refers to these
// as "Withdrawal Methods" for better user experience, the underlying database and
// service layer maintain the "payment_methods" terminology for consistency.

// This service manages the withdrawal process for participants:
// - Handles withdrawals to payment methods through Firebase Functions
// - Validates PaxAccount and server wallet information
// - Provides methods to query withdrawal history
// - Includes comprehensive error handling and validation

// lib/services/withdrawal/withdrawal_service.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:pax/models/firestore/withdrawal/withdrawal_model.dart';
import 'package:pax/repositories/firestore/pax_account/pax_account_repository.dart';
import 'package:pax/repositories/firestore/withdrawal/withdrawal_repository.dart';

class WithdrawalService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final PaxAccountRepository _paxAccountRepository;
  final WithdrawalRepository _withdrawalRepository;

  WithdrawalService({
    required PaxAccountRepository paxAccountRepository,
    required WithdrawalRepository withdrawalRepository,
  }) : _paxAccountRepository = paxAccountRepository,
       _withdrawalRepository = withdrawalRepository;

  /// Process a withdrawal to a payment method.
  /// For V2: pass [paymentMethodAddress] (destination wallet) and [v2EncryptedParams].
  Future<Map<String, dynamic>> withdrawToPaymentMethod({
    required String userId,
    required String paymentMethodId,
    required int predefinedId,
    required double amountToWithdraw,
    required int tokenId,
    required String currencyAddress,
    int decimals = 18,
    String? paymentMethodAddress,
    Map<String, String>? v2EncryptedParams,
  }) async {
    try {
      // 1. Get PaxAccount for user
      final paxAccount = await _paxAccountRepository.getAccount(userId);
      if (paxAccount == null) {
        throw Exception('PaxAccount not found');
      }

      final paxAccountAddress = paxAccount.payoutWalletAddress;
      if (paxAccountAddress == null || paxAccountAddress.isEmpty) {
        throw Exception('Pax account wallet address not found');
      }

      final isV2 = paxAccount.isV2;
      if (isV2) {
        if (v2EncryptedParams == null ||
            paymentMethodAddress == null ||
            paymentMethodAddress.isEmpty) {
          throw Exception(
            'V2 withdraw requires paymentMethodAddress and v2EncryptedParams',
          );
        }
      } else {
        final serverWalletId = paxAccount.serverWalletId;
        if (serverWalletId == null || serverWalletId.isEmpty) {
          throw Exception('Server wallet not found');
        }
      }

      // 2. Call the cloud function
      final callable = _functions.httpsCallable(
        'withdrawToPaymentMethod',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 300)),
      );

      final payload = <String, dynamic>{
        'paxAccountAddress': paxAccountAddress,
        'amountRequested': amountToWithdraw.toString(),
        'currency': currencyAddress,
        'decimals': decimals,
        'tokenId': tokenId,
        'withdrawalPaymentMethodId': paymentMethodId,
      };

      if (isV2) {
        payload['encryptedPrivateKey'] = v2EncryptedParams!['encryptedPrivateKey'];
        payload['sessionKey'] = v2EncryptedParams['sessionKey'];
        payload['eoWalletAddress'] = v2EncryptedParams['eoWalletAddress'];
        payload['paymentMethodAddress'] = paymentMethodAddress;
      } else {
        payload['serverWalletId'] = paxAccount.serverWalletId;
        payload['paymentMethodId'] = predefinedId - 1;
      }

      final result = await callable.call(payload);

      if (result.data == null) {
        throw Exception('Withdrawal failed - empty response');
      }

      final data = result.data as Map<String, dynamic>;
      final txnHash = data['txnHash'] ?? data['bundleTxnHash'];

      return {
        'success': true,
        'txnHash': txnHash,
        'withdrawalId': data['withdrawalId'],
        'details': data['details'],
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error withdrawing tokens: $e');
        if (e is FirebaseFunctionsException) {
          debugPrint('Firebase Functions error code: ${e.code}');
          debugPrint('Firebase Functions error details: ${e.details}');
        }
      }
      throw Exception('Failed to withdraw tokens: ${e.toString()}');
    }
  }

  /// Get all withdrawals for a participant
  Future<List<Withdrawal>> getWithdrawalsForParticipant(String userId) async {
    return await _withdrawalRepository.getWithdrawalsForParticipant(userId);
  }

  /// Get a specific withdrawal by ID
  Future<Withdrawal?> getWithdrawal(String withdrawalId) async {
    return await _withdrawalRepository.getWithdrawal(withdrawalId);
  }
}
