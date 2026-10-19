import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'repository.dart';

/// One company a user belongs to, with their role there.
class Membership {
  const Membership({required this.companyId, required this.role});
  final String companyId, role;

  Map<String, dynamic> toJson() => {'company_id': companyId, 'role': role};
}

/// A user as shown on the admin Users screen (auth user + company memberships).
class ManagedUser {
  ManagedUser.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        email = (j['email'] ?? '') as String,
        fullName = (j['full_name'] ?? '') as String,
        memberships = [
          for (final m in (j['memberships'] as List? ?? const [])) Membership(companyId: m['company_id'] as String, role: (m['role'] ?? 'member') as String),
          // the previous version of the admin-users function returned a single company_id + role
          if (j['memberships'] == null && j['company_id'] != null) Membership(companyId: j['company_id'] as String, role: (j['role'] ?? 'member') as String),
        ],
        canEditAccount = j['can_edit_account'] != false,
        suspended = j['suspended'] == true,
        isAdmin = j['is_admin'] == true,
        lastSignIn = j['last_sign_in_at'] == null ? null : DateTime.tryParse(j['last_sign_in_at'] as String);
  final String id, email, fullName;
  final List<Membership> memberships;

  /// False when the user also belongs to companies the caller doesn't administer: name, password,
  /// suspend and delete are then locked, and only the caller's own company access can change.
  final bool canEditAccount;
  final bool suspended, isAdmin;
  final DateTime? lastSignIn;
}

/// Admin-only operations. Companies go straight to Postgres (RLS allows app_admins);
/// users go through the `admin-users` Edge Function because they need the service role.
class AdminRepository {
  Future<List<Tenant>> companies() async {
    final rows = await sb.from('tenants').select().order('name');
    return rows.map<Tenant>((r) => Tenant.fromRow(r)).toList();
  }

  Future<void> saveCompany({String? id, required String name, String? code, String? domain, String? plan}) async {
    final row = {'name': name.trim(), 'code': _nullIfEmpty(code), 'domain': _nullIfEmpty(domain), 'plan': _nullIfEmpty(plan)};
    if (id == null) {
      await sb.from('tenants').insert(row);
    } else {
      await sb.from('tenants').update(row).eq('id', id);
    }
  }

  Future<void> deleteCompany(String id) => sb.from('tenants').delete().eq('id', id);

  Future<List<ManagedUser>> users() async {
    final data = await _call({'action': 'list'});
    return (data['users'] as List).map((u) => ManagedUser.fromJson(Map<String, dynamic>.from(u as Map))).toList();
  }

  Future<void> createUser({required String email, required String password, required String fullName, required List<Membership> memberships}) =>
      _call({'action': 'create', 'email': email.trim(), 'password': password, 'full_name': fullName.trim(), 'memberships': [for (final m in memberships) m.toJson()]});

  /// Only the fields passed are changed. [memberships] replaces the caller-managed company access.
  Future<void> updateUser(String id, {String? fullName, List<Membership>? memberships, String? password, bool? suspended}) => _call({
        'action': 'update',
        'user_id': id,
        'full_name': ?fullName?.trim(),
        if (memberships != null) 'memberships': [for (final m in memberships) m.toJson()],
        if (password != null && password.isNotEmpty) 'password': password,
        'suspended': ?suspended,
      });

  Future<void> deleteUser(String id) => _call({'action': 'delete', 'user_id': id});

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await sb.functions.invoke('admin-users', body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final d = e.details;
      throw Exception(d is Map && d['error'] != null ? d['error'] : 'Request failed (${e.status})');
    }
  }

  static String? _nullIfEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}

final adminRepo = AdminRepository();
