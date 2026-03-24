import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/route/home_selected_index_provider.dart';
import 'package:pax/providers/route/root_selected_index_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;
import 'package:pax/providers/local/claim_reward_context_provider.dart';
import 'package:flutter_svg/svg.dart';
import 'package:pax/utils/token_balance_util.dart';
import 'package:pax/utils/currency_symbol.dart';
import 'package:pax/constants/task_timer.dart';
import 'package:pax/widgets/toast.dart';
import 'package:pax/providers/local/claim_payout_context_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';

class ClaimRewardView extends ConsumerStatefulWidget {
  const ClaimRewardView({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ClaimRewardViewState();
}

class _ClaimRewardViewState extends ConsumerState<ClaimRewardView> {
  bool isClaiming = false;
  Timer? _countdownTimer;
  Timer? _refreshTimer;
  Duration _remainingTime = Duration.zero;

  /// Checks if the cooldown period has elapsed
  /// Returns true if the user can claim the reward (cooldown has passed)
  bool _canClaimReward({
    required int numberOfCooldownHours,
    required DateTime? timeCompleted,
  }) {
    if (numberOfCooldownHours == 0) return true;
    if (timeCompleted == null) return false;

    final cooldownEndDate = timeCompleted.add(
      Duration(hours: numberOfCooldownHours),
    );
    final now = DateTime.now();

    return now.isAfter(cooldownEndDate) ||
        now.isAtSameMomentAs(cooldownEndDate);
  }

  /// Formats duration as HH:MM:SS
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Starts the countdown timer
  void _startCountdown({
    required int numberOfCooldownHours,
    required DateTime? timeCompleted,
  }) {
    if (timeCompleted == null) return;

    final cooldownEndDate = timeCompleted.add(
      Duration(hours: numberOfCooldownHours),
    );
    final now = DateTime.now();
    final difference = cooldownEndDate.difference(now);

    if (difference.isNegative) return;

    _remainingTime = difference;
    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _remainingTime = _remainingTime - Duration(seconds: 1);
          if (_remainingTime.isNegative || _remainingTime == Duration.zero) {
            _remainingTime = Duration.zero;
            timer.cancel();
          }
        });
      }
    });
  }

  /// Stops the countdown timer
  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (!mounted) return;
      final taskIsCompleted =
          ref.read(claimRewardContextProvider)?.taskIsCompleted;
      if (taskIsCompleted == true) {
        timer.cancel();
        _refreshTimer = null;
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _stopCountdown();
    super.dispose();
  }

  void _navigateToClaimPayout(BuildContext context, {bool isDonation = false}) {
    final claimContext = ref.read(claimRewardContextProvider);
    if (claimContext == null) {
      _showErrorDialog('No claim context found.');
      return;
    }
    final isReferral = claimContext.isReferral == true;
    final isAchievement = claimContext.isAchievement == true;

    if (isAchievement) {
      ref.read(analyticsProvider).claimAchievementTapped({
        "achievementId": claimContext.achievementId,
      });
    } else if (isReferral) {
      ref.read(analyticsProvider).referralRewardClaimStarted({
        "referralId": claimContext.referralId,
      });
    } else {
      ref.read(analyticsProvider).claimRewardTapped({
        "taskId": claimContext.taskId,
        "screeningId": claimContext.screeningId,
        "taskCompletionId": claimContext.taskCompletionId,
      });
    }

    ref
        .read(claimPayoutContextProvider.notifier)
        .setContext(
          ClaimPayoutContext(
            claimKind:
                isAchievement
                    ? ClaimKind.achievement
                    : isReferral
                    ? ClaimKind.referral
                    : ClaimKind.task,
            tokenId: claimContext.tokenId ?? 1,
            amount: claimContext.amount ?? 0,
            taskCompletionId: claimContext.taskCompletionId,
            referralId: claimContext.referralId,
            achievementId: claimContext.achievementId,
            isDonation: isDonation,
          ),
        );

    context.push('/claim-reward/claim-payout/select-wallet');
  }

  void _showErrorDialog(String errorMessage) {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('Claim Reward Error'),
            content: Text(
              errorMessage,
              maxLines: 3,
              style: TextStyle(color: PaxColors.black),
            ),
            actions: [
              OutlineButton(
                onPressed: () {
                  ref.read(analyticsProvider).claimErrorDialogOkTapped();
                  dialogContext.go("/home");
                },
                child: Text('OK'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _goHome(BuildContext context) {
    final claimContext = ref.read(claimRewardContextProvider);
    final taskCompletionId = claimContext?.taskCompletionId;

    ref.read(analyticsProvider).goHomeToCompleteTaskTapped({
      "taskCompletionId": taskCompletionId,
    });
    ref.read(rootSelectedIndexProvider.notifier).setIndex(0);
    ref.read(claimRewardContextProvider.notifier).clear();
    ref.read(homeSelectedIndexProvider.notifier).setIndex(1);
    context.go("/home");
  }

  @override
  Widget build(BuildContext context) {
    final claimContext = ref.watch(claimRewardContextProvider);
    final taskCompletionId = claimContext?.taskCompletionId;
    final amount = claimContext?.amount;
    final tokenId = claimContext?.tokenId;
    final txnHash = claimContext?.txnHash;
    final taskIsCompleted = claimContext?.taskIsCompleted;
    final numberOfCooldownHours = claimContext?.numberOfCooldownHours ?? 0;
    final timeCompleted = claimContext?.timeCompleted?.toDate();
    final timeCreated = claimContext?.timeCreated?.toDate();
    final isValid = claimContext?.isValid ?? true;
    final isReferral = claimContext?.isReferral == true;
    final isAchievement = claimContext?.isAchievement == true;
    final referralId = claimContext?.referralId;

    final isExpired =
        !isReferral &&
        !isAchievement &&
        taskIsCompleted == false &&
        (timeCreated == null ||
            DateTime.now().isAfter(
              timeCreated.add(Duration(minutes: taskTimerDurationMinutes)),
            ));

    final canClaim = _canClaimReward(
      numberOfCooldownHours: numberOfCooldownHours,
      timeCompleted: timeCompleted,
    );
    final disableClaimActions =
        (txnHash != null && txnHash.isNotEmpty) ||
        (!canClaim && taskIsCompleted == true) ||
        (isValid == false && taskIsCompleted == true) ||
        (taskIsCompleted == false && isExpired);
    final goodCollectiveConfigAsync = ref.watch(goodCollectiveConfigProvider);
    final showDonationClaimCta =
        kDebugMode ||
        goodCollectiveConfigAsync.maybeWhen(
          data:
              (config) =>
                  config.isDonationAvailable &&
                  config.goodcollectives.isNotEmpty,
          orElse: () => false,
        );
    final claimActionLabel =
        isReferral
            ? (txnHash != null && txnHash.isNotEmpty)
                ? 'Claimed'
                : 'Claim reward'
            : isAchievement
            ? (txnHash != null && txnHash.isNotEmpty)
                ? 'Claimed'
                : 'Claim achievement reward'
            : taskIsCompleted == false
            ? (isExpired ? 'Task expired' : 'Complete task')
            : (txnHash != null && txnHash.isNotEmpty)
            ? 'Claimed'
            : isValid == false
            ? 'Invalid Submission'
            : !canClaim
            ? 'Cooldown Active'
            : 'Claim reward';

    // Start countdown timer if cooldown is active
    if (numberOfCooldownHours > 0 &&
        taskIsCompleted == true &&
        isValid != false &&
        (txnHash == null || txnHash.isEmpty) &&
        !canClaim) {
      _startCountdown(
        numberOfCooldownHours: numberOfCooldownHours,
        timeCompleted: timeCompleted,
      );
    } else {
      _stopCountdown();
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      headers: [
        AppBar(
          padding: EdgeInsets.all(8),
          leading: [],
          backgroundColor: PaxColors.white,
        ).withPadding(top: 16, horizontal: 8),
      ],
      footers: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            children: [
              Divider().withPadding(top: 10, bottom: 10),
              if (showDonationClaimCta &&
                  !disableClaimActions &&
                  taskIsCompleted == true)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: PrimaryButton(
                    onPressed:
                        isClaiming
                            ? null
                            : () {
                              ref.read(analyticsProvider).claimDonationCtaTapped({
                                "claimKind":
                                    isAchievement
                                        ? "achievement"
                                        : isReferral
                                        ? "referral"
                                        : "task",
                                "isDonation": true,
                              });
                              _navigateToClaimPayout(
                                context,
                                isDonation: true,
                              );
                            },
                    child: Text(
                      'Claim and make an impact',
                      style: Theme.of(context).typography.base.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: PaxColors.white,
                      ),
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: showDonationClaimCta
                    ? OutlineButton(
                      onPressed:
                          disableClaimActions
                              ? null
                              : () {
                                if (isClaiming) return;
                                ref.read(analyticsProvider).claimPrimaryCtaTapped({
                                  "claimKind":
                                      isAchievement
                                          ? "achievement"
                                          : isReferral
                                          ? "referral"
                                          : "task",
                                  "isDonation": false,
                                  "taskIsCompleted": taskIsCompleted,
                                });

                                if (taskIsCompleted == false) {
                                  _goHome(context);
                                } else {
                                  _navigateToClaimPayout(context);
                                }
                              },
                      child:
                          isClaiming
                              ? const CircularProgressIndicator()
                              : Text(
                                claimActionLabel,
                                style: Theme.of(context).typography.base
                                    .copyWith(
                                      fontWeight: FontWeight.normal,
                                      fontSize: 14,
                                      color: PaxColors.deepPurple,
                                    ),
                              ),
                    )
                    : PrimaryButton(
                      onPressed:
                          disableClaimActions
                              ? null
                              : () {
                                if (isClaiming) return;
                                ref.read(analyticsProvider).claimPrimaryCtaTapped({
                                  "claimKind":
                                      isAchievement
                                          ? "achievement"
                                          : isReferral
                                          ? "referral"
                                          : "task",
                                  "isDonation": false,
                                  "taskIsCompleted": taskIsCompleted,
                                });

                                if (taskIsCompleted == false) {
                                  _goHome(context);
                                } else {
                                  _navigateToClaimPayout(context);
                                }
                              },
                      child:
                          isClaiming
                              ? const CircularProgressIndicator()
                              : Text(
                                claimActionLabel,
                                style: Theme.of(context).typography.base
                                    .copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: PaxColors.white,
                                    ),
                              ),
                    ),
              ).withPadding(top: 10),
            ],
          ),
        ).withPadding(bottom: 32),
      ],
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    isReferral
                        ? 'lib/assets/svgs/pax_v2_referral.svg'
                        : 'lib/assets/svgs/task_complete.svg',
                  ),
                  if (isReferral ||
                      isAchievement ||
                      isValid != false ||
                      taskIsCompleted == false)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          isReferral
                              ? "Referral Reward"
                              : isAchievement
                              ? "Achievement Reward"
                              : taskIsCompleted == false
                              ? "You will earn"
                              : "You earned",
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                          ),
                        ).withPadding(bottom: 16, top: 16),
                        // Placeholder for reward amount and currency
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              amount != null
                                  ? TokenBalanceUtil.getLocaleFormattedAmount(
                                    amount,
                                  )
                                  : '--',
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.normal,
                              ),
                            ).withPadding(right: 4),
                            if (tokenId != null)
                              SvgPicture.asset(
                                'lib/assets/svgs/currencies/${CurrencySymbolUtil.getNameForCurrency(tokenId)}.svg',
                                height: tokenId == 1 ? 25 : 20,
                              ),
                          ],
                        ),
                      ],
                    ).withPadding(bottom: 12),
                  if (isReferral && referralId != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Referral ID: ${referralId.substring(0, 8)}...",
                          style: TextStyle(
                            fontSize: 12,
                            color: PaxColors.darkGrey,
                          ),
                        ).withPadding(right: 8),
                        InkWell(
                          onTap: () async {
                            ref.read(analyticsProvider).claimReferralIdCopyTapped({
                              "referralId": referralId,
                            });
                            await Clipboard.setData(
                              ClipboardData(text: referralId),
                            );
                            if (context.mounted) {
                              showToast(
                                context: context,
                                location: ToastLocation.topCenter,
                                builder:
                                    (context, overlay) => Toast(
                                      toastColor: PaxColors.green,
                                      text: 'Referral ID copied',
                                      trailingIcon:
                                          FontAwesomeIcons.solidCircleCheck,
                                    ),
                              );
                            }
                          },
                          child: Container(
                            padding: EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: PaxColors.deepPurple.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: FaIcon(
                              FontAwesomeIcons.copy,
                              size: 12,
                              color: PaxColors.deepPurple,
                            ),
                          ),
                        ),
                      ],
                    ).withPadding(top: 16),
                  if (isAchievement &&
                      claimContext?.achievementId != null &&
                      claimContext!.achievementId!.isNotEmpty)
                    Text(
                      "Achievement ID: ${claimContext.achievementId!.substring(0, 8)}...",
                      style: TextStyle(fontSize: 12, color: PaxColors.darkGrey),
                    ).withPadding(top: 16),
                  if (!isReferral &&
                      !isAchievement &&
                      taskCompletionId != null &&
                      (isValid != false || taskIsCompleted == false))
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Task Completion ID: ${taskCompletionId.substring(0, 8)}...",
                          style: TextStyle(
                            fontSize: 12,
                            color: PaxColors.darkGrey,
                          ),
                        ).withPadding(right: 8),
                        InkWell(
                          onTap: () async {
                            ref
                                .read(analyticsProvider)
                                .claimTaskCompletionIdCopyTapped({
                                  "taskCompletionId": taskCompletionId,
                                });
                            await Clipboard.setData(
                              ClipboardData(text: taskCompletionId),
                            );
                            if (context.mounted) {
                              showToast(
                                context: context,
                                location: ToastLocation.topCenter,
                                builder:
                                    (context, overlay) => Toast(
                                      toastColor: PaxColors.green,
                                      text: 'Task Completion ID copied',
                                      trailingIcon:
                                          FontAwesomeIcons.solidCircleCheck,
                                    ),
                              );
                            }
                          },
                          child: Container(
                            padding: EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: PaxColors.deepPurple.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: FaIcon(
                              FontAwesomeIcons.copy,
                              size: 12,
                              color: PaxColors.deepPurple,
                            ),
                          ),
                        ),
                      ],
                    ).withPadding(top: 16),

                  if (!isReferral &&
                      !isAchievement &&
                      numberOfCooldownHours > 0 &&
                      taskIsCompleted == true &&
                      isValid != false &&
                      (txnHash == null || txnHash.isEmpty))
                    Container(
                      margin: EdgeInsets.only(top: 24),
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:
                            canClaim
                                ? PaxColors.green.withValues(alpha: 0.1)
                                : PaxColors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: canClaim ? PaxColors.green : PaxColors.red,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                canClaim
                                    ? Icons.check_circle
                                    : Icons.access_time,
                                color:
                                    canClaim ? PaxColors.green : PaxColors.red,
                                size: 20,
                              ).withPadding(right: 8),
                              Text(
                                canClaim
                                    ? 'Cooldown Complete'
                                    : 'Cooldown Active',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      canClaim
                                          ? PaxColors.green
                                          : PaxColors.red,
                                ),
                              ),
                            ],
                          ).withPadding(bottom: canClaim ? 0 : 8),
                          if (!canClaim && _remainingTime > Duration.zero)
                            Column(
                              children: [
                                Text(
                                  'You can claim this reward in:',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: PaxColors.black,
                                  ),
                                  textAlign: TextAlign.center,
                                ).withPadding(bottom: 8),
                                Text(
                                  _formatDuration(_remainingTime),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: PaxColors.red,
                                    fontFamily: 'monospace',
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          if (canClaim)
                            Text(
                              'You can now claim your reward!',
                              style: TextStyle(
                                fontSize: 14,
                                color: PaxColors.black,
                              ),
                              textAlign: TextAlign.center,
                            ).withPadding(top: 8),
                        ],
                      ),
                    ),

                  if (!isReferral &&
                      !isAchievement &&
                      taskIsCompleted == false &&
                      isExpired)
                    Container(
                      margin: EdgeInsets.only(top: 24),
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: PaxColors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: PaxColors.red, width: 1),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.schedule,
                                color: PaxColors.red,
                                size: 20,
                              ).withPadding(right: 8),
                              Text(
                                'Task expired.',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: PaxColors.red,
                                ),
                              ),
                            ],
                          ).withPadding(bottom: 8),
                          Text(
                            'This task can no longer be completed. The time to complete it has passed.',
                            style: TextStyle(
                              fontSize: 14,
                              color: PaxColors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            'Contact support if you have questions.',
                            style: TextStyle(
                              fontSize: 14,
                              color: PaxColors.black,
                            ),
                            textAlign: TextAlign.center,
                          ).withPadding(top: 12),
                        ],
                      ),
                    ),

                  if (!isReferral &&
                      isValid == false &&
                      taskIsCompleted == true)
                    Container(
                      margin: EdgeInsets.only(top: 24),
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: PaxColors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: PaxColors.red, width: 1),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: PaxColors.red,
                                size: 20,
                              ).withPadding(right: 8),
                              Text(
                                'Invalid submission.',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: PaxColors.red,
                                ),
                              ),
                            ],
                          ).withPadding(bottom: 8),
                          Text(
                            'Your task submission cannot be rewarded. Copy the task completion ID and contact support.',
                            style: TextStyle(
                              fontSize: 14,
                              color: PaxColors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (taskCompletionId != null)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Task Completion ID: ${taskCompletionId.substring(0, 8)}...",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: PaxColors.darkGrey,
                                  ),
                                ).withPadding(right: 8),
                                InkWell(
                                  onTap: () async {
                                    ref
                                        .read(analyticsProvider)
                                        .claimTaskCompletionIdCopyTapped({
                                          "taskCompletionId": taskCompletionId,
                                        });
                                    await Clipboard.setData(
                                      ClipboardData(text: taskCompletionId),
                                    );
                                    if (context.mounted) {
                                      showToast(
                                        context: context,
                                        location: ToastLocation.topCenter,
                                        builder:
                                            (context, overlay) => Toast(
                                              toastColor: PaxColors.green,
                                              text: 'Task Completion ID copied',
                                              trailingIcon:
                                                  FontAwesomeIcons
                                                      .solidCircleCheck,
                                            ),
                                      );
                                    }
                                  },
                                  child: Container(
                                    padding: EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: PaxColors.deepPurple.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: FaIcon(
                                      FontAwesomeIcons.copy,
                                      size: 12,
                                      color: PaxColors.deepPurple,
                                    ),
                                  ),
                                ),
                              ],
                            ).withPadding(top: 16),
                        ],
                      ),
                    ),
                  Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
