import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/config.dart';
import 'data/repository.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/mfa_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/tenant_select_screen.dart';
import 'features/domain/domain_search_screen.dart';
import 'features/home/home_screen.dart';
import 'features/hosting/hosting_embed_test_screen.dart';
import 'features/products/product_detail_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/placeholder_screen.dart';

/// Re-runs router redirects whenever the Supabase session or selected tenant changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh() {
    if (!Env.offline) _sub = sb.auth.onAuthStateChange.listen((_) => notifyListeners());
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
  static const login = '/login';
  static const register = '/register';
  static const mfa = '/mfa';
  static const tenants = '/tenants';
  static const home = '/home';
  static const software = '/software';
  static const domainSearch = '/domain-search';
  static const hostingTest = '/hosting-test';
  static String product(String id) => '/products/$id';
  static String section(String slug) => '/section/$slug';
}

/// Temporary: skip the company/tenant step and land on the embedded panel after login.
/// Set to false to restore the tenant-select -> home flow.
const _skipTenantStep = true;

final router = GoRouter(
  initialLocation: (Env.offline || _skipTenantStep) ? Routes.domainSearch : Routes.home,
  refreshListenable: _RouterRefresh(),
  redirect: (context, state) {
    if (Env.offline) return null;
    final loc = state.matchedLocation;
    final signedIn = sb.auth.currentSession != null;

    if (!signedIn) return (loc == Routes.login || loc == Routes.register) ? null : Routes.login;
    if (authRepo.needsMfa) return loc == Routes.mfa ? null : Routes.mfa;
    if (loc == Routes.login || loc == Routes.register || loc == Routes.mfa) return _skipTenantStep ? Routes.domainSearch : Routes.tenants;
    if (!_skipTenantStep && loc != Routes.tenants && AppState.instance.tenant == null) return Routes.tenants;
    return null;
  },
  routes: [
    GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
    GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
    GoRoute(path: Routes.mfa, builder: (_, _) => const MfaScreen()),
    GoRoute(path: Routes.tenants, builder: (_, _) => const TenantSelectScreen()),
    ShellRoute(
      builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
      routes: [
        GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
        GoRoute(path: Routes.software, builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/products/:id', builder: (_, s) => ProductDetailScreen(productId: s.pathParameters['id']!)),
        GoRoute(path: Routes.domainSearch, builder: (_, _) => const DomainSearchScreen()),
        GoRoute(path: Routes.hostingTest, builder: (_, _) => const HostingEmbedTestScreen()),
        GoRoute(path: '/section/:slug', builder: (_, s) => PlaceholderScreen(slug: s.pathParameters['slug']!)),
      ],
    ),
  ],
);
