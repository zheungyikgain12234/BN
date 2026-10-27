import 'models.dart';
import 'repository.dart';

class Client {
  Client.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        contactName = (j['contact_name'] ?? '') as String,
        email = (j['email'] ?? '') as String,
        phone = (j['phone'] ?? '') as String,
        notes = (j['notes'] ?? '') as String;
  final String id, name, contactName, email, phone, notes;
}

/// One purchased license (a single unit). Assigned when [clientId] is set.
class License {
  License.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        product = Product.fromJson(j['products'] as Map<String, dynamic>),
        unitPrice = (j['unit_price'] as num).toDouble(),
        currency = (j['currency'] ?? '') as String,
        purchasedAt = DateTime.parse(j['purchased_at'] as String),
        clientId = j['client_id'] as String?,
        clientName = ((j['clients'] as Map<String, dynamic>?)?['name'] ?? '') as String,
        sellPrice = (j['sell_price'] as num?)?.toDouble(),
        assignedAt = j['assigned_at'] == null ? null : DateTime.tryParse(j['assigned_at'] as String);
  final String id, currency, clientName;
  final String? clientId;
  final Product product;
  final double unitPrice;
  final double? sellPrice;
  final DateTime purchasedAt;
  final DateTime? assignedAt;

  bool get assigned => clientId != null;
  double? get profit => sellPrice == null ? null : sellPrice! - unitPrice;
}

/// One purchased domain. Assigned when [clientId] is set; [unitPrice] is what the reseller paid.
class PurchasedDomain {
  PurchasedDomain.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        domain = j['domain'] as String,
        years = j['years'] as int,
        unitPrice = (j['unit_price'] as num).toDouble(),
        currency = (j['currency'] ?? '') as String,
        status = j['status'] as String,
        note = j['note'] as String?,
        purchasedAt = DateTime.parse(j['purchased_at'] as String),
        clientId = j['client_id'] as String?,
        clientName = ((j['clients'] as Map<String, dynamic>?)?['name'] ?? '') as String,
        sellPrice = (j['sell_price'] as num?)?.toDouble();
  final String id, domain, currency, status, clientName;
  final String? clientId, note;
  final int years;
  final double unitPrice;
  final double? sellPrice;
  final DateTime purchasedAt;

  bool get assigned => clientId != null;
  bool get failed => status == 'failed';
  double? get profit => sellPrice == null ? null : sellPrice! - unitPrice;
}

/// One purchased hosting package. Assigned when [clientId] is set; [unitPrice] is what the reseller paid.
class PurchasedHosting {
  PurchasedHosting.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        planName = j['plan_name'] as String,
        domain = j['domain'] as String,
        months = j['months'] as int,
        unitPrice = (j['unit_price'] as num).toDouble(),
        currency = (j['currency'] ?? '') as String,
        status = j['status'] as String,
        note = j['note'] as String?,
        purchasedAt = DateTime.parse(j['purchased_at'] as String),
        clientId = j['client_id'] as String?,
        clientName = ((j['clients'] as Map<String, dynamic>?)?['name'] ?? '') as String,
        sellPrice = (j['sell_price'] as num?)?.toDouble();
  final String id, planName, domain, currency, status, clientName;
  final String? clientId, note;
  final int months;
  final double unitPrice;
  final double? sellPrice;
  final DateTime purchasedAt;

  bool get assigned => clientId != null;
  bool get failed => status == 'failed';
  double? get profit => sellPrice == null ? null : sellPrice! - unitPrice;
}

/// One purchased VPS. Assigned when [clientId] is set; [unitPrice] is what the reseller paid.
class PurchasedVps {
  PurchasedVps.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        planName = j['plan_name'] as String,
        serverName = j['server_name'] as String,
        osLabel = j['os_label'] as String,
        location = j['location'] as String,
        months = j['months'] as int,
        unitPrice = (j['unit_price'] as num).toDouble(),
        currency = (j['currency'] ?? '') as String,
        status = j['status'] as String,
        note = j['note'] as String?,
        purchasedAt = DateTime.parse(j['purchased_at'] as String),
        clientId = j['client_id'] as String?,
        clientName = ((j['clients'] as Map<String, dynamic>?)?['name'] ?? '') as String,
        sellPrice = (j['sell_price'] as num?)?.toDouble();
  final String id, planName, serverName, osLabel, location, currency, status, clientName;
  final String? clientId, note;
  final int months;
  final double unitPrice;
  final double? sellPrice;
  final DateTime purchasedAt;

  bool get assigned => clientId != null;
  bool get failed => status == 'failed';
  double? get profit => sellPrice == null ? null : sellPrice! - unitPrice;
}

/// A cart line's choice at checkout: assign now to [clientId] at [sellPrice] per license, or leave both null.
class CheckoutLine {
  const CheckoutLine(this.cartItemId, {this.clientId, this.sellPrice});
  final String cartItemId;
  final String? clientId;
  final double? sellPrice;

  Map<String, dynamic> toJson() => {'cart_item_id': cartItemId, 'client_id': clientId, 'sell_price': sellPrice};
}

class ResellerRepository {
  Future<List<Client>> clients() async {
    final rows = await sb.from('clients').select().order('name');
    return rows.map<Client>(Client.fromJson).toList();
  }

  Future<void> saveClient({String? id, required String tenantId, required String name, String? contactName, String? email, String? phone, String? notes}) async {
    String? n(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    final row = {'name': name.trim(), 'contact_name': n(contactName), 'email': n(email), 'phone': n(phone), 'notes': n(notes)};
    if (id == null) {
      await sb.from('clients').insert({...row, 'tenant_id': tenantId});
    } else {
      await sb.from('clients').update(row).eq('id', id);
    }
  }

  Future<void> deleteClient(String id) => sb.from('clients').delete().eq('id', id);

  Future<List<License>> licenses(String tenantId) async {
    final rows = await sb
        .from('licenses')
        .select('*, clients(name), products(*, software_categories(name, icon), tenants(name))')
        .eq('tenant_id', tenantId)
        .order('purchased_at', ascending: false);
    return rows.map<License>(License.fromJson).toList();
  }

  Future<void> assign(String licenseId, String? clientId, double? sellPrice) =>
      sb.rpc('assign_license', params: {'p_license': licenseId, 'p_client': clientId, 'p_sell_price': sellPrice});

  Future<List<PurchasedDomain>> purchasedDomains(String tenantId) async {
    final rows = await sb.from('purchased_domains').select('*, clients(name)').eq('tenant_id', tenantId).order('purchased_at', ascending: false);
    return rows.map<PurchasedDomain>(PurchasedDomain.fromJson).toList();
  }

  Future<void> assignDomain(String domainId, String? clientId, double? sellPrice) =>
      sb.rpc('assign_domain', params: {'p_domain': domainId, 'p_client': clientId, 'p_sell_price': sellPrice});

  Future<List<PurchasedHosting>> purchasedHosting(String tenantId) async {
    final rows = await sb.from('purchased_hosting').select('*, clients(name)').eq('tenant_id', tenantId).order('purchased_at', ascending: false);
    return rows.map<PurchasedHosting>(PurchasedHosting.fromJson).toList();
  }

  Future<void> assignHosting(String hostingId, String? clientId, double? sellPrice) =>
      sb.rpc('assign_hosting', params: {'p_hosting': hostingId, 'p_client': clientId, 'p_sell_price': sellPrice});

  Future<List<PurchasedVps>> purchasedVps(String tenantId) async {
    final rows = await sb.from('purchased_vps').select('*, clients(name)').eq('tenant_id', tenantId).order('purchased_at', ascending: false);
    return rows.map<PurchasedVps>(PurchasedVps.fromJson).toList();
  }

  Future<void> assignVps(String vpsId, String? clientId, double? sellPrice) =>
      sb.rpc('assign_vps', params: {'p_vps': vpsId, 'p_client': clientId, 'p_sell_price': sellPrice});

  Future<void> checkout(String tenantId, List<CheckoutLine> lines) =>
      sb.rpc('checkout', params: {'p_tenant': tenantId, 'p_lines': [for (final l in lines) l.toJson()]});
}

final resellerRepo = ResellerRepository();
