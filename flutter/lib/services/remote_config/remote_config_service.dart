import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pax/models/remote_config/app_version_config.dart';
import 'package:pax/models/remote_config/maintenance_config.dart';
import 'package:pax/models/remote_config/miniapps_config.dart';
import 'package:pax/utils/remote_config_constants.dart';
import 'dart:convert';

class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  RemoteConfigService._internal();

  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;
  bool _isInitialized = false;
  DateTime? _lastFetchTime;
  static const _refreshInterval = Duration(seconds: 3);

  static const _miniappsConfigAssetPath = 'lib/data/miniapps_config.json';

  Future<String> _loadMiniappsConfigDefault() async {
    try {
      return await rootBundle.loadString(_miniappsConfigAssetPath);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'Remote Config Service: Could not load miniapps default from asset: $e',
        );
      }
      return json.encode({
        RemoteConfigKeys.areMiniappsAvailable: true,
        RemoteConfigKeys.miniapps: [],
      });
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      if (kDebugMode) {
        debugPrint('Remote Config Service: Already initialized');
      }
      return;
    }

    try {
      await _remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(minutes: 1),
          minimumFetchInterval: Duration(hours: 12),
        ),
      );

      // Set default values before fetching
      await _remoteConfig.setDefaults({
        RemoteConfigKeys.appVersionConfig: json.encode({
          RemoteConfigKeys.currentVersion: '2.0.16+110',
          RemoteConfigKeys.forceUpdate: true,
          RemoteConfigKeys.updateMessage: 'A new version is available',
          RemoteConfigKeys.updateUrl:
              'https://play.google.com/store/apps/details?id=app.thepax.android',
        }),
        RemoteConfigKeys.maintenanceConfig: json.encode({
          RemoteConfigKeys.isUnderMaintenance: false,
          RemoteConfigKeys.maintenanceMessage:
              'The app is currently under maintenance',
        }),
        RemoteConfigKeys.featureFlags: json.encode({
          RemoteConfigKeys.isWalletAvailable: true,
          RemoteConfigKeys.areAchievementsAvailable: true,
          RemoteConfigKeys.areTasksAvailable: true,
          RemoteConfigKeys.areTasksCompletionsAvailable: true,
          RemoteConfigKeys.isCustomAppAccessFeatureAvailable: false,
          RemoteConfigKeys.isV2ReferralFeatureAvailable: false,
        }),
        RemoteConfigKeys.miniappsConfig: await _loadMiniappsConfigDefault(),
      });

      final bool activated = await _remoteConfig.fetchAndActivate();
      _isInitialized = true;
      _lastFetchTime = DateTime.now();

      if (kDebugMode) {
        debugPrint('Remote Config Service: Successfully initialized');
        debugPrint(
          'Remote Config Service: Config ${activated ? "activated" : "not activated"}',
        );
        debugPrint(
          'Remote Config Service: All parameters: ${_remoteConfig.getAll().map((key, value) => MapEntry(key, value.asString()))}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Remote Config Service: Error initializing: $e');
      }
      // Set initialized to true even on error to prevent infinite retry loops
      _isInitialized = true;
      rethrow;
    }
  }

  Future<AppVersionConfig> getAppVersionConfig() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Force refresh if last fetch was more than 3 seconds ago
    if (_lastFetchTime == null ||
        DateTime.now().difference(_lastFetchTime!) > _refreshInterval) {
      await refreshConfig();
    }

    try {
      if (kDebugMode) {
        debugPrint(
          'Remote Config Service: All parameters: ${_remoteConfig.getAll()}',
        );
      }

      final jsonString = _remoteConfig.getString(
        RemoteConfigKeys.appVersionConfig,
      );
      if (kDebugMode) {
        debugPrint('Remote Config Service: Raw config string: $jsonString');
      }

      if (jsonString.isEmpty) {
        // Return default config if no remote config is available
        return AppVersionConfig(
          currentVersion: '1.0.0',
          forceUpdate: false,
          updateMessage: 'A new version is available',
          updateUrl:
              'https://play.google.com/store/apps/details?id=com.pax.app',
        );
      }

      final Map<String, dynamic> configMap = json.decode(jsonString);
      if (kDebugMode) {
        debugPrint('Remote Config Service: Parsed config map: $configMap');
      }

      return AppVersionConfig.fromJson(configMap);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'Remote Config Service: Error getting app version config: $e',
        );
      }
      // Return default config on error
      return AppVersionConfig(
        currentVersion: '1.0.0',
        forceUpdate: false,
        updateMessage: 'A new version is available',
        updateUrl: 'https://play.google.com/store/apps/details?id=com.pax.app',
      );
    }
  }

  Future<MaintenanceConfig> getMaintenanceConfig() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Force refresh if last fetch was more than 3 seconds ago
    if (_lastFetchTime == null ||
        DateTime.now().difference(_lastFetchTime!) > _refreshInterval) {
      await refreshConfig();
    }

    try {
      if (kDebugMode) {
        debugPrint(
          'Remote Config Service: All parameters: ${_remoteConfig.getAll()}',
        );
      }

      final jsonString = _remoteConfig.getString(
        RemoteConfigKeys.maintenanceConfig,
      );
      if (kDebugMode) {
        debugPrint(
          'Remote Config Service: Raw maintenance config string: $jsonString',
        );
      }

      if (jsonString.isEmpty) {
        // Return default config if no remote config is available
        return MaintenanceConfig(
          isUnderMaintenance: false,
          message: 'The app is currently under maintenance',
        );
      }

      final Map<String, dynamic> configMap = json.decode(jsonString);
      if (kDebugMode) {
        debugPrint(
          'Remote Config Service: Parsed maintenance config map: $configMap',
        );
      }

      return MaintenanceConfig.fromJson(configMap);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'Remote Config Service: Error getting maintenance config: $e',
        );
      }
      // Return default config on error
      return MaintenanceConfig(
        isUnderMaintenance: false,
        message: 'The app is currently under maintenance',
      );
    }
  }

  Future<void> refreshConfig() async {
    if (!_isInitialized) {
      await initialize();
    }

    int retryCount = 0;
    const maxRetries = 2;
    const retryDelay = Duration(seconds: 5);

    while (retryCount < maxRetries) {
      try {
        if (kDebugMode) {
          debugPrint(
            'Remote Config Service: Attempting to fetch config (attempt ${retryCount + 1}/$maxRetries)',
          );
        }

        final bool activated = await _remoteConfig.fetchAndActivate();
        _lastFetchTime = DateTime.now();

        if (kDebugMode) {
          debugPrint(
            'Remote Config Service: Config refresh ${activated ? "successful" : "not activated"}',
          );
          debugPrint(
            'Remote Config Service: All parameters after refresh: ${_remoteConfig.getAll().map((key, value) => MapEntry(key, value.asString()))}',
          );
        }
        return;
      } catch (e) {
        retryCount++;
        if (kDebugMode) {
          debugPrint(
            'Remote Config Service: Error refreshing config (attempt $retryCount/$maxRetries): $e',
          );
          if (e is PlatformException) {
            debugPrint('Remote Config Service: Error code: ${e.code}');
            debugPrint('Remote Config Service: Error message: ${e.message}');
            debugPrint('Remote Config Service: Error details: ${e.details}');
          }
        }

        if (retryCount == maxRetries) {
          if (kDebugMode) {
            debugPrint('Remote Config Service: Max retries reached, giving up');
          }
          return;
        }

        await Future.delayed(retryDelay);
      }
    }
  }

  Future<Map<String, bool>> getFeatureFlags() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Force refresh if last fetch was more than 3 seconds ago
    if (_lastFetchTime == null ||
        DateTime.now().difference(_lastFetchTime!) > _refreshInterval) {
      await refreshConfig();
    }

    try {
      final jsonString = _remoteConfig.getString(RemoteConfigKeys.featureFlags);
      if (kDebugMode) {
        debugPrint(
          'Remote Config Service: Raw feature flags string: $jsonString',
        );
      }

      if (jsonString.isEmpty) {
        // Return default config if no remote config is available
        return {
          RemoteConfigKeys.isWalletAvailable: true,
          RemoteConfigKeys.areAchievementsAvailable: true,
          RemoteConfigKeys.areTasksAvailable: true,
          RemoteConfigKeys.areTasksCompletionsAvailable: true,
          RemoteConfigKeys.isWithdrawalMethodConnectionAvailable: true,
          RemoteConfigKeys.isV2UpgradeAvailable: false,
          RemoteConfigKeys.isCustomAppAccessFeatureAvailable: false,
          RemoteConfigKeys.isV2ReferralFeatureAvailable: false,
        };
      }

      final Map<String, dynamic> configMap = json.decode(jsonString);
      if (kDebugMode) {
        debugPrint(
          'Remote Config Service: Parsed feature flags map: $configMap',
        );
      }

      return {
        RemoteConfigKeys.isWalletAvailable:
            configMap[RemoteConfigKeys.isWalletAvailable] ?? true,
        RemoteConfigKeys.areAchievementsAvailable:
            configMap[RemoteConfigKeys.areAchievementsAvailable] ?? true,
        RemoteConfigKeys.areTasksAvailable:
            configMap[RemoteConfigKeys.areTasksAvailable] ?? true,
        RemoteConfigKeys.areTasksCompletionsAvailable:
            configMap[RemoteConfigKeys.areTasksCompletionsAvailable] ?? true,
        RemoteConfigKeys.isWithdrawalMethodConnectionAvailable:
            configMap[RemoteConfigKeys.isWithdrawalMethodConnectionAvailable] ??
            true,
        RemoteConfigKeys.isV2UpgradeAvailable:
            configMap[RemoteConfigKeys.isV2UpgradeAvailable] ?? false,
        RemoteConfigKeys.isCustomAppAccessFeatureAvailable:
            configMap[RemoteConfigKeys.isCustomAppAccessFeatureAvailable] ??
            false,
        RemoteConfigKeys.isV2ReferralFeatureAvailable:
            configMap[RemoteConfigKeys.isV2ReferralFeatureAvailable] ?? false,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Remote Config Service: Error getting feature flags: $e');
      }
      // Return default config on error
      return {
        RemoteConfigKeys.isWalletAvailable: true,
        RemoteConfigKeys.areAchievementsAvailable: true,
        RemoteConfigKeys.areTasksAvailable: true,
        RemoteConfigKeys.areTasksCompletionsAvailable: true,
        RemoteConfigKeys.isWithdrawalMethodConnectionAvailable: true,
        RemoteConfigKeys.isV2UpgradeAvailable: false,
        RemoteConfigKeys.isCustomAppAccessFeatureAvailable: false,
        RemoteConfigKeys.isV2ReferralFeatureAvailable: false,
      };
    }
  }

  Future<MiniappsConfig> getMiniappsConfig() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_lastFetchTime == null ||
        DateTime.now().difference(_lastFetchTime!) > _refreshInterval) {
      await refreshConfig();
    }

    try {
      final jsonString = _remoteConfig.getString(
        RemoteConfigKeys.miniappsConfig,
      );
      if (kDebugMode) {
        debugPrint(
          'Remote Config Service: Raw miniapps config string: $jsonString',
        );
      }

      if (jsonString.isEmpty) {
        return MiniappsConfig(areMiniappsAvailable: false, miniapps: []);
      }

      final Map<String, dynamic> configMap = json.decode(jsonString);
      if (kDebugMode) {
        debugPrint(
          'Remote Config Service: Parsed miniapps config map: $configMap',
        );
      }

      return MiniappsConfig.fromJson(configMap);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Remote Config Service: Error getting miniapps config: $e');
      }
      return MiniappsConfig(areMiniappsAvailable: false, miniapps: []);
    }
  }

  // Expose the real-time config update stream
  Stream<RemoteConfigUpdate> get onConfigUpdated =>
      _remoteConfig.onConfigUpdated;
}
