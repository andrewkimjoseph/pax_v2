import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/providers/referral_link_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/providers/withdrawal_method_connection/withdrawal_method_connection_provider.dart';
import 'package:pax/theming/colors.dart' show PaxColors;
import 'package:pax/utils/remote_config_constants.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/routing/routes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:share_plus/share_plus.dart';

class ReferralProgramCard extends ConsumerWidget {
  const ReferralProgramCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featureFlags = ref.watch(featureFlagsProvider);
    final accountType = ref.watch(accountTypeProvider);
    final hasVerifiedWithdrawal = ref.watch(
      hasVerifiedWithdrawalMethodProvider,
    );
    final v2NeedsVerification = ref.watch(paxWalletNeedsVerificationProvider);

    final referralFeatureOn =
        kDebugMode ||
        (featureFlags.value != null &&
            (featureFlags.value![RemoteConfigKeys
                    .isV2ReferralFeatureAvailable] ??
                false));
    final isV1WithVerified =
        accountType == AccountType.v1 && hasVerifiedWithdrawal.value == true;
    final isV2WithFaceVerification =
        accountType == AccountType.v2 && v2NeedsVerification.value == false;

    // Always show the referral card in debug, otherwise respect eligibility.
    final isVisible =
        kDebugMode ||
        (referralFeatureOn && (isV1WithVerified || isV2WithFaceVerification));

    if (!isVisible) return const SizedBox.shrink();

    final referralLinkAsync = ref.watch(referralLinkProvider);
    final inviteLink = referralLinkAsync.value;
    final loading = referralLinkAsync.isLoading && inviteLink == null;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: PaxColors.orangeToPinkGradient,
        ),
        border: Border.all(
          color: PaxColors.orange.withValues(alpha: 0.9),
          width: 1.4,
        ),
      ),
      child: Container(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Referral Program - Pax V2',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: PaxColors.white,
                        ),
                      ).withPadding(bottom: 12),
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 14,
                            color: PaxColors.white,
                          ),
                          children: [
                            const TextSpan(text: 'Earn between 100 '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Image.asset(
                                'lib/assets/images/good_dollar.png',
                                height: 16,
                                width: 16,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const TextSpan(text: ' and 1000 '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Image.asset(
                                'lib/assets/images/good_dollar.png',
                                height: 16,
                                width: 16,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const TextSpan(
                              text:
                                  ' when friends join V2 and complete face verification within the app. Use your link below to share with your friends.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  variance: ButtonStyle.linkIcon(),
                  onPressed: () => context.push(Routes.referral),
                  icon: FaIcon(
                    FontAwesomeIcons.circleQuestion,
                    size: 24,
                    color: PaxColors.white,
                  ),
                ),
              ],
            ).withPadding(bottom: 16),

            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: PaxColors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inviteLink ??
                              (loading
                                  ? 'Generating your link…'
                                  : 'Tap to view and share'),
                          style: TextStyle(
                            fontSize: 15,
                            color: PaxColors.darkGrey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Text(
                        //   inviteLink != null
                        //       ? 'Share this link with your friends'
                        //       : 'Your personal invite link lives here',
                        //   style: TextStyle(
                        //     fontSize: 11,
                        //     color: PaxColors.darkGrey.withValues(alpha: 0.8),
                        //   ),
                        // ),
                      ],
                    ),
                  ),
                  IconButton(
                    variance: ButtonStyle.linkIcon(),
                    onPressed:
                        inviteLink != null
                            ? () async {
                              try {
                                await Share.share(
                                  inviteLink,
                                  subject: 'Join Pax with my link',
                                );
                              } catch (_) {
                                // Silent failure; user can tap again if needed.
                              }
                            }
                            : null,
                    icon: FaIcon(
                      FontAwesomeIcons.shareNodes,
                      size: 24,
                      color: PaxColors.goodDollarBlue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
