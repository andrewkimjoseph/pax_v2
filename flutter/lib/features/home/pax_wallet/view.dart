import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/extensions/tooltip.dart';
import 'package:pax/providers/local/pax_wallet_view_provider.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/providers/local/refresh_time_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/token_balance_util.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;

class PaxWalletView extends ConsumerStatefulWidget {
  const PaxWalletView({super.key});

  @override
  ConsumerState<PaxWalletView> createState() => _PaxWalletViewState();
}

class _PaxWalletViewState extends ConsumerState<PaxWalletView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBalance();
      ref.read(analyticsProvider).v2PaxWalletRouteVisited();
    });
  }

  void _loadBalance() {
    final walletState = ref.read(paxWalletProvider);
    final eoAddress = walletState.wallet?.eoAddress;
    if (eoAddress != null) {
      ref.read(paxWalletViewProvider.notifier).fetchBalance(eoAddress);
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(paxWalletProvider);
    final viewState = ref.watch(paxWalletViewProvider);
    final wallet = walletState.wallet;
    final lastRefreshTime = ref.watch(refreshTimeProvider);
    const walletRefreshCooldown = Duration(seconds: 15);
    final canRefresh =
        lastRefreshTime == null ||
        DateTime.now().difference(lastRefreshTime) > walletRefreshCooldown;
    final isFetching = viewState.state == PaxWalletViewState.loading;

    return Scaffold(
      headers: [
        AppBar(
          padding: EdgeInsets.all(8),
          height: 50,
          backgroundColor: PaxColors.white,
          header: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Wallet',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 32,
                  color: PaxColors.black,
                ),
              ),
            ],
          ),
        ),
        Divider(color: PaxColors.lightGrey),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Balance card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: PaxColors.orangeToPinkGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SvgPicture.asset(
                        'lib/assets/svgs/wallets/pax_wallet.svg',
                        width: 32,
                        height: 32,
                      ).withPadding(right: 12),
                      Text(
                        'PaxWallet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: PaxColors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton.outline(
                        onPressed:
                            !canRefresh || isFetching
                                ? null
                                : () {
                                  ref
                                      .read(refreshTimeProvider.notifier)
                                      .setNow();
                                  _loadBalance();
                                },
                        density: ButtonDensity.icon,
                        icon:
                            isFetching
                                ? const CircularProgressIndicator(
                                  onSurface: true,
                                )
                                : const FaIcon(
                                  FontAwesomeIcons.arrowsRotate,
                                  color: PaxColors.white,
                                  size: 16,
                                ),
                      ).withToolTip(
                        lastRefreshTime == null
                            ? 'You can refresh now'
                            : 'You can refresh again in ${(walletRefreshCooldown.inSeconds - DateTime.now().difference(lastRefreshTime).inSeconds).clamp(0, walletRefreshCooldown.inSeconds)} sec(s)',
                        showTooltip: !canRefresh,
                      ),
                    ],
                  ).withPadding(bottom: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                                TokenBalanceUtil.getLocaleFormattedAmount(
                                  viewState.gdBalance.truncate(),
                                ),
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: PaxColors.white,
                                ),
                              )
                              .asSkeleton(
                                enabled:
                                    viewState.state ==
                                    PaxWalletViewState.loading,
                              )
                              .withPadding(right: 8),
                          SvgPicture.asset(
                            'lib/assets/svgs/currencies/good_dollar.svg',
                            width: 32,
                            height: 32,
                          ),
                        ],
                      ).withPadding(bottom: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                                '${TokenBalanceUtil.getLocaleFormattedAmount(viewState.cusdBalance)} cUSD',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: PaxColors.white.withValues(alpha: 0.9),
                                ),
                              )
                              .asSkeleton(
                                enabled:
                                    viewState.state ==
                                    PaxWalletViewState.loading,
                              )
                              .withPadding(right: 8),
                          SvgPicture.asset(
                            'lib/assets/svgs/currencies/celo_dollar.svg',
                            width: 24,
                            height: 24,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ).withPadding(bottom: 24),

            // Wallet details
            Text(
              'Wallet Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: PaxColors.deepPurple,
              ),
            ).withPadding(bottom: 16),

            _buildAddressRow(wallet?.eoAddress).withPadding(bottom: 12),
            // _buildDetailRow(
            //   'Created',
            //   wallet?.timeCreated != null
            //       ? wallet!.timeCreated!.toDate().toString().split('.').first
            //       : 'N/A',
            // ).withPadding(bottom: wallet?.logTxnHash != null ? 12 : 24),
            // if (wallet?.logTxnHash != null)
            //   _buildDetailRow(
            //     'Registry Tx',
            //     '${wallet!.logTxnHash!.substring(0, 10)}...${wallet.logTxnHash!.substring(wallet.logTxnHash!.length - 8)}',
            //   ).withPadding(bottom: 24),

            // Refresh button
            // SizedBox(
            //   width: double.infinity,
            //   height: 48,
            //   child: OutlineButton(
            //     onPressed: _loadBalance,
            //     child: const Text('Refresh Balance'),
            //   ),
            // ),
          ],
        ),
      ).withPadding(left: 8, right: 8, bottom: 8),
    );
  }

  Widget _buildAddressRow(String? address) {
    final value = address ?? 'N/A';
    final canCopy = address != null && address.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            'Address',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: PaxColors.darkGrey,
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap:
                canCopy
                    ? () async {
                      await Clipboard.setData(ClipboardData(text: address));
                    }
                    : null,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      decoration: canCopy ? TextDecoration.underline : null,
                      decorationColor: PaxColors.deepPurple,
                    ),
                  ),
                ),
                if (canCopy)
                  FaIcon(
                    FontAwesomeIcons.copy,
                    size: 16,
                    color: PaxColors.deepPurple,
                  ).withPadding(left: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Widget _buildDetailRow(String label, String value) {
  //   return Row(
  //     crossAxisAlignment: CrossAxisAlignment.start,
  //     children: [
  //       SizedBox(
  //         width: 100,
  //         child: Text(
  //           label,
  //           style: TextStyle(
  //             fontSize: 14,
  //             fontWeight: FontWeight.w600,
  //             color: PaxColors.darkGrey,
  //           ),
  //         ),
  //       ),
  //       Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
  //     ],
  //   );
  // }
}
