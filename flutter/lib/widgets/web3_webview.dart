import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:wallet/wallet.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import 'package:pax/theming/colors.dart';
import 'package:pax/providers/local/pax_wallet_view_provider.dart';
import 'package:pax/providers/local/wallet_transactions_provider.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class Web3WebView extends ConsumerStatefulWidget {
  final String url;
  final Credentials credentials;
  final void Function(String url)? onUrlChanged;
  final void Function({required bool verified, required String chain})?
  onVerificationResult;
  final void Function(InAppWebViewController controller)? onControllerCreated;

  /// Called after a transaction is successfully sent (e.g. to refresh wallet balances).
  final void Function(String eoAddress)? onTransactionSent;

  const Web3WebView({
    super.key,
    required this.url,
    required this.credentials,
    this.onUrlChanged,
    this.onVerificationResult,
    this.onControllerCreated,
    this.onTransactionSent,
  });

  @override
  ConsumerState<Web3WebView> createState() => _Web3WebViewState();
}

class _Web3WebViewState extends ConsumerState<Web3WebView> {
  late Web3Client _web3Client;
  late Credentials _credentials;
  String? _currentAddress;
  String? _currentChainId;
  late String _rpcUrl;
  http.Client? _httpClient;
  String? _providerJavaScript;
  String? _lastPopupUrl;
  bool _isPopupShowing = false;
  InAppWebViewController? _controller;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isPageLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWeb3();
  }

  Future<void> _updateNavigationState() async {
    final controller = _controller;
    if (!mounted || controller == null) return;
    try {
      final canBack = await controller.canGoBack();
      final canForward = await controller.canGoForward();
      if (!mounted) return;
      setState(() {
        _canGoBack = canBack;
        _canGoForward = canForward;
      });
    } catch (_) {
      // Ignore navigation state errors.
    }
  }

  Future<void> _initializeWeb3() async {
    _providerJavaScript = await rootBundle.loadString(
      'assets/scripts/ethereum_provider.js',
    );

    _rpcUrl = "https://forno.celo.org";
    _httpClient = http.Client();
    _web3Client = Web3Client(_rpcUrl, _httpClient!);

    _credentials = widget.credentials;
    final address = _credentials.address;
    try {
      final chainId = await _web3Client.getChainId();
      if (mounted) {
        setState(() {
          _currentAddress = address.with0x;
          _currentChainId = chainId.toString();
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Web3WebView: Failed to fetch chainId: $e');
      }
      if (mounted) {
        setState(() {
          _currentAddress = address.with0x;
          _currentChainId = '42220';
        });
      }
    }
  }

  String get _injectedJavaScript => _providerJavaScript ?? '';

  bool _requiresUserConfirmation(String method) {
    switch (method) {
      case 'eth_sendTransaction':
      case 'eth_signTransaction':
      case 'personal_sign':
      case 'eth_sign':
        return true;
      default:
        return false;
    }
  }

  String _getConfirmationTitle(String method) {
    switch (method) {
      case 'eth_sendTransaction':
      case 'eth_signTransaction':
        return 'Approve transaction';
      case 'personal_sign':
      case 'eth_sign':
        return 'Approve message';
      default:
        return 'Confirm';
    }
  }

  String _getConfirmationBody(String method) {
    switch (method) {
      case 'eth_sendTransaction':
        return 'This app wants to send a transaction from your wallet. Only approve if you trust this app.';
      case 'eth_signTransaction':
        return 'This app wants to prepare a transaction from your wallet. Only approve if you trust this app.';
      case 'personal_sign':
      case 'eth_sign':
        return 'This app wants you to approve a message. This proves you own this wallet. Only approve if you trust this app.';
      default:
        return 'Only approve if you trust this app.';
    }
  }

  Future<bool?> _showWeb3ConfirmationDialog(String method) {
    if (!mounted) return Future.value(false);
    final completer = Completer<bool>();
    final title = _getConfirmationTitle(method);
    final body = _getConfirmationBody(method);
    openDrawer(
      context: context,
      barrierDismissible: false,
      expands: false,
      transformBackdrop: false,
      position: OverlayPosition.bottom,
      builder: (drawerContext) {
        return Container(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          color: PaxColors.deepPurple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ).withPadding(bottom: 8),
                  Divider().withPadding(top: 8, bottom: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          body,
                          style: TextStyle(
                            fontSize: 14,
                            color: PaxColors.black,
                            fontWeight: FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ).withPadding(top: 8, bottom: 32),
                  Divider().withPadding(top: 8, bottom: 8),
                ],
              ).withPadding(left: 16, right: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  SizedBox(
                    width: MediaQuery.of(drawerContext).size.width * 0.4,
                    height: 48,
                    child: Button(
                      style: const ButtonStyle.primary(),
                      onPressed: () {
                        closeDrawer(drawerContext);
                        if (!completer.isCompleted) completer.complete(false);
                      },
                      child: Text(
                        'Cancel',
                        style: Theme.of(drawerContext).typography.base.copyWith(
                          fontWeight: FontWeight.normal,
                          fontSize: 14,
                          color: PaxColors.white,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.of(drawerContext).size.width * 0.4,
                    height: 48,
                    child: Button.outline(
                      onPressed: () {
                        closeDrawer(drawerContext);
                        if (!completer.isCompleted) completer.complete(true);
                      },
                      child: Text(
                        'Approve',
                        style: Theme.of(drawerContext).typography.base.copyWith(
                          fontWeight: FontWeight.normal,
                          fontSize: 14,
                          color: PaxColors.deepPurple,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ).withPadding(bottom: 32);
      },
    );
    return completer.future;
  }

  Future<Map<String, dynamic>> _handleWeb3Request(
    Map<String, dynamic> request,
  ) async {
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
          return await _rpcPassthrough(request['id'], method, []);

        case 'eth_getBalance':
          final address = EthereumAddress.fromHex(params[0] as String);
          final balance = await _web3Client.getBalance(address);
          return {
            'id': request['id'],
            'result': '0x${balance.getInWei.toRadixString(16)}',
          };

        case 'eth_getCode':
        case 'eth_getTransactionCount':
          final address = params[0] as String;
          final blockTag = params.length > 1 ? params[1] as String? : 'latest';
          return await _rpcPassthrough(request['id'], method, [
            address,
            blockTag ?? 'latest',
          ]);

        case 'eth_estimateGas':
          final txParams = params[0] as Map<String, dynamic>;
          final blockTag = params.length > 1 ? params[1] as String? : 'latest';
          return await _rpcPassthrough(request['id'], method, [
            txParams,
            blockTag ?? 'latest',
          ]);

        case 'eth_call':
          final callParams = params[0] as Map<String, dynamic>;
          final blockTag = params.length > 1 ? params[1] as String? : 'latest';
          return await _rpcPassthrough(request['id'], method, [
            callParams,
            blockTag ?? 'latest',
          ]);

        case 'eth_getTransactionReceipt':
        case 'eth_getTransactionByHash':
          final txHash = params[0] as String;
          return await _rpcPassthrough(request['id'], method, [txHash]);

        case 'eth_sendTransaction':
          return await _handleSendTransaction(
            request['id'],
            params[0] as Map<String, dynamic>,
          );

        case 'eth_signTransaction':
          return await _handleSignTransaction(
            request['id'],
            params[0] as Map<String, dynamic>,
          );

        case 'personal_sign':
        case 'eth_sign':
          return await _handleSign(request['id'], params);

        case 'eth_signTypedData':
        case 'eth_signTypedData_v4':
          return {
            'id': request['id'],
            'error': 'SignTypedData not fully implemented',
          };

        case 'wallet_switchEthereumChain':
          return {'id': request['id'], 'result': null};

        default:
          return {'id': request['id'], 'error': 'Method $method not supported'};
      }
    } catch (e) {
      return {'id': request['id'], 'error': e.toString()};
    }
  }

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
      Uri.parse(_rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(rpcRequest),
    );
    final responseData = jsonDecode(response.body) as Map<String, dynamic>;
    if (responseData.containsKey('error')) {
      return {'id': id, 'error': responseData['error']};
    }
    return {'id': id, 'result': responseData['result']};
  }

  Future<String> _sendRawTransaction(Uint8List signedTransaction) async {
    final hexTx = bytesToHex(signedTransaction, include0x: true);

    if (kDebugMode) {
      debugPrint('[Web3WebView]: ==== TRANSACTION DEBUG ====');
      debugPrint('[Web3WebView]: Sending to: $_rpcUrl');
      debugPrint(
        '[Web3WebView]: Raw TX length: ${signedTransaction.length} bytes',
      );

      // Check transaction type from first byte
      final txType = signedTransaction[0];
      if (txType == 0x02) {
        debugPrint(
          '[Web3WebView]: ⚠️ Transaction type: EIP-1559 (Type 2) - This may not work on Celo!',
        );
      } else if (txType >= 0xc0) {
        debugPrint('[Web3WebView]: ✓ Transaction type: Legacy (RLP encoded)');
      } else {
        debugPrint(
          '[Web3WebView]: Transaction type byte: 0x${txType.toRadixString(16)}',
        );
      }

      debugPrint('[Web3WebView]: Full signed TX: $hexTx');
    }

    final rpcRequest = {
      'jsonrpc': '2.0',
      'method': 'eth_sendRawTransaction',
      'params': [hexTx],
      'id': 1,
    };

    final response = await _httpClient!.post(
      Uri.parse(_rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(rpcRequest),
    );

    if (kDebugMode) {
      debugPrint('[Web3WebView]: RPC response status: ${response.statusCode}');
      debugPrint('[Web3WebView]: RPC response body: ${response.body}');
    }

    final responseData = jsonDecode(response.body) as Map<String, dynamic>;

    if (responseData.containsKey('error')) {
      final error = responseData['error'];
      final errorMessage =
          error is Map
              ? (error['message'] ?? error.toString())
              : error.toString();

      if (kDebugMode) {
        debugPrint('[Web3WebView]: ❌ RPC error: $errorMessage');
      }

      throw Exception('RPC Error: $errorMessage');
    }

    final txHash = responseData['result'] as String;

    if (kDebugMode) {
      debugPrint('[Web3WebView]: ✓ TX hash: $txHash');
      debugPrint('[Web3WebView]: Check: https://celoscan.io/tx/$txHash');
      debugPrint('Web3WebView: ==========================');
    }

    return txHash;
  }

  Future<Map<String, dynamic>> _handleSendTransaction(
    dynamic id,
    Map<String, dynamic> txParams,
  ) async {
    try {
      // Check CELO balance
      final celoBalance = await _web3Client.getBalance(_credentials.address);
      if (celoBalance.getInWei < BigInt.from(10000000000000000)) {
        return {
          'id': id,
          'error':
              'Insufficient CELO balance. Need ~0.01 CELO to process transactions.',
        };
      }

      // Get nonce
      final nonce = await _web3Client.getTransactionCount(
        _credentials.address,
        atBlock: const BlockNum.pending(),
      );

      // Get gas price - don't bump it too high
      final baseGasPrice = await _web3Client.getGasPrice();
      final gasPrice = EtherAmount.inWei(
        (baseGasPrice.getInWei * BigInt.from(110)) ~/
            BigInt.from(100), // Only 10% bump
      );

      // Parse value
      final value =
          txParams['value'] != null
              ? EtherAmount.fromBigInt(
                EtherUnit.wei,
                BigInt.parse(
                  (txParams['value'] as String).replaceFirst('0x', ''),
                  radix: 16,
                ),
              )
              : EtherAmount.zero();

      // Parse data
      final data =
          txParams['data'] != null
              ? Uint8List.fromList(hexToBytes(txParams['data'] as String))
              : null;

      // Get gas limit
      int? maxGas;
      if (txParams['gas'] != null) {
        maxGas = int.parse(
          (txParams['gas'] as String).replaceFirst('0x', ''),
          radix: 16,
        );
      }

      final transaction = Transaction(
        to: EthereumAddress.fromHex(txParams['to'] as String),
        from: _credentials.address,
        value: value,
        data: data,
        maxGas: maxGas,
        gasPrice: gasPrice,
        nonce: nonce,
      );

      if (kDebugMode) {
        debugPrint('[Web3WebView]: Creating transaction:');
        debugPrint('[Web3WebView]: Nonce: $nonce');
        debugPrint('[Web3WebView]: Gas: $maxGas');
        debugPrint('[Web3WebView]: Gas Price: ${gasPrice.getInWei}');
      }

      // Sign transaction
      final signedTx = await _web3Client.signTransaction(
        _credentials,
        transaction,
        chainId: int.parse(_currentChainId!),
      );

      // Send transaction
      final txHash = await _sendRawTransaction(signedTx);

      // Refresh wallet balances and transactions. Use parent callback when set so
      // refresh runs with the correct ref; also refresh both providers here so
      // transactions always update after a send. Balance refreshes immediately;
      // transaction refresh is delayed so the chain/indexer can include the new tx.
      final eoAddress = _credentials.address.with0x;
      if (mounted) {
        ref
            .read(paxWalletViewProvider.notifier)
            .fetchBalance(eoAddress, forceRefresh: true);
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          ref.read(walletTransactionsProvider.notifier).refresh(eoAddress);
        });
        if (widget.onTransactionSent != null) {
          widget.onTransactionSent!(eoAddress);
        }
      }

      return {'id': id, 'result': txHash};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Web3WebView: Transaction error: $e');
      }
      return {'id': id, 'error': e.toString()};
    }
  }

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
                  BigInt.parse(
                    (txParams['value'] as String).replaceFirst('0x', ''),
                    radix: 16,
                  ),
                )
                : EtherAmount.zero(),
        data:
            txParams['data'] != null
                ? Uint8List.fromList(hexToBytes(txParams['data'] as String))
                : null,
      );

      final signed = await _web3Client.signTransaction(
        _credentials,
        transaction,
      );
      return {'id': id, 'result': bytesToHex(signed, include0x: true)};
    } catch (e) {
      return {'id': id, 'error': e.toString()};
    }
  }

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

  Future<void> _injectWeb3Provider(InAppWebViewController controller) async {
    if (_currentAddress == null ||
        _currentChainId == null ||
        _providerJavaScript == null) {
      return;
    }

    try {
      final chainIdHex = '0x${int.parse(_currentChainId!).toRadixString(16)}';

      await controller.evaluateJavascript(source: _injectedJavaScript);

      await controller.evaluateJavascript(
        source: '''
        (function() {
          if (window.ethereum && window.ethereum.isFlutterWeb3) {
            try {
              Object.defineProperty(window.ethereum, 'selectedAddress', {
                value: '$_currentAddress',
                writable: false, configurable: true, enumerable: true
              });
            } catch (e) { window.ethereum.selectedAddress = '$_currentAddress'; }
            try {
              Object.defineProperty(window.ethereum, 'chainId', {
                value: '$chainIdHex',
                writable: false, configurable: true, enumerable: true
              });
            } catch (e) { window.ethereum.chainId = '$chainIdHex'; }
            window.ethereum.networkVersion = '$_currentChainId';
            setTimeout(() => {
              window.ethereum._emit('connect', { chainId: '$chainIdHex' });
            }, 100);
            window.PaxWallet = window.ethereum;
            try {
              Object.defineProperty(window, 'ethereum', {
                value: window.ethereum,
                writable: false, configurable: false, enumerable: true
              });
            } catch (e) {}
          }
        })();
      ''',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Web3WebView]: Error injecting provider: $e');
      }
    }
  }

  static String? _decodeBase64Param(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final decoded = Uri.decodeComponent(value);
      return utf8.decode(base64Decode(decoded));
    } catch (_) {
      try {
        return utf8.decode(base64Decode(value));
      } catch (_) {
        return value;
      }
    }
  }

  ({bool verified, String chain})? _parseVerifiedAndChainParams(
    String? urlString,
  ) {
    if (urlString == null) return null;
    try {
      final uri = Uri.parse(urlString);
      final queryParams = uri.queryParameters;
      final verifiedRaw = queryParams['verified'];
      final chainRaw = queryParams['chain'];
      if (verifiedRaw == null || chainRaw == null) return null;
      final verifiedStr = _decodeBase64Param(verifiedRaw) ?? verifiedRaw;
      final chainStr = _decodeBase64Param(chainRaw) ?? chainRaw;
      final verified = verifiedStr.toLowerCase() == 'true';
      return (verified: verified, chain: chainStr);
    } catch (_) {
      return null;
    }
  }

  void _checkUrlForVerificationParams(String? urlString) {
    if (urlString == null) return;
    widget.onUrlChanged?.call(urlString);

    final parsed = _parseVerifiedAndChainParams(urlString);
    if (parsed != null && !_isPopupShowing && _lastPopupUrl != urlString) {
      _lastPopupUrl = urlString;
      _isPopupShowing = true;
      widget.onVerificationResult?.call(
        verified: parsed.verified,
        chain: parsed.chain,
      );
      _isPopupShowing = false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    _httpClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show bottom nav bar from first frame so it doesn't pop in after _initializeWeb3().
    final Widget content;
    if (_currentAddress == null) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      final webview = InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          allowsInlineMediaPlayback: true,
          mediaPlaybackRequiresUserGesture: false,
        ),
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: _injectedJavaScript,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        onWebViewCreated: (controller) {
          _controller = controller;
          widget.onControllerCreated?.call(controller);
          controller.addJavaScriptHandler(
            handlerName: 'web3Request',
            callback: (args) async {
              dynamic requestId;
              Map<String, dynamic>? responseToSend;
              try {
                final request = args[0] as Map<String, dynamic>;
                requestId = request['id'];
                final method = request['method'] as String?;
                if (method != null && _requiresUserConfirmation(method)) {
                  if (!mounted) {
                    responseToSend = {
                      'id': requestId,
                      'error': 'User rejected the request',
                    };
                  } else {
                    final approved = await _showWeb3ConfirmationDialog(method);
                    if (approved != true) {
                      responseToSend = {
                        'id': requestId,
                        'error': 'User rejected the request',
                      };
                    }
                  }
                }

                if (responseToSend == null) {
                  final response = await _handleWeb3Request(request);
                  responseToSend = Map<String, dynamic>.from(response);
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('[Web3WebView]: Error handling web3 request: $e');
                }
                responseToSend = {
                  'id': requestId,
                  'error': e is Exception ? e.toString() : 'Unknown error',
                };
              } finally {
                if (responseToSend != null) {
                  try {
                    await controller.evaluateJavascript(
                      source:
                          'window.handleWeb3Response(${jsonEncode(responseToSend)})',
                    );
                  } catch (e) {
                    if (kDebugMode) {
                      debugPrint(
                        '[Web3WebView]: Failed to send response to page: $e',
                      );
                    }
                  }
                }
              }
            },
          );
          _updateNavigationState();
        },
        onLoadStart: (controller, url) async {
          if (mounted) setState(() => _isPageLoading = true);
          _checkUrlForVerificationParams(url?.toString());
          await _injectWeb3Provider(controller);
          _updateNavigationState();
        },
        onLoadStop: (controller, url) async {
          _checkUrlForVerificationParams(url?.toString());
          await _injectWeb3Provider(controller);
          _updateNavigationState();
          if (mounted) setState(() => _isPageLoading = false);
        },
      );

      content = Stack(
        children: [
          webview,
          if (_isPageLoading)
            Positioned.fill(
              child: Container(
                color: PaxColors.white,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      );
    }

    return SafeArea(
      top: false,
      bottom: true,
      left: false,
      right: false,
      child: Column(
        children: [
          Expanded(child: content),
          const Divider(height: 1).withPadding(bottom: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: PaxColors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton.outline(
                      onPressed:
                          _canGoBack && _controller != null
                              ? () {
                                _controller?.goBack();
                                _updateNavigationState();
                              }
                              : null,
                      density: ButtonDensity.icon,
                      variance: const ButtonStyle.outline(
                        density: ButtonDensity.icon,
                      ),
                      icon: const FaIcon(
                        FontAwesomeIcons.chevronLeft,
                        size: 22,
                        color: PaxColors.deepPurple,
                      ),
                    ),
                    IconButton.outline(
                      onPressed:
                          _controller != null
                              ? () {
                                _controller?.reload();
                                _updateNavigationState();
                              }
                              : null,
                      density: ButtonDensity.icon,
                      variance: const ButtonStyle.outline(
                        density: ButtonDensity.icon,
                      ),
                      icon: const FaIcon(
                        FontAwesomeIcons.arrowsRotate,
                        size: 22,
                        color: PaxColors.deepPurple,
                      ),
                    ),
                    IconButton.outline(
                      onPressed:
                          _canGoForward && _controller != null
                              ? () {
                                _controller?.goForward();
                                _updateNavigationState();
                              }
                              : null,
                      density: ButtonDensity.icon,
                      variance: const ButtonStyle.outline(
                        density: ButtonDensity.icon,
                      ),
                      icon: const FaIcon(
                        FontAwesomeIcons.chevronRight,
                        size: 22,
                        color: PaxColors.deepPurple,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
