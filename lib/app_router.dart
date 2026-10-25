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
import 'features/domain/domain_search_screen.dart';
import 'features/hosting/hosting_embed_test_screen.dart';
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
  static const domainSearch = '/domain-search';
  static const domainSearchApi = '/domain-search-api';
  static const orderVps = '/order-vps';
  static const orderHosting = '/order-hosting';
  static const orderSsl = '/order-ssl';
  static const orderWordpress = '/order-wordpress-hosting';
  static const hostingTest = '/hosting-test';
  static String section(String slug) => '/section/$slug';
}


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
    if (onAuthScreen || loc == Routes.company || loc == Routes.mfa) return Routes.domainSearch;
    if (loc == Routes.adminCompanies && !app.isSuperAdmin) return Routes.domainSearch;
    if (loc == Routes.adminUsers && !app.canBuy) return Routes.domainSearch;
    if (loc == Routes.adminSoftware && !app.canManageCatalog) return Routes.domainSearch;
    if (loc == Routes.adminMasters && !app.isSuperAdmin) return Routes.domainSearch;
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
        GoRoute(path: Routes.adminMasters, builder: (_, _) => const MastersScreen()),
        for (final e in const {
          Routes.domainSearch: 'Domain Search',
          Routes.orderVps: 'VPS',
          Routes.orderHosting: 'Web Hosting',
          Routes.orderSsl: 'SSL Certificates',
          Routes.orderWordpress: 'WordPress Hosting',
        }.entries)
          GoRoute(path: e.key, builder: (_, _) => PanelEmbedScreen(title: e.value, url: '${Env.panelBase}${e.key}')),
        GoRoute(path: Routes.domainSearchApi, builder: (_, _) => const DomainSearchApiScreen()),
        GoRoute(path: Routes.adminCompanies, builder: (_, _) => const CompaniesScreen()),
        GoRoute(path: Routes.adminUsers, builder: (_, _) => const UsersScreen()),
        GoRoute(path: Routes.hostingTest, builder: (_, _) => const HostingEmbedTestScreen()),
        GoRoute(path: '/section/:slug', builder: (_, s) => PlaceholderScreen(slug: s.pathParameters['slug']!)),
      ],
    ),
  ],
);
