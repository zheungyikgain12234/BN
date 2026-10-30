import '../core/format.dart';

class Tenant {
  Tenant({
    required this.id,
    required this.name,
    required this.code,
    required this.domain,
    required this.plan,
    required this.seats,
    required this.role,
  });
  final String id, name, code, domain, plan, role;
  final int seats;

  /// Just an id + name, as listed on the pre-login company screen.
  Tenant.basic({required this.id, required this.name})
      : code = '',
        domain = '',
        plan = 'enterprise',
        seats = 0,
        role = 'member';

  /// Plain row from `tenants`.
  factory Tenant.fromRow(Map<String, dynamic> t, {String role = 'member'}) => Tenant(
        id: t['id'] as String,
        name: t['name'] as String,
        code: (t['code'] ?? '') as String,
        domain: (t['domain'] ?? '') as String,
        plan: (t['plan'] ?? 'enterprise') as String,
        seats: (t['seats_active'] ?? 0) as int,
        role: role,
      );

  String get initials {
    final w = name.split(' ').where((e) => e.isNotEmpty).toList();
    return w.take(2).map((e) => e[0].toUpperCase()).join();
  }

  /// Row from `tenant_members` with embedded `tenants`.
  factory Tenant.fromMember(Map<String, dynamic> m) {
    final t = m['tenants'] as Map<String, dynamic>;
    return Tenant(
      id: t['id'] as String,
      name: t['name'] as String,
      code: (t['code'] ?? '') as String,
      domain: (t['domain'] ?? '') as String,
      plan: (t['plan'] ?? 'enterprise') as String,
      seats: (t['seats_active'] ?? 0) as int,
      role: (m['role'] ?? 'member') as String,
    );
  }
}

class SoftwareCategory {
  SoftwareCategory({required this.id, required this.name, this.icon, this.sortOrder = 0});
  final String id, name;
  final String? icon;
  final int sortOrder;

  factory SoftwareCategory.fromJson(Map<String, dynamic> j) => SoftwareCategory(
        id: j['id'] as String,
        name: j['name'] as String,
        icon: j['icon'] as String?,
        sortOrder: (j['sort_order'] ?? 0) as int,
      );
}

class Product {
  Product({
    required this.id,
    required this.name,
    this.tenantId,
    this.tenantName = '',
    this.categoryId,
    this.categoryName = '',
    this.categoryIcon,
    this.description = '',
    this.about = '',
    this.version = '',
    this.sku = '',
    this.pricingModel = '',
    this.price,
    this.currency = '',
    this.imageUrl,
    this.tags = const [],
    this.createdAt,
  });
  final String id, name, tenantName, categoryName, description, about, version, sku, pricingModel, currency;
  final String? tenantId, categoryId, categoryIcon, imageUrl;
  final double? price;
  final List<String> tags;
  final DateTime? createdAt;

  /// "SGD 22.00"; empty when the app has no price.
  String get priceLabel => price == null ? '' : '$kCurrency ${_money(price!)}';

  /// "per user / monthly" style unit line under the price.
  String get priceUnit => pricingModel;

  static String _money(double v) => v.toStringAsFixed(2);

  /// Row from `products` with embedded `software_categories` and `tenants`.
  factory Product.fromJson(Map<String, dynamic> j) {
    final cat = j['software_categories'] as Map<String, dynamic>?;
    final ten = j['tenants'] as Map<String, dynamic>?;
    return Product(
      id: j['id'] as String,
      name: j['name'] as String,
      tenantId: j['tenant_id'] as String?,
      tenantName: (ten?['name'] ?? '') as String,
      categoryId: j['category_id'] as String?,
      categoryName: (cat?['name'] ?? '') as String,
      categoryIcon: cat?['icon'] as String?,
      description: (j['description'] ?? '') as String,
      about: (j['about'] ?? '') as String,
      version: (j['version'] ?? '') as String,
      sku: (j['sku'] ?? '') as String,
      pricingModel: (j['pricing_model'] ?? '') as String,
      price: (j['price'] as num?)?.toDouble(),
      currency: kCurrency,
      imageUrl: j['image_url'] as String?,
      tags: ((j['tags'] ?? const []) as List).cast<String>(),
      createdAt: j['created_at'] == null ? null : DateTime.tryParse(j['created_at'] as String),
    );
  }
}

class ProductScreenshot {
  ProductScreenshot({this.id, required this.title, required this.caption, required this.url});
  final String? id;
  final String title, caption, url;
  factory ProductScreenshot.fromJson(Map<String, dynamic> j) => ProductScreenshot(
        id: j['id'] as String?,
        title: (j['title'] ?? '') as String,
        caption: (j['caption'] ?? '') as String,
        url: j['image_url'] as String,
      );
}

class ProductComment {
  ProductComment({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.authorTitle,
    required this.body,
    required this.createdAt,
    this.attachmentName,
    this.attachmentUrl,
    this.attachmentType,
    this.avatarUrl,
  });
  final String id, userId, authorName, authorTitle, body;
  final DateTime createdAt;
  final String? attachmentName, attachmentUrl, attachmentType, avatarUrl;

  bool get hasImage => attachmentUrl != null && attachmentType == 'image';

  factory ProductComment.fromJson(Map<String, dynamic> j) {
    final p = (j['profiles'] as Map<String, dynamic>?) ?? const {};
    return ProductComment(
      id: j['id'] as String,
      userId: (j['user_id'] ?? '') as String,
      authorName: (p['full_name'] ?? '') as String,
      authorTitle: (p['job_title'] ?? '') as String,
      avatarUrl: p['avatar_url'] as String?,
      body: (j['body'] ?? '') as String,
      createdAt: DateTime.parse(j['created_at'] as String),
      attachmentName: j['attachment_name'] as String?,
      attachmentUrl: j['attachment_url'] as String?,
      attachmentType: j['attachment_type'] as String?,
    );
  }
}

class CartItem {
  CartItem({required this.id, required this.quantity, required this.product});
  final String id;
  final int quantity;
  final Product product;

  double get subtotal => (product.price ?? 0) * quantity;

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
        id: j['id'] as String,
        quantity: (j['quantity'] ?? 1) as int,
        product: Product.fromJson(j['products'] as Map<String, dynamic>),
      );
}

/// What the reseller charges per year for one extension (always SGD). [costPerYear] is what 20i charges, if known.
class DomainPrice {
  const DomainPrice({required this.tld, required this.pricePerYear, this.costPerYear});
  final String tld;
  final double pricePerYear;
  final double? costPerYear;

  /// The reseller can buy any number of years; the price is simply years x the yearly price.
  double total(int years) => pricePerYear * years;

  factory DomainPrice.fromJson(Map<String, dynamic> j) => DomainPrice(
        tld: j['tld'] as String,
        pricePerYear: (j['price_per_year'] as num).toDouble(),
        costPerYear: (j['cost_per_year'] as num?)?.toDouble(),
      );
}

/// Longest registration the domain search offers (20i allows up to 10 years).
const maxDomainYears = 10;

class DomainCartItem {
  const DomainCartItem({required this.id, required this.domain, required this.years, required this.price, required this.currency});
  final String id, domain, currency;
  final int years;
  final double price;

  factory DomainCartItem.fromJson(Map<String, dynamic> j) => DomainCartItem(
        id: j['id'] as String,
        domain: j['domain'] as String,
        years: j['years'] as int,
        price: (j['price'] as num).toDouble(),
        currency: kCurrency,
      );
}

/// A paid (or pending) domain checkout, with one line per domain.
class DomainOrder {
  const DomainOrder({required this.id, required this.status, required this.currency, required this.total, required this.createdAt, required this.items});
  final String id, status, currency;
  final double total;
  final DateTime createdAt;
  final List<DomainOrderItem> items;

  factory DomainOrder.fromJson(Map<String, dynamic> j) => DomainOrder(
        id: j['id'] as String,
        status: j['status'] as String,
        currency: kCurrency,
        total: (j['total'] as num).toDouble(),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        items: [for (final i in (j['domain_order_items'] as List? ?? const [])) DomainOrderItem.fromJson(i as Map<String, dynamic>)],
      );
}

class DomainOrderItem {
  const DomainOrderItem({required this.domain, required this.years, required this.status, this.note});
  final String domain, status;
  final int years;
  final String? note;

  factory DomainOrderItem.fromJson(Map<String, dynamic> j) =>
      DomainOrderItem(domain: j['domain'] as String, years: j['years'] as int, status: j['status'] as String, note: j['note'] as String?);
}

/// What the reseller charges for one hosting plan over one billing period (Master Data > Hosting prices).
class HostingPrice {
  const HostingPrice({required this.packageTypeId, required this.planName, required this.months, required this.price, required this.currency, this.cost = 0});
  final String packageTypeId, planName, currency;
  final int months;
  final double price;

  /// What 20i charges for the whole period (the selling [price] is this plus the profit %).
  final double cost;

  String get label => '$months ${months == 1 ? 'month' : 'months'} for $currency ${price.toStringAsFixed(2)}';

  factory HostingPrice.fromJson(Map<String, dynamic> j) => HostingPrice(
        packageTypeId: j['package_type_id'] as String,
        planName: j['plan_name'] as String,
        months: j['months'] as int,
        price: (j['price'] as num).toDouble(),
        currency: kCurrency,
        cost: (j['cost'] as num?)?.toDouble() ?? 0,
      );
}

class HostingCartItem {
  const HostingCartItem({required this.id, required this.packageTypeId, required this.planName, required this.months, required this.domain, required this.price, required this.currency});
  final String id, packageTypeId, planName, domain, currency;
  final int months;
  final double price;

  factory HostingCartItem.fromJson(Map<String, dynamic> j) => HostingCartItem(
        id: j['id'] as String,
        packageTypeId: j['package_type_id'] as String,
        planName: j['plan_name'] as String,
        months: j['months'] as int,
        domain: j['domain'] as String,
        price: (j['price'] as num).toDouble(),
        currency: kCurrency,
      );
}

/// A paid (or pending) hosting checkout, with one line per hosting package.
class HostingOrder {
  const HostingOrder({required this.id, required this.status, required this.currency, required this.total, required this.items});
  final String id, status, currency;
  final double total;
  final List<HostingOrderItem> items;

  factory HostingOrder.fromJson(Map<String, dynamic> j) => HostingOrder(
        id: j['id'] as String,
        status: j['status'] as String,
        currency: kCurrency,
        total: (j['total'] as num).toDouble(),
        items: [for (final i in (j['hosting_order_items'] as List? ?? const [])) HostingOrderItem.fromJson(i as Map<String, dynamic>)],
      );
}

class HostingOrderItem {
  const HostingOrderItem({required this.planName, required this.domain, required this.months, required this.status, this.note});
  final String planName, domain, status;
  final int months;
  final String? note;

  factory HostingOrderItem.fromJson(Map<String, dynamic> j) => HostingOrderItem(
        planName: j['plan_name'] as String,
        domain: j['domain'] as String,
        months: j['months'] as int,
        status: j['status'] as String,
        note: j['note'] as String?,
      );
}

/// Longest VPS term the shop offers, in years (same limit as domains), and the same in months.
const maxVpsYears = 10;
const maxVpsMonths = maxVpsYears * 12;

/// "1 year 6 months", "10 years", "3 months".
String termLabel(int months) {
  final y = months ~/ 12, m = months % 12;
  return [if (y > 0) '$y ${y == 1 ? 'year' : 'years'}', if (m > 0) '$m ${m == 1 ? 'month' : 'months'}'].join(' ');
}

/// What the reseller charges per month for one VPS plan (Master Data > VPS prices). The reseller admin enters the term (years
/// and months, up to [maxVpsYears] years) when adding it to the basket, like domains.
class VpsPrice {
  const VpsPrice({required this.vpsType, required this.planName, required this.pricePerMonth, required this.currency, this.costPerMonth = 0, this.cores, this.ramMb, this.diskGb});
  final String vpsType, planName, currency;
  final double pricePerMonth;

  /// What 20i charges per month (the selling [pricePerMonth] is this plus the profit %).
  final double costPerMonth;

  /// Selling price for a term of [months] months.
  double totalForMonths(int months) => (pricePerMonth * months * 100).round() / 100;

  /// 20i's cost for a term of [months] months (what the panel basket holds).
  double costForMonths(int months) => (costPerMonth * months * 100).round() / 100;

  /// Specs copied from 20i when the plan was picked in Master Data; null when unknown.
  final int? cores, ramMb, diskGb;

  /// e.g. ["1 GB memory", "1 core", "25 GB SSD"]; only the parts 20i gave us, empty when none are known.
  List<String> get specLines {
    String gb(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
    return [
      if (ramMb != null) '${gb(ramMb! / 1024)} GB memory',
      if (cores != null) '$cores ${cores == 1 ? 'core' : 'cores'}',
      if (diskGb != null) '$diskGb GB SSD',
    ];
  }

  String get specs => specLines.join(' · ');

  factory VpsPrice.fromJson(Map<String, dynamic> j) => VpsPrice(
        vpsType: j['vps_type'] as String,
        planName: j['plan_name'] as String,
        pricePerMonth: (j['price_per_month'] as num).toDouble(),
        currency: kCurrency,
        costPerMonth: (j['cost_per_month'] as num?)?.toDouble() ?? 0,
        cores: j['cpu_cores'] as int?,
        ramMb: j['ram_mb'] as int?,
        diskGb: j['disk_gb'] as int?,
      );
}

/// An operating system the reseller can choose for a VPS (Master Data > VPS operating systems).
class VpsOs {
  const VpsOs({required this.label, required this.code});
  final String label, code;

  factory VpsOs.fromJson(Map<String, dynamic> j) => VpsOs(label: j['label'] as String, code: j['code'] as String);
}

/// What the reseller charges for one VPS add-on over one billing period (Master Data > VPS add-on prices).
/// [spec] is the 20i productSpec, e.g. vps_addon-cpanelpro, vps_addon-backup or vps_addon-disk100GB.
class VpsAddonPrice {
  const VpsAddonPrice({required this.label, required this.spec, required this.pricePerMonth, required this.currency, this.costPerMonth = 0});
  final String label, spec, currency;
  final double pricePerMonth;

  /// What 20i charges per month.
  final double costPerMonth;

  /// An add-on runs for the server's whole term, so it is priced for the same number of months.
  double totalForMonths(int months) => (pricePerMonth * months * 100).round() / 100;
  double costForMonths(int months) => (costPerMonth * months * 100).round() / 100;

  bool get isCpanel => spec.startsWith('vps_addon-cpanel');
  bool get isBackup => spec == 'vps_addon-backup';
  bool get isDisk => RegExp(r'^vps_addon-disk\d+GB$').hasMatch(spec);

  /// Disk size in GB (0 when this is not a disk), to sort the disk list.
  int get diskGb => int.tryParse(RegExp(r'\d+').firstMatch(spec)?.group(0) ?? '') ?? 0;

  factory VpsAddonPrice.fromJson(Map<String, dynamic> j) => VpsAddonPrice(
        label: j['label'] as String,
        spec: j['product_spec'] as String,
        pricePerMonth: (j['price_per_month'] as num).toDouble(),
        currency: kCurrency,
        costPerMonth: (j['cost_per_month'] as num?)?.toDouble() ?? 0,
      );
}

/// One add-on picked for a VPS in the basket: the add-on and its billing period.
class VpsAddonChoice {
  const VpsAddonChoice({required this.spec, required this.label, required this.months, required this.price});
  final String spec, label;
  final int months;
  final double price;
}

class VpsCartItem {
  const VpsCartItem({required this.id, required this.vpsType, required this.planName, required this.months, required this.osLabel, required this.location, required this.serverName, required this.price, required this.currency, this.addons = const [], this.addonSpecs = const []});
  final String id, vpsType, planName, osLabel, location, serverName, currency;
  final int months;
  final double price;

  /// The add-ons with today's Master Data price (filled in by the basket); [addonSpecs] is what was saved.
  final List<VpsAddonChoice> addons;
  final List<({String spec, int months})> addonSpecs;

  /// The server plus every add-on.
  double get total => price + addons.fold<double>(0, (t, a) => t + a.price);

  factory VpsCartItem.fromJson(Map<String, dynamic> j) => VpsCartItem(
        id: j['id'] as String,
        vpsType: j['vps_type'] as String,
        planName: j['plan_name'] as String,
        months: j['months'] as int,
        osLabel: j['os_label'] as String,
        location: j['location'] as String,
        serverName: j['server_name'] as String,
        price: (j['price'] as num).toDouble(),
        currency: kCurrency,
        addonSpecs: [for (final a in (j['addons'] as List? ?? const [])) (spec: '${a['spec']}', months: (a['months'] as num).toInt())],
      );
}

/// A paid (or pending) VPS checkout, with one line per server.
class VpsOrder {
  const VpsOrder({required this.id, required this.status, required this.currency, required this.total, required this.items});
  final String id, status, currency;
  final double total;
  final List<VpsOrderItem> items;

  factory VpsOrder.fromJson(Map<String, dynamic> j) => VpsOrder(
        id: j['id'] as String,
        status: j['status'] as String,
        currency: kCurrency,
        total: (j['total'] as num).toDouble(),
        items: [for (final i in (j['vps_order_items'] as List? ?? const [])) VpsOrderItem.fromJson(i as Map<String, dynamic>)],
      );
}

class VpsOrderItem {
  const VpsOrderItem({required this.planName, required this.serverName, required this.months, required this.status, this.note});
  final String planName, serverName, status;
  final int months;
  final String? note;

  factory VpsOrderItem.fromJson(Map<String, dynamic> j) => VpsOrderItem(
        planName: j['plan_name'] as String,
        serverName: j['server_name'] as String,
        months: j['months'] as int,
        status: j['status'] as String,
        note: j['note'] as String?,
      );
}

/// What the reseller charges for one SSL certificate type over one period (Master Data > SSL prices).
class SslPrice {
  const SslPrice({required this.classCode, required this.planName, required this.months, required this.price, required this.currency, this.cost = 0});
  final String classCode, planName, currency;
  final int months;
  final double price;

  /// What 20i charges for the whole period (the selling [price] is this plus the profit %).
  final double cost;

  /// A wildcard certificate covers every subdomain, so its name is always "*.domain".
  bool get wildcard => classCode.endsWith('_wildcard');

  String get label => '${months % 12 == 0 ? '${months ~/ 12} ${months == 12 ? 'year' : 'years'}' : '$months months'} for $currency ${price.toStringAsFixed(2)}';

  factory SslPrice.fromJson(Map<String, dynamic> j) => SslPrice(
        classCode: j['class_code'] as String,
        planName: j['plan_name'] as String,
        months: j['months'] as int,
        price: (j['price'] as num).toDouble(),
        currency: kCurrency,
        cost: (j['cost'] as num?)?.toDouble() ?? 0,
      );
}

class SslCartItem {
  const SslCartItem({required this.id, required this.classCode, required this.planName, required this.months, required this.hostname, required this.price, required this.currency});
  final String id, classCode, planName, hostname, currency;
  final int months;
  final double price;

  factory SslCartItem.fromJson(Map<String, dynamic> j) => SslCartItem(
        id: j['id'] as String,
        classCode: j['class_code'] as String,
        planName: j['plan_name'] as String,
        months: j['months'] as int,
        hostname: j['hostname'] as String,
        price: (j['price'] as num).toDouble(),
        currency: kCurrency,
      );
}

/// A paid (or pending) SSL checkout, with one line per certificate.
class SslOrder {
  const SslOrder({required this.id, required this.status, required this.currency, required this.total, required this.items});
  final String id, status, currency;
  final double total;
  final List<SslOrderItem> items;

  factory SslOrder.fromJson(Map<String, dynamic> j) => SslOrder(
        id: j['id'] as String,
        status: j['status'] as String,
        currency: kCurrency,
        total: (j['total'] as num).toDouble(),
        items: [for (final i in (j['ssl_order_items'] as List? ?? const [])) SslOrderItem.fromJson(i as Map<String, dynamic>)],
      );
}

class SslOrderItem {
  const SslOrderItem({required this.planName, required this.hostname, required this.months, required this.status, this.note});
  final String planName, hostname, status;
  final int months;
  final String? note;

  factory SslOrderItem.fromJson(Map<String, dynamic> j) => SslOrderItem(
        planName: j['plan_name'] as String,
        hostname: j['hostname'] as String,
        months: j['months'] as int,
        status: j['status'] as String,
        note: j['note'] as String?,
      );
}
