// lib/views/activity/activity_view.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/models/local/activity_model.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/local/activity_providers.dart';
import 'package:pax/widgets/achievement/filter_button.dart';
import 'package:pax/widgets/activity/activity_card.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../theming/colors.dart' show PaxColors;
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';

class ActivityView extends ConsumerStatefulWidget {
  const ActivityView({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ActivityViewState();
}

class _ActivityViewState extends ConsumerState<ActivityView> {
  Timer? _refreshTimer;

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
      default:
        return 0;
    }
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
            ],
          ).withPadding(bottom: 8),
          subtitle: featureFlags.when(
            data: (flags) {
              bool showTaskCompletions =
                  kDebugMode ||
                  flags['are_tasks_completions_available'] == true;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showTaskCompletions)
                      Button(
                        style: const ButtonStyle.primary(
                              density: ButtonDensity.dense,
                            )
                            .withBackgroundColor(
                              color:
                                  selectedIndex == 0
                                      ? PaxColors.deepPurple
                                      : Colors.transparent,
                            )
                            .withBorder(
                              border: Border.all(
                                color:
                                    selectedIndex == 0
                                        ? PaxColors.deepPurple
                                        : PaxColors.lilac,
                                width: 2,
                              ),
                            )
                            .withBorderRadius(
                              borderRadius: BorderRadius.circular(7),
                            ),
                        onPressed: () {
                          activityNotifier.setFilterType(
                            ActivityType.taskCompletion,
                          );
                          ref.read(analyticsProvider).taskCompletionsTapped();
                        },
                        child: () {
                          final unclaimedCount = ref
                              .watch(unclaimedTaskCompletionsCountProvider)
                              .maybeWhen(data: (c) => c, orElse: () => null);
                          final textColor =
                              selectedIndex == 0
                                  ? PaxColors.white
                                  : PaxColors.black;
                          final hasBadge =
                              unclaimedCount != null && unclaimedCount > 0;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Completions',
                                style: TextStyle(color: textColor),
                              ).withPadding(right: 6),
                              if (hasBadge) ...[
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: PaxColors.orange,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    unclaimedCount > 99
                                        ? '99+'
                                        : '$unclaimedCount',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: PaxColors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        }(),
                      ).withPadding(right: 8),

                    Button(
                      style: const ButtonStyle.primary(
                            density: ButtonDensity.dense,
                          )
                          .withBackgroundColor(
                            color:
                                selectedIndex == 1
                                    ? PaxColors.deepPurple
                                    : Colors.transparent,
                          )
                          .withBorder(
                            border: Border.all(
                              color:
                                  selectedIndex == 1
                                      ? PaxColors.deepPurple
                                      : PaxColors.lilac,
                              width: 2,
                            ),
                          )
                          .withBorderRadius(
                            borderRadius: BorderRadius.circular(7),
                          ),
                      onPressed: () {
                        activityNotifier.setFilterType(ActivityType.reward);
                        ref.read(analyticsProvider).rewardsTapped();
                      },
                      child: Text(
                        'Rewards',
                        style: TextStyle(
                          color:
                              selectedIndex == 1
                                  ? PaxColors.white
                                  : PaxColors.black,
                        ),
                      ),
                    ).withPadding(right: 8),

                    Button(
                      style: const ButtonStyle.primary(
                            density: ButtonDensity.dense,
                          )
                          .withBackgroundColor(
                            color:
                                selectedIndex == 2
                                    ? PaxColors.deepPurple
                                    : Colors.transparent,
                          )
                          .withBorder(
                            border: Border.all(
                              color:
                                  selectedIndex == 2
                                      ? PaxColors.deepPurple
                                      : PaxColors.lilac,
                              width: 2,
                            ),
                          )
                          .withBorderRadius(
                            borderRadius: BorderRadius.circular(7),
                          ),
                      onPressed: () {
                        activityNotifier.setFilterType(ActivityType.withdrawal);
                        ref.read(analyticsProvider).withdrawalsTapped();
                      },
                      child: Text(
                        'Withdrawals',
                        style: TextStyle(
                          color:
                              selectedIndex == 2
                                  ? PaxColors.white
                                  : PaxColors.black,
                        ),
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
              }
              final activityNotifier = ref.watch(
                activityNotifierProvider.notifier,
              );
              final completionFilter =
                  ref.watch(activityNotifierProvider).completionFilter;
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
                                          : 'No withdrawals',
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
