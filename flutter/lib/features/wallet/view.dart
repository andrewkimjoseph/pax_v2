import 'package:flutter/material.dart' show InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/withdrawal_method/withdrawal_method_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/widgets/current_balance_card.dart';
import 'package:pax/widgets/payment_method_cards/minipay_payment_method_card.dart';
import 'package:pax/widgets/payment_method_cards/good_wallet_withdrawal_method_card.dart';
import 'package:pax/widgets/payment_method_cards/pax_wallet_payment_method_card.dart';
import 'package:pax/routing/routes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../theming/colors.dart' show PaxColors;

class WalletView extends ConsumerStatefulWidget {
  const WalletView({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _WalletViewViewState();
}

class _WalletViewViewState extends ConsumerState<WalletView> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final withdrawalState = ref.watch(withdrawalMethodsProvider);
    final withdrawalMethods = withdrawalState.withdrawalMethods;
    final isLoading =
        withdrawalState.state == WithdrawalMethodsState.initial ||
        withdrawalState.state == WithdrawalMethodsState.loading;
    final accountType = ref.watch(accountTypeProvider);
    final isV2 = accountType == AccountType.v2;
    final paxWalletVerifiedAsync = ref.watch(
      paxWalletNeedsVerificationProvider,
    );

    /// For V2, only show MiniPay/GoodWallet when Pax Wallet address is verified.
    final bool showMinipayAndGoodWalletForV2 =
        isV2
            ? (paxWalletVerifiedAsync.maybeWhen(
              data: (needsVerification) => !needsVerification,
              orElse: () => false,
            ))
            : true;

    final paxWalletMethod =
        withdrawalMethods.isNotEmpty
            ? withdrawalMethods
                .where(
                  (method) => method.name.toLowerCase().contains('paxwallet'),
                )
                .firstOrNull
            : null;
    final minipayMethod =
        withdrawalMethods.isNotEmpty
            ? withdrawalMethods
                .where(
                  (method) => method.name.toLowerCase().contains('minipay'),
                )
                .firstOrNull
            : null;
    final goodWalletMethod =
        withdrawalMethods.isNotEmpty
            ? withdrawalMethods
                .where(
                  (method) => method.name.toLowerCase().contains('goodwallet'),
                )
                .firstOrNull
            : null;

    final paxWalletCard = PaxWalletPaymentMethodCard(
      paxWalletMethod,
      isLoading: isLoading,
      callBack: () {
        ref.read(analyticsProvider).withdrawalMethodConnectionTapped({
          "method": "PaxWallet",
        });
        context.go(Routes.createV2Wallet);
      },
    );
    final minipayCard = MiniPayPaymentMethodCard(
      minipayMethod,
      isLoading: isLoading,
      callBack: () {
        ref.read(analyticsProvider).withdrawalMethodConnectionTapped({
          "method": "MiniPay",
        });
        context.push("/withdrawal-methods/minipay-connection");
      },
    ).withPadding(bottom: 8);
    final goodWalletCard = GoodWalletWithdrawalMethodCard(
      goodWalletMethod,
      isLoading: isLoading,
      callBack: () {
        ref.read(analyticsProvider).withdrawalMethodConnectionTapped({
          "method": "GoodWallet",
        });
        context.push("/withdrawal-methods/good-wallet-connection");
      },
    );

    final cardChildren =
        isV2
            ? [
              paxWalletCard.withPadding(
                bottom: showMinipayAndGoodWalletForV2 ? 8 : 0,
              ),
              if (showMinipayAndGoodWalletForV2) ...[
                minipayCard,
                goodWalletCard,
              ],
            ]
            : [minipayCard, goodWalletCard];

    return Scaffold(
      headers: [
        AppBar(
          padding: EdgeInsets.all(8),

          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go("/home");
                  }
                },
                child: FaIcon(
                  FontAwesomeIcons.arrowLeftLong,
                  size: 20,
                  color: PaxColors.deepPurple,
                ),
              ),
              Spacer(),
              Text(
                "Account",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20),
              ),

              Spacer(),
            ],
          ),
        ).withPadding(top: 16),
        Divider(color: PaxColors.lightGrey),
      ],

      child: SingleChildScrollView(
        child: Column(
          children: [
            const CurrentBalanceCard(
              nextLocation: '/wallet/withdraw',
            ).withPadding(bottom: 8),

            Container(
              padding: EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: PaxColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PaxColors.lightLilac, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available Withdrawal Methods',
                    style: TextStyle(fontSize: 20),
                  ).withPadding(bottom: 8),
                  Column(children: cardChildren),
                ],
              ),
            ),
          ],
        ),
      ).withPadding(all: 8),
    );
  }
}

// String? selectedValue;
// @override
// Widget build(BuildContext context) {
//   return 
// }

// Note: The UI presents these as "Withdrawal Methods" for better user experience,
// while the underlying data structure and database collection remain as "payment_methods".

