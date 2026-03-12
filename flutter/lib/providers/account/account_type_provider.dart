import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';

enum AccountType { v1, v2, unknown }

final accountTypeProvider = Provider<AccountType>((ref) {
  if (kIsWeb) return AccountType.v1;
  final paxAccountState = ref.watch(paxAccountProvider);
  final account = paxAccountState.account;
  if (account == null) return AccountType.unknown;
  if (account.isV1) return AccountType.v1;
  if (account.isV2) return AccountType.v2;

  // Fallback: treat users as V2 when a PaxWallet document with a valid EO address exists,
  // even if the PaxAccount model has not yet been updated locally.
  final paxWalletState = ref.watch(paxWalletProvider);
  final wallet = paxWalletState.wallet;
  final eoAddress = wallet?.eoAddress;
  if (eoAddress != null && eoAddress.isNotEmpty) {
    return AccountType.v2;
  }

  return AccountType.unknown;
});
