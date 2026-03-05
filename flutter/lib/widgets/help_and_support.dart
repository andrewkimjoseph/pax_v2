import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class HelpAndSupportCard extends ConsumerWidget {
  const HelpAndSupportCard(this.label, {this.icon, super.key});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (icon != null)
            FaIcon(
              icon!,
              size: 18,
              color: PaxColors.deepPurple,
            ).withPadding(right: 12),
          Expanded(
            child: Text(
              label,
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
