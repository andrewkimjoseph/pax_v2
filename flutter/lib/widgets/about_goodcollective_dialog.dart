import 'package:flutter_svg/flutter_svg.dart' show SvgPicture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class AboutGoodCollectiveDialog extends ConsumerWidget {
  const AboutGoodCollectiveDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'lib/assets/svgs/goodcollective.svg',
            width: 32,
            height: 32,
          ).withPadding(bottom: 12),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GoodCollective connects donors to local climate action through transparent, verified payouts.\n\n'
              'How it works:\n'
              '- Donors fund a collective.\n'
              '- Stewards complete verified climate work.\n'
              '- Funds are released directly to steward wallets.\n\n'
              'Who can receive funds:\n'
              '- Community members included in a collective, or\n'
              '- People who complete verified partner-program activities.\n\n'
              'Donations can be one-time or recurring using GoodDollar and supported Celo assets.',
            ),
          ],
        ),
      ),
      actions: [
        PrimaryButton(
          onPressed: () {
            context.pop();
          },
          child: const Text('Close'),
        ),
      ],
    );
  }
}
