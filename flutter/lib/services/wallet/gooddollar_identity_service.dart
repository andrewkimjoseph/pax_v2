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
  // identities(address) -> (uint256,uint256,string,uint256,uint8,uint32)
  static final String _identitiesSelector = EvmSelectorUtil.computeSelector(
    'identities(address)',
  );
  // getWhitelistedOnChainId(address) -> string
  static final String _getWhitelistedOnChainIdSelector =
      EvmSelectorUtil.computeSelector('getWhitelistedOnChainId(address)');
  // getWhitelistedRoot(address) -> address
  static final String _getWhitelistedRootSelector =
      EvmSelectorUtil.computeSelector('getWhitelistedRoot(address)');

  static const String _zeroAddress =
      '0x0000000000000000000000000000000000000000';

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
      String readWord(String hexStr, int index) {
        final start = index * 64;
        final end = start + 64;
        if (hexStr.length < end) {
          throw FormatException('Identities response too short at word $index');
        }
        return hexStr.substring(start, end);
      }

      BigInt readUint(String hexStr, int index) {
        return BigInt.parse(readWord(hexStr, index), radix: 16);
      }

      String readDynamicString(String hexStr, int offsetWordIndex) {
        final offsetHex = readWord(hexStr, offsetWordIndex);
        final offsetBytes = int.parse(offsetHex, radix: 16);
        final offsetChars = offsetBytes * 2;

        if (hexStr.length < offsetChars + 64) {
          throw const FormatException(
            'Identities response too short for string length',
          );
        }

        final length = int.parse(
          hexStr.substring(offsetChars, offsetChars + 64),
          radix: 16,
        );
        final dataStart = offsetChars + 64;
        final dataEnd = dataStart + length * 2;
        if (hexStr.length < dataEnd) {
          throw const FormatException(
            'Identities response too short for string bytes',
          );
        }

        final contentHex = hexStr.substring(dataStart, dataEnd);
        final bytes = <int>[];
        for (var i = 0; i < contentHex.length; i += 2) {
          bytes.add(int.parse(contentHex.substring(i, i + 2), radix: 16));
        }
        return String.fromCharCodes(bytes);
      }

      final paddedAddress = walletAddress
          .replaceFirst('0x', '')
          .toLowerCase()
          .padLeft(64, '0');

      final data = '$_identitiesSelector$paddedAddress';
      final result = await _rpcCall('eth_call', [
        {'to': _identityContractAddressProxy, 'data': data},
        'latest',
      ]);

      final returnValue = result['result'] as String? ?? '0x';
      if (returnValue == '0x' || returnValue.length <= 2) {
        throw const FormatException('Empty identities response');
      }

      final hexStr = returnValue.substring(2);
      final dateAuthenticated = readUint(hexStr, 0);
      final dateAdded = readUint(hexStr, 1);
      final did = readDynamicString(hexStr, 2);
      final whitelistedOnChainId = readUint(hexStr, 3);
      final status = readUint(hexStr, 4).toInt();
      final authCount = readUint(hexStr, 5).toInt();

      if (kDebugMode) {
        debugPrint(
          '[GoodDollarIdentityService] identities($walletAddress): '
          '${jsonEncode({
            'dateAuthenticated': dateAuthenticated.toString(),
            'dateAdded': dateAdded.toString(),
            'did': did,
            'whitelistedOnChainId': whitelistedOnChainId.toString(),
            'status': status,
            'authCount': authCount,
          })}',
        );
      }

      return status == 1;
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

  /// Returns the whitelisted identity root for [walletAddress], or null if
  /// not whitelisted / zero address / RPC failure.
  static Future<String?> getWhitelistedRoot(String walletAddress) async {
    Future<String?> attempt() async {
      final paddedAddress = walletAddress
          .replaceFirst('0x', '')
          .toLowerCase()
          .padLeft(64, '0');

      final data = '$_getWhitelistedRootSelector$paddedAddress';
      final result = await _rpcCall('eth_call', [
        {'to': _identityContractAddressProxy, 'data': data},
        'latest',
      ]);

      final returnValue = result['result'] as String? ?? '0x';
      if (returnValue == '0x' || returnValue.length <= 2) {
        throw const FormatException('Empty getWhitelistedRoot response');
      }

      final hexStr = returnValue.substring(2);
      if (hexStr.length < 64) {
        throw const FormatException('getWhitelistedRoot response too short');
      }

      final root = '0x${hexStr.substring(24, 64)}';
      if (root.toLowerCase() == _zeroAddress.toLowerCase()) {
        return null;
      }
      return root;
    }

    try {
      return await attempt();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'GoodDollarIdentityService: getWhitelistedRoot first attempt error: $e, retrying once',
        );
      }
    }

    try {
      return await attempt();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[GoodDollarIdentityService] getWhitelistedRoot retry failed: $e',
        );
      }
      return null;
    }
  }

  /// True when [walletAddress] is whitelisted and is the identity root itself
  /// (not a connected wallet under another root).
  static Future<bool> isWhitelistedRoot(String walletAddress) async {
    final whitelisted = await isWhitelisted(walletAddress);
    if (!whitelisted) return false;

    final root = await getWhitelistedRoot(walletAddress);
    if (root == null) return false;

    return root.toLowerCase() == walletAddress.toLowerCase();
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
