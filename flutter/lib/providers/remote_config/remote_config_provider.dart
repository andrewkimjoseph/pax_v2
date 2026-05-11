import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/models/remote_config/goodcollective_config.dart';
import 'package:pax/models/remote_config/links_config.dart';
import 'package:pax/models/remote_config/miniapps_config.dart';
import 'package:pax/services/remote_config/remote_config_service.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

final remoteConfigServiceProvider = Provider((ref) => RemoteConfigService());

final appVersionConfigProvider = FutureProvider((ref) async {
  final service = ref.watch(remoteConfigServiceProvider);
  return service.getAppVersionConfig();
});

final maintenanceConfigProvider = FutureProvider((ref) async {
  final service = ref.watch(remoteConfigServiceProvider);
  return service.getMaintenanceConfig();
});

final featureFlagsProvider = FutureProvider((ref) async {
  final service = ref.watch(remoteConfigServiceProvider);
  return service.getFeatureFlags();
});

final miniappsConfigProvider = FutureProvider<MiniAppsConfig>((ref) async {
  final service = ref.watch(remoteConfigServiceProvider);
  return service.getMiniappsConfig();
});

final goodCollectiveConfigProvider = FutureProvider<GoodCollectiveConfig>((
  ref,
) async {
  final service = ref.watch(remoteConfigServiceProvider);
  return service.getGoodCollectiveConfig();
});

final achievementAmountsProvider = FutureProvider<Map<String, int>>((
  ref,
) async {
  final service = ref.watch(remoteConfigServiceProvider);
  return service.getAchievementAmounts();
});

final paxWalletConfigProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  final service = ref.watch(remoteConfigServiceProvider);
  return service.getPaxWalletConfig();
});

final linksConfigProvider = FutureProvider<LinksConfig>((ref) async {
  final service = ref.watch(remoteConfigServiceProvider);
  return service.getLinksConfig();
});

final remoteConfigUpdateProvider = StreamProvider<RemoteConfigUpdate>((ref) {
  final service = ref.watch(remoteConfigServiceProvider);
  return service.onConfigUpdated;
});
