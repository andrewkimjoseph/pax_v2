import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pax/providers/analytics/clarity/clarity_provider.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Consumer;
import 'package:flutter/services.dart';

import 'package:pax/env/env.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/fcm/fcm_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/routing/service.dart';
import 'package:pax/services/app_initializer.dart';
import 'package:pax/services/notifications/notification_service.dart';
import 'package:pax/theming/theme_provider.dart';
import 'package:pax/utils/version_util.dart';
import 'package:pax/widgets/app_lifecycle_handler.dart';
import 'package:pax/widgets/maintenance_dialog.dart';
import 'package:pax/widgets/mobile_only_wrapper.dart';
import 'package:pax/widgets/update_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, // Draw behind status bar
      statusBarIconBrightness:
          Brightness.dark, // Use dark icons for light backgrounds
      statusBarBrightness: Brightness.light, // For iOS
      systemNavigationBarColor: Colors.white, // Or your app's nav bar color
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // On web, initialize Firebase only (fast), then start app
  // Other services initialize in background to allow faster splash removal
  if (kIsWeb) {
    // Only initialize Firebase synchronously (required for app to work)
    await AppInitializer().initializeFirebaseOnly();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    // Start app immediately - splash will be removed when Flutter renders
    runApp(ProviderScope(child: App()));
    // Continue other initializations in background
    AppInitializer().initializeRemaining().catchError((error) {
      if (kDebugMode) {
        debugPrint('[Background] Background initialization error: $error');
      }
    });
  } else {
    // On mobile, wait for full initialization before starting app
    await AppInitializer().initialize();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    runApp(ProviderScope(child: App()));
  }
}

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  final _notificationService = NotificationService();
  String? _currentVersion;

  @override
  void initState() {
    super.initState();
    _setupNotifications();
    _initializeAnalytics();
    _loadCurrentVersion();
  }

  void _initializeAnalytics() {
    final amplitudeApiKey = Env.amplitudeAPIKey;
    ref.read(analyticsProvider).initialize(amplitudeApiKey);
  }

  Future<void> _loadCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _currentVersion = info.version);
  }

  void _setupNotifications() {
    _notificationService.setupForegroundMessageHandling(_handleMessage);
    _notificationService.checkForInitialMessage(_handleMessage);
  }

  void _handleMessage(RemoteMessage message) {
    if (message.data.containsKey('route')) {
      final route = message.data['route'];
      if (kDebugMode) {
        debugPrint('[Navigating] Navigating to route from FCM: $route');
      }
      final router = ref.read(routerProvider);
      router.push(route);
    }
  }

  void _handleDeepLink(Map<dynamic, dynamic> linkData) {
    if (kDebugMode) {
      debugPrint('[Handling] Handling deep link in App: $linkData');
    }

    if (linkData['+clicked_branch_link'] == true) {
      String? path;
      if (linkData.containsKey('~referring_link')) {
        final url = Uri.parse(linkData['~referring_link'] as String);
        if (url.path.isNotEmpty) path = url.path;
      }

      if (path != null && path.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('[:_handleDeepLink] Path from Deep Link:  $path');
        }
      } else {
        if (kDebugMode) {
          debugPrint('[:_handleDeepLink] No path from Deep Link');
        }
      }

      // Debug-print referringParticipantId if present in Branch params
      String? referringParticipantId;
      if (linkData.containsKey('referringParticipantId')) {
        referringParticipantId = linkData['referringParticipantId']?.toString();
      } else {
        // Fallback: look for any key that contains 'referringParticipantId'
        try {
          final entry = linkData.entries.firstWhere(
            (e) => e.key.toString().contains('referringParticipantId'),
          );
          referringParticipantId = entry.value?.toString();
        } catch (_) {
          referringParticipantId = null;
        }
      }

      if (kDebugMode) {
        if (referringParticipantId != null &&
            referringParticipantId.isNotEmpty) {
          debugPrint(
            '[:_handleDeepLink] referringParticipantId from Deep Link: $referringParticipantId',
          );
        } else {
          debugPrint(
            '[:_handleDeepLink] No referringParticipantId found in Deep Link params',
          );
        }
      }
    } else {
      if (kDebugMode) {
        debugPrint('[:_handleDeepLink] No +clicked_branch_link from Deep Link');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    ref.watch(fcmInitProvider);

    return AppLifecycleHandler(
      onDeepLink: _handleDeepLink,
      child: ShadcnApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        title: 'Pax',
        theme: ref.watch(themeProvider),
        builder: (context, child) {
          return MobileOnlyWrapper(
            child: ClarityWidget(
              clarityConfig: ref.watch(clarityConfigProvider),
              app: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.noScaling),
                child: Consumer(
                  builder: (context, ref, _) {
                    final appVersionConfigAsync = ref.watch(
                      appVersionConfigProvider,
                    );
                    final maintenanceConfigAsync = ref.watch(
                      maintenanceConfigProvider,
                    );

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        child ?? const CircularProgressIndicator(),
                        appVersionConfigAsync.when(
                          data: (config) {
                            // Do not show update or maintenance dialogs in debug builds
                            if (kDebugMode) {
                              return const SizedBox.shrink();
                            }

                            if (_currentVersion == null) {
                              return const SizedBox.shrink();
                            }

                            final needsUpdate =
                                config.forceUpdate &&
                                VersionUtil.isVersionNotTheSame(
                                  _currentVersion!,
                                  config.currentVersion,
                                );

                            if (needsUpdate) return const UpdateDialog();

                            return maintenanceConfigAsync.when(
                              data: (maintenanceConfig) {
                                if (!maintenanceConfig.isUnderMaintenance) {
                                  return const SizedBox.shrink();
                                }

                                return const MaintenanceDialog();
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

// Backward-compatible entry point for older persisted callback handles.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await firebaseMessagingBackgroundHandler(message);
}
