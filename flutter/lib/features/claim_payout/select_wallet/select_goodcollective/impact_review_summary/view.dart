import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart' show SvgPicture;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/db/achievement/achievement_provider.dart';
import 'package:pax/providers/local/achievement_claim_provider.dart';
import 'package:pax/providers/local/activity_providers.dart';
import 'package:pax/providers/local/claim_payout_context_provider.dart';
import 'package:pax/providers/local/donation_provider.dart';
import 'package:pax/services/reward_service.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/currency_symbol.dart';
import 'package:pax/utils/error_message_util.dart';
import 'package:pax/utils/token_balance_util.dart';
import 'package:pax/utils/url_handler.dart';
import 'package:pax/widgets/change_withdrawal_method_card.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;

class ClaimImpactReviewSummaryView extends ConsumerStatefulWidget {
  const ClaimImpactReviewSummaryView({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ClaimImpactReviewSummaryViewState();
}

class _ClaimImpactReviewSummaryViewState
    extends ConsumerState<ClaimImpactReviewSummaryView> {
  bool _isProcessing = false;

  Future<void> _processClaim() async {
    final claimContext = ref.read(claimPayoutContextProvider);
    if (claimContext == null) {
      _showErrorDialog('Claim details not found');
      return;
    }

    final withdrawalMethod = claimContext.selectedWithdrawalMethod;
    final collective = claimContext.selectedGoodCollective;
    if (withdrawalMethod == null || collective == null) {
      _showErrorDialog('Wallet or collective not selected');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    ref.read(analyticsProvider).claimImpactReviewSubmitTapped({
      "claimKind": claimContext.claimKind.name,
      "selectedPaymentMethodId": withdrawalMethod.id,
      "selectedDonationContract": collective.donationContract,
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => PopScope(
            canPop: false,
            child: AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator().withPadding(bottom: 24),
                  Text(
                    'Please wait while we process your claim...',
                    textAlign: TextAlign.center,
                  ).withPadding(bottom: 12),
                  Text(
                    'Please be patient and do not close the app.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
    );

    try {
      final recipientAddress = withdrawalMethod.walletAddress;
      final donationBasisPoints = claimContext.donationBasisPoints;
      final donationContractAddress = collective.donationContract;
      final donationAmount =
          claimContext.amount * (claimContext.donationBasisPoints / 10000);
      late final String txnHash;
      switch (claimContext.claimKind) {
        case ClaimKind.task:
          final rewardResult = await ref
              .read(rewardServiceProvider)
              .rewardParticipant(
                taskCompletionId: claimContext.taskCompletionId!,
                recipientAddress: recipientAddress,
                donationContractAddress: donationContractAddress,
                donationBasisPoints: donationBasisPoints,
              );
          txnHash = rewardResult.txnHash;
          break;
        case ClaimKind.referral:
          txnHash = await ref
              .read(rewardServiceProvider)
              .claimReferralReward(
                referralId: claimContext.referralId!,
                recipientAddress: recipientAddress,
                donationContractAddress: donationContractAddress,
                donationBasisPoints: donationBasisPoints,
              );
          break;
        case ClaimKind.achievement:
          final achievements = ref.read(achievementsProvider).achievements;
          final achievement = achievements.firstWhere(
            (a) => a.id == claimContext.achievementId,
          );
          txnHash = await ref
              .read(achievementClaimProvider.notifier)
              .claimAchievement(
                achievement: achievement,
                recipientAddress: recipientAddress,
                donationContractAddress: donationContractAddress,
                donationBasisPoints: donationBasisPoints,
              );
          break;
      }

      final userId = ref.read(authProvider).user.uid;
      await ref
          .read(donationRepositoryProvider)
          .createDonation(
            participantId: userId,
            amountDonated: donationAmount,
            collectiveDonatedTo: donationContractAddress,
            txnHash: txnHash,
          );

      await ref
          .read(donationProvider.notifier)
          .recordGoodImpactDonation(donationAmount);

      // Force-refresh activity/donation providers now so downstream dashboard
      // cards update immediately after navigation.
      ref.invalidate(activityRepositoryProvider);
      await Future.wait([
        ref.refresh(donationActivitiesProvider(userId).future),
        ref.refresh(allActivitiesProvider(userId).future),
      ]);

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
    final amount = (claimContext?.amount ?? 0).toDouble();
    final tokenId = claimContext?.tokenId ?? 0;
    final donationPct = (claimContext?.donationBasisPoints ?? 1000) / 10000;
    final donationAmount = amount * donationPct;
    final walletAmount = amount - donationAmount;

    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'lib/assets/svgs/goodcollective.svg',
                  width: 30,
                  height: 30,
                ).withPadding(bottom: 8),
                Text(
                  'Reward Claimed and Donated!',
                  style: const TextStyle(
                    color: PaxColors.deepPurple,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ).withPadding(bottom: 10),
                Text(
                  '${TokenBalanceUtil.getLocaleFormattedAmount(walletAmount)} sent to your wallet',
                  textAlign: TextAlign.center,
                ),
                Text(
                  '${TokenBalanceUtil.getLocaleFormattedAmount(donationAmount)} donated to collective',
                  textAlign: TextAlign.center,
                ).withPadding(top: 6, bottom: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      TokenBalanceUtil.getLocaleFormattedAmount(amount),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ).withPadding(right: 4),
                    SvgPicture.asset(
                      'lib/assets/svgs/currencies/${CurrencySymbolUtil.getNameForCurrency(tokenId)}.svg',
                      height: 20,
                    ),
                  ],
                ).withPadding(bottom: 12),
                SizedBox(
                  width: MediaQuery.of(context).size.width / 2.5,
                  child: PrimaryButton(
                    child: const Text('OK'),
                    onPressed: () {
                      ref
                          .read(analyticsProvider)
                          .claimImpactReviewSuccessOkTapped({
                            "claimKind": claimContext?.claimKind.name,
                          });
                      ref.read(claimPayoutContextProvider.notifier).clear();
                      context.go('/home');
                    },
                  ),
                ),
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
      builder:
          (context) => PopScope(
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
                    ref
                        .read(analyticsProvider)
                        .claimImpactReviewErrorOkTapped();
                    context.go('/home');
                  },
                  child: Text('OK'),
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final claimContext = ref.watch(claimPayoutContextProvider);
    final amount = (claimContext?.amount ?? 0).toDouble();
    final tokenId = claimContext?.tokenId ?? 0;
    final paymentMethod = claimContext?.selectedWithdrawalMethod;
    final collective = claimContext?.selectedGoodCollective;
    final donationPct = (claimContext?.donationBasisPoints ?? 1000) / 10000;
    final donationAmount = amount * donationPct;
    final walletAmount = amount - donationAmount;

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
                  ref.read(analyticsProvider).claimImpactReviewBackTapped({
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
                'Impact Review',
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
                _summaryAmountRow('Reward Amount', amount, tokenId),
                _summaryAmountRow('Wallet (90%)', walletAmount, tokenId),
                _summaryAmountRow('Collective (10%)', donationAmount, tokenId),
                Divider(),
                _summaryAmountRow('Total', amount, tokenId),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                'Withdraw to',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ).withPadding(vertical: 12),
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
                          onChangeTap: () {
                            ref
                                .read(analyticsProvider)
                                .claimImpactReviewChangeWalletTapped({
                                  "claimKind": claimContext?.claimKind.name,
                                  "selectedPaymentMethodId": paymentMethod.id,
                                });
                            // Return to the existing wallet selector in-stack:
                            // impact-review -> select-goodcollective -> select-wallet.
                            if (context.canPop()) {
                              context.pop();
                            }
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go(
                                '/claim-reward/claim-payout/select-wallet',
                              );
                            }
                          },
                        ),
                      ]
                      : [Text('No payment method selected')],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                'Donate to',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ).withPadding(right: 4),
              SvgPicture.asset(
                'lib/assets/svgs/goodcollective.svg',
                width: 16,
                height: 16,
              ),
            ],
          ).withPadding(vertical: 12),
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: PaxColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PaxColors.lightLilac, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child:
                          (collective?.coverURI ?? '').isNotEmpty
                              ? Image.network(
                                collective!.coverURI!,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (_, __, ___) => SvgPicture.asset(
                                      'lib/assets/svgs/goodcollective.svg',
                                      width: 52,
                                      height: 52,
                                    ),
                              )
                              : SvgPicture.asset(
                                'lib/assets/svgs/goodcollective.svg',
                                width: 52,
                                height: 52,
                              ),
                    ).withPadding(right: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            collective?.name ?? '-',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: PaxColors.black,
                            ),
                          ).withPadding(bottom: 6),
                          Builder(
                            builder: (context) {
                              final contract = collective?.donationContract;
                              if (contract == null) {
                                return const Text(
                                  '-',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: PaxColors.lilac,
                                  ),
                                );
                              }
                              return InkWell(
                                onTap:
                                    () => UrlHandler.launchCustomTab(
                                      context,
                                      'https://goodcollective.xyz/collective/$contract',
                                    ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${contract.substring(0, 20)}...',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: PaxColors.lilac,
                                        decoration: TextDecoration.underline,
                                        decorationColor: PaxColors.lilac,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const FaIcon(
                                      FontAwesomeIcons.arrowUpRightFromSquare,
                                      size: 10,
                                      color: PaxColors.lilac,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const FaIcon(
                      FontAwesomeIcons.circleCheck,
                      color: PaxColors.deepPurple,
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Spacer(),
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
                    onPressed:
                        (paymentMethod == null ||
                                collective == null ||
                                _isProcessing)
                            ? null
                            : _processClaim,
                    child:
                        _isProcessing
                            ? CircularProgressIndicator(onSurface: true)
                            : Text(
                              'Claim and make an impact',
                              style: Theme.of(context).typography.base.copyWith(
                                fontWeight: FontWeight.bold,
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

  Widget _summaryAmountRow(String title, double amount, int tokenId) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
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
                height: 20,
              ).withPadding(left: 4),
            ],
          ),
        ],
      ),
    );
  }
}
