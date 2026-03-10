import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet/wallet.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import 'package:pax/env/env.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class FaceVerificationWebView extends ConsumerStatefulWidget {
  final Credentials credentials;
  final void Function({required bool verified, required String chain})
  onVerificationResult;

  const FaceVerificationWebView({
    super.key,
    required this.credentials,
    required this.onVerificationResult,
  });

  @override
  ConsumerState<FaceVerificationWebView> createState() =>
      _FaceVerificationWebViewState();
}

class _FaceVerificationWebViewState
    extends ConsumerState<FaceVerificationWebView> {
  static const String _verificationUrl =
      'https://thegoodpax.app/verify-identity';

  late Web3Client _web3Client;
  late Credentials _credentials;
  String? _currentAddress;
  String? _currentChainId;
  late String _rpcUrl;
  late http.Client _httpClient;
  String? _providerJavaScript;
  String? _lastPopupUrl;
  Timer? _popupTimer;
  bool _isPopupShowing = false;
  InAppWebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _initializeWeb3();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera].request();
  }

  Future<void> _initializeWeb3() async {
    _providerJavaScript = await rootBundle.loadString(
      'assets/scripts/ethereum_provider.js',
    );

    _rpcUrl = 'https://lb.drpc.live/celo/${Env.drpcAPIKey}';
    _httpClient = http.Client();
    _web3Client = Web3Client(_rpcUrl, _httpClient);

    _credentials = widget.credentials;
    final address = _credentials.address;
    final chainId = await _web3Client.getChainId();

    if (mounted) {
      setState(() {
        _currentAddress = address.with0x;
        _currentChainId = chainId.toString();
      });
    }
  }

  String get _injectedJavaScript => _providerJavaScript ?? '';

  // ---------------------------------------------------------------------------
  // Web3 RPC handling
  // ---------------------------------------------------------------------------

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
    final response = await _httpClient.post(
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

  Future<Map<String, dynamic>> _handleSendTransaction(
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
        maxGas:
            txParams['gas'] != null
                ? int.parse(
                  (txParams['gas'] as String).replaceFirst('0x', ''),
                  radix: 16,
                )
                : null,
      );

      final txHash = await _web3Client.sendTransaction(
        _credentials,
        transaction,
        chainId: int.parse(_currentChainId!),
      );

      return {'id': id, 'result': txHash};
    } catch (e) {
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

  // ---------------------------------------------------------------------------
  // Provider injection
  // ---------------------------------------------------------------------------

  Future<void> _injectWeb3Provider(InAppWebViewController controller) async {
    if (!mounted) return;
    if (_currentAddress == null ||
        _currentChainId == null ||
        _providerJavaScript == null) {
      return;
    }

    try {
      final chainIdHex = '0x${int.parse(_currentChainId!).toRadixString(16)}';

      await controller.evaluateJavascript(source: _injectedJavaScript);
      if (!mounted) return;

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
      if (mounted) {
        if (kDebugMode) {
          debugPrint('FaceVerificationWebView: Error injecting provider: $e');
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Redirect / verification-result parsing (ported from pax_v2)
  // ---------------------------------------------------------------------------

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

  void _fireVerificationResult({
    required bool verified,
    required String chain,
    String? urlForTracking,
  }) {
    if (!mounted || _isPopupShowing) return;

    _isPopupShowing = true;
    if (urlForTracking != null) {
      _lastPopupUrl = urlForTracking;
    }

    widget.onVerificationResult(verified: verified, chain: chain);

    _isPopupShowing = false;
  }

  /// Schedules verification-result delivery after [delay], with guards against
  /// duplicate firing. Mirrors the timer-based dedup pattern from pax_v2.
  void _scheduleVerificationCallback({
    required ({bool verified, String chain}) parsed,
    required String urlString,
    required WebUri? currentWebUri,
    required Duration delay,
  }) {
    _popupTimer?.cancel();
    _popupTimer = Timer(delay, () {
      if (!mounted) return;
      if (urlString != currentWebUri?.toString()) return;
      if (_isPopupShowing) return;
      if (_lastPopupUrl == urlString) return;

      _fireVerificationResult(
        verified: parsed.verified,
        chain: parsed.chain,
        urlForTracking: urlString,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    _popupTimer?.cancel();
    _httpClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentAddress == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_verificationUrl)),
      initialSettings: InAppWebViewSettings(
        domStorageEnabled: true,
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: false,
        useHybridComposition: false,
        hardwareAcceleration: false,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: _injectedJavaScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'web3Request',
          callback: (args) async {
            if (!mounted) return;
            try {
              final request = args[0] as Map<String, dynamic>;
              final response = await _handleWeb3Request(request);
              if (!mounted) return;
              await controller.evaluateJavascript(
                source: 'window.handleWeb3Response(${jsonEncode(response)})',
              );
            } catch (e) {
              if (mounted) {
                if (kDebugMode) {
                  debugPrint(
                    'FaceVerificationWebView: Error handling web3 request: $e',
                  );
                }
              }
            }
          },
        );
      },

      shouldOverrideUrlLoading: (controller, navigationAction) async {
        if (!mounted) return NavigationActionPolicy.CANCEL;
        return NavigationActionPolicy.ALLOW;
      },

      // --- onLoadStart: early redirect detection with 800 ms timer ----------
      onLoadStart: (controller, url) async {
        if (!mounted) return;
        final urlString = url?.toString();

        if (urlString != null) {
          final hasParams = _parseVerifiedAndChainParams(urlString) != null;
          if (!hasParams && _lastPopupUrl != null) {
            _lastPopupUrl = null;
          }
        }

        if (urlString != null) {
          final parsed = _parseVerifiedAndChainParams(urlString);
          if (parsed != null) {
            _popupTimer?.cancel();

            if (_lastPopupUrl != null && _lastPopupUrl != urlString) {
              _lastPopupUrl = null;
            }

            if (_lastPopupUrl != urlString && !_isPopupShowing) {
              _scheduleVerificationCallback(
                parsed: parsed,
                urlString: urlString,
                currentWebUri: url,
                delay: const Duration(milliseconds: 800),
              );
            }
          }
        }

        try {
          await _injectWeb3Provider(controller);
        } catch (_) {}

        Future.delayed(const Duration(milliseconds: 100), () async {
          if (!mounted) return;
          try {
            await _injectWeb3Provider(controller);
          } catch (_) {}
        });
      },

      // --- onLoadStop: final redirect detection with 500 ms timer -----------
      onLoadStop: (controller, url) async {
        if (!mounted) return;
        final urlString = url?.toString();

        _popupTimer?.cancel();
        _popupTimer = null;

        final parsed = _parseVerifiedAndChainParams(urlString);
        if (parsed != null) {
          if (_lastPopupUrl != null && _lastPopupUrl != urlString) {
            _lastPopupUrl = null;
          }

          if (_lastPopupUrl != urlString && !_isPopupShowing) {
            _scheduleVerificationCallback(
              parsed: parsed,
              urlString: urlString!,
              currentWebUri: url,
              delay: const Duration(milliseconds: 500),
            );
          }
        } else {
          _lastPopupUrl = null;
        }

        try {
          await _injectWeb3Provider(controller);
        } catch (_) {}
        if (!mounted) return;

        try {
          final providerCheck = await controller.evaluateJavascript(
            source: '''
              (function() {
                if (!window.ethereum || !window.ethereum.isFlutterWeb3) {
                  return false;
                }
                window.PaxWallet = window.ethereum;
                return true;
              })();
            ''',
          );

          if (providerCheck == false || providerCheck == 'false') {
            await _injectWeb3Provider(controller);
          }
        } catch (_) {}
      },

      // --- onUpdateVisitedHistory: catch client-side redirects --------------
      onUpdateVisitedHistory: (controller, url, isReload) async {
        if (!mounted) return;
        final urlString = url?.toString();

        if (urlString != null && isReload == false) {
          final parsed = _parseVerifiedAndChainParams(urlString);

          if (parsed == null) {
            if (_lastPopupUrl != null) {
              _lastPopupUrl = null;
            }
          } else {
            _popupTimer?.cancel();

            if (_lastPopupUrl != null && _lastPopupUrl != urlString) {
              _lastPopupUrl = null;
            }

            if (_lastPopupUrl != urlString && !_isPopupShowing) {
              _scheduleVerificationCallback(
                parsed: parsed,
                urlString: urlString,
                currentWebUri: url,
                delay: const Duration(milliseconds: 500),
              );
            }
          }
        }
      },

      onPermissionRequest: (controller, request) async {
        if (!mounted) {
          return PermissionResponse(
            resources: request.resources,
            action: PermissionResponseAction.DENY,
          );
        }
        return PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.GRANT,
        );
      },
    );
  }
}
