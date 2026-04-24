import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/services/web3/web3_miniapp_service.dart';
import 'package:web3dart/web3dart.dart';

final web3MiniAppServiceProvider =
    Provider.family<Web3MiniAppService, Credentials>((
  ref,
  credentials,
) {
  final paxWalletConfig = ref.watch(paxWalletConfigProvider).maybeWhen(
    data: (config) => config,
    orElse: () => <String, dynamic>{},
  );
  final service = Web3MiniAppService(
    credentials: credentials,
    paxWalletConfig: paxWalletConfig,
  );
  return service;
});
