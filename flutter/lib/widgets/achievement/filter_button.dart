import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class FilterButton extends ConsumerWidget {
  const FilterButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.badgeCount,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onPressed;
  final int? badgeCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textColor = isSelected ? PaxColors.white : PaxColors.black;
    final hasBadge = badgeCount != null && badgeCount! > 0;

    return Button(
      style: const ButtonStyle.primary(density: ButtonDensity.dense)
          .withBackgroundColor(
            color: isSelected ? PaxColors.deepPurple : Colors.transparent,
          )
          .withBorder(
            border: Border.all(
              color: isSelected ? PaxColors.deepPurple : PaxColors.lilac,
              width: 2,
            ),
          )
          .withBorderRadius(borderRadius: BorderRadius.circular(7)),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(color: textColor),
          ).withPadding(right: 6),
          if (hasBadge) ...[
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: PaxColors.orange,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badgeCount! > 99 ? '99+' : '$badgeCount',
                style: TextStyle(
                  fontSize: 10,
                  color: PaxColors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    ).withPadding(right: 8);
  }
}
