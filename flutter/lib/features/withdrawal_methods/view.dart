import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/withdrawal_method/withdrawal_method_provider.dart'
    show WithdrawalMethodsState, withdrawalMethodsProvider;
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/widgets/payment_method_cards/minipay_payment_method_card.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;
import 'package:pax/utils/remote_config_constants.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:flutter/foundation.dart';
import '../../theming/colors.dart' show PaxColors;
import '../../widgets/payment_method_cards/good_wallet_withdrawal_method_card.dart';
import 'package:pax/widgets/payment_method_cards/pax_wallet_payment_method_card.dart';
import 'package:pax/routing/routes.dart';

class WithdrawalMethodsView extends ConsumerStatefulWidget {
  const WithdrawalMethodsView({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _WithdrawalMethodsViewState();
}

class _WithdrawalMethodsViewState extends ConsumerState<WithdrawalMethodsView> {
  @override
  Widget build(BuildContext context) {
    final featureFlags = ref.watch(featureFlagsProvider);

    final withdrawalState = ref.watch(withdrawalMethodsProvider);
    final withdrawalMethods = withdrawalState.withdrawalMethods;
    final isLoading =
        withdrawalState.state == WithdrawalMethodsState.initial ||
        withdrawalState.state == WithdrawalMethodsState.loading;
    final accountType = ref.watch(accountTypeProvider);
    final isV2 = accountType == AccountType.v2;

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
              paxWalletCard,
            ]
            : [minipayCard, goodWalletCard];

    return featureFlags.when(
      data: (flags) {
        final isWithdrawalMethodConnectionAvailable =
            flags[RemoteConfigKeys.isWithdrawalMethodConnectionAvailable] ??
            true;
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
                    "Withdrawal Methods",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20),
                  ),
                  Spacer(),
                ],
              ),
            ).withPadding(top: 16),
            Divider(color: PaxColors.lightGrey),
          ],
          child:
              kDebugMode || (isWithdrawalMethodConnectionAvailable == true)
                  ? SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: PaxColors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: PaxColors.lightLilac,
                              width: 1,
                            ),
                          ),
                          child: Column(children: cardChildren),
                        ),
                      ],
                    ),
                  ).withPadding(horizontal: 8)
                  : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Linking a withdrawal method is not possible at this time.\nTry again later.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: PaxColors.black),
                      ).withPadding(top: 16),
                    ],
                  ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
