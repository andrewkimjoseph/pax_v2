import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pax/env/env.dart';
import 'package:pax/utils/evm_selector_util.dart';

/// Verifies GoodDollar identity status for V2 users via direct RPC calls
/// rather than relying on Firestore participant fields.
class GoodDollarIdentityService {
  static final String _rpcUrl = 'https://lb.drpc.live/celo/${Env.drpcAPIKey}';

  // GoodDollar Identity contract on Celo
  static const String _identityContractAddressProxy =
      '0xC361A6E67822a0EDc17D899227dd9FC50BD62F42';

  // Function signatures
  // isWhitelisted(address) -> bool
  static final String _isWhitelistedSelector = EvmSelectorUtil.computeSelector(
    'isWhitelisted(address)',
  );
  // getWhitelistedOnChainId(address) -> string
  static final String _getWhitelistedOnChainIdSelector =
      EvmSelectorUtil.computeSelector('getWhitelistedOnChainId(address)');

  static Future<Map<String, dynamic>> _rpcCall(
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

  /// Checks if a wallet address is whitelisted (verified) in GoodDollar Identity.
  static Future<bool> isWhitelisted(String walletAddress) async {
    Future<bool> attempt() async {
      final paddedAddress = walletAddress
          .replaceFirst('0x', '')
          .toLowerCase()
          .padLeft(64, '0');

      final data = '$_isWhitelistedSelector$paddedAddress';
      final result = await _rpcCall('eth_call', [
        {'to': _identityContractAddressProxy, 'data': data},
        'latest',
      ]);

      final returnValue = result['result'] as String? ?? '0x0';
      return returnValue.endsWith('1');
    }

    try {
      return await attempt();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'GoodDollarIdentityService: isWhitelisted first attempt error: $e, retrying once',
        );
      }
    }

    try {
      return await attempt();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[GoodDollarIdentityService] GoodDollarIdentityService: isWhitelisted retry failed: $e',
        );
      }
      return false;
    }
  }

  /// Gets the chain ID on which the wallet was whitelisted.
  /// Returns null if not whitelisted.
  static Future<String?> getWhitelistedChainId(String walletAddress) async {
    try {
      final paddedAddress = walletAddress
          .replaceFirst('0x', '')
          .toLowerCase()
          .padLeft(64, '0');

      final data = '$_getWhitelistedOnChainIdSelector$paddedAddress';
      final result = await _rpcCall('eth_call', [
        {'to': _identityContractAddressProxy, 'data': data},
        'latest',
      ]);

      final returnValue = result['result'] as String? ?? '0x';
      if (returnValue == '0x' || returnValue.length <= 2) return null;

      // Decode ABI-encoded string
      final hexStr = returnValue.substring(2);
      if (hexStr.length < 128) return null;

      final dataOffset = int.parse(hexStr.substring(0, 64), radix: 16) * 2;
      final length = int.parse(
        hexStr.substring(dataOffset, dataOffset + 64),
        radix: 16,
      );
      if (length == 0) return null;

      final contentHex = hexStr.substring(
        dataOffset + 64,
        dataOffset + 64 + length * 2,
      );
      final bytes = <int>[];
      for (var i = 0; i < contentHex.length; i += 2) {
        bytes.add(int.parse(contentHex.substring(i, i + 2), radix: 16));
      }
      return String.fromCharCodes(bytes);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'GoodDollarIdentityService: getWhitelistedChainId error: $e',
        );
      }
      return null;
    }
  }

  /// Full identity check: returns whitelisted status and chain info.
  static Future<GoodDollarIdentityStatus> checkIdentity(
    String walletAddress,
  ) async {
    final whitelisted = await isWhitelisted(walletAddress);
    String? chainId;
    if (whitelisted) {
      chainId = await getWhitelistedChainId(walletAddress);
    }
    return GoodDollarIdentityStatus(
      isWhitelisted: whitelisted,
      chainId: chainId,
    );
  }
}

class GoodDollarIdentityStatus {
  final bool isWhitelisted;
  final String? chainId;

  GoodDollarIdentityStatus({required this.isWhitelisted, this.chainId});
}
