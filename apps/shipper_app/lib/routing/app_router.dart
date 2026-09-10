import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../features/auth/forgot_password_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/dashboard/dashboard_home_tab.dart';
import '../features/dashboard/home_shell.dart';
import '../features/dashboard/more_tab.dart';
import '../features/organization/organization_documents_screen.dart';
import '../features/shipments/containers_screen.dart';
import '../features/shipments/create_shipment_screen.dart';
import '../features/shipments/open_bid_items_screen.dart';
import '../features/shipments/rejected_ship_items_screen.dart';
import '../features/shipments/ship_item_bids_screen.dart';
import '../features/shipments/shipment_containers_screen.dart';
import '../features/shipments/shipment_detail_screen.dart';
import '../features/shipments/shipment_documents_screen.dart';
import '../features/shipments/shipment_quotes_screen.dart';
import '../features/shipments/shipment_tracking_screen.dart';
import '../features/shipments/shipments_list_screen.dart';

class AppRoutes {
  const AppRoutes._();
  static const signIn = '/sign-in';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const dashboard = '/dashboard';
  static const shipments = '/dashboard/shipments';
  static const containers = '/dashboard/containers';
  static const openBids = '/dashboard/open-bids';
  static const more = '/dashboard/more';
  static const organizationDocuments = '/dashboard/more/organization-documents';
  static const rejectedShipItems = '/dashboard/shipments/rejected';
}

int _id(GoRouterState state, [String key = 'id']) =>
    int.tryParse(state.pathParameters[key] ?? '') ?? 0;

final routerProvider = Provider<GoRouter>((ref) {
  // Built once. We must NOT `watch` the auth state here — that would recreate
  // the whole GoRouter (and tear down the navigator + any open modal sheet) on
  // every auth change. Instead the redirect reads it lazily, and the
  // status-only refresh listenable re-runs the redirect on real transitions.
  return GoRouter(
    initialLocation: AppRoutes.signIn,
    refreshListenable: _AuthRefreshNotifier(ref),
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      if (auth.isInitializing) return null;

      final path = state.matchedLocation;
      final preLogin = path == AppRoutes.signIn ||
          path == AppRoutes.forgotPassword ||
          path == AppRoutes.resetPassword;

      if (!auth.isSignedIn && !preLogin) return AppRoutes.signIn;
      if (auth.isSignedIn && preLogin) return AppRoutes.dashboard;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) => const ResetPasswordScreen(),
      ),

      // Post-login app shell: 5 branches behind the animated bottom nav.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          // 0 — Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (context, state) => const DashboardHomeTab(),
              ),
            ],
          ),
          // 1 — Shipments (+ detail and its sub-screens)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.shipments,
                builder: (context, state) => const ShipmentsListScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) => const CreateShipmentScreen(),
                  ),
                  GoRoute(
                    // Literal segment — must be declared before `:id` so the
                    // router doesn't try to parse "rejected" as an id.
                    path: 'rejected',
                    builder: (context, state) {
                      final raw = state.uri.queryParameters['ship_id'];
                      final shipId = raw == null ? null : int.tryParse(raw);
                      return RejectedShipItemsScreen(shipId: shipId);
                    },
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) =>
                        ShipmentDetailScreen(shipmentId: _id(state)),
                    routes: [
                      GoRoute(
                        path: 'track',
                        builder: (context, state) =>
                            ShipmentTrackingScreen(shipmentId: _id(state)),
                      ),
                      GoRoute(
                        path: 'quotes',
                        builder: (context, state) =>
                            ShipmentQuotesScreen(shipmentId: _id(state)),
                      ),
                      GoRoute(
                        path: 'documents',
                        builder: (context, state) =>
                            ShipmentDocumentsScreen(shipmentId: _id(state)),
                      ),
                      GoRoute(
                        path: 'containers',
                        builder: (context, state) =>
                            ShipmentContainersScreen(shipmentId: _id(state)),
                      ),
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) =>
                            CreateShipmentScreen(shipmentId: _id(state)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // 2 — Containers
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.containers,
                builder: (context, state) => const ContainersScreen(),
              ),
            ],
          ),
          // 3 — Bids (+ bids list for an item)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.openBids,
                builder: (context, state) => const OpenBidItemsScreen(),
                routes: [
                  GoRoute(
                    path: ':shipItemId/bids',
                    builder: (context, state) => ShipItemBidsScreen(
                      shipItemId: _id(state, 'shipItemId'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 4 — More (+ organization documents)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.more,
                builder: (context, state) => const MoreTab(),
                routes: [
                  GoRoute(
                    path: 'organization-documents',
                    builder: (context, state) =>
                        const OrganizationDocumentsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Refreshes the router only when the *auth status* transitions
/// (initializing/signedOut/signedIn). It deliberately ignores error-only
/// changes — a failed login sets `error` while staying `signedOut`, and
/// refreshing on that would rebuild the navigator and tear down the open login
/// modal before its inline error could show.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(this._ref) {
    _last = _ref.read(authControllerProvider).status;
    _ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.status != _last) {
        _last = next.status;
        notifyListeners();
      }
    });
  }
  final Ref _ref;
  late AuthStatus _last;
}
