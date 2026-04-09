import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pax/env/env.dart';
import 'package:pax/utils/evm_selector_util.dart';

class WalletRegistryResult {
  final String? txnHash;
  final Timestamp logTimeCreated;
  final bool alreadyLogged;

  WalletRegistryResult({
    required this.txnHash,
    required this.logTimeCreated,
    this.alreadyLogged = false,
  });
}

class WalletRegistryService {
  final FirebaseFunctions _functions;
  static final String _rpcUrl = 'https://lb.drpc.live/celo/${Env.drpcAPIKey}';
  static const String _canvassingWalletRegistryProxyAddress =
      '0x74Cc10C7c8EE72CbAB508f3A6142C90c68579f3F';
  static final String _isWalletLoggedSelector = EvmSelectorUtil.computeSelector(
    'isWalletLogged(address)',
  );

  WalletRegistryService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  Future<Map<String, dynamic>> _rpcCall(
    String method,
    List<dynamic> params,
  ) async {
    final response = await http.post(
      Uri.parse(_rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
        'id': 1,
      }),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Direct on-chain read against CanvassingWalletRegistry proxy.
  Future<bool> isWalletLogged(String walletAddress) async {
    Future<bool> attempt() async {
      final paddedAddress = walletAddress
          .replaceFirst('0x', '')
          .toLowerCase()
          .padLeft(64, '0');
      final data = '$_isWalletLoggedSelector$paddedAddress';
      final result = await _rpcCall('eth_call', [
        {'to': _canvassingWalletRegistryProxyAddress, 'data': data},
        'latest',
      ]);
      final returnValue = result['result'] as String? ?? '0x0';
      final normalized =
          returnValue.startsWith('0x') ? returnValue.substring(2) : returnValue;
      if (normalized.isEmpty) return false;
      return BigInt.parse(normalized, radix: 16) != BigInt.zero;
    }

    try {
      return await attempt();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[WalletRegistryService] isWalletLogged first attempt error: $e, retrying once',
        );
      }
    }

    try {
      return await attempt();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WalletRegistryService] isWalletLogged retry failed: $e');
      }
      return false;
    }
  }

  /// Calls the `logWalletToRegistry` Cloud Function which sends the
  /// `logWallet` transaction on behalf of the contract owner.
  Future<WalletRegistryResult> logWallet({
    required String eoWalletAddress,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('WalletRegistryService: logging wallet $eoWalletAddress');
      }

      final callable = _functions.httpsCallable(
        'logWalletToRegistry',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );

      final result = await callable.call({'eoWalletAddress': eoWalletAddress});

      final data = Map<String, dynamic>.from(result.data as Map);
      final txnHash = data['txnHash'] as String?;
      final alreadyLogged = (data['alreadyLogged'] as bool?) ?? false;
      final timestampStr = data['timestamp'] as String?;
      final dt =
          timestampStr != null && timestampStr.isNotEmpty
              ? DateTime.parse(timestampStr)
              : DateTime.now();

      if (kDebugMode) {
        debugPrint(
          '[WalletRegistryService] WalletRegistryService: wallet log response, '
          'txHash=$txnHash, alreadyLogged=$alreadyLogged',
        );
      }

      return WalletRegistryResult(
        txnHash: txnHash,
        logTimeCreated: Timestamp.fromDate(dt),
        alreadyLogged: alreadyLogged,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[WalletRegistryService] WalletRegistryService: error logging wallet: $e',
        );
      }
      rethrow;
    }
  }
}
