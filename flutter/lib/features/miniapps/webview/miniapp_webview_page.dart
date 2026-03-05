import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/wallet/wallet_credentials_provider.dart';
import 'package:pax/services/wallet/wallet_restore_helper.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/widgets/web3_webview.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;

/// Full-screen Web3WebView for opening a miniapp URL with wallet injection.
class MiniAppWebViewPage extends ConsumerStatefulWidget {
  const MiniAppWebViewPage({super.key, required this.url, this.title});

  final String url;

  /// App bar title; defaults to 'Apps' when null.
  final String? title;

  String get _appBarTitle => title ?? 'Apps';

  @override
  ConsumerState<MiniAppWebViewPage> createState() => _MiniAppWebViewPageState();
}

class _MiniAppWebViewPageState extends ConsumerState<MiniAppWebViewPage> {
  bool _restoreTriggered = false;

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletCredentialsProvider);

    final isWaitingForWallet =
        walletState.status == WalletCredentialsStatus.loading ||
        (walletState.status == WalletCredentialsStatus.initial &&
            walletState.credentials == null);

    // Trigger restore once when we're on this page and wallet isn't loaded yet
    // (e.g. user opened miniapp before Apps tab ran restore, or restore never ran)
    if (isWaitingForWallet && !_restoreTriggered) {
      _restoreTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        restoreWalletIfNeeded(ref, silentOnly: true);
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
                  child: FaIcon(FontAwesomeIcons.arrowLeftLong, size: 20, color: PaxColors.deepPurple),
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
                  child: FaIcon(FontAwesomeIcons.arrowLeftLong, size: 20, color: PaxColors.deepPurple),
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
          child: Padding(
            padding: const EdgeInsets.all(24),
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
                          restoreWalletIfNeeded(ref, silentOnly: false);
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final credentials = walletState.credentials!;

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
      child: Web3WebView(url: widget.url, credentials: credentials),
    );
  }
}
