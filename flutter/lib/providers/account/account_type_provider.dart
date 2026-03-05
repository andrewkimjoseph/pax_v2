import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';

enum AccountType { v1, v2, unknown }

final accountTypeProvider = Provider<AccountType>((ref) {
  if (kIsWeb) return AccountType.v1;
  final paxAccountState = ref.watch(paxAccountProvider);
  final account = paxAccountState.account;
  if (account == null) return AccountType.unknown;
  if (account.isV1) return AccountType.v1;
  if (account.isV2) return AccountType.v2;
  return AccountType.unknown;
});
