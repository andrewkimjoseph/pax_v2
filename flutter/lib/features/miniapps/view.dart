import 'package:flutter/material.dart' show Divider, InkWell;
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
import 'package:pax/services/wallet/wallet_restore_helper.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;

class MiniappsView extends ConsumerStatefulWidget {
  const MiniappsView({super.key});

  @override
  ConsumerState<MiniappsView> createState() => _MiniappsViewState();
}

class _MiniappsViewState extends ConsumerState<MiniappsView> {
  bool _walletPreloadTriggered = false;

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
          padding: const EdgeInsets.all(8),
          itemCount: config.miniapps.length,
          itemBuilder: (context, index) {
            final app = config.miniapps[index];
            return _MiniappCard(app: app);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountType = ref.watch(accountTypeProvider);
    final configAsync = ref.watch(miniappsConfigProvider);
    final paxWalletNeedsVerificationAsync = ref.watch(
      paxWalletNeedsVerificationProvider,
    );

    // Preload wallet when Miniapps tab is shown so opening a miniapp is fast
    if (accountType == AccountType.v2 && !_walletPreloadTriggered) {
      _walletPreloadTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        restoreWalletIfNeeded(ref, silentOnly: true);
      });
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
            ],
          ),
        ),
        Divider(color: PaxColors.lightGrey),
      ],
      child: paxWalletNeedsVerificationAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildMiniappsList(configAsync),
        data: (needsVerification) {
          if (!needsVerification) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
                          context.go(
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

          return _buildMiniappsList(configAsync);
        },
      ),
    );
  }
}

class _MiniappCard extends ConsumerWidget {
  const _MiniappCard({required this.app});

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
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
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
                  borderRadius: BorderRadius.circular(8),
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
              ),
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
