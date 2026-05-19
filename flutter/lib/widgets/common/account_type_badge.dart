import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class AccountTypeBadge extends ConsumerWidget {
  const AccountTypeBadge({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountType = ref.watch(accountTypeProvider);
    if (accountType == AccountType.unknown) {
      return const SizedBox.shrink();
    }

    final label = accountType == AccountType.v2 ? 'V2' : 'V1';

    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: PaxColors.deepPurple,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: PaxColors.white,
        ),
      ),
    );
  }
}
