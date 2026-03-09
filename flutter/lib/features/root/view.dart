import 'package:flutter/material.dart' show Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/exports/views.dart';
import 'package:pax/features/home/pax_wallet/view.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/providers/db/achievement/achievement_provider.dart';
import 'package:pax/providers/local/activity_providers.dart';
import 'package:pax/providers/route/root_selected_index_provider.dart';
import 'package:pax/services/wallet/wallet_restore_helper.dart';
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
      final isV2 = ref.read(accountTypeProvider) == AccountType.v2;
      if (isV2) restoreWalletIfNeeded(ref, silentOnly: true);
    });
  }

  @override
  Widget build(BuildContext context) {
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
        achievementState.achievements.map((a) => a.name).whereType<String>().toSet();
    final hasAllRequired =
        requiredAchievements.every((ach) => userAchievementNames.contains(ach));
    final showAccountBadge =
        !isV2 &&
            achievementState.state == AchievementState.loaded &&
            !hasAllRequired;

    final tabChildren = _buildTabChildren(isV2);

    return Scaffold(
      footers: [
        const Divider(),
        SizedBox(
          child: NavigationBar(
            alignment: NavigationBarAlignment.spaceBetween,
            labelType: NavigationLabelType.expanded,
            onSelected: (index) {
              ref.read(rootSelectedIndexProvider.notifier).setIndex(index);
            },
            index: selected,
            children: [
              buildButton('Home', selected == 0, badgeCount: null, isV2: isV2),
              if (isV2)
                buildButton(
                  'Wallet',
                  selected == 1,
                  badgeCount: null,
                  isV2: isV2,
                ),
              if (isV2)
                buildButton(
                  'Apps',
                  selected == 2,
                  badgeCount: null,
                  isV2: isV2,
                ),
              buildButton(
                'Activity',
                selected == (isV2 ? 3 : 1),
                badgeCount: ref
                    .watch(unclaimedTaskCompletionsCountProvider)
                    .maybeWhen(data: (c) => c, orElse: () => null),
                isV2: isV2,
              ),
              buildButton(
                'Account',
                selected == (isV2 ? 4 : 2),
                badgeCount: null,
                isV2: isV2,
                showAccountBadge: showAccountBadge,
              ),
            ],
          ),
        ),
      ],
      child: IndexedStack(
        index: selected,
        children: tabChildren,
      ),
    );
  }

  List<Widget> _buildTabChildren(bool isV2) {
    if (isV2) {
      return [
        HomeView(key: const ValueKey('home')),
        const PaxWalletView(key: ValueKey('pax-wallet')),
        const MiniAppsView(key: ValueKey('miniapps')),
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
      case 'Wallet':
        return FontAwesomeIcons.wallet;
      case 'Apps':
        return FontAwesomeIcons.puzzlePiece;
      case 'Activity':
        return FontAwesomeIcons.chartLine;
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
      child: Badge(
        isLabelVisible: showAccountBadge || showActivityBadge,
        offset: const Offset(10, -5),
        label:
            showActivityBadge
                ? Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: TextStyle(
                    fontSize: 10,
                    color: PaxColors.white,
                    fontWeight: FontWeight.w600,
                  ),
                )
                : const Text(''),
        backgroundColor: showActivityBadge ? PaxColors.orange : PaxColors.red,
        smallSize: 10,
        child: FaIcon(
          _getIconForLabel(label),
          size: 24,
          color: isSelected ? PaxColors.deepPurple : PaxColors.lilac,
        ),
      ),
    );
  }
}
