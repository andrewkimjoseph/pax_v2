import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:pax/models/auth/auth_state_model.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/remote_config/remote_config_provider.dart';
import 'package:pax/providers/account/account_type_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/services/branch_service.dart';
import 'package:pax/services/wallet/wallet_restore_helper.dart';

/// A widget that handles app lifecycle events to refresh auth state
/// when the app is resumed from background
class AppLifecycleHandler extends ConsumerStatefulWidget {
  final Widget child;
  final Function(Map<dynamic, dynamic>) onDeepLink;

  const AppLifecycleHandler({
    super.key,
    required this.child,
    required this.onDeepLink,
  });

  @override
  ConsumerState<AppLifecycleHandler> createState() =>
      _AppLifecycleHandlerState();
}

class _AppLifecycleHandlerState extends ConsumerState<AppLifecycleHandler>
    with WidgetsBindingObserver {
  final _branchService = BranchService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _branchService.init(
      deepLinkHandler: widget.onDeepLink,
    ); // Initialize with handler
    _branchService.listenToDeepLinks(); // Start listening (waits for SDK init)
    if (kDebugMode) {
      debugPrint(
        '[AppLifecycleHandler] AppLifecycleHandler: initState, observer added',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _branchService.dispose(); // Dispose the Branch service
    if (kDebugMode) {
      debugPrint(
        '[AppLifecycleHandler] AppLifecycleHandler: dispose, observer removed',
      );
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kDebugMode) {
      debugPrint(
        'AppLifecycleHandler: didChangeAppLifecycleState state=$state',
      );
    }
    if (state == AppLifecycleState.resumed) {
      // Defer ALL resume operations until after the first frame,
      // so the resumed UI can paint before any refreshes or rebuilds.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (kDebugMode) {
          debugPrint(
            'AppLifecycleHandler: resumed postFrameCallback, refreshing remote config and invalidating config providers',
          );
        }
        unawaited(
          ref.read(remoteConfigServiceProvider).refreshConfig().catchError((e) {
            if (kDebugMode) {
              debugPrint(
                '[AppLifecycleHandler] Remote config refresh failed on resume: $e',
              );
            }
          }),
        );
        // ref.invalidate(appVersionConfigProvider);
        // ref.invalidate(maintenanceConfigProvider);
        // ref.invalidate(featureFlagsProvider);

        // Only refresh auth state when in a stable non-authenticated state.
        // Skip when initial (cold start: let authStateChanges restore session) or loading (sign-in in progress).
        final currentAuthState = ref.read(authProvider);
        final shouldRefreshAuth =
            currentAuthState.state != AuthState.authenticated &&
            currentAuthState.state != AuthState.initial &&
            currentAuthState.state != AuthState.loading;
        if (shouldRefreshAuth) {
          if (kDebugMode) {
            debugPrint(
              'AppLifecycleHandler: refreshing auth state (currentState=${currentAuthState.state})',
            );
          }
          ref.read(authProvider.notifier).refreshUserState();
        } else if (currentAuthState.state == AuthState.authenticated) {
          // Preload wallet credentials for V2 users so miniapps open quickly
          if (ref.read(accountTypeProvider) == AccountType.v2) {
            if (kDebugMode) {
              debugPrint(
                '[AppLifecycleHandler] V2 authenticated, calling restoreWalletIfNeeded(silentOnly: true)',
              );
            }
            final container = ProviderScope.containerOf(context);
            restoreWalletIfNeeded(container, silentOnly: true);

            if (kDebugMode) {
              debugPrint(
                '[AppLifecycleHandler] triggering backfillPostVerificationSideEffects on resume',
              );
            }
            unawaited(
              ref
                  .read(paxWalletProvider.notifier)
                  .backfillPostVerificationSideEffects(),
            );
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PaxWalletStateModel>(paxWalletProvider, (previous, next) {
      final didLoadWallet =
          previous?.state != PaxWalletState.loaded &&
          next.state == PaxWalletState.loaded;
      if (!didLoadWallet) {
        return;
      }

      final isAuthenticated =
          ref.read(authProvider).state == AuthState.authenticated;
      final isV2Account = ref.read(accountTypeProvider) == AccountType.v2;
      if (!isAuthenticated || !isV2Account) {
        return;
      }

      unawaited(
        ref.read(paxWalletProvider.notifier).backfillPostVerificationSideEffects(),
      );
    });

    // Listen to remote config updates - moved from initState to build
    ref.listen<AsyncValue<RemoteConfigUpdate>>(remoteConfigUpdateProvider, (
      previous,
      next,
    ) {
      if (next is AsyncData) {
        if (kDebugMode) {
          debugPrint(
            'AppLifecycleHandler: remoteConfigUpdate received, invalidating config providers',
          );
        }
        ref.invalidate(appVersionConfigProvider);
        ref.invalidate(maintenanceConfigProvider);
        ref.invalidate(featureFlagsProvider);
      }
    });

    return widget.child;
  }
}
