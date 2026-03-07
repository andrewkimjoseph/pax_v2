import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class ContactSupportCard extends ConsumerWidget {
  const ContactSupportCard(this.channel, this.icon, {super.key});

  final String channel;
  final String icon;

  static const _faIcons = <String, IconData>{
    'customer_support': FontAwesomeIcons.ticket,
    'website': FontAwesomeIcons.globe,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faIcon = _faIcons[icon];

    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (faIcon != null)
            FaIcon(
              faIcon,
              size: 18,
              color: PaxColors.black,
            ).withPadding(right: 12)
          else
            SvgPicture.asset(
              'lib/assets/svgs/$icon.svg',
              width: icon == 'telegram' ? 18 : 24,
              height: icon == 'telegram' ? 18 : 24,
            ).withPadding(right: 12, left: icon == 'telegram' ? 3 : 0),
          Expanded(
            child: Text(
              channel,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: PaxColors.black,
              ),
            ),
          ),
          FaIcon(
            FontAwesomeIcons.chevronRight,
            size: 12,
            color: PaxColors.darkGrey,
          ),
        ],
      ),
    ).withPadding(bottom: 8);
  }
}
