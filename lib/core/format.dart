/// Membership role codes stored in tenant_members.role. Super admin is separate (public.app_admins).
const roleCustomer = 'member';
const roleCompanyAdmin = 'admin';
const memberRoles = [roleCustomer, roleCompanyAdmin];

String roleLabel(String role) => switch (role) {
      roleCompanyAdmin => 'Reseller admin',
      roleCustomer => 'Reseller',
      _ => role,
    };

String formatDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

String money(double v, [String? _]) => '$kCurrency ${v.toStringAsFixed(2)}';

/// Every price in the system is in Singapore dollars.
const kCurrency = 'SGD';
