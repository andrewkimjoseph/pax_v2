import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart' show InkWell;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/models/remote_config/links_config.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/remote_config_constants.dart';
import 'package:pax/widgets/toast.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class EngagementRewardsCard extends ConsumerWidget {
  const EngagementRewardsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linksConfig = ref
        .watch(linksConfigProvider)
        .maybeWhen(data: (value) => value, orElse: LinksConfig.defaults);
    final featureFlags = ref.watch(featureFlagsProvider);
    final accountType = ref.watch(accountTypeProvider);
    final participantId = ref.watch(participantProvider).participant?.id;

    final isEngagementCardAvailable =
        kDebugMode ||
        (featureFlags.value != null &&
            (featureFlags.value![RemoteConfigKeys
                    .isEngagementRewardCardAvailable] ??
                false));

    if (!isEngagementCardAvailable) return const SizedBox.shrink();

    final uri = Uri.parse(linksConfig.theGoodPaxAppEngageLink);
    final engageUrl =
        (participantId != null && participantId.isNotEmpty)
            ? uri
                .replace(
                  queryParameters: {
                    ...uri.queryParameters,
                    'participantId': participantId,
                  },
                )
                .toString()
            : uri.toString();

    if (accountType == AccountType.unknown) return const SizedBox.shrink();

    final card = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PaxColors.goodDollarBlue, PaxColors.deepPurple],
        ),
        // border: Border.all(
        //   color: PaxColors.deepPurple.withValues(alpha: 0.5),
        //   width: 1.4,
        // ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Engagement Rewards',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: PaxColors.white,
                        ),
                      ).withPadding(bottom: 8),
                      Text(
                        accountType == AccountType.v2
                            ? 'Tap to claim your reward 🎉.'
                            : 'Copy the link and open it to claim your reward 🎉.',
                        style: TextStyle(fontSize: 14, color: PaxColors.white),
                      ),
                    ],
                  ),
                ),
                if (accountType == AccountType.v2)
                  FaIcon(
                    FontAwesomeIcons.chevronRight,
                    size: 18,
                    color: PaxColors.white,
                  ).withPadding(top: 8, right: 8),
              ],
            ),
            if (accountType == AccountType.v1)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: PaxColors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        engageUrl,
                        style: TextStyle(
                          fontSize: 14,
                          color: PaxColors.darkGrey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      variance: ButtonStyle.linkIcon(),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: engageUrl));
                        if (!context.mounted) return;
                        showToast(
                          context: context,
                          location: ToastLocation.topCenter,
                          builder:
                              (context, overlay) => Toast(
                                toastColor: PaxColors.green,
                                text: 'Engagement link copied',
                                trailingIcon: FontAwesomeIcons.solidCircleCheck,
                              ),
                        );
                      },
                      icon: FaIcon(
                        FontAwesomeIcons.copy,
                        size: 18,
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

    if (accountType == AccountType.v2) {
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(Routes.miniappWebView, extra: engageUrl),
        child: card,
      );
    }

    return card;
  }
}
