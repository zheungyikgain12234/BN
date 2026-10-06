import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import 'models.dart';

SupabaseClient get sb => Supabase.instance.client;

/// Session-wide state: which tenant the user picked on the company-select screen.
class AppState extends ChangeNotifier {
  AppState._();
  static final instance = AppState._();

  Tenant? _tenant = Env.offline
      ? Tenant(id: 'demo', name: 'Gain City Digital Innovation Pte Ltd', code: 'TEN-94820-SG', domain: 'gaincity.com.sg', plan: 'enterprise', seats: 142, role: 'admin')
      : null;
  Tenant? get tenant => _tenant;

  void selectTenant(Tenant? t) {
    _tenant = t;
    notifyListeners();
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
  Future<void> signIn(String email, String password) =>
      sb.auth.signInWithPassword(email: email.trim(), password: password);

  Future<void> signInWithProvider(OAuthProvider provider) => sb.auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb ? null : Env.oauthRedirect,
        scopes: provider == OAuthProvider.azure ? 'email' : null,
      );

  Future<void> resetPassword(String email) => sb.auth.resetPasswordForEmail(email.trim());

  Future<void> signOut() async {
    if (Env.offline) return;
    AppState.instance.selectTenant(null);
    await sb.auth.signOut();
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
  Future<List<Tenant>> myTenants() async {
    final rows = await sb.from('tenant_members').select('role, tenants(*)').eq('user_id', sb.auth.currentUser!.id);
    return rows.map<Tenant>(Tenant.fromMember).toList();
  }
}

class CatalogRepository {
  Future<List<Product>> products() async {
    final rows = await sb.from('products').select().order('sort_order');
    return rows.map<Product>(Product.fromJson).toList();
  }

  Future<Product> product(String id) async => Product.fromJson(await sb.from('products').select().eq('id', id).single());

  Future<List<ProductScreenshot>> screenshots(String productId) async {
    final rows = await sb.from('product_screenshots').select().eq('product_id', productId).order('sort_order');
    return rows.map<ProductScreenshot>(ProductScreenshot.fromJson).toList();
  }

  Future<List<ProductComment>> comments(String productId) async {
    final rows = await sb
        .from('product_comments')
        .select('*, profiles(full_name, job_title, avatar_url)')
        .eq('product_id', productId)
        .order('endorsements', ascending: false)
        .order('created_at', ascending: false);
    return rows.map<ProductComment>(ProductComment.fromJson).toList();
  }

  Future<int> commentCount(String productId) => sb.from('product_comments').count().eq('product_id', productId);

  Future<void> postComment(String productId, String body) =>
      sb.from('product_comments').insert({'product_id': productId, 'body': body});
}

final authRepo = AuthRepository();
final tenantRepo = TenantRepository();
final catalogRepo = CatalogRepository();
