import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_svg/svg.dart' show SvgPicture;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/local/claim_payout_context_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/currency_symbol.dart';
import 'package:pax/utils/token_balance_util.dart';
import 'package:pax/widgets/change_withdrawal_method_card.dart';
import 'package:pax/services/reward_service.dart';
import 'package:pax/providers/local/achievement_claim_provider.dart';
import 'package:pax/providers/db/achievement/achievement_provider.dart';
import 'package:pax/utils/error_message_util.dart';

import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider, Consumer;

class ClaimReviewSummaryView extends ConsumerStatefulWidget {
  const ClaimReviewSummaryView({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ClaimReviewSummaryViewState();
}

class _ClaimReviewSummaryViewState
    extends ConsumerState<ClaimReviewSummaryView> {
  bool _isProcessing = false;

  Future<void> _processClaim() async {
    final claimContext = ref.read(claimPayoutContextProvider);
    if (claimContext == null) {
      _showErrorDialog('Claim details not found');
      return;
    }

    final withdrawalMethod = claimContext.selectedWithdrawalMethod;
    if (withdrawalMethod == null) {
      _showErrorDialog('No payment method selected');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    ref.read(analyticsProvider).claimReviewSummarySubmitTapped({
      "claimKind": claimContext.claimKind.name,
      "selectedPaymentMethodId": withdrawalMethod.id,
    });
    ref.read(analyticsProvider).reviewSummaryWithdrawTapped();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => PopScope(
            canPop: false,
            child: AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator().withPadding(bottom: 24),
                  Text(
                    'Please wait while we process your claim...',
                    style: TextStyle(
                      color: PaxColors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                  ).withPadding(bottom: 12),
                  Text(
                    'Please be patient and do not close the app.',
                    style: TextStyle(
                      color: PaxColors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
    );

    try {
      final recipientAddress = withdrawalMethod.walletAddress;

      switch (claimContext.claimKind) {
        case ClaimKind.task:
          await ref
              .read(rewardServiceProvider)
              .rewardParticipant(
                taskCompletionId: claimContext.taskCompletionId!,
                recipientAddress: recipientAddress,
              );
          ref.read(analyticsProvider).claimRewardComplete({
            "taskCompletionId": claimContext.taskCompletionId,
            "selectedPaymentMethodId": withdrawalMethod.id,
          });
          break;
        case ClaimKind.referral:
          await ref
              .read(rewardServiceProvider)
              .claimReferralReward(
                referralId: claimContext.referralId!,
                recipientAddress: recipientAddress,
              );
          ref.read(analyticsProvider).referralRewardClaimSucceeded({
            "referralId": claimContext.referralId,
            "selectedPaymentMethodId": withdrawalMethod.id,
          });
          break;
        case ClaimKind.achievement:
          final achievements = ref.read(achievementsProvider).achievements;
          final achievement = achievements.firstWhere(
            (a) => a.id == claimContext.achievementId,
          );
          await ref
              .read(achievementClaimProvider.notifier)
              .claimAchievement(
                achievement: achievement,
                recipientAddress: recipientAddress,
              );
          ref.read(analyticsProvider).claimAchievementComplete({
            "achievementId": claimContext.achievementId,
            "selectedPaymentMethodId": withdrawalMethod.id,
          });
          break;
      }

      if (!mounted) return;
      context.pop();
      _showSuccessDialog();
    } catch (e) {
      if (!mounted) return;
      context.pop();
      _showErrorDialog(
        'Claim failed: ${ErrorMessageUtil.userFacing(e.toString())}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showSuccessDialog() {
    final claimContext = ref.read(claimPayoutContextProvider);
    final amount = claimContext?.amount ?? 0;
    final tokenId = claimContext?.tokenId ?? 0;
    final paymentMethod = claimContext?.selectedWithdrawalMethod;

    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  'lib/assets/svgs/withdrawal_complete.svg',
                ).withPadding(bottom: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Reward Claimed!',
                      style: TextStyle(
                        color: PaxColors.deepPurple,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ).withPadding(bottom: 8),
                  ],
                ),
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          TokenBalanceUtil.getLocaleFormattedAmount(amount),
                          style: TextStyle(
                            color: PaxColors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ).withPadding(right: 4),
                        SvgPicture.asset(
                          'lib/assets/svgs/currencies/${CurrencySymbolUtil.getNameForCurrency(tokenId)}.svg',
                          height: 25,
                        ),
                      ],
                    ).withPadding(vertical: 4),
                    Text(
                      'sent to your ${toBeginningOfSentenceCase(paymentMethod?.name)} account!',
                      style: TextStyle(
                        color: PaxColors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ).withPadding(vertical: 8),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: MediaQuery.of(context).size.width / 2.5,
                      child: PrimaryButton(
                        child: const Text('OK'),
                        onPressed: () {
                          ref
                              .read(analyticsProvider)
                              .claimReviewSummarySuccessOkTapped({
                                "claimKind": claimContext?.claimKind.name,
                              });
                          ref.read(claimPayoutContextProvider.notifier).clear();
                          context.go("/home");
                        },
                      ),
                    ),
                  ],
                ).withPadding(top: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showErrorDialog(String errorMessage) {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Column(
              children: [
                SvgPicture.asset(
                  'lib/assets/svgs/canvassing.svg',
                  height: 24,
                ).withPadding(bottom: 16),
                Text(
                  'Claim Failed',
                  style: TextStyle(fontSize: 16),
                ).withAlign(Alignment.center),
              ],
            ),
            content: Text(
              errorMessage,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              OutlineButton(
                onPressed: () {
                  ref.read(analyticsProvider).claimReviewSummaryErrorOkTapped();
                  context.go("/home");
                },
                child: Text('OK'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final claimContext = ref.watch(claimPayoutContextProvider);
    final amount = claimContext?.amount ?? 0;
    final tokenId = claimContext?.tokenId ?? 0;
    final paymentMethod = claimContext?.selectedWithdrawalMethod;

    final claimKind = claimContext?.claimKind ?? ClaimKind.task;
    final claimLabel = switch (claimKind) {
      ClaimKind.achievement => 'Achievement Reward',
      ClaimKind.referral => 'Referral Reward',
      ClaimKind.task => 'Task Reward',
    };

    return Scaffold(
      backgroundColor: PaxColors.white,
      headers: [
        AppBar(
          padding: EdgeInsets.all(8),
          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  ref.read(analyticsProvider).claimReviewSummaryBackTapped({
                    "claimKind": claimContext?.claimKind.name,
                  });
                  context.pop();
                },
                child: FaIcon(
                  FontAwesomeIcons.arrowLeftLong,
                  size: 20,
                  color: PaxColors.deepPurple,
                ),
              ),
              Spacer(),
              Text(
                "Review Summary",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, color: PaxColors.black),
              ),
              Spacer(),
            ],
          ),
        ).withPadding(top: 16, horizontal: 8),
        Divider(color: PaxColors.lightGrey),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            width: double.infinity,
            decoration: BoxDecoration(
              color: PaxColors.lightLilac.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                FaIcon(
                  claimKind == ClaimKind.achievement
                      ? FontAwesomeIcons.trophy
                      : claimKind == ClaimKind.referral
                      ? FontAwesomeIcons.userPlus
                      : FontAwesomeIcons.clipboardCheck,
                  size: 14,
                  color: PaxColors.deepPurple,
                ),
                SizedBox(width: 8),
                Text(
                  claimLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: PaxColors.deepPurple,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: PaxColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PaxColors.lightLilac, width: 1),
            ),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: PaxColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PaxColors.lightLilac, width: 1),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Reward Amount',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          Text(
                            TokenBalanceUtil.getLocaleFormattedAmount(amount),
                            style: const TextStyle(
                              fontSize: 16,
                              color: PaxColors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SvgPicture.asset(
                            'lib/assets/svgs/currencies/${CurrencySymbolUtil.getNameForCurrency(tokenId)}.svg',
                            height: 25,
                          ).withPadding(left: 4),
                        ],
                      ).withPadding(bottom: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Gas Fee',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Free',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ).withPadding(bottom: 16),
                      Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          Text(
                            TokenBalanceUtil.getLocaleFormattedAmount(amount),
                            style: const TextStyle(
                              fontSize: 16,
                              color: PaxColors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SvgPicture.asset(
                            'lib/assets/svgs/currencies/${CurrencySymbolUtil.getNameForCurrency(tokenId)}.svg',
                            height: 25,
                          ).withPadding(left: 4),
                        ],
                      ).withPadding(vertical: 16),
                    ],
                  ),
                ).withPadding(bottom: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      'Withdraw to',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ).withPadding(vertical: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PaxColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PaxColors.lightLilac, width: 1),
                  ),
                  child: Column(
                    children:
                        paymentMethod != null
                            ? [
                              ChangeWithdrawalMethodCard(
                                paymentMethod,
                                fallbackRoute:
                                    '/claim-reward/claim-payout/select-wallet',
                              ),
                            ]
                            : [Text('No payment method selected')],
                  ),
                ),
              ],
            ),
          ),
          Spacer(flex: 2),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            color: Colors.white,
            child: Column(
              children: [
                Divider().withPadding(vertical: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: PrimaryButton(
                    onPressed: _isProcessing ? null : _processClaim,
                    child:
                        _isProcessing
                            ? CircularProgressIndicator(onSurface: true)
                            : Text(
                              'Claim reward',
                              style: Theme.of(context).typography.base.copyWith(
                                fontWeight: FontWeight.normal,
                                fontSize: 14,
                                color: PaxColors.white,
                              ),
                            ),
                  ),
                ),
              ],
            ),
          ).withMargin(bottom: 32),
        ],
      ).withPadding(horizontal: 8, bottom: 8),
    );
  }
}
