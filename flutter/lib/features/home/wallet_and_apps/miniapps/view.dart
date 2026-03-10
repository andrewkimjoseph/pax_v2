import 'package:flutter/material.dart' show InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/models/remote_config/miniapps_config.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/remote_config_constants.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class MiniAppsView extends ConsumerStatefulWidget {
  const MiniAppsView({super.key, this.embedded = false});

  /// When true, only the body content is built (no Scaffold/AppBar).
  /// Used when embedded inside [WalletAndAppsView]. Caller is responsible
  /// for showing the custom dapp button in the AppBar when needed.
  final bool embedded;

  @override
  ConsumerState<MiniAppsView> createState() => _MiniAppsViewState();
}

class _MiniAppsViewState extends ConsumerState<MiniAppsView> {
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

  Widget _buildVerificationPrompt(BuildContext context) {
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
                    extra: 'dashboard',
                  );
                },
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOpenCustomDappDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (dialogContext) => _OpenCustomDappDialog(
            onOpen: (String url) {
              Navigator.of(dialogContext).pop();
              ref.read(analyticsProvider).customDappOpened({
                'custom_dapp_url': url,
              });
              context.push(Routes.miniappWebView, extra: url);
            },
            onCancel: () => Navigator.of(dialogContext).pop(),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountType = ref.watch(accountTypeProvider);
    final configAsync = ref.watch(miniappsConfigProvider);
    final paxWalletNeedsVerificationAsync = ref.watch(
      paxWalletNeedsVerificationProvider,
    );

    if (widget.embedded) {
      return paxWalletNeedsVerificationAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildVerificationPrompt(context),
        data: (needsVerification) {
          if (needsVerification) {
            return _buildVerificationPrompt(context);
          }
          return _buildMiniappsList(configAsync);
        },
      );
    }

    if (accountType != AccountType.v2) {
      return Scaffold(
        headers: [
          AppBar(
            padding: const EdgeInsets.all(8),
            height: 50,
            backgroundColor: PaxColors.white,
            header: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Apps',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 32,
                    color: PaxColors.black,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: PaxColors.lightGrey),
        ],
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Only available for PaxWallet users.',
                style: TextStyle(fontSize: 16, color: PaxColors.darkGrey),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      headers: [
        AppBar(
          padding: const EdgeInsets.all(8),
          height: 50,
          backgroundColor: PaxColors.white,
          header: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Apps',
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
                            (flags[RemoteConfigKeys
                                        .isCustomAppAccessFeatureAvailable] ==
                                    true)
                                ? Button(
                                  onPressed:
                                      () => _showOpenCustomDappDialog(
                                        context,
                                        ref,
                                      ),
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
          ),
        ),
        Divider(color: PaxColors.lightGrey),
      ],
      child: paxWalletNeedsVerificationAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildVerificationPrompt(context),
        data: (needsVerification) {
          if (needsVerification) {
            return _buildVerificationPrompt(context);
          }

          return _buildMiniappsList(configAsync);
        },
      ),
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
