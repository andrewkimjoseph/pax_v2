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
        debugPrint('[BranchService] BranchService: SDK marked as initialized');
      }
    }
  }

  /// Wait for the SDK to be initialized
  static Future<void> waitForSdkInit() => _sdkInitCompleter.future;

  void init({required Function(Map<dynamic, dynamic>) deepLinkHandler}) {
    _deepLinkHandler = deepLinkHandler;
    if (kDebugMode) {
      debugPrint('[BranchService] BranchService: Initialized with deep link handler');
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
        debugPrint('[Already] Already listening to deep links');
      }
      return;
    }

    // Wait for SDK to be initialized before listening
    if (!_sdkInitialized) {
      if (kDebugMode) {
        debugPrint('[BranchService] BranchService: Waiting for SDK initialization...');
      }
      await waitForSdkInit();
    }

    if (kDebugMode) {
      debugPrint('[BranchService] BranchService: Starting deep link listener');
    }
    _linkDataStreamSubscription = FlutterBranchSdk.listSession().listen(
      (linkData) {
        if (kDebugMode) {
          debugPrint('[BranchService] BranchService: Deep link being listened to: $linkData');
        }
        // Only handle deep links if they contain actual link data
        if (linkData.isNotEmpty && linkData['+clicked_branch_link'] == true) {
          _deepLinkHandler?.call(linkData);
        }
      },
      onError: (error) {
        if (kDebugMode) {
          debugPrint('[BranchService] BranchService: Error receiving deep link: $error');
        }
      },
    );
    _isListening = true;
  }

  void dispose() {
    if (kDebugMode) {
      debugPrint('[BranchService] BranchService: Disposing deep link listener');
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
        '[BranchService] generateReferralLink called for participant $referringParticipantId',
      );
      debugPrint(
        '[BranchService] SDK initialized: $_sdkInitialized, completer completed: ${_sdkInitCompleter.isCompleted}',
      );
    }

    await waitForSdkInit();

    if (kDebugMode) {
      debugPrint('[BranchService] waitForSdkInit resolved — proceeding to create short URL');
    }

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
          ..addControlParam(r'$deeplink_path', Routes.loading);

    if (kDebugMode) {
      debugPrint('[BranchService] Calling FlutterBranchSdk.getShortUrl...');
    }

    try {
      final response = await FlutterBranchSdk.getShortUrl(
        buo: buo,
        linkProperties: linkProperties,
      );
      if (kDebugMode) {
        debugPrint('[BranchService] getShortUrl returned — success: ${response.success}, '
            'result: ${response.result}');
      }
      return response;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[BranchService] getShortUrl threw: $e');
        debugPrint('[BranchService] Stack trace: $st');
      }
      rethrow;
    }
  }
}
