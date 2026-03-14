import 'package:flutter/material.dart' show Divider, InkWell, PopScope;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pax/providers/wallet/wallet_credentials_provider.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/providers/local/pax_wallet_view_provider.dart';
import 'package:pax/services/wallet/wallet_restore_helper.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/widgets/web3_webview.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;

/// Full-screen Web3WebView for opening a miniapp URL with wallet injection.
class MiniAppWebView extends ConsumerStatefulWidget {
  const MiniAppWebView({super.key, required this.url, this.title});

  final String url;

  /// App bar title; defaults to 'Apps' when null.
  final String? title;

  String get _appBarTitle => title ?? 'Apps';

  @override
  ConsumerState<MiniAppWebView> createState() => _MiniAppWebView();
}

class _MiniAppWebView extends ConsumerState<MiniAppWebView> {
  bool _restoreTriggered = false;
  bool _mismatchRecoveryTriggered = false;
  InAppWebViewController? _webViewController;

  static bool _eoAddressMatches(String? a, String? b) {
    if (a == null || b == null) return false;
    final na = a.trim().toLowerCase().replaceFirst(RegExp(r'^0x'), '');
    final nb = b.trim().toLowerCase().replaceFirst(RegExp(r'^0x'), '');
    return na == nb;
  }

  Future<void> _handleBack() async {
    if (_webViewController == null) {
      if (mounted) context.pop();
      return;
    }
    final canGoBack = await _webViewController!.canGoBack();
    if (canGoBack) {
      _webViewController!.goBack();
      return;
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletCredentialsProvider);
    final paxWallet = ref.watch(paxWalletProvider).wallet;
    final walletEoAddress = paxWallet?.eoAddress;

    final isWaitingForWallet =
        walletState.status == WalletCredentialsStatus.loading ||
        (walletState.status == WalletCredentialsStatus.initial &&
            walletState.credentials == null);

    // Trigger restore once when we're on this page and wallet isn't loaded yet
    // (e.g. user opened miniapp before Apps tab ran restore, or restore never ran)
    if (isWaitingForWallet && !_restoreTriggered) {
      final isV2 = ref.read(accountTypeProvider) == AccountType.v2;
      if (isV2) {
        _restoreTriggered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          restoreWalletIfNeeded(ref, silentOnly: true);
        });
      }
    }

    // Loaded but eoAddress mismatch with Firestore: clear and try interactive restore once (recovery-first).
    if (walletState.status == WalletCredentialsStatus.loaded &&
        walletState.credentials != null &&
        walletState.eoAddress != null &&
        walletEoAddress != null &&
        walletEoAddress.isNotEmpty &&
        !_eoAddressMatches(walletState.eoAddress, walletEoAddress) &&
        !_mismatchRecoveryTriggered) {
      _mismatchRecoveryTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        ref.read(walletCredentialsProvider.notifier).clearCredentials();
        _restoreTriggered = true;
        await restoreWalletIfNeeded(ref, silentOnly: false);
      });
    }

    if (isWaitingForWallet) {
      return Scaffold(
        headers: [
          AppBar(
            padding: const EdgeInsets.all(8),
            backgroundColor: PaxColors.white,
            child: Row(
              children: [
                InkWell(
                  onTap: () => context.pop(),
                  child: FaIcon(
                    FontAwesomeIcons.arrowLeftLong,
                    size: 20,
                    color: PaxColors.deepPurple,
                  ),
                ),
                const Spacer(),
                Text(
                  widget._appBarTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, color: PaxColors.deepPurple),
                ).withPadding(right: 16),
                const Spacer(),
              ],
            ),
          ).withPadding(top: 16),
          Divider(color: PaxColors.lightGrey),
        ],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator().withPadding(bottom: 16),
              Text('Loading wallet...'),
            ],
          ),
        ),
      );
    }

    if (walletState.status == WalletCredentialsStatus.error ||
        walletState.credentials == null) {
      return Scaffold(
        headers: [
          AppBar(
            padding: const EdgeInsets.all(8),
            backgroundColor: PaxColors.white,
            child: Row(
              children: [
                InkWell(
                  onTap: () => context.pop(),
                  child: FaIcon(
                    FontAwesomeIcons.arrowLeftLong,
                    size: 20,
                    color: PaxColors.deepPurple,
                  ),
                ),
                const Spacer(),
                Text(
                  widget._appBarTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, color: PaxColors.deepPurple),
                ).withPadding(right: 16),
                const Spacer(),
              ],
            ),
          ).withPadding(top: 16),
          Divider(color: PaxColors.lightGrey),
        ],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                walletState.errorMessage ?? 'Wallet could not be loaded.',
                style: TextStyle(fontSize: 16, color: PaxColors.darkGrey),
                textAlign: TextAlign.center,
              ).withPadding(bottom: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Go back'),
                  ),
                  TextButton(
                    onPressed: () {
                      ref
                          .read(walletCredentialsProvider.notifier)
                          .clearCredentials();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (ref.read(accountTypeProvider) == AccountType.v2) {
                          restoreWalletIfNeeded(ref, silentOnly: false);
                        }
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ).withPadding(all: 24),
        ),
      );
    }

    final credentials = walletState.credentials!;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        headers: [
          AppBar(
            padding: const EdgeInsets.all(8),
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
                const Spacer(),
                Text(
                  widget._appBarTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, color: PaxColors.deepPurple),
                ).withPadding(right: 16),
                const Spacer(),
              ],
            ),
          ).withPadding(top: 16),
          Divider(color: PaxColors.lightGrey),
        ],
        child: Web3WebView(
          url: widget.url,
          credentials: credentials,
          onControllerCreated:
              (controller) => setState(() => _webViewController = controller),
          onTransactionSent: (eoAddress) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ref
                  .read(paxWalletViewProvider.notifier)
                  .fetchBalance(eoAddress, forceRefresh: true);
            });
          },
        ),
      ),
    );
  }
}
