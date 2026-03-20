import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class GradientBadge extends ConsumerWidget {
  const GradientBadge({
    required this.child,
    super.key,
    this.isVisible = true,
    this.label,
    this.offset = const Offset(10, -6),
    this.dotSize = 10,
    this.isOverlay = true,
  });

  final Widget child;
  final bool isVisible;
  final String? label;
  final Offset offset;
  final double dotSize;
  final bool isOverlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isVisible) return child;

    final hasLabel = (label ?? '').isNotEmpty;
    final badge =
        hasLabel
            ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: PaxColors.orangeToPinkGradient,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label!,
                style: const TextStyle(
                  fontSize: 10,
                  color: PaxColors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
            : Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: PaxColors.orangeToPinkGradient,
                ),
              ),
            );

    if (!isOverlay) {
      return badge;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(right: offset.dx, top: offset.dy, child: badge),
      ],
    );
  }
}
