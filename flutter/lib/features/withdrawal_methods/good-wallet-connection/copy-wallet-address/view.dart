import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/widgets/withdrawal_method_guides/goodwallet/for_copying_wallet_address/steps.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;

class CopyWalletAddressGoodWalletView extends ConsumerStatefulWidget {
  const CopyWalletAddressGoodWalletView({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _CopyWalletAddressGoodWalletViewState();
}

class _CopyWalletAddressGoodWalletViewState
    extends ConsumerState<CopyWalletAddressGoodWalletView> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      headers: [
        AppBar(
          padding: EdgeInsets.all(8),

          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  context.pop();
                },
                child: FaIcon(FontAwesomeIcons.arrowLeftLong, size: 20, color: PaxColors.deepPurple),
              ),
              Spacer(),
              Text(
                "Copy Your Wallet Address",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20),
              ).withPadding(right: 16),
              Spacer(),
            ],
          ),
        ).withPadding(top: 16, horizontal: 8),
        Divider(color: PaxColors.lightGrey),
      ],

      child: SingleChildScrollView(
        child: Column(
          children: [
            Column(
              spacing: 24,
              children: [ForCopyingGoodWalletWalletAddress()],
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

