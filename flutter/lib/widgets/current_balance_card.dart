import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart' show SvgPicture;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/extensions/tooltip.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';
import 'package:pax/providers/local/donation_context_provider.dart';
// import 'package:pax/providers/local/balance_update_provider.dart';
import 'package:pax/providers/local/reward_currency_context.dart';
import 'package:pax/providers/local/withdraw_context_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/currency_symbol.dart';
import 'package:pax/utils/donation_constants.dart';
import 'package:pax/utils/gradient_border.dart';
import 'package:pax/utils/remote_config_constants.dart';
import 'package:pax/utils/token_balance_util.dart';
import 'package:pax/widgets/select_currency_button.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
// import 'dart:math' as math;

class CurrentBalanceCard extends ConsumerStatefulWidget {
  const CurrentBalanceCard({required this.nextLocation, super.key});

  final String nextLocation;

  @override
  ConsumerState<CurrentBalanceCard> createState() => _CurrentBalanceCardState();
}

class _CurrentBalanceCardState extends ConsumerState<CurrentBalanceCard> {
  Widget _buildDonateButton({
    required bool canDonate,
    required int? tokenId,
    required num? currentBalance,
  }) {
    final donateGradientColors =
        canDonate
            ? PaxColors.orangeToPinkGradient
            : [
              PaxColors.orange.withValues(alpha: 0.45),
              PaxColors.pink.withValues(alpha: 0.45),
            ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Positioned.fill(
            child: ShaderMask(
              shaderCallback:
                  (bounds) => LinearGradient(
                    colors: donateGradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: Container(color: Colors.white),
            ),
          ),
          Button(
            style:
                const ButtonStyle.primary(density: ButtonDensity.normal)
                    .withBackgroundColor(color: PaxColors.transparent)
                    .withBorder(),
            onPressed:
                canDonate
                    ? () {
                      ref
                          .read(donationContextProvider.notifier)
                          .setDonationContext(
                            tokenId ?? 1,
                            currentBalance ?? 0,
                          );
                      context.push('/wallet/donate');
                    }
                    : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaIcon(
                  FontAwesomeIcons.handHoldingHeart,
                  color: PaxColors.white,
                  size: 14,
                ).withPadding(right: 6),
                Text(
                  'Donate',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: PaxColors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).withToolTip(
      canDonate
          ? 'Donate to GoodCollective'
          : 'Minimum donation is ${kMinDonationAmountGd.toInt()} G\$',
    );
  }

  @override
  Widget build(BuildContext context) {
    final paxAccount = ref.watch(paxAccountProvider);
    final payoutAddress = paxAccount.account?.payoutWalletAddress;
    final showPaxAccountCopy =
        widget.nextLocation == "/wallet" &&
        payoutAddress != null &&
        payoutAddress.isNotEmpty;
    final selectedCurrency =
        ref.watch(rewardCurrencyContextProvider).selectedCurrency;
    final tokenId = TokenBalanceUtil.getTokenIdForCurrency(selectedCurrency);
    final currentBalance = paxAccount.balances[tokenId];
    final isGoodDollarSelected = selectedCurrency == "good_dollar";

    final isFetching =
        paxAccount.state == PaxAccountState.initial ||
        paxAccount.state == PaxAccountState.loading ||
        paxAccount.state == PaxAccountState.syncing;

    return Container(
      decoration: ShapeDecoration(
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
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'PaxAccount Balance',
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 20,
                      color: PaxColors.black,
                    ),
                  ).withPadding(bottom: 8),
                  Spacer(),

                  if (widget.nextLocation == "/wallet")
                    IconButton.outline(
                      onPressed:
                          paxAccount.state == PaxAccountState.syncing
                              ? null
                              : () {
                                ref
                                    .read(analyticsProvider)
                                    .refreshBalancesTapped({
                                      "tokenId": tokenId,
                                      "currentBalance": currentBalance,
                                      "selectedCurrency": selectedCurrency,
                                    });

                                ref
                                    .read(paxAccountProvider.notifier)
                                    .syncBalancesFromBlockchain();
                              },
                      density: ButtonDensity.icon,
                      icon:
                          isFetching
                              ? const CircularProgressIndicator(size: 25)
                              : const FaIcon(
                                FontAwesomeIcons.arrowsRotate,
                                color: PaxColors.deepPurple,
                              ),
                    ).withToolTip(
                      "Refresh on-chain balances",
                      showTooltip: false,
                    ),
                ],
              ),

              Builder(
                builder: (context) {
                  final isLoading =
                      paxAccount.state == PaxAccountState.initial ||
                      paxAccount.state == PaxAccountState.loading;
                  final isSyncing = paxAccount.state == PaxAccountState.syncing;

                  String currentBalance =
                      TokenBalanceUtil.getFormattedBalanceByCurrency(
                        paxAccount.balances,
                        selectedCurrency,
                      );

                  return Row(
                    children: [
                      Flexible(
                        child: Text(
                              currentBalance,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 26,
                                color: PaxColors.black,
                              ),
                            )
                            .asSkeleton(enabled: isSyncing || isLoading)
                            .withPadding(right: 8),
                      ),
                      SvgPicture.asset(
                        'lib/assets/svgs/currencies/$selectedCurrency.svg',
                        height: tokenId == 2 ? 30 : (tokenId == 1 ? 25 : 20),
                      ),
                    ],
                  ).withPadding(bottom: 16);
                },
              ),

              Row(
                children: [
                  FaIcon(
                    FontAwesomeIcons.circleInfo,
                    size: 12,
                    color: PaxColors.darkGrey,
                  ).withPadding(right: 6),
                  Text(
                    'Switch currency to view other balances',
                    style: TextStyle(
                      fontSize: 12,
                      color: PaxColors.darkGrey,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ).withPadding(bottom: 12),

              LayoutBuilder(
                builder: (context, constraints) {
                  final selectWidth = (constraints.maxWidth * 0.38).clamp(
                    108.0,
                    150.0,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                            height: 40,
                            width: selectWidth,
                            child: Select<String>(
                              itemBuilder: (context, item) {
                                final height =
                                    item == 'usdm'
                                        ? 28.5
                                        : (item == 'good_dollar' ? 25.0 : 20.0);
                                return Row(
                                  children: [
                                    SvgPicture.asset(
                                      'lib/assets/svgs/currencies/$item.svg',
                                      height: height,
                                    ).withPadding(right: 8),
                                    Text(
                                      CurrencySymbolUtil.getSymbolForCurrency(
                                        item,
                                      ),
                                    ),
                                  ],
                                );
                              },
                              onChanged: (value) {
                                if (value != null) {
                                  ref
                                      .read(
                                        rewardCurrencyContextProvider.notifier,
                                      )
                                      .setSelectedCurrency(value);

                                  ref
                                      .read(withdrawContextProvider.notifier)
                                      .setWithdrawContext(
                                        tokenId ?? 1,
                                        currentBalance ?? 0,
                                      );
                                }
                              },
                              value: selectedCurrency,
                              placeholder: const Text('Change currency'),
                              popup:
                                  (context) => SelectPopup(
                                    items: SelectItemList(
                                      children: [
                                        SelectCurrencyButton(
                                          'good_dollar',
                                          selectedCurrency == 'good_dollar',
                                        ),
                                        SelectCurrencyButton(
                                          'usdm',
                                          selectedCurrency == 'usdm',
                                        ),
                                        SelectCurrencyButton(
                                          'tether_usd',
                                          selectedCurrency == 'tether_usd',
                                        ),
                                        SelectCurrencyButton(
                                          'usd_coin',
                                          selectedCurrency == 'usd_coin',
                                        ).withPadding(bottom: kIsWeb ? 0 : 30),
                                      ],
                                    ),
                                  ),
                            ),
                          )
                          .withToolTip(
                            'View your balance in other currencies',
                            showTooltip: widget.nextLocation == "/wallet",
                          )
                          .withPadding(right: 8),

                      Expanded(
                        child: ref
                            .watch(featureFlagsProvider)
                            .when(
                              data: (flags) {
                                final isWalletAvailable =
                                    kDebugMode ||
                                    flags[RemoteConfigKeys.isWalletAvailable] ==
                                        true;
                                if (!isWalletAvailable) {
                                  return const SizedBox.shrink();
                                }

                                final actionEnabled =
                                    currentBalance != null &&
                                    currentBalance > 0;

                                final withdrawButton = Button(
                                  style:
                                      const ButtonStyle.primary(
                                            density: ButtonDensity.normal,
                                          )
                                          .withBackgroundColor(
                                            color: PaxColors.deepPurple,
                                          )
                                          .withBorder(),
                                  onPressed:
                                      actionEnabled
                                          ? () async {
                                            ref
                                                .read(
                                                  rewardCurrencyContextProvider
                                                      .notifier,
                                                )
                                                .setSelectedCurrency(
                                                  selectedCurrency,
                                                );

                                            ref
                                                .read(
                                                  withdrawContextProvider
                                                      .notifier,
                                                )
                                                .setWithdrawContext(
                                                  tokenId ?? 1,
                                                  currentBalance,
                                                );

                                            if (widget.nextLocation ==
                                                "/wallet") {
                                              ref
                                                  .read(analyticsProvider)
                                                  .homeWalletTapped({
                                                    "selectedCurrency":
                                                        selectedCurrency,
                                                    "currentBalance":
                                                        currentBalance,
                                                    "tokenId": tokenId,
                                                    "toLocation":
                                                        widget.nextLocation,
                                                  });
                                            } else {
                                              ref
                                                  .read(analyticsProvider)
                                                  .walletWithdrawTapped({
                                                    "selectedCurrency":
                                                        selectedCurrency,
                                                    "currentBalance":
                                                        currentBalance,
                                                    "tokenId": tokenId,
                                                    "toLocation":
                                                        widget.nextLocation,
                                                  });
                                            }
                                            context.push(widget.nextLocation);
                                          }
                                          : null,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      widget.nextLocation == "/wallet"
                                          ? SvgPicture.asset(
                                            actionEnabled
                                                ? 'lib/assets/svgs/canvassing.svg'
                                                : 'lib/assets/svgs/canvassing_lilac.svg',
                                            width: 14,
                                            height: 14,
                                          ).withPadding(right: 6)
                                          : FaIcon(
                                            FontAwesomeIcons.arrowUpFromBracket,
                                            color: PaxColors.white,
                                            size: 14,
                                          ).withPadding(right: 6),
                                      Text(
                                        widget.nextLocation == "/wallet"
                                            ? "Account"
                                            : "Withdraw",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                          color: PaxColors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ).withToolTip(
                                  widget.nextLocation == "/wallet"
                                      ? 'Account & wallet'
                                      : 'Withdraw',
                                );

                                return ref
                                    .watch(goodCollectiveConfigProvider)
                                    .when(
                                      data: (goodCollectiveConfig) {
                                        final canShowDonateButton =
                                            widget.nextLocation ==
                                                "/wallet/withdraw" &&
                                            isGoodDollarSelected &&
                                            (kDebugMode ||
                                                (goodCollectiveConfig
                                                        .isDonationAvailable &&
                                                    goodCollectiveConfig
                                                        .goodcollectives
                                                        .isNotEmpty));
                                        final canDonate =
                                            currentBalance != null &&
                                            currentBalance >=
                                                kMinDonationAmountGd;

                                        final copyWalletAddressButton =
                                            showPaxAccountCopy
                                                ? IconButton.outline(
                                                  onPressed:
                                                      () => Clipboard.setData(
                                                        ClipboardData(
                                                          text: payoutAddress,
                                                        ),
                                                      ),
                                                  density: ButtonDensity.icon,
                                                  icon: const FaIcon(
                                                    FontAwesomeIcons.copy,
                                                    size: 14,
                                                    color: PaxColors.deepPurple,
                                                  ),
                                                ).withToolTip(
                                                  "Copy PaxAccount address",
                                                  showTooltip: false,
                                                )
                                                : null;

                                        return Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                alignment:
                                                    widget.nextLocation ==
                                                            "/wallet"
                                                        ? WrapAlignment.start
                                                        : WrapAlignment.end,
                                                children: [
                                                  if (canShowDonateButton)
                                                    _buildDonateButton(
                                                      canDonate: canDonate,
                                                      tokenId: tokenId,
                                                      currentBalance:
                                                          currentBalance,
                                                    ),
                                                  withdrawButton,
                                                ],
                                              ),
                                            ),
                                            if (copyWalletAddressButton != null)
                                              copyWalletAddressButton,
                                          ],
                                        );
                                      },
                                      loading:
                                          () => Align(
                                            alignment:
                                                widget.nextLocation == "/wallet"
                                                    ? Alignment.centerLeft
                                                    : Alignment.centerRight,
                                            child: withdrawButton,
                                          ),
                                      error:
                                          (_, __) => Align(
                                            alignment:
                                                widget.nextLocation == "/wallet"
                                                    ? Alignment.centerLeft
                                                    : Alignment.centerRight,
                                            child: withdrawButton,
                                          ),
                                    );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ).withPadding(all: 12),
        ],
      ),
    );
  }
}
