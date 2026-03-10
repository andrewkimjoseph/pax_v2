import 'package:flutter/material.dart' show InkWell, PopScope;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart' show SvgPicture;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class WebViewPage extends ConsumerStatefulWidget {
  final String url;

  const WebViewPage({super.key, required this.url});

  @override
  ConsumerState<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends ConsumerState<WebViewPage> {
  bool isLoading = true;
  InAppWebViewController? _controller;
  bool _canGoBack = false;
  bool _canGoForward = false;

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
    } catch (_) {}
  }

  Future<void> _handleBack() async {
    if (_controller == null) {
      if (mounted) context.pop();
      return;
    }
    final canGoBack = await _controller!.canGoBack();
    if (canGoBack) {
      _controller!.goBack();
      _updateNavigationState();
      return;
    }
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        headers: [
          AppBar(
            padding: EdgeInsets.all(8),
            backgroundColor: PaxColors.white,
            child: Row(
              children: [
                InkWell(
                  onTap: () => _handleBack(),
                  child: FaIcon(
                    FontAwesomeIcons.arrowLeftLong,
                    size: 20,
                    color: PaxColors.deepPurple,
                  ),
                ),
                Spacer(),
                SvgPicture.asset('lib/assets/svgs/canvassing.svg', height: 24),
                Spacer(),
              ],
            ),
          ).withPadding(top: 16),
          Divider(color: PaxColors.lightGrey),
        ],
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                    initialSettings: InAppWebViewSettings(
                      useHybridComposition: false,
                    ),
                    onLoadStart: (controller, url) {
                      _controller ??= controller;
                      setState(() => isLoading = true);
                      _updateNavigationState();
                    },
                    onLoadStop: (controller, url) {
                      _controller ??= controller;
                      setState(() => isLoading = false);
                      _updateNavigationState();
                    },
                  ),
                  if (isLoading)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
            const Divider(height: 1).withPadding(bottom: 8),
            SafeArea(
              bottom: true,
              top: false,
              left: false,
              right: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: PaxColors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton.outline(
                      onPressed:
                          _canGoBack
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
                      onPressed: () {
                        _controller?.reload();
                        _updateNavigationState();
                      },
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
                          _canGoForward
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
