import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:pax/exports/views.dart';
import 'package:pax/features/account_and_security/view.dart';
// import 'package:pax/features/canvassing_x_gooddollar/view.dart';
import 'package:pax/features/claim_reward/view.dart';
import 'package:pax/features/complete_profile/view.dart';
import 'package:pax/features/face_verification/view.dart';
import 'package:pax/features/home/pax_wallet/view.dart';
import 'package:pax/features/report_page/view.dart';
import 'package:pax/features/task/task_itself/check_out_app/view.dart';
import 'package:pax/features/task/task_itself/fill_a_form/view.dart';
import 'package:pax/features/wallet_creation/view.dart';
import 'package:pax/features/home/pax_wallet/miniapps/webview/miniapp_webview.dart';
import 'package:pax/models/remote_config/miniapps_config.dart';
import 'package:pax/features/webview/view.dart';
import 'package:pax/features/webview/converter_view.dart';
import 'package:pax/features/webview/webview_converter_payload.dart';
import 'package:pax/features/withdrawal_methods/good-wallet-connection/copy-wallet-address/view.dart';
import 'package:pax/features/withdrawal_methods/good-wallet-connection/view.dart';
import 'package:pax/features/withdrawal_methods/minipay-connection/copy-wallet-address/view.dart';
import 'package:pax/models/auth/auth_state_model.dart';
import 'package:pax/widgets/image_step_photo_view/image_step_photo_view.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/db/pax_account/pax_account_provider.dart';
import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
import 'package:pax/providers/route/route_notifier_provider.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/features/onboarding/onboarding_questionnaire/view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'routes.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

final routerProvider = Provider((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    refreshListenable: notifier,
    initialLocation: Routes.loading,
    observers: [
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
    ],
    errorBuilder: (context, state) {
      // When a routing error occurs, navigate to the onboarding questionnaire so new users can continue.
      // Redirect will send unauthenticated users to sign-in and already-onboarded users to the right step.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.go(Routes.onboardingQuestionnaire);
      });
      return Scaffold(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator().withPadding(bottom: 16),
              Text('Loading...'),
            ],
          ),
        ),
      );
    },
    redirect: (context, state) {
      if (kIsWeb &&
          (state.matchedLocation == Routes.paxWallet ||
              state.matchedLocation == Routes.checkV2Eligibility)) {
        return Routes.home;
      }

      final authState = ref.read(authStateForRouterProvider);
      final isOnboardingRoute = state.matchedLocation == Routes.onboarding;

      // If not authenticated and not on onboarding, redirect to onboarding
      if (authState != AuthState.authenticated && !isOnboardingRoute) {
        return Routes.onboarding;
      }

      // If authenticated and on onboarding, redirect to home
      if (authState == AuthState.authenticated && isOnboardingRoute) {
        return Routes.home;
      }

      // If authenticated and route has an error, redirect to questionnaire so new users can continue (redirect runs on refresh and would otherwise send to home and re-trigger the error).
      if (authState == AuthState.authenticated && state.error != null) {
        return Routes.onboardingQuestionnaire;
      }

      // If authenticated, check if new user needs onboarding
      if (authState == AuthState.authenticated) {
        // Prevent landing on FV route implicitly (e.g. after app restart) without a known source.
        if (state.matchedLocation ==
            Routes.completeGoodDollarFaceVerification) {
          final extra = state.extra;
          if (extra is! String || extra.isEmpty) {
            return Routes.home;
          }
        }

        final paxAccountState = ref.read(paxAccountProvider);
        final account = paxAccountState.account;
        final isAccountLoaded = paxAccountState.state == PaxAccountState.loaded;
        final isAccountInitialOrLoading =
            paxAccountState.state == PaxAccountState.initial ||
            paxAccountState.state == PaxAccountState.loading;

        // Don't show home until we know if user is new — stay on loading while account loads (not when syncing/refreshing)
        if (isAccountInitialOrLoading && state.matchedLocation == Routes.home) {
          return Routes.loading;
        }

        // Loading screen: once account is loaded, send to the right destination
        if (state.matchedLocation == Routes.loading && isAccountLoaded) {
          if (account != null) {
            // V2 users cannot use web — block and sign out from the block page
            if (kIsWeb && account.isV2) {
              return Routes.v2WebBlocked;
            }
            final isNewUser =
                account.contractAddress == null &&
                account.eoWalletAddress == null;
            final participantState = ref.read(participantProvider);
            final onboardingType = participantState.participant?.onboardingType;

            if (isNewUser) {
              if (onboardingType == null) {
                return Routes.onboardingQuestionnaire;
              }
              if (onboardingType == 'v1_legacy') {
                return Routes.home;
              }
              return Routes.createV2Wallet;
            }
          }
          return Routes.home;
        }

        final participantState = ref.read(participantProvider);
        final onboardingType = participantState.participant?.onboardingType;

        if (isAccountLoaded && account != null) {
          final isNewUser =
              account.contractAddress == null &&
              account.eoWalletAddress == null;
          final isOnV2OnboardingRoute =
              state.matchedLocation == Routes.createV2Wallet ||
              state.matchedLocation ==
                  Routes.completeGoodDollarFaceVerification ||
              state.matchedLocation == Routes.completeProfile;
          final isOnQuestionnaireRoute =
              state.matchedLocation == Routes.onboardingQuestionnaire;

          if (isNewUser) {
            if (onboardingType == null && !isOnQuestionnaireRoute) {
              return Routes.onboardingQuestionnaire;
            }

            // Let new users stay on the questionnaire (avoid redirect loop: questionnaire ⇄ createV2Wallet).
            if (isOnQuestionnaireRoute) {
              return null;
            }

            if (!isOnV2OnboardingRoute) {
              // V1 legacy: land on home; link withdrawal methods from Wallet when ready
              if (onboardingType == 'v1_legacy') {
                return null;
              }

              // User has a Pax wallet (e.g. skipped FV then profile) — allow home instead of forcing back to wallet/FV
              final paxWalletState = ref.read(paxWalletProvider);
              if (paxWalletState.state == PaxWalletState.loaded &&
                  paxWalletState.wallet != null) {
                return null;
              }

              // Default to V2 wallet creation for v2_native and mixed
              return Routes.createV2Wallet;
            }
          }
        }

        // V2 users on web: redirect to block page (e.g. refresh or deep link)
        if (kIsWeb &&
            isAccountLoaded &&
            account != null &&
            account.isV2 &&
            state.matchedLocation != Routes.v2WebBlocked) {
          return Routes.v2WebBlocked;
        }

        return null;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: Routes.loading,
        builder:
            (context, state) => Scaffold(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator().withPadding(bottom: 16),
                    Text('Taking you to the right place...'),
                  ],
                ),
              ),
            ),
      ),
      GoRoute(
        path: Routes.home,
        builder:
            (BuildContext context, GoRouterState state) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.noScaling),
              child: RootView(),
            ),
      ),
      GoRoute(
        path: Routes.reportPage,
        builder: (context, state) => ReportPageView(state.extra as String),
      ),
      GoRoute(
        path: "/webview",
        builder: (context, state) => WebViewPage(url: state.extra as String),
      ),
      GoRoute(
        path: Routes.webviewConverter,
        builder:
            (context, state) => WebViewConverterPage(
              payload: state.extra as WebViewConverterPayload,
            ),
      ),
      GoRoute(
        path: Routes.miniappWebView,
        builder: (context, state) {
          final extra = state.extra;
          final String url;
          final String? title;
          if (extra is PaxMiniApp) {
            url = extra.url;
            title = extra.title.isNotEmpty ? extra.title : extra.name;
          } else {
            url = extra is String ? extra : '';
            title = null;
          }
          return MiniAppWebView(url: url, title: title);
        },
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingView(),
      ),
      GoRoute(
        path: Routes.onboardingQuestionnaire,
        builder: (context, state) => const OnboardingQuestionnaireView(),
      ),
      // GoRoute(
      //   path: Routes.canvassingXGoodDollar,
      //   builder: (context, state) => const CanvassingXGoodDollarView(),
      // ),
      GoRoute(
        path: Routes.activity,
        builder: (context, state) => const ActivityView(),
      ),
      GoRoute(
        path: Routes.reports,
        builder: (context, state) => const ReportsView(),
      ),
      GoRoute(
        path: Routes.accountAndSecurity,
        builder: (context, state) => const AccountAndSecurityView(),
      ),
      GoRoute(
        path: "/wallet",
        builder: (BuildContext context, GoRouterState state) => WalletView(),
        routes: [
          GoRoute(
            path: "/withdraw",
            builder:
                (BuildContext context, GoRouterState state) => WithdrawView(),
            routes: [
              GoRoute(
                path: "/select-wallet",
                builder:
                    (BuildContext context, GoRouterState state) =>
                        SelectWalletView(),
                routes: [
                  GoRoute(
                    path: "/review-summary",
                    builder:
                        (BuildContext context, GoRouterState state) =>
                            ReviewSummaryView(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: "/profile",
        builder: (BuildContext context, GoRouterState state) => ProfileView(),
      ),
      GoRoute(
        path: "/account-and-security",
        builder:
            (BuildContext context, GoRouterState state) =>
                AccountAndSecurityView(),
      ),
      GoRoute(
        path: "/help-and-support",
        builder:
            (BuildContext context, GoRouterState state) => HelpAndSupportView(),
        routes: [
          GoRoute(
            path: "/faq",
            builder: (BuildContext context, GoRouterState state) => FAQView(),
          ),
          GoRoute(
            path: "/contact-support",
            builder:
                (BuildContext context, GoRouterState state) =>
                    ContactSupportView(),
          ),
        ],
      ),

      // GoRoute(
      //   path: "/developer-options",
      //   builder:
      //       (BuildContext context, GoRouterState state) =>
      //           DeveloperOptionsView(),
      //   routes: [
      //     GoRoute(
      //       path: "/test-submit-for-forms",
      //       builder:
      //           (BuildContext context, GoRouterState state) =>
      //               TestSubmitForFormsView(),
      //     ),
      //   ],
      // ),
      GoRoute(
        path: "/tasks",
        builder: (BuildContext context, GoRouterState state) => TasksView(),
        routes: [
          GoRoute(
            path: "/task-summary",
            builder:
                (BuildContext context, GoRouterState state) =>
                    TaskSummaryView(),
            routes: [
              GoRoute(
                path: "/image-photo-view",
                builder:
                    (BuildContext context, GoRouterState state) =>
                        ImageStepPhotoView(path: state.extra as String),
              ),
            ],
          ),

          GoRoute(
            path: "/task-complete",
            builder:
                (BuildContext context, GoRouterState state) =>
                    TaskCompleteView(),
          ),
          GoRoute(
            path: "/fill-a-form",
            builder:
                (BuildContext context, GoRouterState state) => FillAFormView(),
          ),
          GoRoute(
            path: "/check-out-app",
            builder:
                (BuildContext context, GoRouterState state) =>
                    CheckOutAppView(),
            routes: [
              GoRoute(
                path: "/image-photo-view",
                builder:
                    (BuildContext context, GoRouterState state) =>
                        ImageStepPhotoView(path: state.extra as String),
              ),
            ],
          ),
        ],
      ),

      GoRoute(
        path: "/withdrawal-methods",
        builder:
            (BuildContext context, GoRouterState state) =>
                WithdrawalMethodsView(),
        routes: [
          GoRoute(
            path: "/minipay-connection",
            builder:
                (BuildContext context, GoRouterState state) =>
                    MiniPayConnectionView(),
            routes: [
              GoRoute(
                path: "/image-photo-view",
                builder:
                    (BuildContext context, GoRouterState state) =>
                        ImageStepPhotoView(path: state.extra as String),
              ),

              GoRoute(
                path: "/copy-wallet-address",
                builder:
                    (BuildContext context, GoRouterState state) =>
                        CopyWalletAddressMiniPayView(),

                routes: [
                  GoRoute(
                    path: "/image-photo-view",
                    builder:
                        (BuildContext context, GoRouterState state) =>
                            ImageStepPhotoView(path: state.extra as String),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: "/good-wallet-connection",
            builder:
                (BuildContext context, GoRouterState state) =>
                    GoodWalletConnectionView(),
            routes: [
              GoRoute(
                path: "/image-photo-view",
                builder:
                    (BuildContext context, GoRouterState state) =>
                        ImageStepPhotoView(path: state.extra as String),
              ),

              GoRoute(
                path: "/copy-wallet-address",
                builder:
                    (BuildContext context, GoRouterState state) =>
                        CopyWalletAddressGoodWalletView(),

                routes: [
                  GoRoute(
                    path: "/image-photo-view",
                    builder:
                        (BuildContext context, GoRouterState state) =>
                            ImageStepPhotoView(path: state.extra as String),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: "/claim-reward",
        builder:
            (BuildContext context, GoRouterState state) => ClaimRewardView(),
      ),
      GoRoute(
        path: Routes.createV2Wallet,
        builder: (context, state) => const WalletCreationView(),
      ),
      GoRoute(
        path: Routes.completeGoodDollarFaceVerification,
        builder:
            (context, state) =>
                FaceVerificationView(source: state.extra as String?),
      ),
      GoRoute(
        path: Routes.completeProfile,
        builder: (context, state) => const CompleteProfileView(),
      ),
      GoRoute(
        path: Routes.paxWallet,
        builder: (context, state) => const WalletAndAppsView(),
      ),
      GoRoute(
        path: Routes.checkV2Eligibility,
        builder: (context, state) => const V2EligibilityView(),
      ),
      GoRoute(
        path: Routes.v2WebBlocked,
        builder: (context, state) => const V2WebBlockedView(),
      ),
    ],
  );
});
