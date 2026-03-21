import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/models/local/activity_model.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/local/activity_providers.dart';
import 'package:pax/widgets/achievement/filter_button.dart';
import 'package:pax/widgets/activity/activity_card.dart';
import 'package:pax/widgets/common/gradient_badge.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../theming/colors.dart' show PaxColors;
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';

class ActivityView extends ConsumerStatefulWidget {
  const ActivityView({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ActivityViewState();
}

class _ActivityFilterChipConfig {
  final String label;
  final ActivityType type;
  final VoidCallback? onTap;
  final int? badgeCount;

  const _ActivityFilterChipConfig({
    required this.label,
    required this.type,
    this.onTap,
    this.badgeCount,
  });
}

class _ActivityViewState extends ConsumerState<ActivityView> {
  Timer? _refreshTimer;
  bool _isRefreshingReferrals = false;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (ref.read(activityNotifierProvider).filterType ==
          ActivityType.taskCompletion) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  int get selectedIndex {
    final filterType = ref.watch(activityNotifierProvider).filterType;
    switch (filterType) {
      case ActivityType.taskCompletion:
        return 0;
      case ActivityType.reward:
        return 1;
      case ActivityType.withdrawal:
        return 2;
      case ActivityType.referral:
        return 3;
      case ActivityType.donation:
        return 4;
      default:
        return 0;
    }
  }

  AbstractButtonStyle _chipStyle(bool isSelected) {
    return const ButtonStyle.primary(density: ButtonDensity.dense)
        .withBackgroundColor(
          color: isSelected ? PaxColors.deepPurple : Colors.transparent,
        )
        .withBorder(
          border: Border.all(
            color: isSelected ? PaxColors.deepPurple : PaxColors.lilac,
            width: 2,
          ),
        )
        .withBorderRadius(borderRadius: BorderRadius.circular(7));
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onPressed,
    int? badgeCount,
  }) {
    final textColor = isSelected ? PaxColors.white : PaxColors.black;
    final hasBadge = badgeCount != null && badgeCount > 0;
    return Button(
      style: _chipStyle(isSelected),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: textColor)).withPadding(right: 6),
          if (hasBadge)
            GradientBadge(
              label: badgeCount > 99 ? '99+' : '$badgeCount',
              isOverlay: false,
              child: const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get the activity notifier to set filters
    final activityNotifier = ref.watch(activityNotifierProvider.notifier);

    // Get the userId
    final userId = ref.watch(authProvider).user.uid;

    // Get the current filter type
    final activityState = ref.watch(activityNotifierProvider);
    final filterType = activityState.filterType;
    // Watch for all activities (unfiltered)
    final allActivitiesAsync = ref.watch(allActivitiesProvider(userId));
    // Watch feature flags
    final featureFlags = ref.watch(featureFlagsProvider);

    return Scaffold(
      headers: [
        AppBar(
          height: 87.5,
          padding: EdgeInsets.all(8),
          backgroundColor: PaxColors.white,
          header: Row(
            children: [
              Text(
                'Activity',
                style: Theme.of(context).typography.base.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 32,
                  color: PaxColors.black,
                ),
              ),
              const Spacer(),
              IconButton.outline(
                onPressed:
                    _isRefreshingReferrals
                        ? null
                        : () async {
                          setState(() {
                            _isRefreshingReferrals = true;
                          });
                          try {
                            // Refresh only referral activities (backed by allActivitiesProvider).
                            if (kDebugMode) {
                              debugPrint('Refreshing referral activities');
                            }
                            ref.invalidate(allActivitiesProvider(userId));
                            // Wait for the new activities to load before clearing the spinner.
                            await ref.read(
                              allActivitiesProvider(userId).future,
                            );
                          } catch (_) {
                            // Ignore errors here; UI will show error state via provider.
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isRefreshingReferrals = false;
                              });
                            }
                          }
                        },
                density: ButtonDensity.icon,
                icon:
                    _isRefreshingReferrals
                        ? const CircularProgressIndicator(size: 20)
                        : const FaIcon(
                          FontAwesomeIcons.arrowsRotate,
                          size: 18,
                          color: PaxColors.deepPurple,
                        ),
              ),
            ],
          ).withPadding(bottom: 8),
          subtitle: featureFlags.when(
            data: (flags) {
              bool showTaskCompletions =
                  kDebugMode ||
                  flags['are_tasks_completions_available'] == true;
              final unclaimedCompletions = ref
                  .watch(unclaimedTaskCompletionsCountProvider)
                  .maybeWhen(data: (c) => c, orElse: () => null);
              final unclaimedReferrals = ref
                  .watch(unclaimedReferralsCountProvider)
                  .maybeWhen(data: (c) => c, orElse: () => null);

              final primaryConfigs = <_ActivityFilterChipConfig>[
                if (showTaskCompletions)
                  _ActivityFilterChipConfig(
                    label: 'Completions',
                    type: ActivityType.taskCompletion,
                    onTap: ref.read(analyticsProvider).taskCompletionsTapped,
                    badgeCount: unclaimedCompletions,
                  ),
                _ActivityFilterChipConfig(
                  label: 'Rewards',
                  type: ActivityType.reward,
                  onTap: ref.read(analyticsProvider).rewardsTapped,
                ),
                _ActivityFilterChipConfig(
                  label: 'Referrals',
                  type: ActivityType.referral,
                  onTap: ref.read(analyticsProvider).referralsTapped,
                  badgeCount: unclaimedReferrals,
                ),
              ];

              final overflowConfigs = const <_ActivityFilterChipConfig>[
                _ActivityFilterChipConfig(
                  label: 'Withdrawals',
                  type: ActivityType.withdrawal,
                ),
                _ActivityFilterChipConfig(
                  label: 'Donations',
                  type: ActivityType.donation,
                ),
              ];

              final isOverflowSelection = overflowConfigs.any(
                (config) => config.type == filterType,
              );

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final config in primaryConfigs)
                      _buildFilterChip(
                        label: config.label,
                        isSelected: filterType == config.type,
                        badgeCount: config.badgeCount,
                        onPressed: () {
                          activityNotifier.setFilterType(config.type);
                          config.onTap?.call();
                        },
                      ).withPadding(right: 8),
                    Button(
                      style: _chipStyle(isOverflowSelection),
                      onPressed: () {
                        showPopover(
                          context: context,
                          alignment: Alignment.topCenter,
                          offset: const Offset(0, 8),
                          builder: (popoverContext) {
                            return ModalContainer(
                              child: SizedBox(
                                width: MediaQuery.of(context).size.width,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final config in overflowConfigs)
                                      _buildFilterChip(
                                        label: config.label,
                                        isSelected: filterType == config.type,
                                        onPressed: () {
                                          activityNotifier.setFilterType(
                                            config.type,
                                          );
                                          closeOverlay(popoverContext);
                                        },
                                      ).withPadding(bottom: 8),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                      child: FaIcon(
                        FontAwesomeIcons.ellipsis,
                        size: 14,
                        color:
                            isOverflowSelection
                                ? PaxColors.white
                                : PaxColors.black,
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ),
        Divider(color: PaxColors.lightGrey),
      ],

      child: featureFlags.when(
        data: (flags) {
          bool showTaskCompletions =
              kDebugMode || flags['are_tasks_completions_available'] == true;

          if (selectedIndex == 0 && !showTaskCompletions) {
            return const SizedBox.shrink();
          }
          return allActivitiesAsync.when(
            data: (allActivities) {
              var filteredActivities = filterActivities(
                allActivities,
                filterType,
              );
              if (filterType == ActivityType.taskCompletion) {
                final completionFilter =
                    ref.watch(activityNotifierProvider).completionFilter;
                filteredActivities = filterTaskCompletionActivities(
                  filteredActivities,
                  allActivities,
                  completionFilter,
                );
              } else if (filterType == ActivityType.referral) {
                final referralFilter =
                    ref.watch(activityNotifierProvider).referralFilter;
                filteredActivities = filterReferralActivities(
                  filteredActivities,
                  referralFilter,
                );
              }
              final activityNotifier = ref.watch(
                activityNotifierProvider.notifier,
              );
              final completionFilter =
                  ref.watch(activityNotifierProvider).completionFilter;
              final referralFilter =
                  ref.watch(activityNotifierProvider).referralFilter;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (filterType == ActivityType.taskCompletion &&
                      showTaskCompletions)
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: PaxColors.deepPurple,
                          width: 0.1,
                        ),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: double.infinity,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FilterButton(
                                label: 'All',
                                isSelected:
                                    completionFilter == CompletionFilter.all,
                                onPressed:
                                    () => activityNotifier.setCompletionFilter(
                                      CompletionFilter.all,
                                    ),
                              ),
                              FilterButton(
                                label: 'Claimed',
                                isSelected:
                                    completionFilter ==
                                    CompletionFilter.claimed,
                                onPressed:
                                    () => activityNotifier.setCompletionFilter(
                                      CompletionFilter.claimed,
                                    ),
                              ),
                              FilterButton(
                                label: 'Unclaimed',
                                isSelected:
                                    completionFilter ==
                                    CompletionFilter.unclaimed,
                                onPressed:
                                    () => activityNotifier.setCompletionFilter(
                                      CompletionFilter.unclaimed,
                                    ),
                                badgeCount: ref
                                    .watch(
                                      unclaimedTaskCompletionsCountProvider,
                                    )
                                    .maybeWhen(
                                      data: (c) => c,
                                      orElse: () => null,
                                    ),
                              ),
                              FilterButton(
                                label: 'Incomplete',
                                isSelected:
                                    completionFilter ==
                                    CompletionFilter.incomplete,
                                onPressed:
                                    () => activityNotifier.setCompletionFilter(
                                      CompletionFilter.incomplete,
                                    ),
                              ),
                              FilterButton(
                                label: 'Expired',
                                isSelected:
                                    completionFilter ==
                                    CompletionFilter.expired,
                                onPressed:
                                    () => activityNotifier.setCompletionFilter(
                                      CompletionFilter.expired,
                                    ),
                                badgeCount: ref
                                    .watch(expiredTaskCompletionsCountProvider)
                                    .maybeWhen(
                                      data: (c) => c,
                                      orElse: () => null,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ).withPadding(bottom: 8),
                  if (filterType == ActivityType.referral)
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: PaxColors.deepPurple,
                          width: 0.1,
                        ),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: double.infinity,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FilterButton(
                                label: 'All',
                                isSelected:
                                    referralFilter == ReferralFilter.all,
                                onPressed:
                                    () => activityNotifier.setReferralFilter(
                                      ReferralFilter.all,
                                    ),
                              ),
                              FilterButton(
                                label: 'Unclaimed',
                                isSelected:
                                    referralFilter == ReferralFilter.unclaimed,
                                onPressed:
                                    () => activityNotifier.setReferralFilter(
                                      ReferralFilter.unclaimed,
                                    ),
                                badgeCount: ref
                                    .watch(unclaimedReferralsCountProvider)
                                    .maybeWhen(
                                      data: (c) => c,
                                      orElse: () => null,
                                    ),
                              ),
                              FilterButton(
                                label: 'Claimed',
                                isSelected:
                                    referralFilter == ReferralFilter.claimed,
                                onPressed:
                                    () => activityNotifier.setReferralFilter(
                                      ReferralFilter.claimed,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ).withPadding(bottom: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Builder(
                        builder: (context) {
                          if (filteredActivities.isEmpty) {
                            return SizedBox(
                              height: MediaQuery.of(context).size.height / 2,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      selectedIndex == 0
                                          ? 'No task completions'
                                          : selectedIndex == 1
                                          ? 'No rewards'
                                          : selectedIndex == 2
                                          ? 'No withdrawals'
                                          : selectedIndex == 3
                                          ? 'No referrals'
                                          : 'No donations',
                                      style: TextStyle(
                                        color: PaxColors.darkGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return Column(
                            children: [
                              for (var activity in filteredActivities)
                                ActivityCard(
                                  activity,
                                  allActivities: allActivities,
                                ).withPadding(bottom: 8),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ).withPadding(top: 8, left: 8, right: 8);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error:
                (error, stackTrace) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Error loading activities',
                        style: TextStyle(color: PaxColors.darkGrey),
                      ).withPadding(bottom: 8),
                    ],
                  ),
                ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stackTrace) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error loading feature flags',
                    style: TextStyle(color: PaxColors.darkGrey),
                  ).withPadding(bottom: 8),
                ],
              ),
            ),
      ),
    );
  }
}
