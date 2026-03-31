import 'package:flutter/material.dart' show InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart' show SvgPicture;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/data/forum_reports.dart';
import 'package:pax/models/firestore/achievement/achievement_model.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/achievement/achievement_provider.dart';
import 'package:pax/providers/local/activity_providers.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/token_balance_util.dart';
import 'package:pax/widgets/current_balance_card.dart';
import 'package:pax/widgets/face_verification_prompt_banner.dart';
import 'package:pax/widgets/profile_completion_prompt_banner.dart';
import 'package:pax/widgets/published_reports_card.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:pax/widgets/socials/social_links_carousel.dart'
    show SocialLinksRow;
import 'package:pax/widgets/v2_availability_banner.dart';
import 'package:pax/widgets/vote_for_canvassing_banner.dart';
import 'package:pax/widgets/withdrawal_method_prompt_banner.dart';

class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  @override
  Widget build(BuildContext context) {
    final tasksCount = ref.watch(totalTaskCompletionsProvider);
    final totalGoodDollars = ref.watch(totalGoodDollarTokensEarnedProvider);
    final unclaimedCount = ref.watch(unclaimedTaskCompletionsCountProvider);
    final totalReferralsCount = ref.watch(totalReferralsCountProvider);
    final totalReferralAmountGd = ref.watch(totalReferralAmountGdProvider);
    final unclaimedReferralRewardsCount = ref.watch(
      unclaimedReferralsCountProvider,
    );
    final donationsMadeCount = ref.watch(donationsMadeCountProvider);
    final totalGoodDollarDonated = ref.watch(totalGoodDollarDonatedProvider);
    final achievementState = ref.watch(achievementsProvider);
    final accountType = ref.watch(accountTypeProvider);
    final isV2 = accountType == AccountType.v2;

    final unclaimedAchievements =
        achievementState.achievements
            .where((a) => a.status == AchievementStatus.earned)
            .length;

    return Scaffold(
      child: SingleChildScrollView(
        child: Column(
          children: [
            const VoteForCanvassingBanner(),

            const V2AvailabilityBanner(),

            if (isV2) const FaceVerificationPromptBanner(),

            if (!isV2) const WithdrawalMethodPromptBanner(),

            const ProfileCompletionPromptBanner(),

            const CurrentBalanceCard(
              nextLocation: '/wallet',
            ).withPadding(bottom: 8),

            const SocialLinksRow().withPadding(bottom: 8),

            Row(
              children: [
                Expanded(
                  child: _statCard(
                    icon: FontAwesomeIcons.circleCheck,
                    value: tasksCount.when(
                      data: (c) => c.toString(),
                      loading: () => '--',
                      error: (_, __) => '0',
                    ),
                    label: 'Completed Tasks',
                    isLoading: tasksCount is AsyncLoading,
                  ).withPadding(right: 8),
                ),
                Expanded(
                  child: _statCard(
                    icon: FontAwesomeIcons.sackDollar,
                    value: totalGoodDollars.when(
                      data: (a) => TokenBalanceUtil.getLocaleFormattedAmount(a),
                      loading: () => '--',
                      error: (_, __) => '0',
                    ),
                    label: 'Lifetime G\$ Earned',
                    isLoading: totalGoodDollars is AsyncLoading,
                    suffix: totalGoodDollars.maybeWhen(
                      data:
                          (_) => SvgPicture.asset(
                            'lib/assets/svgs/currencies/good_dollar.svg',
                            height: 18,
                          ).withPadding(left: 4),
                      orElse: () => null,
                    ),
                  ).withPadding(right: 8),
                ),
                Expanded(
                  child: _statCard(
                    icon: FontAwesomeIcons.handHoldingHeart,
                    value: donationsMadeCount.when(
                      data: (c) => c.toString(),
                      loading: () => '--',
                      error: (_, __) => '0',
                    ),
                    label: 'Donations Made',
                    isLoading: donationsMadeCount is AsyncLoading,
                  ),
                ),
              ],
            ).withPadding(bottom: 8),

            Row(
              children: [
                Expanded(
                  child: _statCard(
                    icon: FontAwesomeIcons.handHoldingDollar,
                    value: totalGoodDollarDonated.when(
                      data: (a) => TokenBalanceUtil.getLocaleFormattedAmount(a),
                      loading: () => '--',
                      error: (_, __) => '0',
                    ),
                    label: 'G\$ Donated',
                    isLoading: totalGoodDollarDonated is AsyncLoading,
                    suffix: totalGoodDollarDonated.maybeWhen(
                      data:
                          (_) => SvgPicture.asset(
                            'lib/assets/svgs/currencies/good_dollar.svg',
                            height: 18,
                          ).withPadding(left: 4),
                      orElse: () => null,
                    ),
                  ).withPadding(right: 8),
                ),
                Expanded(
                  child: _statCard(
                    icon: FontAwesomeIcons.userGroup,
                    value: totalReferralsCount.when(
                      data: (c) => c.toString(),
                      loading: () => '--',
                      error: (_, __) => '0',
                    ),
                    label: 'Referrals Made',
                    isLoading: totalReferralsCount is AsyncLoading,
                  ).withPadding(right: 8),
                ),
                Expanded(
                  child: _statCard(
                    icon: FontAwesomeIcons.moneyBillTrendUp,
                    value: totalReferralAmountGd.when(
                      data: (a) => TokenBalanceUtil.getLocaleFormattedAmount(a),
                      loading: () => '--',
                      error: (_, __) => '0',
                    ),
                    label: 'Referral G\$ Made',
                    isLoading: totalReferralAmountGd is AsyncLoading,
                    suffix: totalReferralAmountGd.maybeWhen(
                      data:
                          (_) => SvgPicture.asset(
                            'lib/assets/svgs/currencies/good_dollar.svg',
                            height: 18,
                          ).withPadding(left: 4),
                      orElse: () => null,
                    ),
                  ),
                ),
              ],
            ).withPadding(bottom: 8),

            Row(
              children: [
                Expanded(
                  child: _statCard(
                    icon: FontAwesomeIcons.userClock,
                    value: unclaimedReferralRewardsCount.when(
                      data: (c) => c.toString(),
                      loading: () => '--',
                      error: (_, __) => '0',
                    ),
                    label: 'Pending Referrals',
                    isLoading: unclaimedReferralRewardsCount is AsyncLoading,
                  ).withPadding(right: 8),
                ),
                Expanded(
                  child: _statCard(
                    icon: FontAwesomeIcons.hourglassHalf,
                    value: unclaimedCount.when(
                      data: (c) => c.toString(),
                      loading: () => '--',
                      error: (_, __) => '0',
                    ),
                    label: 'Pending Tasks',
                    isLoading: unclaimedCount is AsyncLoading,
                  ).withPadding(right: 8),
                ),
                Expanded(
                  child: _statCard(
                    icon: FontAwesomeIcons.trophy,
                    value:
                        achievementState.state == AchievementState.loading
                            ? '--'
                            : unclaimedAchievements.toString(),
                    label: 'Pending Badges',
                    isLoading:
                        achievementState.state == AchievementState.loading,
                  ),
                ),
              ],
            ).withPadding(bottom: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Published Reports',
                  style: TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 20,
                    color: PaxColors.deepPurple,
                  ),
                ).withPadding(bottom: 8),

                InkWell(
                  onTap: () {
                    ref.read(analyticsProvider).reportsTapped({
                      'source': 'dashboard_see_all',
                    });
                    context.push(Routes.reports);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See all',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: PaxColors.deepPurple,
                        ),
                      ).withPadding(right: 8),
                      FaIcon(
                        FontAwesomeIcons.chevronRight,
                        size: 12,
                        color: PaxColors.deepPurple,
                      ),
                    ],
                  ),
                ),
              ],
            ).withPadding(bottom: 8, top: 4),

            _reportsTeaser().withPadding(bottom: 12),
          ],
        ).withPadding(all: 8),
      ),
    );
  }

  Widget _reportsTeaser() {
    final teaserReports = forumReports.take(2).toList();
    final cardWidth = MediaQuery.of(context).size.width * 0.75;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: PaxColors.lightLilac, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SizedBox(
        height: 150,
        child: ListView(
          scrollDirection: Axis.horizontal,
          shrinkWrap: true,
          padding: const EdgeInsets.all(8),
          children: [
            for (final report in teaserReports)
              ForumReportCard(report, width: cardWidth).withPadding(right: 8),
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String value,
    required String label,
    Color? valueColor,
    bool isLoading = false,
    Widget? suffix,
  }) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PaxColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PaxColors.lightLilac, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FaIcon(
            icon,
            color: PaxColors.mediumPurple,
            size: 18,
          ).withPadding(bottom: 8),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: valueColor ?? PaxColors.black,
                ),
              ).asSkeleton(enabled: isLoading),
              if (suffix != null) suffix,
            ],
          ).withPadding(bottom: 4),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: 12,
              color: PaxColors.darkGrey,
            ),
          ),
        ],
      ),
    );
  }
}
