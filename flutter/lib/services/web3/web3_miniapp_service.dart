import 'dart:convert';

import 'package:pax/env/env.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pax/utils/remote_config_constants.dart';
import 'package:pax/utils/secret_constants.dart';
import 'package:wallet/wallet.dart';
import 'package:web3dart/web3dart.dart';

/// Service responsible for all mini-app Web3 operations.
///
/// Why this exists:
/// - `Web3WebView` should focus on UI and WebView lifecycle.
/// - Blockchain-specific logic (RPC routing, tx construction, signing, sending)
///   should live in one place that is easier to test and reason about.
///
/// This class acts as the "wallet backend" for JavaScript requests coming from
/// the mini-app WebView bridge.
class Web3MiniAppService {
  static final String _rpcUrl =
      'https://lb.drpc.live/celo/${Env.drpcRpcApiKey}';

  Web3MiniAppService({
    required Credentials credentials,
    required Map<String, dynamic> paxWalletConfig,
    String? rpcUrl,
  }) : _credentials = credentials,
       _paxWalletConfig = paxWalletConfig,
       _defaultRpcUrl = rpcUrl ?? _rpcUrl;

  final Credentials _credentials;
  final Map<String, dynamic> _paxWalletConfig;
  final String _defaultRpcUrl;
  String? _resolvedRpcUrl;

  http.Client? _httpClient;
  Web3Client? _web3Client;
  String? _currentAddress;
  String? _currentChainId;

  /// Current EOA exposed to the dApp provider.
  String? get currentAddress => _currentAddress;

  /// Current chain id in decimal string form (e.g. "42220").
  String? get currentChainId => _currentChainId;

  /// Initialize transport + derive runtime wallet metadata.
  ///
  /// We do this once up-front so request handlers can stay lightweight.
  Future<void> initialize() async {
    _resolvedRpcUrl = _resolveRpcUrl(_paxWalletConfig);
    final fallbackChainId = _resolveFallbackChainId(_paxWalletConfig);

    _httpClient = http.Client();
    _web3Client = Web3Client(_resolvedRpcUrl!, _httpClient!);

    final address = _credentials.address;
    try {
      final chainId = await _web3Client!.getChainId();
      _currentAddress = address.with0x;
      _currentChainId = chainId.toString();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Web3MiniAppService] Failed to fetch chainId: $e');
      }
      // Fallback keeps mini-app usable when chain-id probe fails transiently.
      _currentAddress = address.with0x;
      _currentChainId = fallbackChainId.toString();
    }
  }

  /// Reads `chain_id` from `pax_wallet_config`; defaults to Celo mainnet.
  int _resolveFallbackChainId(Map<String, dynamic> config) {
    final dynamic rawChainId = config[RemoteConfigKeys.chainId];
    if (rawChainId is int) return rawChainId;
    if (rawChainId is num) return rawChainId.toInt();
    if (rawChainId is String) return int.tryParse(rawChainId) ?? 42220;
    return 42220;
  }

  /// Reads `rpc_url` from `pax_wallet_config`; defaults to constructor RPC URL.
  String _resolveRpcUrl(Map<String, dynamic> config) {
    if (kDebugMode && web3MiniAppDebugRpcUrlOverride.trim().isNotEmpty) {
      return web3MiniAppDebugRpcUrlOverride.trim();
    }
    final dynamic rawRpcUrl = config[RemoteConfigKeys.rpcUrl];
    if (rawRpcUrl is String && rawRpcUrl.trim().isNotEmpty) {
      return rawRpcUrl.trim();
    }
    return _defaultRpcUrl;
  }

  /// Routes one JSON-RPC style request from the JavaScript bridge.
  ///
  /// [onTransactionSent] is intentionally injected from the UI layer so this
  /// service stays framework-agnostic and can be reused without Riverpod.
  Future<Map<String, dynamic>> handleRequest(
    Map<String, dynamic> request, {
    void Function(String eoAddress)? onTransactionSent,
  }) async {
    // Recover automatically if the service was disposed or not fully initialized
    // when a dApp request arrives.
    if (_web3Client == null ||
        _currentAddress == null ||
        _currentChainId == null) {
      await initialize();
      if (_web3Client == null ||
          _currentAddress == null ||
          _currentChainId == null) {
        return {
          'id': request['id'],
          'error': 'Wallet provider is still initializing. Please try again.',
        };
      }
    }

    final method = request['method'] as String;
    final params = request['params'] as List? ?? [];

    try {
      switch (method) {
        case 'eth_requestAccounts':
        case 'eth_accounts':
          return {
            'id': request['id'],
            'result': [_currentAddress],
          };

        case 'eth_chainId':
          return {
            'id': request['id'],
            'result': '0x${int.parse(_currentChainId!).toRadixString(16)}',
          };

        case 'eth_blockNumber':
        case 'eth_gasPrice':
          return _rpcPassthrough(request['id'], method, []);

        case 'eth_getBalance':
          if (params.isEmpty) {
            return {'id': request['id'], 'error': 'Missing address parameter'};
          }
          final address = EthereumAddress.fromHex(params[0] as String);
          final balance = await _web3Client!.getBalance(address);
          return {
            'id': request['id'],
            'result': '0x${balance.getInWei.toRadixString(16)}',
          };

        case 'eth_getCode':
        case 'eth_getTransactionCount':
          if (params.isEmpty) {
            return {'id': request['id'], 'error': 'Missing address parameter'};
          }
          final address = params[0] as String;
          final blockTag = params.length > 1 ? params[1] as String? : 'latest';
          return _rpcPassthrough(request['id'], method, [
            address,
            blockTag ?? 'latest',
          ]);

        case 'eth_estimateGas':
          if (params.isEmpty) {
            return {
              'id': request['id'],
              'error': 'Missing transaction parameter',
            };
          }
          final txParams = Map<String, dynamic>.from(params[0] as Map);
          final blockTag = params.length > 1 ? params[1] as String? : 'latest';
          return _rpcPassthrough(request['id'], method, [
            txParams,
            blockTag ?? 'latest',
          ]);

        case 'eth_call':
          if (params.isEmpty) {
            return {'id': request['id'], 'error': 'Missing call parameter'};
          }
          final callParams = Map<String, dynamic>.from(params[0] as Map);
          final blockTag = params.length > 1 ? params[1] as String? : 'latest';
          return _rpcPassthrough(request['id'], method, [
            callParams,
            blockTag ?? 'latest',
          ]);

        case 'eth_getTransactionReceipt':
        case 'eth_getTransactionByHash':
          if (params.isEmpty) {
            return {'id': request['id'], 'error': 'Missing transaction hash'};
          }
          final txHash = params[0] as String;
          return _rpcPassthrough(request['id'], method, [txHash]);

        case 'eth_sendTransaction':
          if (params.isEmpty) {
            return {
              'id': request['id'],
              'error': 'Missing transaction parameter',
            };
          }
          return _handleSendTransaction(
            request['id'],
            Map<String, dynamic>.from(params[0] as Map),
            onTransactionSent: onTransactionSent,
          );

        case 'eth_signTransaction':
          if (params.isEmpty) {
            return {
              'id': request['id'],
              'error': 'Missing transaction parameter',
            };
          }
          return _handleSignTransaction(
            request['id'],
            Map<String, dynamic>.from(params[0] as Map),
          );

        case 'personal_sign':
        case 'eth_sign':
          return _handleSign(request['id'], params);

        case 'eth_signTypedData':
        case 'eth_signTypedData_v4':
          return {
            'id': request['id'],
            'error': 'SignTypedData not fully implemented',
          };

        case 'wallet_switchEthereumChain':
          // Not switching yet; we only expose Celo mainnet currently.
          return {'id': request['id'], 'result': null};

        case 'net_version':
          return {'id': request['id'], 'result': _currentChainId};

        case 'eth_getBlockByNumber':
          final blockTag =
              params.isNotEmpty ? params[0] as String? ?? 'latest' : 'latest';
          final includeTransactions =
              params.length > 1 ? params[1] as bool? ?? false : false;
          return _rpcPassthrough(request['id'], method, [
            blockTag,
            includeTransactions,
          ]);

        default:
          return {'id': request['id'], 'error': 'Method $method not supported'};
      }
    } catch (e) {
      return {'id': request['id'], 'error': e.toString()};
    }
  }

  /// Forwards simple RPC methods to the upstream node.
  ///
  /// This keeps method support broad without re-implementing every RPC.
  Future<Map<String, dynamic>> _rpcPassthrough(
    dynamic id,
    String method,
    List<dynamic> params,
  ) async {
    final rpcRequest = {
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
      'id': 1,
    };
    final response = await _httpClient!.post(
      Uri.parse(_resolvedRpcUrl ?? _defaultRpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(rpcRequest),
    );
    final responseData = jsonDecode(response.body) as Map<String, dynamic>;
    if (responseData.containsKey('error')) {
      return {'id': id, 'error': responseData['error']};
    }
    return {'id': id, 'result': responseData['result']};
  }

  /// Broadcast a signed transaction and return tx hash.
  Future<String> _sendRawTransaction(Uint8List signedTransaction) async {
    final hexTx = bytesToHex(signedTransaction, include0x: true);

    if (kDebugMode) {
      debugPrint('[Web3MiniAppService] ==== TRANSACTION DEBUG ====');
      debugPrint(
        '[Web3MiniAppService] Sending to: ${_resolvedRpcUrl ?? _defaultRpcUrl}',
      );
      debugPrint(
        '[Web3MiniAppService] Raw TX length: ${signedTransaction.length} bytes',
      );
    }

    final rpcRequest = {
      'jsonrpc': '2.0',
      'method': 'eth_sendRawTransaction',
      'params': [hexTx],
      'id': 1,
    };

    final response = await _httpClient!.post(
      Uri.parse(_resolvedRpcUrl ?? _defaultRpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(rpcRequest),
    );

    if (kDebugMode) {
      debugPrint('[Web3MiniAppService] RPC status: ${response.statusCode}');
      debugPrint('[Web3MiniAppService] RPC body: ${response.body}');
    }

    final responseData = jsonDecode(response.body) as Map<String, dynamic>;
    if (responseData.containsKey('error')) {
      final error = responseData['error'];
      final errorMessage =
          error is Map
              ? (error['message'] ?? error.toString())
              : error.toString();
      throw Exception('RPC Error: $errorMessage');
    }

    return responseData['result'] as String;
  }

  /// Handles `eth_sendTransaction` by creating a Celo-safe EIP-1559 tx.
  ///
  /// Important: We sign manually to guarantee type-2 payload shape and avoid
  /// node-side interpretation issues seen with mixed legacy/EIP-1559 dApp input.
  Future<Map<String, dynamic>> _handleSendTransaction(
    dynamic id,
    Map<String, dynamic> txParams, {
    void Function(String eoAddress)? onTransactionSent,
  }) async {
    try {
      final nonce = await _web3Client!.getTransactionCount(
        _credentials.address,
        atBlock: const BlockNum.pending(),
      );

      final valueWei = _parseHexBigInt(txParams['value']) ?? BigInt.zero;
      final value = EtherAmount.fromBigInt(EtherUnit.wei, valueWei);

      final dataHex =
          txParams['data'] != null ? txParams['data'] as String : null;
      // We normalize all fee knobs to wei BigInt for deterministic math.
      final networkGasPriceWei = (await _web3Client!.getGasPrice()).getInWei;
      final requestedGasPriceWei =
          _parseHexBigInt(txParams['gasPrice']) ??
          _parseHexBigInt(txParams['maxFeePerGas']);
      final requestedPriorityWei =
          _parseHexBigInt(txParams['maxPriorityFeePerGas']) ??
          BigInt.from(2000000000); // 2 gwei fallback

      // Query current block base fee so maxFee never falls below protocol floor.
      BigInt baseFeeWei = BigInt.zero;
      try {
        final latestBlock = await _rpcPassthrough(1, 'eth_getBlockByNumber', [
          'latest',
          false,
        ]);
        final blockData = latestBlock['result'];
        if (blockData is Map<String, dynamic>) {
          baseFeeWei =
              _parseHexBigInt(blockData['baseFeePerGas']) ?? BigInt.zero;
        }
      } catch (_) {
        // If this fails we still proceed using network gas price.
      }

      // Protocol-valid floor:
      // maxFee must cover current baseFee + tip. Using 2x baseFee can reject
      // low-balance wallets even when the tx would execute right now.
      final minRequiredWei =
          baseFeeWei > BigInt.zero
              ? (baseFeeWei + requestedPriorityWei)
              : BigInt.zero;
      final candidateGasPriceWei = _maxBigInt(
        networkGasPriceWei,
        requestedGasPriceWei ?? BigInt.zero,
      );
      final maxFeePerGasWei = _maxBigInt(candidateGasPriceWei, minRequiredWei);

      final data =
          dataHex != null ? Uint8List.fromList(hexToBytes(dataHex)) : null;

      int gasLimit = 100000;
      if (txParams['gas'] != null) {
        gasLimit = int.parse(
          (txParams['gas'] as String).replaceFirst('0x', ''),
          radix: 16,
        );
      } else {
        try {
          final estimateParams = <String, dynamic>{
            'from': _credentials.address.with0x,
            'to': txParams['to'],
            'value': _toRpcHex(valueWei),
          };
          if (dataHex != null && dataHex.trim().isNotEmpty) {
            estimateParams['data'] = dataHex;
          }
          final estimateResponse = await _rpcPassthrough(1, 'eth_estimateGas', [
            estimateParams,
            'latest',
          ]);
          final estimatedGas = _parseHexBigInt(estimateResponse['result']);
          if (estimatedGas != null && estimatedGas > BigInt.zero) {
            // Keep a modest safety buffer to avoid overestimating affordability.
            gasLimit = ((estimatedGas.toInt() * 11) / 10).ceil();
          }
        } catch (_) {
          // Keep fallback gas when estimate endpoint is unavailable.
        }
      }

      // Use a realistic live gas price for affordability checks (clamped by
      // maxFeePerGas). This avoids false negatives from max-fee ceiling math.
      final likelyEffectiveGasPriceWei = _minBigInt(
        maxFeePerGasWei,
        _maxBigInt(networkGasPriceWei, requestedPriorityWei),
      );
      final celoBalance = await _web3Client!.getBalance(_credentials.address);
      final gasLimitWei = BigInt.from(gasLimit);

      // Nodes validate sender affordability against the max-fee envelope:
      // value + (gasLimit * maxFeePerGas). Cap maxFee when possible so valid
      // transactions are not rejected just because the initial ceiling is high.
      BigInt finalMaxFeePerGasWei = maxFeePerGasWei;
      final spendableForGasWei = celoBalance.getInWei - valueWei;
      if (spendableForGasWei > BigInt.zero && gasLimitWei > BigInt.zero) {
        final affordableMaxFeePerGasWei = spendableForGasWei ~/ gasLimitWei;
        final protocolMinMaxFeeWei = _maxBigInt(minRequiredWei, requestedPriorityWei);
        if (finalMaxFeePerGasWei > affordableMaxFeePerGasWei &&
            affordableMaxFeePerGasWei >= protocolMinMaxFeeWei) {
          finalMaxFeePerGasWei = affordableMaxFeePerGasWei;
          if (kDebugMode) {
            debugPrint(
              '[Web3MiniAppService] Capped MaxFeePerGas to affordable value: '
              '$finalMaxFeePerGasWei',
            );
          }
        }
      }

      final estimatedGasFeeWei =
          likelyEffectiveGasPriceWei * gasLimitWei;
      final estimatedTotalCostWei = valueWei + estimatedGasFeeWei;
      final maxEnvelopeCostWei = valueWei + (finalMaxFeePerGasWei * gasLimitWei);
      if (celoBalance.getInWei < estimatedTotalCostWei ||
          celoBalance.getInWei < maxEnvelopeCostWei) {
        final requiredWei = _maxBigInt(estimatedTotalCostWei, maxEnvelopeCostWei);
        final shortfallWei = requiredWei - celoBalance.getInWei;
        final envelopeGasWei = finalMaxFeePerGasWei * gasLimitWei;
        if (kDebugMode) {
          debugPrint(
            '[Web3MiniAppService] Insufficient GAS details: '
            'requiredWei=$requiredWei, balanceWei=${celoBalance.getInWei}, '
            'valueWei=$valueWei, estimatedGasFeeWei=$estimatedGasFeeWei, '
            'envelopeGasWei=$envelopeGasWei, shortfallWei=$shortfallWei',
          );
        }
        return {
          'id': id,
          'error': 'Not enough GAS units to complete this transaction.',
        };
      }

      if (kDebugMode) {
        debugPrint('[Web3MiniAppService] Nonce: $nonce');
        debugPrint('[Web3MiniAppService] Gas: $gasLimit');
        debugPrint('[Web3MiniAppService] BaseFee: $baseFeeWei');
        debugPrint('[Web3MiniAppService] MaxFeePerGas: $maxFeePerGasWei');
        debugPrint(
          '[Web3MiniAppService] FinalMaxFeePerGas: $finalMaxFeePerGasWei',
        );
        debugPrint(
          '[Web3MiniAppService] LikelyEffectiveGasPrice: $likelyEffectiveGasPriceWei',
        );
        debugPrint(
          '[Web3MiniAppService] MaxPriorityFeePerGas: $requestedPriorityWei',
        );
      }

      final signedTx = await _signEip1559Transaction(
        nonce: nonce,
        maxFeePerGas: finalMaxFeePerGasWei,
        maxPriorityFeePerGas: requestedPriorityWei,
        chainId: int.parse(_currentChainId!),
        to: EthereumAddress.fromHex(txParams['to'] as String),
        value: value.getInWei,
        gasLimit: gasLimit,
        data: data ?? Uint8List(0),
      );

      final txHash = await _sendRawTransaction(signedTx);
      onTransactionSent?.call(_credentials.address.with0x);
      return {'id': id, 'result': txHash};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Web3MiniAppService] Transaction error: $e');
      }
      return {'id': id, 'error': e.toString()};
    }
  }

  /// Handles explicit sign-transaction requests.
  Future<Map<String, dynamic>> _handleSignTransaction(
    dynamic id,
    Map<String, dynamic> txParams,
  ) async {
    try {
      final transaction = Transaction(
        to: EthereumAddress.fromHex(txParams['to'] as String),
        from: _credentials.address,
        value:
            txParams['value'] != null
                ? EtherAmount.fromBigInt(
                  EtherUnit.wei,
                  _parseHexBigInt(txParams['value']) ?? BigInt.zero,
                )
                : EtherAmount.zero(),
        data:
            txParams['data'] != null
                ? Uint8List.fromList(hexToBytes(txParams['data'] as String))
                : null,
      );

      final signed = await _web3Client!.signTransaction(
        _credentials,
        transaction,
      );
      return {'id': id, 'result': bytesToHex(signed, include0x: true)};
    } catch (e) {
      return {'id': id, 'error': e.toString()};
    }
  }

  /// Handles personal-sign style message signatures.
  Future<Map<String, dynamic>> _handleSign(dynamic id, List params) async {
    try {
      final message = params[0] as String;
      final messageBytes = Uint8List.fromList(hexToBytes(message));
      final signature = (_credentials as EthPrivateKey)
          .signPersonalMessageToUint8List(messageBytes);
      final signatureHex = bytesToHex(signature.toList(), include0x: true);
      return {'id': id, 'result': signatureHex};
    } catch (e) {
      return {'id': id, 'error': e.toString()};
    }
  }

  /// Manual type-2 EIP-1559 signer.
  ///
  /// We keep these internals local and heavily commented because tx encoding
  /// bugs are subtle and expensive in production.
  Future<Uint8List> _signEip1559Transaction({
    required int nonce,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    required int chainId,
    required EthereumAddress to,
    required BigInt value,
    required int gasLimit,
    required Uint8List data,
  }) async {
    final List<dynamic> txList = [
      _encodeInt(chainId),
      _encodeInt(nonce),
      _encodeBigInt(maxPriorityFeePerGas),
      _encodeBigInt(maxFeePerGas),
      _encodeInt(gasLimit),
      to.value,
      _encodeBigInt(value),
      data,
      <dynamic>[], // access list
    ];

    final encoded = _rlpEncode(txList);
    final signingPayload = Uint8List.fromList([0x02, ...encoded]);
    final hash = keccak256(signingPayload);

    final privateKey = (_credentials as EthPrivateKey).privateKey;
    final sig = sign(hash, privateKey);

    // EIP-1559 y-parity value (0 or 1), not legacy 27/28.
    final yParity = sig.v == 27 ? 0 : 1;
    final r = _padTo32(_encodeBigInt(sig.r));
    final s = _padTo32(_encodeBigInt(sig.s));

    final List<dynamic> signedList = [
      _encodeInt(chainId),
      _encodeInt(nonce),
      _encodeBigInt(maxPriorityFeePerGas),
      _encodeBigInt(maxFeePerGas),
      _encodeInt(gasLimit),
      to.value,
      _encodeBigInt(value),
      data,
      <dynamic>[],
      _encodeInt(yParity),
      r,
      s,
    ];

    final signedEncoded = _rlpEncode(signedList);
    return Uint8List.fromList([0x02, ...signedEncoded]);
  }

  Uint8List _padTo32(Uint8List bytes) {
    if (bytes.length == 32) return bytes;
    if (bytes.length > 32) return bytes.sublist(bytes.length - 32);
    final padded = Uint8List(32);
    padded.setRange(32 - bytes.length, 32, bytes);
    return padded;
  }

  Uint8List _encodeInt(int value) {
    if (value == 0) return Uint8List(0);
    final hex = value.toRadixString(16);
    final evenHex = hex.length.isOdd ? '0$hex' : hex;
    return Uint8List.fromList(hexToBytes(evenHex));
  }

  Uint8List _encodeBigInt(BigInt value) {
    if (value == BigInt.zero) return Uint8List(0);
    final hex = value.toRadixString(16);
    final evenHex = hex.length.isOdd ? '0$hex' : hex;
    return Uint8List.fromList(hexToBytes(evenHex));
  }

  Uint8List _rlpEncode(List<dynamic> items) {
    final encoded = items.map(_rlpItem).toList();
    final payload = encoded.fold<List<int>>([], (a, b) => [...a, ...b]);
    return Uint8List.fromList([
      ..._rlpLength(payload.length, 0xc0),
      ...payload,
    ]);
  }

  List<int> _rlpItem(dynamic item) {
    if (item is Uint8List || item is List<int>) {
      final bytes =
          item is Uint8List ? item : Uint8List.fromList(item as List<int>);
      if (bytes.length == 1 && bytes[0] < 0x80) return bytes;
      return [..._rlpLength(bytes.length, 0x80), ...bytes];
    } else if (item is List) {
      final encoded = item
          .map(_rlpItem)
          .fold<List<int>>([], (a, b) => [...a, ...b]);
      return [..._rlpLength(encoded.length, 0xc0), ...encoded];
    }
    throw ArgumentError('Unsupported RLP type: ${item.runtimeType}');
  }

  List<int> _rlpLength(int length, int offset) {
    if (length < 56) return [offset + length];
    final hexLen = length.toRadixString(16);
    final evenHex = hexLen.length.isOdd ? '0$hexLen' : hexLen;
    final lenBytes = hexToBytes(evenHex);
    return [offset + 55 + lenBytes.length, ...lenBytes];
  }

  BigInt _maxBigInt(BigInt a, BigInt b) => a >= b ? a : b;

  BigInt _minBigInt(BigInt a, BigInt b) => a <= b ? a : b;

  String _toRpcHex(BigInt value) => '0x${value.toRadixString(16)}';

  BigInt? _parseHexBigInt(dynamic raw) {
    if (raw == null) return null;
    final normalized = raw.toString().trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final hex = normalized.replaceFirst(RegExp(r'^0x'), '');
    if (hex.isEmpty) return BigInt.zero;
    return BigInt.parse(hex, radix: 16);
  }

  /// Release transport resources.
  void dispose() {
    _httpClient?.close();
    _httpClient = null;
    _web3Client = null;
  }
}
