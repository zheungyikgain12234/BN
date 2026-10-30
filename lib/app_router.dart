import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/config.dart';
import 'data/repository.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/mfa_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/admin/companies_screen.dart';
import 'features/admin/masters_screen.dart';
import 'features/admin/software_admin_screen.dart';
import 'features/cart/cart_screen.dart';
import 'features/clients/clients_screen.dart';
import 'features/licenses/licenses_screen.dart';
import 'features/software/software_store_screen.dart';
import 'features/admin/users_screen.dart';
import 'features/auth/company_select_screen.dart';
import 'features/domain/domain_search_api_screen.dart';
import 'features/hosting/hosting_screen.dart';
import 'features/ssl/purchased_ssl_screen.dart';
import 'features/ssl/ssl_screen.dart';
import 'features/vps/purchased_vps_screen.dart';
import 'features/vps/vps_screen.dart';
import 'features/hosting/purchased_hosting_screen.dart';
import 'features/domain/purchased_domains_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/placeholder_screen.dart';

/// Re-runs router redirects whenever the Supabase session or selected tenant changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh() {
    if (!Env.offline) {
      _sub = sb.auth.onAuthStateChange.listen((s) {
        final app = AppState.instance;
        if (s.session != null && !app.verified && !app.busy) authRepo.restore(); // OAuth return, sign-up
        notifyListeners();
      });
    }
    AppState.instance.addListener(notifyListeners);
  }
  StreamSubscription? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    AppState.instance.removeListener(notifyListeners);
    super.dispose();
  }
}

class Routes {
  static const company = '/company';
  static const adminCompanies = '/admin/companies';
  static const adminUsers = '/admin/users';
  static const login = '/login';
  static const register = '/register';
  static const mfa = '/mfa';
  static const software = '/software';
  static const cart = '/cart';
  static const clients = '/clients';
  static const licenses = '/licenses';
  static const adminSoftware = '/admin/software';
  static const adminMasters = '/admin/masters';
  static String adminMaster(String table) => '$adminMasters/$table';
  static const domainSearch = '/domain-search';
  static const purchasedDomains = '/purchased-domains';
  static const purchasedHosting = '/purchased-hosting';
  static const purchasedVps = '/purchased-vps';
  static const orderVps = '/order-vps';
  static const orderHosting = '/order-hosting';
  static const orderSsl = '/order-ssl';
  static const purchasedSsl = '/purchased-ssl';
  static String section(String slug) => '/section/$slug';
}

/// Pages a super admin may open.
const _superAdminRoutes = {Routes.adminCompanies, Routes.adminUsers, Routes.adminSoftware};

final router = GoRouter(
  initialLocation: Env.offline ? Routes.domainSearch : Routes.login,
  refreshListenable: _RouterRefresh(),
  redirect: (context, state) {
    if (Env.offline) return null;
    final loc = state.matchedLocation;
    final app = AppState.instance;
    final signedIn = sb.auth.currentSession != null;
    final onAuthScreen = loc == Routes.login || loc == Routes.register;

    if (!signedIn) return onAuthScreen ? null : Routes.login;
    if (authRepo.needsMfa) return loc == Routes.mfa ? null : Routes.mfa;
    if (!app.verified) return onAuthScreen ? null : Routes.login; // companies still loading
    if (!app.entered) return loc == Routes.company ? null : Routes.company; // signed in, now pick a company
    final home = app.isSuperAdmin ? Routes.adminCompanies : Routes.domainSearch;
    if (onAuthScreen || loc == Routes.company || loc == Routes.mfa) return home;
    // A super admin only manages: no shopping, clients or licenses pages.
    if (app.isSuperAdmin && !_superAdminRoutes.contains(loc) && !loc.startsWith('${Routes.adminMasters}/')) return home;
    if (loc == Routes.adminCompanies && !app.isSuperAdmin) return home;
    if (loc == Routes.adminUsers && !app.canManageUsers) return home;
    if (loc == Routes.adminSoftware && !app.canManageCatalog) return home;
    if (loc.startsWith('${Routes.adminMasters}/') && !app.isSuperAdmin) return home;
    return null;
  },
  routes: [
    GoRoute(path: Routes.company, builder: (_, _) => const CompanySelectScreen()),
    GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
    GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
    GoRoute(path: Routes.mfa, builder: (_, _) => const MfaScreen()),
    ShellRoute(
      builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
      routes: [
        GoRoute(path: Routes.software, builder: (_, _) => const SoftwareStoreScreen()),
        GoRoute(path: Routes.cart, builder: (_, _) => const CartScreen()),
        GoRoute(path: Routes.clients, builder: (_, _) => const ClientsScreen()),
        GoRoute(path: Routes.licenses, builder: (_, _) => const LicensesScreen()),
        GoRoute(path: Routes.adminSoftware, builder: (_, _) => const SoftwareAdminScreen()),
        GoRoute(path: '${Routes.adminMasters}/:table', builder: (_, s) => MastersScreen(key: ValueKey(s.pathParameters['table']), table: s.pathParameters['table']!)),
        GoRoute(path: Routes.domainSearch, builder: (_, _) => const DomainSearchApiScreen()),
        GoRoute(path: Routes.orderSsl, builder: (_, _) => const SslScreen()),
        GoRoute(path: Routes.purchasedSsl, builder: (_, _) => const PurchasedSslScreen()),
        GoRoute(path: Routes.orderHosting, builder: (_, _) => const HostingScreen()),
        GoRoute(path: Routes.purchasedDomains, builder: (_, _) => const PurchasedDomainsScreen()),
        GoRoute(path: Routes.purchasedHosting, builder: (_, _) => const PurchasedHostingScreen()),
        GoRoute(path: Routes.orderVps, builder: (_, _) => const VpsScreen()),
        GoRoute(path: Routes.purchasedVps, builder: (_, _) => const PurchasedVpsScreen()),
        GoRoute(path: Routes.adminCompanies, builder: (_, _) => const CompaniesScreen()),
        GoRoute(path: Routes.adminUsers, builder: (_, _) => const UsersScreen()),
        GoRoute(path: '/section/:slug', builder: (_, s) => PlaceholderScreen(slug: s.pathParameters['slug']!)),
      ],
    ),
  ],
);
