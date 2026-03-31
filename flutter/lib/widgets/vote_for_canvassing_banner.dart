import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart' show InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/models/remote_config/miniapps_config.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/remote_config_constants.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class VoteForCanvassingBanner extends ConsumerWidget {
  const VoteForCanvassingBanner({super.key});

  static const int _miniAppId = 4;
  static const String _miniAppName = 'Flowstate';
  static const String _miniAppTitle = 'Vote for Canvassing!';
  static const String _miniAppImageUrl =
      'https://firebasestorage.googleapis.com/v0/b/thepaxapp.firebasestorage.app/o/miniapps%2Fflowstate.png?alt=media&token=7ff23404-0a42-4a90-9989-d2d2a7c90929';
  static const String _miniAppUrl =
      'https://flowstate.network/flow-councils/42220/0xfabef1abae4998146e8a8422813eb787caa26ec2';
  static const PaxMiniApp _miniApp = PaxMiniApp(
    id: _miniAppId,
    name: _miniAppName,
    title: _miniAppTitle,
    imageURI: _miniAppImageUrl,
    url: _miniAppUrl,
    isMiniappAvailable: true,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featureFlags = ref.watch(featureFlagsProvider);
    final accountType = ref.watch(accountTypeProvider);
    final needsProfileCompletion = ref.watch(profileNeedsCompletionProvider);
    final needsVerification = ref.watch(paxWalletNeedsVerificationProvider);

    final featureEnabled =
        featureFlags.value?[RemoteConfigKeys.isVoteForCanvassingAvailable] ==
        true;
    final isVerifiedWallet = needsVerification.value == false;

    final isV2 = accountType == AccountType.v2;
    final shouldShow =
        isV2 &&
        (kDebugMode ||
            (featureEnabled && isVerifiedWallet && !needsProfileCompletion));

    if (!shouldShow) {
      return const SizedBox.shrink();
    }

    return InkWell(
      onTap: () {
        ref.read(analyticsProvider).voteForCanvassingTapped({
          'source': 'dashboard',
          'miniapp_id': _miniAppId,
          'miniapp_name': _miniAppName,
          'miniapp_title': _miniAppTitle,
          'miniapp_image_uri': _miniAppImageUrl,
          'miniapp_url': _miniAppUrl,
        });
        context.push(Routes.miniappWebView, extra: _miniApp);
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              PaxColors.deepPurple.withValues(alpha: 0.1),
              PaxColors.lilac.withValues(alpha: 0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: PaxColors.deepPurple.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            FaIcon(
              FontAwesomeIcons.checkToSlot,
              color: PaxColors.deepPurple,
              size: 24,
            ).withPadding(right: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _miniAppTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: PaxColors.deepPurple,
                    ),
                  ).withPadding(bottom: 2),
                  Text(
                    'Support Canvassing on Flowstate by casting your vote.',
                    style: TextStyle(fontSize: 13, color: PaxColors.darkGrey),
                  ),
                ],
              ),
            ),
            FaIcon(
              FontAwesomeIcons.chevronRight,
              color: PaxColors.deepPurple,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
