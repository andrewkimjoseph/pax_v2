import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/features/home/pax_wallet/miniapps/view.dart';
import 'package:pax/features/home/pax_wallet/overview/view.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/remote_config_constants.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

enum WalletAndAppsSegment { wallet, apps }

class WalletAndAppsView extends ConsumerStatefulWidget {
  const WalletAndAppsView({super.key});

  @override
  ConsumerState<WalletAndAppsView> createState() => _WalletAndAppsViewState();
}

class _WalletAndAppsViewState extends ConsumerState<WalletAndAppsView> {
  WalletAndAppsSegment _segment = WalletAndAppsSegment.wallet;

  void _showOpenCustomDappDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (dialogContext) => _OpenCustomDappDialog(
            onOpen: (String url) {
              dialogContext.pop();
              ref.read(analyticsProvider).customDappOpened({
                'custom_dapp_url': url,
              });
              context.push(Routes.miniappWebView, extra: url);
            },
            onCancel: () => dialogContext.pop(),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      headers: [
        AppBar(
          padding: const EdgeInsets.all(8),
          height: 97.5,
          backgroundColor: PaxColors.white,
          header: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _segment == WalletAndAppsSegment.wallet
                    ? 'Overview'
                    : 'Mini Apps',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 32,
                  color: PaxColors.black,
                ),
              ),
              ref
                  .watch(featureFlagsProvider)
                  .when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data:
                        (flags) =>
                            kDebugMode ||
                                    (flags[RemoteConfigKeys
                                            .isCustomAppAccessFeatureAvailable] ==
                                        true)
                                ? Button(
                                  onPressed: _showOpenCustomDappDialog,
                                  style: const ButtonStyle.ghost(
                                    density: ButtonDensity.icon,
                                  ),
                                  child: FaIcon(
                                    FontAwesomeIcons.link,
                                    size: 22,
                                    color: PaxColors.deepPurple,
                                  ),
                                )
                                : const SizedBox.shrink(),
                  ),
            ],
          ).withPadding(bottom: 8),
          subtitle: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _segmentButton(
                  label: 'Overview',
                  isActive: _segment == WalletAndAppsSegment.wallet,
                  onPressed:
                      () => setState(
                        () => _segment = WalletAndAppsSegment.wallet,
                      ),
                ),
                _segmentButton(
                  label: 'Mini Apps',
                  isActive: _segment == WalletAndAppsSegment.apps,
                  onPressed:
                      () =>
                          setState(() => _segment = WalletAndAppsSegment.apps),
                ),
              ],
            ),
          ),
        ),
        Divider(color: PaxColors.lightGrey),
      ],
      child: IndexedStack(
        index: _segment == WalletAndAppsSegment.wallet ? 0 : 1,
        children: [
          PaxWalletView(key: ValueKey('wallet')).withPadding(top: 8),
          MiniAppsView(key: ValueKey('apps')).withPadding(top: 8),
        ],
      ),
    );
  }

  Widget _segmentButton({
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    final textColor = isActive ? PaxColors.white : PaxColors.black;
    return Button(
      style: const ButtonStyle.primary(density: ButtonDensity.dense)
          .withBackgroundColor(
            color: isActive ? PaxColors.deepPurple : PaxColors.transparent,
          )
          .withBorder(
            border: Border.all(
              color: isActive ? PaxColors.deepPurple : PaxColors.lilac,
              width: 2,
            ),
          )
          .withBorderRadius(borderRadius: BorderRadius.circular(7)),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: textColor)).withPadding(right: 6),
        ],
      ),
    ).withPadding(right: 8);
  }
}

class _OpenCustomDappDialog extends StatefulWidget {
  const _OpenCustomDappDialog({required this.onOpen, required this.onCancel});

  final void Function(String url) onOpen;
  final VoidCallback onCancel;

  @override
  State<_OpenCustomDappDialog> createState() => _OpenCustomDappDialogState();
}

class _OpenCustomDappDialogState extends State<_OpenCustomDappDialog> {
  final TextEditingController _controller = TextEditingController(
    text: "https://",
  );
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _errorText = 'Please enter a URL');
      return;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() => _errorText = 'Enter a valid http or https URL');
      return;
    }
    setState(() => _errorText = null);
    widget.onOpen(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Open Mini App',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: PaxColors.deepPurple,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            placeholder: const Text('Paste app URL (e.g. https://…)'),
            keyboardType: TextInputType.url,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
          ),
          if (_errorText != null)
            Text(
              _errorText!,
              style: TextStyle(fontSize: 12, color: PaxColors.red),
            ).withPadding(top: 8),
        ],
      ),
      actions: [
        Button(
          onPressed: widget.onCancel,
          style: const ButtonStyle.outline(),
          child: const Text('Cancel'),
        ),
        PrimaryButton(onPressed: _submit, child: const Text('Open')),
      ],
    );
  }
}
