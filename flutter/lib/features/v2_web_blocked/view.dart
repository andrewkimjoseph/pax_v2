import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class V2WebBlockedView extends ConsumerStatefulWidget {
  const V2WebBlockedView({super.key});

  @override
  ConsumerState<V2WebBlockedView> createState() => _V2WebBlockedViewState();
}

class _V2WebBlockedViewState extends ConsumerState<V2WebBlockedView> {
  bool _didSignOut = false;

  @override
  Widget build(BuildContext context) {
    if (!_didSignOut) {
      _didSignOut = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(authProvider.notifier).signOut();
      });
    }

    return Scaffold(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(
                FontAwesomeIcons.mobileScreen,
                size: 64,
                color: PaxColors.deepPurple,
              ).withPadding(bottom: 24),
              Text(
                'Use the mobile app',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: PaxColors.deepPurple,
                ),
                textAlign: TextAlign.center,
              ).withPadding(bottom: 16),
              Text(
                'Your account uses Pax Wallet. Please sign in on the mobile app to continue.',
                style: TextStyle(fontSize: 16, color: PaxColors.darkGrey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
