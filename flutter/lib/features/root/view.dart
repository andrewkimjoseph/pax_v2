import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_svg/svg.dart' show SvgPicture;
import 'package:pax/exports/views.dart';
import 'package:pax/features/home/pax_wallet/view.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/providers/db/achievement/achievement_provider.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/providers/db/tasks/task_provider.dart';
import 'package:pax/providers/local/activity_providers.dart';
import 'package:pax/providers/referral_link_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/providers/route/root_selected_index_provider.dart';
import 'package:pax/providers/withdrawal_method_connection/withdrawal_method_connection_provider.dart';
import 'package:pax/services/wallet/wallet_restore_helper.dart';
import 'package:pax/utils/remote_config_constants.dart';
import 'package:pax/widgets/common/gradient_badge.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../theming/colors.dart' show PaxColors;
import 'package:pax/utils/achievement_constants.dart';

class RootView extends ConsumerStatefulWidget {
  const RootView({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _RootViewState();
}

class _RootViewState extends ConsumerState<RootView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isV2 = ref.read(accountTypeProvider) == AccountType.v2;
      if (isV2) {
        final container = ProviderScope.containerOf(context);
        restoreWalletIfNeeded(container, silentOnly: true);
        if (kDebugMode) {
          debugPrint(
            '[RootView] triggering backfillPostVerificationSideEffects for V2 user',
          );
        }
        unawaited(
          ref
              .read(paxWalletProvider.notifier)
              .backfillPostVerificationSideEffects(),
        );
      }
      _prefetchReferralCardDeps();
    });
  }

  /// Warms referral card [FutureProvider]s so Account tab is ready without extra wait.
  void _prefetchReferralCardDeps() {
    final participantId = ref.read(participantProvider).participant?.id;
    if (participantId == null || participantId.isEmpty) return;

    unawaited(ref.read(featureFlagsProvider.future));

    final type = ref.read(accountTypeProvider);
    if (type == AccountType.v1) {
      unawaited(ref.read(hasVerifiedWithdrawalMethodProvider.future));
    } else if (type == AccountType.v2) {
      unawaited(ref.read(paxWalletNeedsVerificationProvider.future));
    }

    unawaited(ref.read(referralLinkProvider.future));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AccountType>(accountTypeProvider, (previous, next) {
      if (next != AccountType.v1 && next != AccountType.v2) return;
      if (previous == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _prefetchReferralCardDeps();
      });
    });

    final selected = ref.watch(rootSelectedIndexProvider);
    final accountType = ref.watch(accountTypeProvider);
    final isV2 = accountType == AccountType.v2;

    // Single watch for achievements (V1 Account red-dot badge)
    final achievementState = ref.watch(achievementsProvider);
    final requiredAchievements = [
      AchievementConstants.payoutConnector,
      AchievementConstants.profilePerfectionist,
      AchievementConstants.verifiedHuman,
      AchievementConstants.doublePayoutConnector,
    ];
    final userAchievementNames =
        achievementState.achievements
            .map((a) => a.name)
            .whereType<String>()
            .toSet();
    final hasAllRequired = requiredAchievements.every(
      (ach) => userAchievementNames.contains(ach),
    );
    final showAccountBadge =
        !isV2 &&
        achievementState.state == AchievementState.loaded &&
        !hasAllRequired;

    final participantId = ref.watch(participantProvider).participant?.id;
    final flags = ref
        .watch(featureFlagsProvider)
        .maybeWhen(data: (f) => f, orElse: () => <String, bool>{});
    final tasksEnabled =
        kDebugMode || flags[RemoteConfigKeys.areTasksAvailable] == true;
    final achievementsEnabled =
        kDebugMode || flags[RemoteConfigKeys.areAchievementsAvailable] == true;

    final taskCount =
        tasksEnabled && participantId != null
            ? ref
                .watch(availableTasksStreamProvider(participantId))
                .maybeWhen(data: (tasks) => tasks.length, orElse: () => 0)
            : 0;

    final earnedToClaimCount =
        achievementsEnabled && achievementState.state == AchievementState.loaded
            ? achievementState.achievements
                .where(
                  (a) =>
                      achievementStatusName(a.status) ==
                      AchievementStatusNames.earned,
                )
                .length
            : 0;

    final homeCombinedBadgeCount = taskCount + earnedToClaimCount;
    final int? homeTasksBadgeCount =
        homeCombinedBadgeCount > 0 ? homeCombinedBadgeCount : null;

    final tabChildren = _buildTabChildren(isV2);

    return Scaffold(
      footers: [
        const Divider(),
        SizedBox(
          child: NavigationBar(
            alignment: NavigationBarAlignment.spaceBetween,
            labelType: NavigationLabelType.expanded,
            expands: false,
            onSelected: (index) {
              ref.read(rootSelectedIndexProvider.notifier).setIndex(index);
            },
            index: selected,
            children: [
              buildButton(
                'Home',
                selected == 0,
                badgeCount: homeTasksBadgeCount,
                isV2: isV2,
              ),
              if (isV2)
                buildButton(
                  'PaxWallet',
                  selected == 1,
                  badgeCount: null,
                  isV2: isV2,
                ),
              buildButton(
                'Activity',
                selected == (isV2 ? 2 : 1),
                badgeCount: () {
                  final unclaimedTasks = ref
                      .watch(unclaimedTaskCompletionsCountProvider)
                      .maybeWhen(data: (c) => c, orElse: () => 0);
                  final unclaimedReferrals = ref
                      .watch(unclaimedReferralsCountProvider)
                      .maybeWhen(data: (c) => c, orElse: () => 0);
                  final total = unclaimedTasks + unclaimedReferrals;
                  return total > 0 ? total : null;
                }(),
                isV2: isV2,
              ),
              buildButton(
                'Account',
                selected == (isV2 ? 3 : 2),
                badgeCount: null,
                isV2: isV2,
                showAccountBadge: showAccountBadge,
              ),
            ],
          ),
        ),
      ],
      child: IndexedStack(index: selected, children: tabChildren),
    );
  }

  List<Widget> _buildTabChildren(bool isV2) {
    if (isV2) {
      return [
        HomeView(key: const ValueKey('home')),
        const WalletAndAppsView(key: ValueKey('wallet-and-apps')),
        ActivityView(key: const ValueKey('activity')),
        AccountView(key: const ValueKey('account')),
      ];
    }
    return [
      HomeView(key: const ValueKey('home')),
      ActivityView(key: const ValueKey('activity')),
      AccountView(key: const ValueKey('account')),
    ];
  }

  IconData _getIconForLabel(String label) {
    switch (label) {
      case 'Home':
        return FontAwesomeIcons.house;
      case 'PaxWallet':
        return FontAwesomeIcons.wallet;
      case 'Activity':
        return FontAwesomeIcons.clockRotateLeft;
      case 'Account':
        return FontAwesomeIcons.circleUser;
      default:
        return FontAwesomeIcons.circle;
    }
  }

  NavigationItem buildButton(
    String label,
    bool isSelected, {
    int? badgeCount,
    bool isV2 = false,
    bool showAccountBadge = false,
  }) {
    final showActivityBadge =
        label == 'Activity' && badgeCount != null && badgeCount > 0;
    final showHomeTasksBadge =
        label == 'Home' && badgeCount != null && badgeCount > 0;
    final countForBadge = badgeCount ?? 0;

    Widget navIcon =
        label == 'PaxWallet'
            ? SvgPicture.asset(
              isSelected
                  ? 'lib/assets/svgs/wallets/pax_wallet.svg'
                  : 'lib/assets/svgs/wallets/pax_wallet_lilac.svg',
              width: 32,
              height: 32,
            )
            : FaIcon(
              _getIconForLabel(label),
              size: 24,
              color: isSelected ? PaxColors.deepPurple : PaxColors.lilac,
            );

    final badgeLabel =
        showHomeTasksBadge || showActivityBadge
            ? (countForBadge > 99 ? '99+' : '$countForBadge')
            : null;

    return NavigationItem(
      style: const ButtonStyle.ghost(density: ButtonDensity.icon),
      selectedStyle: const ButtonStyle.ghost(density: ButtonDensity.icon),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: isSelected ? PaxColors.deepPurple : PaxColors.lilac,
          fontWeight: FontWeight.w900,
        ),
      ),
      child: GradientBadge(
        isVisible: showAccountBadge || showHomeTasksBadge || showActivityBadge,
        label: badgeLabel,
        offset: const Offset(-10, -8),
        dotSize: 10,
        child: navIcon,
      ),
    );
  }
}
