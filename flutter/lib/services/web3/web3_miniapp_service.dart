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
  /// Default public RPC endpoint used when remote config does not supply one.
  static final String _rpcUrl =
      'https://lb.drpc.live/celo/${Env.drpcRpcApiKey}';

  Web3MiniAppService({
    required Credentials credentials,
    required Map<String, dynamic> paxWalletConfig,
    String? rpcUrl,
  }) : _credentials = credentials,
       _paxWalletConfig = paxWalletConfig,
       _defaultRpcUrl = rpcUrl ?? _rpcUrl;

  /// Active signing key for all wallet-authorized operations.
  final Credentials _credentials;
  /// Remote-config payload used to tune chain/rpc behavior.
  final Map<String, dynamic> _paxWalletConfig;
  /// Constructor-provided fallback RPC URL.
  final String _defaultRpcUrl;
  /// Effective RPC URL chosen during [initialize].
  String? _resolvedRpcUrl;

  /// Shared HTTP transport reused by all JSON-RPC calls.
  http.Client? _httpClient;
  /// web3dart facade used for convenience chain/wallet helpers.
  Web3Client? _web3Client;
  /// Cached account exposed to injected provider.
  String? _currentAddress;
  /// Cached decimal chain id exposed through provider methods.
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
    // Remote config can deserialize numbers with varying runtime types.
    final dynamic rawChainId = config[RemoteConfigKeys.chainId];
    if (rawChainId is int) return rawChainId;
    if (rawChainId is num) return rawChainId.toInt();
    if (rawChainId is String) return int.tryParse(rawChainId) ?? 42220;
    return 42220;
  }

  /// Reads `rpc_url` from `pax_wallet_config`; defaults to constructor RPC URL.
  String _resolveRpcUrl(Map<String, dynamic> config) {
    // Debug override always wins to simplify local troubleshooting.
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
          // Single-account embedded wallet behavior.
          return {
            'id': request['id'],
            'result': [_currentAddress],
          };

        case 'eth_chainId':
          // EIP-1193 expects chain id in hex quantity format.
          return {
            'id': request['id'],
            'result': '0x${int.parse(_currentChainId!).toRadixString(16)}',
          };

        case 'eth_blockNumber':
        case 'eth_gasPrice':
          // Pure node reads are forwarded unchanged.
          return _rpcPassthrough(request['id'], method, []);

        case 'eth_getBalance':
          if (params.isEmpty) {
            return {'id': request['id'], 'error': 'Missing address parameter'};
          }
          final address = EthereumAddress.fromHex(params[0] as String);
          final balance = await _web3Client!.getBalance(address);
          return {
            'id': request['id'],
            // JS callers expect hex quantities for wei amounts.
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
          // Signs locally, then broadcasts raw transaction bytes.
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
          // Signs transaction payload only (no broadcast).
          return _handleSignTransaction(
            request['id'],
            Map<String, dynamic>.from(params[0] as Map),
          );

        case 'personal_sign':
        case 'eth_sign':
          // Message-signing methods that use the currently loaded key.
          return _handleSign(request['id'], params);

        case 'eth_signTypedData':
        case 'eth_signTypedData_v4':
          // Structured-data signatures for EIP-712 flows.
          return _handleSignTypedData(request['id'], params, method);

        case 'wallet_switchEthereumChain':
          // Not switching yet; we only expose Celo mainnet currently.
          return {'id': request['id'], 'result': null};

        case 'wallet_getCapabilities':
        case 'getCapabilities':
          // Capability discovery call used by some wallet SDKs.
          return _handleGetCapabilities(request['id']);

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

  Future<Map<String, dynamic>> _handleGetCapabilities(dynamic id) async {
    final chainId = _currentChainId ?? '42220';
    final chainIdHex = '0x${int.parse(chainId).toRadixString(16)}';
    // Basic EIP-1193 capability surface; extensions can be added later.
    return {
      'id': id,
      'result': {chainIdHex: <String, dynamic>{}},
    };
  }

  /// Forwards simple RPC methods to the upstream node.
  ///
  /// This keeps method support broad without re-implementing every RPC.
  Future<Map<String, dynamic>> _rpcPassthrough(
    dynamic id,
    String method,
    List<dynamic> params,
  ) async {
    // Wrapper `id` is managed by caller response; inner node id is arbitrary.
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
      // Keep original node error object so UI/dApp can inspect code/data.
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
      // High-level flow for a dApp "send transaction" request:
      // 1) Resolve nonce/value/data/gas + fees.
      // 2) Validate the user can actually afford the tx envelope.
      // 3) Build and sign a type-2 transaction locally.
      // 4) Submit via `eth_sendRawTransaction`.
      //
      // We do this manually (instead of web3dart default helpers) so behavior is
      // deterministic across different dApp payload styles.
      // Use pending nonce so parallel approvals don't reuse mined-only nonce.
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
      // Example: if baseFee = 3 gwei and tip = 2 gwei, maxFee must be >= 5 gwei.
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
        // Respect explicit dApp-provided gas limit.
        gasLimit = int.parse(
          (txParams['gas'] as String).replaceFirst('0x', ''),
          radix: 16,
        );
      } else {
        try {
          // Otherwise, ask RPC node for an estimate against latest state.
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
      //
      // Why both checks:
      // - "estimatedTotalCostWei" approximates what user will likely pay.
      // - "maxEnvelopeCostWei" is what node may require the sender to afford
      //   up front because maxFeePerGas is a ceiling.
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
        final protocolMinMaxFeeWei = _maxBigInt(
          minRequiredWei,
          requestedPriorityWei,
        );
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

      final estimatedGasFeeWei = likelyEffectiveGasPriceWei * gasLimitWei;
      final estimatedTotalCostWei = valueWei + estimatedGasFeeWei;
      final maxEnvelopeCostWei =
          valueWei + (finalMaxFeePerGasWei * gasLimitWei);
      if (celoBalance.getInWei < estimatedTotalCostWei ||
          celoBalance.getInWei < maxEnvelopeCostWei) {
        final requiredWei = _maxBigInt(
          estimatedTotalCostWei,
          maxEnvelopeCostWei,
        );
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
      // Bubble success to UI so it can refresh balances/history.
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
      // Build unsigned tx object from incoming JSON-RPC payload.
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
      // Return signed payload only; caller chooses where to broadcast.
      return {'id': id, 'result': bytesToHex(signed, include0x: true)};
    } catch (e) {
      return {'id': id, 'error': e.toString()};
    }
  }

  /// Handles personal-sign style message signatures.
  Future<Map<String, dynamic>> _handleSign(dynamic id, List params) async {
    try {
      // personal_sign payload is expected to be hex bytes.
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

  /// Handles EIP-712 typed-data signatures (eth_signTypedData / eth_signTypedData_v4).
  ///
  /// Implements the full EIP-712 encoding:
  ///   sign( keccak256( 0x1901 ‖ domainSeparator ‖ hashStruct(message) ) )
  ///
  /// In plain words: we do NOT sign the raw JSON string. We transform the typed
  /// data into a canonical binary digest first, then sign that digest.
  Future<Map<String, dynamic>> _handleSignTypedData(
    dynamic id,
    List params,
    String method,
  ) async {
    try {
      if (params.length < 2) {
        return {
          'id': id,
          'error':
              '$method requires [address, typedData] or [typedData, address].',
        };
      }

      // Normalise param order: MetaMask sends [address, typedDataString],
      // some dApps send [typedData, address].
      final first = params[0];
      final second = params[1];
      final firstString = first?.toString() ?? '';
      final secondString = second?.toString() ?? '';
      final addressRe = RegExp(r'^0x[a-fA-F0-9]{40}$');
      final firstIsAddress = addressRe.hasMatch(firstString);

      final signerAddress = firstIsAddress ? firstString : secondString;
      if (signerAddress.toLowerCase() !=
          _credentials.address.with0x.toLowerCase()) {
        return {
          'id': id,
          'error':
              'Signer mismatch: requested $signerAddress, '
              'wallet is ${_credentials.address.with0x}.',
        };
      }

      final typedDataRaw = firstIsAddress ? second : first;
      final Map<String, dynamic> typedData;
      try {
        if (typedDataRaw is Map) {
          typedData = Map<String, dynamic>.from(typedDataRaw);
        } else {
          typedData =
              jsonDecode(typedDataRaw.toString()) as Map<String, dynamic>;
        }
      } catch (_) {
        return {'id': id, 'error': 'Could not parse typed data JSON.'};
      }

      final digest = _eip712Digest(typedData);

      // The returned signature shape is 65 bytes: r (32) + s (32) + v (1).
      // This is what most JS wallets return for signTypedData.
      final sig = sign(digest, (_credentials as EthPrivateKey).privateKey);
      final r = _padTo32(_encodeBigInt(sig.r));
      final s = _padTo32(_encodeBigInt(sig.s));
      // EIP-712 uses 27/28 for v (legacy parity), same as personal_sign.
      final v = Uint8List.fromList([sig.v]);
      final signature = Uint8List.fromList([...r, ...s, ...v]);

      return {'id': id, 'result': bytesToHex(signature, include0x: true)};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Web3MiniAppService] signTypedData error: $e');
      }
      return {'id': id, 'error': e.toString()};
    }
  }

  /// Produces the 32-byte EIP-712 signing digest:
  ///   keccak256( 0x1901 ‖ domainSeparator ‖ hashStruct(primaryType) )
  Uint8List _eip712Digest(Map<String, dynamic> typedData) {
    // Extract typed-data envelope fields as defined by EIP-712.
    final types = typedData['types'] as Map<String, dynamic>;
    final domain = typedData['domain'] as Map<String, dynamic>;
    final primaryType = typedData['primaryType'] as String;
    final message = typedData['message'] as Map<String, dynamic>;

    // Normalize the type map so every downstream helper works with one shape:
    //   Map<String, List<Map<String, dynamic>>>
    final allTypes = types.map(
      (k, v) => MapEntry(k, (v as List).cast<Map<String, dynamic>>()),
    );

    final domainSeparator = _hashStruct('EIP712Domain', domain, allTypes);
    final messageHash = _hashStruct(primaryType, message, allTypes);

    final payload = Uint8List(2 + 32 + 32);
    payload[0] = 0x19;
    payload[1] = 0x01;
    payload.setRange(2, 34, domainSeparator);
    payload.setRange(34, 66, messageHash);
    return keccak256(payload);
  }

  /// keccak256( typeHash ‖ encodeData(typeName, value, types) )
  Uint8List _hashStruct(
    String typeName,
    Map<String, dynamic> value,
    Map<String, List<Map<String, dynamic>>> types,
  ) {
    final typeHash = _typeHash(typeName, types);
    final encoded = _encodeData(typeName, value, types);
    final payload = Uint8List(32 + encoded.length);
    payload.setRange(0, 32, typeHash);
    payload.setRange(32, payload.length, encoded);
    return keccak256(payload);
  }

  /// keccak256 of the canonical type string, e.g.
  ///   "Mail(address from,address to,string contents)"
  Uint8List _typeHash(
    String typeName,
    Map<String, List<Map<String, dynamic>>> types,
  ) {
    final typeString = _encodeType(typeName, types);
    return keccak256(Uint8List.fromList(utf8.encode(typeString)));
  }

  /// Builds the canonical type string including referenced struct types.
  String _encodeType(
    String typeName,
    Map<String, List<Map<String, dynamic>>> types,
  ) {
    final fields = types[typeName] ?? [];
    // Collect referenced struct types (sorted, appended after primary).
    final deps = <String>{};
    for (final f in fields) {
      final baseType = _baseType(f['type'] as String);
      if (types.containsKey(baseType) && baseType != typeName) {
        deps.add(baseType);
      }
    }
    final sortedDeps = deps.toList()..sort();

    String buildOne(String name) {
      final fs = types[name] ?? [];
      final params = fs.map((f) => '${f['type']} ${f['name']}').join(',');
      return '$name($params)';
    }

    return ([typeName, ...sortedDeps]).map(buildOne).join('');
  }

  /// ABI-encodes the fields of a struct value according to EIP-712 rules.
  Uint8List _encodeData(
    String typeName,
    Map<String, dynamic> value,
    Map<String, List<Map<String, dynamic>>> types,
  ) {
    final fields = types[typeName] ?? [];
    final chunks = <Uint8List>[];

    for (final field in fields) {
      final name = field['name'] as String;
      final type = field['type'] as String;
      final fieldValue = value[name];
      chunks.add(_encodeField(type, fieldValue, types));
    }

    // Each field encodes to one 32-byte word; concatenate in declaration order.
    final result = Uint8List(chunks.length * 32);
    for (var i = 0; i < chunks.length; i++) {
      result.setRange(i * 32, (i + 1) * 32, chunks[i]);
    }
    return result;
  }

  /// Encodes a single field value to a 32-byte word per EIP-712.
  Uint8List _encodeField(
    String type,
    dynamic value,
    Map<String, List<Map<String, dynamic>>> types,
  ) {
    // For newcomers:
    // - Static scalar types (uint256, address, bool, bytes32) become one 32-byte word.
    // - Dynamic types (string, bytes, arrays, structs) are represented by hashes.
    // This mirrors EIP-712 / ABI rules and makes signatures deterministic.

    // Struct reference → recursive hashStruct.
    final baseType = _baseType(type);
    if (types.containsKey(baseType)) {
      if (type.endsWith(']')) {
        // Array of structs → keccak256 of concatenated hashStructs.
        final list = value as List;
        final hashes =
            list
                .map(
                  (item) => _hashStruct(
                    baseType,
                    Map<String, dynamic>.from(item as Map),
                    types,
                  ),
                )
                .expand((b) => b)
                .toList();
        return keccak256(Uint8List.fromList(hashes));
      }
      return _hashStruct(
        baseType,
        Map<String, dynamic>.from(value as Map),
        types,
      );
    }

    // Dynamic types → keccak256 of content.
    if (type == 'string') {
      return keccak256(
        Uint8List.fromList(utf8.encode(value?.toString() ?? '')),
      );
    }
    if (type == 'bytes') {
      final raw = _hexOrUtf8Bytes(value);
      return keccak256(raw);
    }

    // bytesN values are right-padded to fill a 32-byte slot.
    if (type.startsWith('bytes')) {
      final raw = _hexOrUtf8Bytes(value);
      final padded = Uint8List(32);
      padded.setRange(0, raw.length.clamp(0, 32), raw);
      return padded;
    }

    // Boolean.
    if (type == 'bool') {
      final padded = Uint8List(32);
      padded[31] = (value == true || value == 1 || value == '1') ? 1 : 0;
      return padded;
    }

    // address → 20 bytes right-aligned in 32.
    if (type == 'address') {
      final hex = value.toString().replaceFirst('0x', '');
      final addrBytes = hexToBytes(hex);
      final padded = Uint8List(32);
      padded.setRange(12, 32, addrBytes);
      return padded;
    }

    // uintN / intN -> big-endian integer padded to 32-byte word.
    if (type.startsWith('uint') || type.startsWith('int')) {
      BigInt bigVal;
      if (value is BigInt) {
        bigVal = value;
      } else if (value is int) {
        bigVal = BigInt.from(value);
      } else {
        final s = value.toString().trim();
        bigVal =
            s.startsWith('0x')
                ? BigInt.parse(s.substring(2), radix: 16)
                : BigInt.parse(s);
      }
      return _padTo32(_encodeBigInt(bigVal));
    }

    // Fallback: hash unknown types as raw bytes for deterministic behavior.
    final raw = _hexOrUtf8Bytes(value);
    return keccak256(raw);
  }

  /// Strips the array suffix to get the base type name, e.g. "Foo[]" → "Foo".
  String _baseType(String type) => type.replaceAll(RegExp(r'\[.*\]$'), '');

  /// Converts a hex string or arbitrary value to bytes.
  Uint8List _hexOrUtf8Bytes(dynamic value) {
    if (value == null) return Uint8List(0);
    final s = value.toString().trim();
    if (s.startsWith('0x')) {
      return Uint8List.fromList(hexToBytes(s.substring(2)));
    }
    try {
      return Uint8List.fromList(hexToBytes(s));
    } catch (_) {
      return Uint8List.fromList(utf8.encode(s));
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
    // Another plain-language summary:
    // - Build unsigned tx fields.
    // - RLP-encode those fields.
    // - Prefix type byte 0x02 and hash.
    // - Sign hash with private key.
    // - Append signature fields and RLP again to produce final raw tx.

    // Unsigned tx payload for type-2 transactions (without signature fields).
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
    // Type byte 0x02 is part of the signed payload per EIP-1559.
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
    // Final raw tx bytes are [typeByte + signedRlp].
    return Uint8List.fromList([0x02, ...signedEncoded]);
  }

  /// Left-pad or trim bytes to exactly 32 bytes.
  Uint8List _padTo32(Uint8List bytes) {
    if (bytes.length == 32) return bytes;
    if (bytes.length > 32) return bytes.sublist(bytes.length - 32);
    final padded = Uint8List(32);
    padded.setRange(32 - bytes.length, 32, bytes);
    return padded;
  }

  /// Encodes [int] as minimal big-endian byte array.
  Uint8List _encodeInt(int value) {
    if (value == 0) return Uint8List(0);
    final hex = value.toRadixString(16);
    final evenHex = hex.length.isOdd ? '0$hex' : hex;
    return Uint8List.fromList(hexToBytes(evenHex));
  }

  /// Encodes [BigInt] as minimal big-endian byte array.
  Uint8List _encodeBigInt(BigInt value) {
    if (value == BigInt.zero) return Uint8List(0);
    final hex = value.toRadixString(16);
    final evenHex = hex.length.isOdd ? '0$hex' : hex;
    return Uint8List.fromList(hexToBytes(evenHex));
  }

  /// RLP-encodes a list payload.
  Uint8List _rlpEncode(List<dynamic> items) {
    final encoded = items.map(_rlpItem).toList();
    final payload = encoded.fold<List<int>>([], (a, b) => [...a, ...b]);
    return Uint8List.fromList([
      ..._rlpLength(payload.length, 0xc0),
      ...payload,
    ]);
  }

  /// RLP-encodes one item (bytes or nested list).
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

  /// Computes RLP length prefix for strings/lists.
  List<int> _rlpLength(int length, int offset) {
    if (length < 56) return [offset + length];
    final hexLen = length.toRadixString(16);
    final evenHex = hexLen.length.isOdd ? '0$hexLen' : hexLen;
    final lenBytes = hexToBytes(evenHex);
    return [offset + 55 + lenBytes.length, ...lenBytes];
  }

  /// Returns the larger value.
  BigInt _maxBigInt(BigInt a, BigInt b) => a >= b ? a : b;

  /// Returns the smaller value.
  BigInt _minBigInt(BigInt a, BigInt b) => a <= b ? a : b;

  /// Converts a wei amount to RPC hex quantity format.
  String _toRpcHex(BigInt value) => '0x${value.toRadixString(16)}';

  /// Parses a 0x-prefixed (or plain) hex number into BigInt.
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
