import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_branch_sdk/flutter_branch_sdk.dart';
import 'package:pax/routing/routes.dart';

class BranchService {
  static final BranchService _instance = BranchService._internal();
  factory BranchService() => _instance;
  BranchService._internal();

  StreamSubscription<Map>? _linkDataStreamSubscription;
  Function(Map<dynamic, dynamic>)? _deepLinkHandler;
  bool _isListening = false;

  /// Completer to track SDK initialization status
  static final Completer<void> _sdkInitCompleter = Completer<void>();

  /// Whether the Branch SDK has been initialized
  static bool _sdkInitialized = false;

  /// Called when FlutterBranchSdk.init() completes successfully
  static void markSdkInitialized() {
    if (!_sdkInitialized) {
      _sdkInitialized = true;
      if (!_sdkInitCompleter.isCompleted) {
        _sdkInitCompleter.complete();
      }
      if (kDebugMode) {
        debugPrint('BranchService: SDK marked as initialized');
      }
    }
  }

  /// Wait for the SDK to be initialized
  static Future<void> waitForSdkInit() => _sdkInitCompleter.future;

  void init({required Function(Map<dynamic, dynamic>) deepLinkHandler}) {
    _deepLinkHandler = deepLinkHandler;
    if (kDebugMode) {
      debugPrint('BranchService: Initialized with deep link handler');
    }
  }

  Future<void> listenToDeepLinks() async {
    if (_deepLinkHandler == null) {
      if (kDebugMode) {
        debugPrint(
          'BranchService: Error: Deep link handler not set before listening.',
        );
      }
      return;
    }

    if (_isListening) {
      if (kDebugMode) {
        debugPrint('Already listening to deep links');
      }
      return;
    }

    // Wait for SDK to be initialized before listening
    if (!_sdkInitialized) {
      if (kDebugMode) {
        debugPrint('BranchService: Waiting for SDK initialization...');
      }
      await waitForSdkInit();
    }

    if (kDebugMode) {
      debugPrint('BranchService: Starting deep link listener');
    }
    _linkDataStreamSubscription = FlutterBranchSdk.listSession().listen(
      (linkData) {
        if (kDebugMode) {
          debugPrint('BranchService: Deep link being listened to: $linkData');
        }
        // Only handle deep links if they contain actual link data
        if (linkData.isNotEmpty && linkData['+clicked_branch_link'] == true) {
          _deepLinkHandler?.call(linkData);
        }
      },
      onError: (error) {
        if (kDebugMode) {
          debugPrint('BranchService: Error receiving deep link: $error');
        }
      },
    );
    _isListening = true;
  }

  void dispose() {
    if (kDebugMode) {
      debugPrint('BranchService: Disposing deep link listener');
    }
    _linkDataStreamSubscription?.cancel();
    _deepLinkHandler = null;
    _isListening = false;
  }

  Future<BranchResponse> generateReferralLink({
    required String referringParticipantId,
  }) async {
    if (kDebugMode) {
      debugPrint(
        'BranchService: Generating referral link for participant $referringParticipantId',
      );
    }

    await waitForSdkInit();

    final buo = BranchUniversalObject(
      canonicalIdentifier: referringParticipantId,
      title: 'Join Pax with my link',
      contentDescription:
          'Sign up to Pax using my referral link and start earning.',
      contentMetadata:
          BranchContentMetaData()..addCustomMetadata(
            'referringParticipantId',
            referringParticipantId,
          ),
    );

    final linkProperties =
        BranchLinkProperties(
            channel: 'app',
            feature: 'referral',
            campaign: 'road_to_twelve_k',
            stage: 'new share',
            tags: ['referral', 'participant'],
          )
          ..addControlParam('referringParticipantId', referringParticipantId)
          // Force the app to open on a stable in-app path and treat the
          // referringParticipantId purely as data.
          ..addControlParam(r'$deeplink_path', Routes.loading);

    return FlutterBranchSdk.getShortUrl(
      buo: buo,
      linkProperties: linkProperties,
    );
  }
}
