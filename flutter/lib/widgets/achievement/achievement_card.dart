import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' show InkWell;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/local/claim_reward_context_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/gradient_border.dart';
import 'package:pax/models/firestore/achievement/achievement_model.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pax/providers/local/achievement_claim_provider.dart';

class AchievementCard extends ConsumerStatefulWidget {
  const AchievementCard({required this.achievement, super.key});

  final Achievement achievement;

  @override
  ConsumerState<AchievementCard> createState() => _AchievementCardState();
}

class _AchievementCardState extends ConsumerState<AchievementCard> {
  @override
  Widget build(BuildContext context) {
    final isEarned = widget.achievement.status == AchievementStatus.earned;
    final isClaimed = widget.achievement.status == AchievementStatus.claimed;
    final claimState = ref.watch(achievementClaimProvider);
    final isClaiming = claimState.isClaiming(widget.achievement.id);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: (isEarned && !isClaimed && !isClaiming) ? _handleClaim : null,
      child: Container(
        width: MediaQuery.of(context).size.width,
        padding: EdgeInsets.all(8),
        decoration:
            isEarned && !isClaimed
                ? ShapeDecoration(
                  shape: GradientBorder(
                    gradient: LinearGradient(
                      colors: PaxColors.orangeToPinkGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    width: 2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  color: Colors.white,
                )
                : BoxDecoration(
                  color: PaxColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: PaxColors.lightLilac, width: 1),
                ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [_buildAchievementIcon().withPadding(right: 12)],
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              widget.achievement.name ?? 'Achievement',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: PaxColors.black,
                              ),
                            ),
                          ),
                          Text(
                            isEarned
                                ? 'Earned'
                                : 'G\$ ${widget.achievement.amountEarned}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ).withPadding(bottom: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.achievement.goal,
                            style: TextStyle(
                              fontWeight: FontWeight.normal,
                              fontSize: 12,
                              color: PaxColors.black,
                            ),
                          ).withPadding(bottom: 8),

                          if (isEarned || isClaimed)
                            Text(
                              'Earned on ${DateFormat('MMMM d, yyyy | h:mm a').format(widget.achievement.timeCompleted!.toDate())}',
                              style: TextStyle(
                                fontWeight: FontWeight.normal,
                                fontSize: 11,
                                color: PaxColors.black,
                              ),
                            ),

                          if (!isEarned && !isClaimed)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: 5,
                                  child: ShaderMask(
                                    shaderCallback: (Rect bounds) {
                                      return LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: PaxColors.orangeToPinkGradient,
                                        stops: [0.0, 1.0],
                                      ).createShader(bounds);
                                    },
                                    blendMode: BlendMode.srcIn,
                                    child: Progress(
                                      progress:
                                          (widget.achievement.tasksCompleted /
                                                  widget
                                                      .achievement
                                                      .tasksNeededForCompletion *
                                                  100)
                                              .toDouble(),
                                      min: 0,
                                      max: 100,
                                    ),
                                  ),
                                ).withPadding(bottom: 4),

                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      widget.achievement.name == 'Good Impact'
                                          ? '${widget.achievement.tasksCompleted} G\$/${widget.achievement.tasksNeededForCompletion} G\$'
                                          : '${widget.achievement.tasksCompleted}/${widget.achievement.tasksNeededForCompletion}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.normal,
                                        fontSize: 11,
                                        color: PaxColors.black,
                                      ),
                                    ),
                                    Text(
                                      widget.achievement.name == 'Good Impact'
                                          ? 'Donate ${widget.achievement.tasksNeededForCompletion - widget.achievement.tasksCompleted} G\$ more to earn'
                                          : 'Complete ${widget.achievement.tasksNeededForCompletion - widget.achievement.tasksCompleted} more to earn',
                                      style: TextStyle(
                                        fontWeight: FontWeight.normal,
                                        fontSize: 11,
                                        color: PaxColors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ).withPadding(bottom: 8),
            SizedBox(
              width: MediaQuery.of(context).size.width,
              height: 35,
              child: Button(
                onPressed: (isClaiming || isClaimed) ? null : _handleClaim,
                enabled: isEarned && !isClaimed && !isClaiming,
                style:
                    isEarned && !isClaimed && !isClaiming
                        ? const ButtonStyle.primary(
                          density: ButtonDensity.dense,
                        ).withBorderRadius(
                          borderRadius: BorderRadius.circular(7),
                        )
                        : const ButtonStyle.outline(
                              density: ButtonDensity.dense,
                            )
                            .withBorderRadius(
                              borderRadius: BorderRadius.circular(7),
                            )
                            .withBorder(
                              border: Border.all(
                                color: PaxColors.mediumPurple,
                                width: 2,
                              ),
                            ),
                child:
                    isClaiming
                        ? CircularProgressIndicator()
                        : Text(
                          isClaimed
                              ? 'Claimed G\$ ${widget.achievement.amountEarned}'
                              : 'Claim G\$ ${widget.achievement.amountEarned}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color:
                                isEarned && !isClaimed && !isClaiming
                                    ? PaxColors.white
                                    : PaxColors.lilac,
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    ).withPadding(bottom: 8);
  }

  Widget _buildAchievementIcon() {
    final connectorLevel = widget.achievement.connectorLevelBadge;

    if (connectorLevel != null && connectorLevel > 1) {
      final iconCount = connectorLevel == 2 ? 2 : 3;

      return SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          children: List.generate(iconCount, (index) {
            final reverseIndex = iconCount - 1 - index;
            final offset = reverseIndex * 6.0;
            return Positioned(
              left: offset,
              top: offset,
              child: _buildGradientIcon(24),
            );
          }),
        ),
      );
    }

    return SizedBox(
      width: 48,
      height: 48,
      child: Center(child: _buildGradientIcon(30)),
    );
  }

  Widget _buildGradientIcon(double size) {
    return ShaderMask(
      shaderCallback:
          (bounds) => LinearGradient(
            colors: PaxColors.orangeToPinkGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: FaIcon(
        widget.achievement.icon,
        size: size,
        color: PaxColors.white,
      ),
    );
  }

  void _handleClaim() {
    ref.read(analyticsProvider).claimAchievementTapped({
      'achievementId': widget.achievement.id,
      'achievementName': widget.achievement.name,
    });

    ref
        .read(claimRewardContextProvider.notifier)
        .setContext(
          taskIsCompleted: true,
          amount: widget.achievement.amountEarned ?? 0,
          tokenId: 1,
          txnHash: widget.achievement.txnHash,
          isValid: true,
          isAchievement: true,
          achievementId: widget.achievement.id,
        );

    context.push('/claim-reward');
  }
}
