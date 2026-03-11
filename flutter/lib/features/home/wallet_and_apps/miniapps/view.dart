import 'package:flutter/material.dart' show InkWell, VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/models/remote_config/miniapps_config.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class MiniAppsView extends ConsumerStatefulWidget {
  const MiniAppsView({super.key});

  @override
  ConsumerState<MiniAppsView> createState() => _MiniAppsViewState();
}

class _MiniAppsViewState extends ConsumerState<MiniAppsView> {
  /// Invalidate verification at most once per entry when wallet is loaded.
  bool _hasInvalidatedVerificationOnEnter = false;

  /// True while "Check again" has been pressed and verification is refetching.
  bool _isCheckingAgain = false;

  void _onCheckAgainPressed() {
    setState(() => _isCheckingAgain = true);
    ref.invalidate(paxWalletNeedsVerificationProvider);
  }

  Widget _buildMiniappsList(AsyncValue<MiniappsConfig> configAsync) {
    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (_, __) => Center(
            child: Text(
              'No apps available right now.',
              style: TextStyle(fontSize: 16, color: PaxColors.darkGrey),
              textAlign: TextAlign.center,
            ),
          ),
      data: (config) {
        if (!config.areMiniappsAvailable || config.miniapps.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No apps available right now.',
                style: TextStyle(fontSize: 16, color: PaxColors.darkGrey),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: config.miniapps.length,
          itemBuilder: (context, index) {
            final app = config.miniapps[index];
            return _MiniAppCard(app: app);
          },
        );
      },
    );
  }

  Widget _buildVerificationPrompt(
    BuildContext context, {
    VoidCallback? onCheckAgain,
    bool isCheckingAgain = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'lib/assets/images/goodid_fv_lady.png',
              height: 160,
              fit: BoxFit.fitHeight,
            ).withPadding(bottom: 20),
            Text(
              'Verify your identity to use PaxWallet apps.',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: PaxColors.deepPurple,
              ),
              textAlign: TextAlign.center,
            ).withPadding(bottom: 12),
            Text(
              'A quick verification step is required before you can open apps.',
              style: TextStyle(fontSize: 14, color: PaxColors.darkGrey),
              textAlign: TextAlign.center,
            ).withPadding(bottom: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: PrimaryButton(
                onPressed: () {
                  context.push(
                    Routes.completeGoodDollarFaceVerification,
                    extra: 'wallet_and_apps',
                  );
                },
                child: const Text('Continue'),
              ),
            ),
            if (onCheckAgain != null)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlineButton(
                  onPressed: isCheckingAgain ? null : onCheckAgain,
                  child:
                      isCheckingAgain
                          ? CircularProgressIndicator()
                          : const Text('Check again'),
                ),
              ).withPadding(top: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(miniappsConfigProvider);
    final paxWalletState = ref.watch(paxWalletProvider);
    final paxWalletNeedsVerificationAsync = ref.watch(
      paxWalletNeedsVerificationProvider,
    );

    ref.listen<AsyncValue<bool>>(paxWalletNeedsVerificationProvider, (
      prev,
      next,
    ) {
      if (_isCheckingAgain &&
          (next is AsyncData || next is AsyncError) &&
          mounted) {
        setState(() => _isCheckingAgain = false);
      }
    });

    final walletLoaded =
        paxWalletState.state == PaxWalletState.loaded &&
        paxWalletState.wallet != null &&
        (paxWalletState.wallet!.eoAddress ?? '').isNotEmpty;
    final walletLoading =
        paxWalletState.state == PaxWalletState.initial ||
        paxWalletState.state == PaxWalletState.loading;

    if (walletLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!walletLoaded) {
      return _buildVerificationPrompt(context);
    }
    if (!_hasInvalidatedVerificationOnEnter) {
      _hasInvalidatedVerificationOnEnter = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(paxWalletNeedsVerificationProvider);
      });
    }
    return paxWalletNeedsVerificationAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (_, __) => _buildVerificationPrompt(
            context,
            onCheckAgain: _onCheckAgainPressed,
            isCheckingAgain: _isCheckingAgain,
          ),
      data: (needsVerification) {
        if (!needsVerification) {
          return _buildVerificationPrompt(
            context,
            onCheckAgain: _onCheckAgainPressed,
            isCheckingAgain: _isCheckingAgain,
          );
        }
        return _buildMiniappsList(configAsync);
      },
    );
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

class _MiniAppCard extends ConsumerWidget {
  const _MiniAppCard({required this.app});

  final PaxMiniApp app;

  void _openMiniapp(BuildContext context, WidgetRef ref) {
    if (app.url.isEmpty) return;
    ref.read(analyticsProvider).miniappTapped({
      'miniapp_id': app.id,
      'miniapp_name': app.name,
      'miniapp_title': app.title,
      'miniapp_url': app.url,
    });
    context.push(Routes.miniappWebView, extra: app);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openMiniapp(context, ref),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(
              color: PaxColors.deepPurple.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (app.imageURI != null && app.imageURI!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: app.imageURI!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _placeholderIcon(),
                    errorWidget: (_, __, ___) => _placeholderIcon(),
                  ),
                ).withPadding(right: 16)
              else
                _placeholderIcon().withPadding(right: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: PaxColors.deepPurple,
                      ),
                    ).withPadding(bottom: 2),
                    Text(
                      app.name,
                      style: TextStyle(fontSize: 14, color: PaxColors.darkGrey),
                    ),
                  ],
                ),
              ),
              FaIcon(
                FontAwesomeIcons.chevronRight,
                size: 16,
                color: PaxColors.deepPurple,
              ).withPadding(right: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderIcon() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: PaxColors.lilac.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        FontAwesomeIcons.puzzlePiece,
        color: PaxColors.deepPurple,
        size: 24,
      ),
    );
  }
}
