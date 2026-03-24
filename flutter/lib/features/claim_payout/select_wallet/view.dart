import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/withdrawal_method/withdrawal_method_provider.dart';
import 'package:pax/providers/local/claim_payout_context_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/widgets/claim_wallet_option_card.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;

class ClaimSelectWalletView extends ConsumerStatefulWidget {
  const ClaimSelectWalletView({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ClaimSelectWalletViewState();
}

class _ClaimSelectWalletViewState
    extends ConsumerState<ClaimSelectWalletView> {
  @override
  Widget build(BuildContext context) {
    final withdrawalMethods =
        ref.watch(withdrawalMethodsProvider).withdrawalMethods;

    final claimContext = ref.watch(claimPayoutContextProvider);
    final goodCollectiveConfigAsync = ref.watch(goodCollectiveConfigProvider);
    final showDonationFlow =
        kDebugMode ||
        goodCollectiveConfigAsync.maybeWhen(
          data:
              (config) =>
                  config.isDonationAvailable &&
                  config.goodcollectives.isNotEmpty,
          orElse: () => false,
        );

    final isContinueEnabled = claimContext?.selectedWithdrawalMethod != null;

    return Scaffold(
      headers: [
        AppBar(
          padding: const EdgeInsets.all(8),
          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  ref.read(analyticsProvider).claimSelectWalletBackTapped({
                    "claimKind": claimContext?.claimKind.name,
                    "isDonation": claimContext?.isDonation,
                  });
                  context.pop();
                },
                child: FaIcon(FontAwesomeIcons.arrowLeftLong,
                    size: 20, color: PaxColors.deepPurple),
              ),
              const Spacer(),
              const Text(
                "Select Withdrawal Method",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20),
              ),
              const Spacer(),
            ],
          ),
        ).withPadding(top: 16, horizontal: 8),
        const Divider(color: PaxColors.lightGrey),
      ],
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 8, left: 8, right: 8),
            width: double.infinity,
            decoration: BoxDecoration(
              color: PaxColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PaxColors.lightLilac, width: 1),
            ),
            child: Column(
              children: [
                if (withdrawalMethods.isNotEmpty)
                  ...withdrawalMethods.map(
                    (method) =>
                        ClaimWalletOptionCard(method).withPadding(bottom: 8),
                  ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              children: [
                const Divider().withPadding(top: 10, bottom: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: PrimaryButton(
                    enabled: isContinueEnabled,
                    onPressed: isContinueEnabled
                        ? () {
                            ref
                                .read(analyticsProvider)
                                .continueSelectWalletTapped({
                              "amount": claimContext?.amount,
                              "tokenId": claimContext?.tokenId,
                              "selectedPaymentMethodId":
                                  claimContext?.selectedWithdrawalMethod?.id,
                              "claimKind": claimContext?.claimKind.name,
                              "isDonation": claimContext?.isDonation,
                            });
                            final nextPath =
                                (claimContext?.isDonation == true &&
                                        showDonationFlow)
                                    ? '/claim-reward/claim-payout/select-wallet/select-goodcollective'
                                    : '/claim-reward/claim-payout/select-wallet/review-summary';
                            context.push(nextPath);
                          }
                        : null,
                    child: Text(
                      'Continue',
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
