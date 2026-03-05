import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';

class RouterNotifier extends ChangeNotifier {
  RouterNotifier(this.ref) {
    ref.listen(authStateForRouterProvider, (previous, next) {
      if (previous != next) {
        notifyListeners();
      }
    });
    ref.listen(paxAccountProvider, (previous, next) {
      if (previous?.state != next.state) {
        notifyListeners();
      }
    });
    ref.listen(paxWalletProvider, (previous, next) {
      if (previous?.state != next.state ||
          previous?.wallet != next.wallet) {
        notifyListeners();
      }
    });
    ref.listen(participantProvider, (previous, next) {
      if (previous?.state != next.state ||
          previous?.participant?.onboardingType !=
              next.participant?.onboardingType) {
        notifyListeners();
      }
    });
  }

  final Ref ref;
}

// Create a provider for the router notifier
final routerNotifierProvider = Provider((ref) {
  return RouterNotifier(ref);
});
