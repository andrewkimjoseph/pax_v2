import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/db/withdrawal_method/withdrawal_method_provider.dart';
import 'package:pax/services/wallet/gooddollar_identity_service.dart';

enum V2EligibilityResult { eligible, notEligible }

final v2EligibilityProvider = FutureProvider<V2EligibilityResult>((ref) async {
  final withdrawalMethodsState = await _waitForWithdrawalMethods(ref);
  final methods = withdrawalMethodsState.withdrawalMethods;

  for (final method in methods) {
    if (method.walletAddress.isNotEmpty) {
      final whitelisted = await GoodDollarIdentityService.isWhitelisted(
        method.walletAddress,
      );
      if (whitelisted) {
        return V2EligibilityResult.notEligible;
      }
    }
  }

  return V2EligibilityResult.eligible;
});

Future<WithdrawalMethodsStateModel> _waitForWithdrawalMethods(Ref ref) {
  final current = ref.read(withdrawalMethodsProvider);
  if (current.state == WithdrawalMethodsState.loaded ||
      current.state == WithdrawalMethodsState.error) {
    return Future.value(current);
  }

  final completer = Completer<WithdrawalMethodsStateModel>();
  late final ProviderSubscription<WithdrawalMethodsStateModel> sub;
  sub = ref.listen(withdrawalMethodsProvider, (previous, next) {
    if (next.state == WithdrawalMethodsState.loaded ||
        next.state == WithdrawalMethodsState.error) {
      if (!completer.isCompleted) {
        completer.complete(next);
      }
      sub.close();
    }
  });

  return completer.future;
}
