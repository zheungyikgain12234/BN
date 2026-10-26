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

  /// "USD 22.00" (or just the number when no currency is set); empty when the app has no price.
  String get priceLabel => price == null ? '' : [if (currency.isNotEmpty) currency, _money(price!)].join(' ');

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
      currency: (j['currency'] ?? '') as String,
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

/// What the reseller charges to register one extension for [years] (price is for the whole duration).
class DomainPrice {
  const DomainPrice({required this.tld, required this.years, required this.price, required this.currency});
  final String tld, currency;
  final int years;
  final double price;

  String get label => '$years ${years == 1 ? 'year' : 'years'} for $currency ${price.toStringAsFixed(2)}';

  factory DomainPrice.fromJson(Map<String, dynamic> j) =>
      DomainPrice(tld: j['tld'] as String, years: j['years'] as int, price: (j['price'] as num).toDouble(), currency: (j['currency'] ?? 'USD') as String);
}

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
        currency: (j['currency'] ?? 'USD') as String,
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
        currency: j['currency'] as String,
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
