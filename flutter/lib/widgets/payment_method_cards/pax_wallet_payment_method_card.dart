import 'package:flutter/material.dart' show InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:pax/models/firestore/payment_method/payment_method.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class PaxWalletPaymentMethodCard extends ConsumerWidget {
  const PaxWalletPaymentMethodCard(
    this.paxWallet, {
    required this.callBack,
    this.isLoading = false,
    super.key,
  });

  final VoidCallback callBack;
  final WithdrawalMethod? paxWallet;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: isLoading || paxWallet?.walletAddress != null ? null : callBack,
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PaxColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PaxColors.lightLilac, width: 1),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SvgPicture.asset(
                'lib/assets/svgs/wallets/pax_wallet.svg',
                height: 48,
              ),
            ).withPadding(right: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    paxWallet?.name ?? 'PaxWallet',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: PaxColors.black,
                    ),
                  ).withPadding(bottom: 8),
                  Text(
                    paxWallet?.walletAddress != null
                        ? '${paxWallet!.walletAddress.substring(0, 15)}${'.' * 3}'
                        : 'Built-in Canvassing wallet',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: PaxColors.lilac,
                    ),
                  ),
                ],
              ),
            ),
            if (isLoading)
              const CircularProgressIndicator(size: 25)
            else
              PrimaryButton(
                density: ButtonDensity.dense,
                onPressed: paxWallet?.walletAddress != null ? null : callBack,
                child: Text(
                  paxWallet?.walletAddress != null ? 'Connected' : 'Set up',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
