import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Response shape from the getWalletTransactions callable.
/// [result] contains full Etherscan tx objects for DB persistence.
class EtherscanTxListResponse {
  const EtherscanTxListResponse({
    required this.status,
    required this.message,
    required this.result,
  });

  final String status;
  final String message;
  final List<Map<String, dynamic>> result;

  factory EtherscanTxListResponse.fromCallableResult(dynamic data) {
    if (data is! Map) {
      throw FormatException('getWalletTransactions: expected map, got $data');
    }
    final map = Map<String, dynamic>.from(data);
    final status = map['status']?.toString() ?? '0';
    final message = map['message']?.toString() ?? '';
    final rawResult = map['result'];
    List<Map<String, dynamic>> result = [];
    if (rawResult is List) {
      for (final e in rawResult) {
        if (e is Map) {
          result.add(Map<String, dynamic>.from(e));
        }
      }
    }
    return EtherscanTxListResponse(
      status: status,
      message: message,
      result: result,
    );
  }
}

/// Calls the Firebase callable getWalletTransactions (no API keys in app).
/// Returns full tx objects for the provider to persist in local DB.
class WalletTransactionsService {
  WalletTransactionsService({
    FirebaseFunctions? functions,
  }) : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Fetches transaction list for [address] from backend (Etherscan v2 proxy).
  /// On [FirebaseFunctionsException] or network error, rethrows so the provider
  /// can keep showing cached data and set error state.
  Future<EtherscanTxListResponse> getTransactionList(
    String address, {
    int page = 1,
    int offset = 20,
  }) async {
    try {
      final callable = _functions.httpsCallable('getWalletTransactions');
      final result = await callable.call(<String, dynamic>{
        'address': address,
        'page': page,
        'offset': offset,
      });
      return EtherscanTxListResponse.fromCallableResult(result.data);
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('[WalletTransactionsService] WalletTransactionsService: callable error ${e.code} ${e.message}');
      }
      rethrow;
    }
  }
}
