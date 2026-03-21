import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart' show SvgPicture;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/local/donation_context_provider.dart';
import 'package:pax/models/local/donation_state_model.dart';
import 'package:pax/providers/local/donation_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/currency_symbol.dart';
import 'package:pax/utils/token_address_util.dart';
import 'package:pax/utils/token_balance_util.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider, Consumer;

class DonationReviewSummaryView extends ConsumerStatefulWidget {
  const DonationReviewSummaryView({super.key});

  @override
  ConsumerState<DonationReviewSummaryView> createState() =>
      _DonationReviewSummaryViewState();
}

class _DonationReviewSummaryViewState
    extends ConsumerState<DonationReviewSummaryView> {
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(donationProvider.notifier).resetState();
    });
  }

  Future<void> _processDonation() async {
    final donationContext = ref.read(donationContextProvider);
    if (donationContext == null) return;
    final collective = donationContext.selectedGoodCollective;
    final amount = donationContext.amountToDonate ?? 0;
    if (collective == null || amount < 500) return;

    setState(() {
      _isProcessing = true;
    });

    ref
        .read(donationProvider.notifier)
        .donateToGoodCollective(
          amountToDonate: amount.toDouble(),
          tokenId: donationContext.tokenId,
          currencyAddress: TokenAddressUtil.getAddressForCurrency(
            donationContext.tokenId,
          ),
          decimals: TokenAddressUtil.getDecimalsForCurrency(
            donationContext.tokenId,
          ),
          donationContract: collective.donationContract,
          donationMethodId: collective.id,
        );

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildProcessingDialog(),
    );

    setState(() {
      _isProcessing = false;
    });
  }

  Widget _buildProcessingDialog() {
    return PopScope(
      canPop: false,
      child: Consumer(
        builder: (context, ref, _) {
          final donationState = ref.watch(donationProvider);
          if (donationState.state == DonationState.success) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (context.mounted) {
                context.pop();
              }
              _showResultDialog(true, null);
            });
          } else if (donationState.state == DonationState.error) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (context.mounted) {
                context.pop();
              }
              _showResultDialog(false, donationState.errorMessage);
            });
          }
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator().withPadding(bottom: 24),
                const Text(
                  'Processing your donation...',
                  textAlign: TextAlign.center,
                ).withPadding(bottom: 12),
                const Text(
                  'Please be patient and do not close the app.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showResultDialog(bool success, String? message) {
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
                  success
                      ? 'lib/assets/svgs/goodcollective.svg'
                      : 'lib/assets/svgs/canvassing.svg',
                  width: 30,
                  height: 30,
                ).withPadding(bottom: 8),
                Text(
                  success ? 'Donation Complete!' : 'Donation Failed',
                  style: const TextStyle(
                    color: PaxColors.deepPurple,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ).withPadding(bottom: 8),
                if (!success)
                  Text(
                    message ?? 'Unknown donation error',
                  ).withPadding(bottom: 8),
                SizedBox(
                  width: MediaQuery.of(context).size.width / 2.5,
                  child: PrimaryButton(
                    child: const Text('OK'),
                    onPressed: () {
                      context.pop();
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

  @override
  Widget build(BuildContext context) {
    final donationContext = ref.watch(donationContextProvider);
    final amount = donationContext?.amountToDonate ?? 0;
    final tokenId = donationContext?.tokenId ?? 1;
    final collective = donationContext?.selectedGoodCollective;

    return Scaffold(
      backgroundColor: PaxColors.white,
      headers: [
        AppBar(
          padding: const EdgeInsets.all(8),
          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              InkWell(
                onTap: context.pop,
                child: const FaIcon(
                  FontAwesomeIcons.arrowLeftLong,
                  size: 20,
                  color: PaxColors.deepPurple,
                ),
              ),
              const Spacer(),
              const Text('Review Donation', style: TextStyle(fontSize: 20)),
              const Spacer(),
            ],
          ),
        ).withPadding(top: 16),
        const Divider(color: PaxColors.lightGrey),
      ],
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: PaxColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PaxColors.lightLilac, width: 1),
            ),
            child: Column(
              children: [
                _summaryRow(
                  'Donation Amount',
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
                        height: 25,
                      ).withPadding(left: 4),
                    ],
                  ),
                ),
                _summaryRow(
                  'Transaction Fee',
                  const Text(
                    'Free',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(),
                _summaryRow(
                  'Total',
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
                        height: 25,
                      ).withPadding(left: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Text(
                'Donate to',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ).withPadding(vertical: 16),
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: PaxColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PaxColors.lightLilac, width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child:
                      (collective?.coverURI ?? '').isNotEmpty
                          ? Image.network(
                            collective!.coverURI!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, __, ___) => SvgPicture.asset(
                                  'lib/assets/svgs/goodcollective.svg',
                                  width: 48,
                                  height: 48,
                                ),
                          )
                          : SvgPicture.asset(
                            'lib/assets/svgs/goodcollective.svg',
                            width: 48,
                            height: 48,
                          ),
                ).withPadding(right: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        collective?.name ?? '-',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                          color: PaxColors.black,
                        ),
                      ).withPadding(bottom: 8),
                      Text(
                        collective?.donationContract != null
                            ? '${collective!.donationContract.substring(0, 20)}...'
                            : '-',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: PaxColors.lilac,
                        ),
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
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              children: [
                const Divider().withPadding(vertical: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: PrimaryButton(
                    onPressed:
                        collective == null || amount < 500 || _isProcessing
                            ? null
                            : _processDonation,
                    child: Text(
                      'Donate',
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

  Widget _summaryRow(String title, Widget trailing) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          trailing,
        ],
      ),
    );
  }
}
