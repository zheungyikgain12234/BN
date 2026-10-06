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

class Product {
  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.pricingModel,
    required this.priceLabel,
    required this.rating,
    this.imageUrl,
    this.publisher = '',
    this.sku = '',
    this.ratingCount = 0,
    this.tags = const [],
    this.version = '',
    this.about = '',
    this.billingCycle = '',
    this.minCommitment = '',
    this.cloudTargets = '',
    this.publisherCode = '',
    this.multiTenant = false,
    this.seatPrice = '',
  });
  final String id, name, category, description, pricingModel, priceLabel, publisher, sku, version;
  final String about, billingCycle, minCommitment, cloudTargets, publisherCode, seatPrice;
  final double rating;
  final int ratingCount;
  final String? imageUrl;
  final List<String> tags;
  final bool multiTenant;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        name: j['name'] as String,
        category: (j['category'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        pricingModel: (j['pricing_model'] ?? '') as String,
        priceLabel: (j['price_label'] ?? '') as String,
        rating: ((j['rating'] ?? 0) as num).toDouble(),
        ratingCount: (j['rating_count'] ?? 0) as int,
        imageUrl: j['image_url'] as String?,
        publisher: (j['publisher'] ?? '') as String,
        sku: (j['sku'] ?? '') as String,
        version: (j['version'] ?? '') as String,
        about: (j['about'] ?? '') as String,
        billingCycle: (j['billing_cycle'] ?? '') as String,
        minCommitment: (j['min_commitment'] ?? '') as String,
        cloudTargets: (j['cloud_targets'] ?? '') as String,
        publisherCode: (j['publisher_code'] ?? '') as String,
        multiTenant: (j['multi_tenant'] ?? false) as bool,
        seatPrice: (j['seat_price'] ?? '') as String,
        tags: ((j['tags'] ?? const []) as List).cast<String>(),
      );
}

class ProductScreenshot {
  ProductScreenshot({required this.title, required this.caption, required this.url});
  final String title, caption, url;
  factory ProductScreenshot.fromJson(Map<String, dynamic> j) => ProductScreenshot(
        title: (j['title'] ?? '') as String,
        caption: (j['caption'] ?? '') as String,
        url: j['image_url'] as String,
      );
}

class ProductComment {
  ProductComment({
    required this.id,
    required this.authorName,
    required this.authorTitle,
    required this.badge,
    required this.body,
    required this.createdAt,
    required this.endorsements,
    required this.replies,
    this.attachmentName,
    this.attachmentUrl,
    this.attachmentType,
    this.avatarUrl,
  });
  final String id, authorName, authorTitle, badge, body;
  final DateTime createdAt;
  final int endorsements, replies;
  final String? attachmentName, attachmentUrl, attachmentType, avatarUrl;

  factory ProductComment.fromJson(Map<String, dynamic> j) {
    final p = (j['profiles'] as Map<String, dynamic>?) ?? const {};
    return ProductComment(
      id: j['id'] as String,
      authorName: (p['full_name'] ?? 'Unknown user') as String,
      authorTitle: (p['job_title'] ?? '') as String,
      avatarUrl: p['avatar_url'] as String?,
      badge: (j['badge'] ?? '') as String,
      body: j['body'] as String,
      createdAt: DateTime.parse(j['created_at'] as String),
      endorsements: (j['endorsements'] ?? 0) as int,
      replies: (j['replies'] ?? 0) as int,
      attachmentName: j['attachment_name'] as String?,
      attachmentUrl: j['attachment_url'] as String?,
      attachmentType: j['attachment_type'] as String?,
    );
  }
}
