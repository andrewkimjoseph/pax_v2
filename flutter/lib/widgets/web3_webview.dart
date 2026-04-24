import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/providers/local/web3_miniapp_service_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/providers/local/pax_wallet_view_provider.dart';
import 'package:pax/providers/local/wallet_transactions_provider.dart';
import 'package:pax/services/web3/web3_miniapp_service.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:web3dart/web3dart.dart';

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
  Web3MiniAppService? _web3Service;
  String? _currentAddress;
  String? _currentChainId;
  String? _providerJavaScript;
  String? _lastPopupUrl;
  bool _isPopupShowing = false;
  InAppWebViewController? _controller;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isPageLoading = true;
  double _pageProgress = 0;

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
      'lib/assets/scripts/ethereum_provider.js',
    );
    _web3Service = ref.read(web3MiniAppServiceProvider(widget.credentials));
    await _web3Service!.initialize();
    if (mounted) {
      setState(() {
        _currentAddress = _web3Service?.currentAddress;
        _currentChainId = _web3Service?.currentChainId;
      });
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

  void _onTransactionSent(String eoAddress) {
    if (!mounted) return;
    ref
        .read(paxWalletViewProvider.notifier)
        .fetchBalance(eoAddress, forceRefresh: true);
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      ref.read(walletTransactionsProvider.notifier).refresh(eoAddress);
    });
    // Non-blocking, preconditioned sponsorship check after successful tx.
    // Uses existing PaxWalletNotifier safeguards before calling sponsorWalletGas.
    unawaited(
      ref
          .read(paxWalletProvider.notifier)
          .topUpGasIfNeeded()
          .catchError((_) => false),
    );
    widget.onTransactionSent?.call(eoAddress);
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
    _web3Service?.dispose();
    _web3Service = null;
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
        initialSettings: InAppWebViewSettings(useHybridComposition: false),
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
                  final service = _web3Service;
                  if (service == null) {
                    throw StateError('Web3 service is not initialized');
                  }
                  final response = await service.handleRequest(
                    request,
                    onTransactionSent: _onTransactionSent,
                  );
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
          if (mounted) {
            setState(() {
              _isPageLoading = true;
              _pageProgress = 0;
            });
          }
          _checkUrlForVerificationParams(url?.toString());
          await _injectWeb3Provider(controller);
          _updateNavigationState();
        },
        onProgressChanged: (controller, progress) {
          if (!mounted) return;
          setState(() {
            _pageProgress = (progress.clamp(0, 100)) / 100.0;
            if (progress >= 100) {
              _isPageLoading = false;
            }
          });
        },
        onLoadStop: (controller, url) async {
          _checkUrlForVerificationParams(url?.toString());
          await _injectWeb3Provider(controller);
          _updateNavigationState();
          if (mounted) {
            setState(() {
              _isPageLoading = false;
              _pageProgress = 1;
            });
          }
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
          SizedBox(
            width: MediaQuery.of(context).size.width,
            height: _isPageLoading ? 8 : 0,
            child:
                _isPageLoading
                    ? LinearProgressIndicator(
                      value: _pageProgress,
                      borderRadius: BorderRadius.zero,
                    )
                    : const SizedBox.shrink(),
          ),
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
