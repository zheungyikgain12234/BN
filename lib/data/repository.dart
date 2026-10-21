import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

import '../core/config.dart';
import '../main.dart' show messengerKey;
import 'models.dart';
import 'stackcp_sso.dart';

SupabaseClient get sb => Supabase.instance.client;

/// Session-wide state. Sign-in comes first; afterwards the user picks one of the companies they
/// belong to (a super admin can pick any company).
class AppState extends ChangeNotifier {
  AppState._();
  static final instance = AppState._();

  static const _savedCompanyKey = 'biznest.company';

  Tenant? _tenant = Env.offline
      ? Tenant(id: 'demo', name: 'Gain City Digital Innovation Pte Ltd', code: 'TEN-94820-SG', domain: 'gaincity.com.sg', plan: 'enterprise', seats: 142, role: 'admin')
      : null;

  /// The company the user is currently working in.
  Tenant? get tenant => _tenant;

  List<Tenant> _companies = const [];

  /// Companies the signed-in user can enter (all of them for a super admin).
  List<Tenant> get companies => _companies;

  bool _isAdmin = false;
  bool get isAdmin => _isAdmin;

  /// Super admin: manages companies and users (and may edit any catalog).
  bool get isSuperAdmin => _isAdmin;

  /// Company admin: membership role "admin" in the selected company.
  bool get isCompanyAdmin => _tenant?.role == 'admin';

  /// Reseller admin (or super admin): can buy licenses and assign them to clients.
  bool get canBuy => isSuperAdmin || isCompanyAdmin;

  /// Every reseller manages their own company's software; a super admin manages any.
  bool get canManageCatalog => isSuperAdmin || _tenant != null;

  bool _verified = false;

  /// True once the signed-in user's companies have been loaded.
  bool get verified => Env.offline || _verified;

  bool _skippedCompany = false;

  /// True once the user is inside a company (or a super admin chose to continue without one).
  bool get entered => Env.offline || _tenant != null || _skippedCompany;

  /// Set while signIn() runs its own check, so the auth-state listener doesn't start a second one.
  bool busy = false;

  void selectTenant(Tenant t) {
    _tenant = t;
    _skippedCompany = false;
    _remember(t.id);
    notifyListeners();
  }

  /// A super admin may work without picking a company (e.g. when none exist yet).
  void enterWithoutCompany() {
    _skippedCompany = true;
    notifyListeners();
  }

  /// Back to the company list, keeping the session.
  void switchCompany() {
    _tenant = null;
    _skippedCompany = false;
    _remember(null);
    notifyListeners();
  }

  void reset() {
    _tenant = null;
    _companies = const [];
    _isAdmin = false;
    _verified = false;
    _skippedCompany = false;
    _remember(null);
    notifyListeners();
  }

  /// Loads the signed-in user's companies. Returns an error message, or null when the user may continue.
  Future<String?> loadAccess() async {
    final uid = sb.auth.currentUser!.id;
    final admin = await sb.from('app_admins').select('user_id').eq('user_id', uid).maybeSingle() != null;
    final memberships = await tenantRepo.myTenants();

    List<Tenant> companies = memberships;
    if (admin) {
      final rows = await sb.from('tenants').select().order('name');
      final roleOf = {for (final m in memberships) m.id: m.role};
      companies = [for (final r in rows) Tenant.fromRow(r, role: roleOf[r['id']] ?? 'admin')];
    }
    if (companies.isEmpty && !admin) return 'This account is not linked to any company.';

    _isAdmin = admin;
    _companies = companies;
    // come back to the company used last time, if the user still has access to it
    final saved = _savedCompany();
    _tenant = _tenant == null ? companies.where((c) => c.id == saved).firstOrNull : companies.where((c) => c.id == _tenant!.id).firstOrNull;
    _verified = true;
    notifyListeners();
    return null;
  }

  static String? _savedCompany() {
    try {
      return web.window.localStorage.getItem(_savedCompanyKey);
    } catch (_) {
      return null; // storage can be blocked; the user just picks again
    }
  }

  static void _remember(String? id) {
    try {
      if (id == null) {
        web.window.localStorage.removeItem(_savedCompanyKey);
      } else {
        web.window.localStorage.setItem(_savedCompanyKey, id);
      }
    } catch (_) {}
  }

  String get displayName {
    if (Env.offline) return 'Griffin';
    final u = sb.auth.currentUser;
    final meta = u?.userMetadata ?? const {};
    return (meta['full_name'] ?? meta['name'] ?? u?.email?.split('@').first ?? 'there') as String;
  }

  String get firstName => displayName.split(' ').first;
  String? get avatarUrl => Env.offline ? null : sb.auth.currentUser?.userMetadata?['avatar_url'] as String?;
}

class AuthRepository {
  /// Email + password first. The user must belong to at least one company (or be a super admin);
  /// the company itself is chosen on the next screen.
  Future<void> signIn({required String email, required String password}) async {
    final app = AppState.instance;
    app.busy = true;
    try {
      await sb.auth.signInWithPassword(email: email.trim(), password: password);
      final error = await app.loadAccess();
      if (error != null) {
        app.reset();
        await sb.auth.signOut();
        throw AuthException(error);
      }
    } finally {
      app.busy = false;
    }
  }

  bool _restoring = false;

  /// Loads the companies of a session that appeared without signIn() (page reload, sign-up).
  /// Users who don't belong to a company are signed out again.
  Future<void> restore() async {
    if (_restoring || sb.auth.currentSession == null) return;
    _restoring = true;
    try {
      if (await AppState.instance.loadAccess() != null) await signOut();
    } catch (_) {
      await signOut();
    } finally {
      _restoring = false;
    }
  }

  /// Creates the account in [companyId] (the DB trigger adds the membership). Returns true when a
  /// session was started right away; false when the project requires email confirmation first.
  Future<bool> signUp({required String fullName, required String email, required String password, required String companyId}) async {
    final res = await sb.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim(), 'company_id': companyId},
      emailRedirectTo: kIsWeb ? null : Env.oauthRedirect,
    );
    return res.session != null;
  }

  Future<void> signInWithProvider(OAuthProvider provider) => sb.auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb ? null : Env.oauthRedirect,
        scopes: provider == OAuthProvider.azure ? 'email' : null,
      );

  Future<void> resetPassword(String email) => sb.auth.resetPasswordForEmail(email.trim());

  Future<void> signOut() async {
    if (Env.offline) return;
    messengerKey.currentState?.clearSnackBars();
    AppState.instance.reset();
    try {
      clearStackcpSession();
    } catch (_) {} // never let panel cleanup block the actual sign-out
    await sb.auth.signOut(); // router redirect sends the user back to /login
  }

  /// True when the user has a verified TOTP factor that hasn't been proven in this session yet.
  bool get needsMfa {
    final aal = sb.auth.mfa.getAuthenticatorAssuranceLevel();
    return aal.nextLevel == AuthenticatorAssuranceLevels.aal2 && aal.currentLevel != AuthenticatorAssuranceLevels.aal2;
  }

  Future<String?> verifiedTotpFactorId() async {
    final factors = await sb.auth.mfa.listFactors();
    return factors.totp.isEmpty ? null : factors.totp.first.id;
  }

  Future<void> verifyTotp(String factorId, String code) =>
      sb.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
}

class TenantRepository {
  /// Every company (id + name only), readable before sign-in for the company picker.
  Future<List<Tenant>> companies() async {
    final rows = await sb.rpc('list_companies') as List;
    return rows.map<Tenant>((r) => Tenant.basic(id: r['id'] as String, name: r['name'] as String)).toList();
  }

  Future<List<Tenant>> myTenants() async {
    final rows = await sb.from('tenant_members').select('role, tenants(*)').eq('user_id', sb.auth.currentUser!.id);
    return rows.map<Tenant>(Tenant.fromMember).toList();
  }
}

final authRepo = AuthRepository();
final tenantRepo = TenantRepository();
