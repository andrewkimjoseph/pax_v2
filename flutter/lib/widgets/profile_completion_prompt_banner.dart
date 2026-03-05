import 'package:flutter/material.dart' show InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class ProfileCompletionPromptBanner extends ConsumerWidget {
  const ProfileCompletionPromptBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsCompletion = ref.watch(profileNeedsCompletionProvider);

    if (!needsCompletion) {
      return const SizedBox.shrink();
    }

    return InkWell(
      onTap: () {
        context.push(Routes.completeProfile);
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              PaxColors.deepPurple.withValues(alpha: 0.1),
              PaxColors.lilac.withValues(alpha: 0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: PaxColors.deepPurple.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            FaIcon(
              FontAwesomeIcons.solidCircleUser,
              color: PaxColors.deepPurple,
              size: 24,
            ).withPadding(right: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Complete Your Profile',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: PaxColors.deepPurple,
                    ),
                  ).withPadding(bottom: 2),
                  Text(
                    'Add your country, gender, and date of birth to earn the Profile Perfectionist achievement.',
                    style: TextStyle(fontSize: 13, color: PaxColors.darkGrey),
                  ),
                ],
              ),
            ),
            FaIcon(
              FontAwesomeIcons.chevronRight,
              color: PaxColors.deepPurple,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
