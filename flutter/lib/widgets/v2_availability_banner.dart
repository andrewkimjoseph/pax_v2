import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart' show InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/remote_config_constants.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class V2AvailabilityBanner extends ConsumerWidget {
  const V2AvailabilityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const SizedBox.shrink();
    final accountType = ref.watch(accountTypeProvider);
    final featureFlags = ref.watch(featureFlagsProvider);

    return featureFlags.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (flags) {
        final isV2UpgradeAvailable =
            flags[RemoteConfigKeys.isV2UpgradeAvailable] == true;
        final shouldShow =
            accountType == AccountType.v1 &&
            (kDebugMode || isV2UpgradeAvailable);
        if (!shouldShow) {
          return const SizedBox.shrink();
        }

        // ref.read(analyticsProvider).v2AvailabilityBannerShown();

        return InkWell(
          onTap: () {
            ref.read(analyticsProvider).v2UpgradeEligibilityChecked();
            context.push(Routes.checkV2Eligibility);
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
                  FontAwesomeIcons.arrowUpFromBracket,
                  color: PaxColors.deepPurple,
                  size: 24,
                ).withPadding(right: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'V2 is Available!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: PaxColors.deepPurple,
                        ),
                      ).withPadding(bottom: 2),
                      Text(
                        'Upgrade to get your own PaxWallet',
                        style: TextStyle(
                          fontSize: 13,
                          color: PaxColors.darkGrey,
                        ),
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
      },
    );
  }
}
