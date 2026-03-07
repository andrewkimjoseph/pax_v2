import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/local/pax_wallet_view_provider.dart';
import 'package:pax/widgets/pax_wallet/balance_pill.dart';
import 'package:pax/widgets/pax_wallet/balance_row.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// G$ hero row + USDm/USDT pills for [PaxWalletBalanceCard].
class PaxWalletBalanceRows extends ConsumerWidget {
  const PaxWalletBalanceRows({super.key, required this.viewState});

  final PaxWalletViewStateModel viewState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heroRow = PaxWalletBalanceRow(
      label: 'G\$',
      amount: viewState.gdBalance,
      assetPath: 'lib/assets/svgs/currencies/good_dollar.svg',
      isPrimary: true,
    );
    final pillsRow = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        PaxWalletBalancePill(
          label: 'USDm',
          amount: viewState.cusdBalance,
          assetPath: 'lib/assets/svgs/currencies/usdm.svg',
        ),
        PaxWalletBalancePill(
          label: 'USDT',
          amount: viewState.usdtBalance,
          assetPath: 'lib/assets/svgs/currencies/tether_usd.svg',
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [heroRow.withPadding(bottom: 14), pillsRow],
    );
  }
}
