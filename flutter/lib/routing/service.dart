import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
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
import 'package:pax/features/referral/view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'routes.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

final routerProvider = Provider((ref) {
  final notifier = ref.watch(routerNotifierProvider);
  if (kDebugMode) {
    debugPrint(
      '[Router] Building GoRouter with initialLocation=${Routes.loading}',
    );
  }
  return GoRouter(
    refreshListenable: notifier,
    initialLocation: Routes.loading,
    observers: [
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
    ],
    errorBuilder: (context, state) {
      // When a routing error occurs (e.g. unknown deep-link path), show a simple
      // loading screen and let the redirect logic decide what to do next.
      if (kDebugMode) {
        debugPrint(
          '[Router] errorBuilder: matchedLocation=${state.matchedLocation}, error=${state.error}',
        );
      }
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
        if (kDebugMode) {
          debugPrint(
            '[Router] redirect: web block paxWallet/checkV2Eligibility → home',
          );
        }
        return Routes.home;
      }

      final authState = ref.read(authStateForRouterProvider);
      final isOnboardingRoute = state.matchedLocation == Routes.onboarding;
      final isOnQuestionnaireRoute =
          state.matchedLocation == Routes.onboardingQuestionnaire;
      if (kDebugMode) {
        debugPrint(
          '[Router] redirect: matchedLocation=${state.matchedLocation}, authState=$authState',
        );
      }

      // While auth state is still resolving, stay on a neutral loading route
      // instead of sending users to onboarding.
      if ((authState == AuthState.initial || authState == AuthState.loading) &&
          state.matchedLocation != Routes.loading &&
          !isOnboardingRoute &&
          !isOnQuestionnaireRoute) {
        if (kDebugMode) {
          debugPrint('[Router] redirect: auth resolving → loading');
        }
        return Routes.loading;
      }

      // If not authenticated and not on onboarding/questionnaire, redirect to onboarding
      if (authState == AuthState.unauthenticated &&
          !isOnboardingRoute &&
          !isOnQuestionnaireRoute) {
        if (kDebugMode) {
          debugPrint('[Router] redirect: not authenticated → onboarding');
        }
        return Routes.onboarding;
      }

      // If authenticated and on onboarding, send brand‑new users to the questionnaire;
      // existing users go home. Avoid making this decision while participant/account
      // data are still loading to prevent transient misclassification.
      if (authState == AuthState.authenticated && isOnboardingRoute) {
        final participantState = ref.read(participantProvider);
        final paxAccountState = ref.read(paxAccountProvider);
        final onboardingType = participantState.participant?.onboardingType;
        final isParticipantLoaded =
            participantState.state == ParticipantState.loaded;
        final isAccountLoaded =
            paxAccountState.state == PaxAccountState.loaded &&
            paxAccountState.account != null;

        // While either participant or account are not yet loaded, avoid pushing
        // users into the questionnaire or home prematurely. Send them to the
        // neutral loading route and let subsequent redirects decide once data
        // is ready.
        if (!isParticipantLoaded || !isAccountLoaded) {
          if (kDebugMode) {
            debugPrint(
              '[Router] redirect: authenticated on onboarding while data loading → loading',
            );
          }
          return Routes.loading;
        }

        final account = paxAccountState.account!;
        final isNewUser =
            account.contractAddress == null && account.eoWalletAddress == null;

        if (isNewUser && onboardingType == null) {
          if (kDebugMode) {
            debugPrint(
              '[Router] redirect: authenticated on onboarding, new user with no onboardingType → onboardingQuestionnaire',
            );
          }
          return Routes.onboardingQuestionnaire;
        }

        if (kDebugMode) {
          debugPrint(
            '[Router] redirect: authenticated on onboarding (existing user or questionnaire complete) → home',
          );
        }
        return Routes.home;
      }

      // If authenticated and on the questionnaire, only allow brand‑new users (no onboardingType);
      // everyone else should be redirected away (typically home).
      if (authState == AuthState.authenticated && isOnQuestionnaireRoute) {
        final participantState = ref.read(participantProvider);
        final onboardingType = participantState.participant?.onboardingType;

        if (onboardingType == null) {
          if (kDebugMode) {
            debugPrint(
              '[Router] redirect: authenticated on questionnaire with no onboardingType → null',
            );
          }
          return null;
        }

        if (kDebugMode) {
          debugPrint(
            '[Router] redirect: authenticated on questionnaire with onboardingType=$onboardingType → home',
          );
        }
        return Routes.home;
      }

      // If authenticated and route has an error, do not force questionnaire.
      // Let the errorBuilder or current route handle it.
      if (authState == AuthState.authenticated && state.error != null) {
        if (kDebugMode) {
          debugPrint(
            '[Router] redirect: authenticated with error → null (no redirect)',
          );
        }
        return null;
      }

      // If authenticated, check if new user needs onboarding
      if (authState == AuthState.authenticated) {
        // Prevent landing on FV route implicitly (e.g. after app restart) without a known source.
        if (state.matchedLocation ==
            Routes.completeGoodDollarFaceVerification) {
          final extra = state.extra;
          if (extra is! String || extra.isEmpty) {
            if (kDebugMode) {
              debugPrint('[Router] redirect: FV route missing extra → home');
            }
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
          if (kDebugMode) {
            debugPrint('[Router] redirect: account loading, on home → loading');
          }
          return null;
        }

        // Loading screen: once account is loaded, send to the right destination
        if (state.matchedLocation == Routes.loading && isAccountLoaded) {
          if (account != null) {
            // V2 users cannot use web — block and sign out from the block page
            if (kIsWeb && account.isV2) {
              if (kDebugMode) {
                debugPrint('[Router] redirect: web + v2 → v2WebBlocked');
              }
              return Routes.v2WebBlocked;
            }
            final isNewUser =
                account.contractAddress == null &&
                account.eoWalletAddress == null;
            final participantState = ref.read(participantProvider);
            final onboardingType = participantState.participant?.onboardingType;
            final isParticipantLoaded =
                participantState.state == ParticipantState.loaded;

            // New users: wait for participant to finish loading before deciding.
            if (isNewUser) {
              if (!isParticipantLoaded) {
                if (kDebugMode) {
                  debugPrint(
                    '[Router] redirect: loading+loaded, new user but participant still loading → null',
                  );
                }
                return null;
              }

              if (onboardingType == null) {
                if (kDebugMode) {
                  debugPrint(
                    '[Router] redirect: loading+loaded, new user with no onboardingType → onboardingQuestionnaire',
                  );
                }
                return Routes.onboardingQuestionnaire;
              }
              if (onboardingType == 'v1_legacy') {
                if (kDebugMode) {
                  debugPrint(
                    '[Router] redirect: loading+loaded V1 legacy → home',
                  );
                }
                return Routes.home;
              }
              if (kDebugMode) {
                debugPrint(
                  '[Router] redirect: loading+loaded new V2 user → createV2Wallet',
                );
              }
              return Routes.createV2Wallet;
            }
          }
          if (kDebugMode) {
            debugPrint('[Router] redirect: loading, account not loaded → home');
          }
          return Routes.home;
        }

        if (isAccountLoaded && account != null) {
          final participantState = ref.read(participantProvider);
          final onboardingType = participantState.participant?.onboardingType;
          final isParticipantLoaded =
              participantState.state == ParticipantState.loaded;
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

          // Global guard: once both account and participant are loaded and the user
          // is new with no onboardingType, force questionnaire from any route.
          if (isNewUser &&
              isParticipantLoaded &&
              onboardingType == null &&
              !isOnQuestionnaireRoute &&
              state.matchedLocation != Routes.loading) {
            if (kDebugMode) {
              debugPrint(
                '[Router] redirect: authenticated new user with no onboardingType → onboardingQuestionnaire',
              );
            }
            return Routes.onboardingQuestionnaire;
          }

          if (isNewUser) {
            if (onboardingType == null && !isOnQuestionnaireRoute) {
              if (kDebugMode) {
                debugPrint(
                  '[Router] redirect: new user, no onboardingType → null',
                );
              }
              return null;
            }

            // Let new users stay on the questionnaire (avoid redirect loop: questionnaire ⇄ createV2Wallet).
            if (isOnQuestionnaireRoute) {
              if (kDebugMode) {
                debugPrint(
                  '[Router] redirect: new user on questionnaire → null',
                );
              }
              return null;
            }

            if (!isOnV2OnboardingRoute) {
              // V1 legacy: land on home; link withdrawal methods from Wallet when ready
              if (onboardingType == 'v1_legacy') {
                if (kDebugMode) {
                  debugPrint('[Router] redirect: v1_legacy → null');
                }
                return null;
              }

              // User has a Pax wallet (e.g. skipped FV then profile) — allow home instead of forcing back to wallet/FV
              final paxWalletState = ref.read(paxWalletProvider);
              if (paxWalletState.state == PaxWalletState.loaded &&
                  paxWalletState.wallet != null) {
                if (kDebugMode) {
                  debugPrint(
                    '[Router] redirect: new user, pax wallet loaded → null',
                  );
                }
                return null;
              }

              // Default to V2 wallet creation for v2_native and mixed
              if (kDebugMode) {
                debugPrint(
                  '[Router] redirect: new user, default → createV2Wallet',
                );
              }
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
          if (kDebugMode) {
            debugPrint('[Router] redirect: v2 on web → v2WebBlocked');
          }
          return Routes.v2WebBlocked;
        }

        if (kDebugMode) {
          debugPrint('[Router] redirect: no redirect → null');
        }
        return null;
      }

      if (kDebugMode) {
        debugPrint('[Router] redirect: no redirect → null');
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
          GoRoute(
            path: "/donate",
            builder: (BuildContext context, GoRouterState state) => DonateView(),
            routes: [
              GoRoute(
                path: "/select-goodcollective",
                builder:
                    (BuildContext context, GoRouterState state) =>
                        SelectGoodCollectiveView(),
                routes: [
                  GoRoute(
                    path: "/review-summary",
                    builder:
                        (BuildContext context, GoRouterState state) =>
                            DonationReviewSummaryView(),
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
        path: Routes.referral,
        builder:
            (BuildContext context, GoRouterState state) => const ReferralView(),
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
      // Catch-all: any unknown path falls back to home instead of raising
      // a routing error, which avoids extra flashes for deep links.
      GoRoute(
        path: '/:path(.*)',
        redirect: (context, state) {
          if (kDebugMode) {
            debugPrint(
              '[Router] catch-all redirect: ${state.matchedLocation} → ${Routes.home}',
            );
          }
          return Routes.home;
        },
      ),
    ],
  );
});
