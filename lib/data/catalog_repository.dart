
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/image_picker.dart';
import 'models.dart';
import 'repository.dart';

const _productSelect = '*, software_categories(name, icon), tenants(name)';
const _bucket = 'catalog-media';

class CatalogRepository {
  Future<List<SoftwareCategory>> categories() async {
    final rows = await sb.from('software_categories').select().order('name');
    return rows.map<SoftwareCategory>(SoftwareCategory.fromJson).toList();
  }


  /// Every app in the catalogue, across all companies.
  Future<List<Product>> products() async {
    final rows = await sb.from('products').select(_productSelect).order('name');
    return rows.map<Product>(Product.fromJson).toList();
  }

  /// Software a user manages: a company admin only their own company's apps, a super admin everything.
  Future<List<Product>> managedProducts({String? onlyTenantId}) async {
    var q = sb.from('products').select(_productSelect);
    if (onlyTenantId != null) q = q.eq('tenant_id', onlyTenantId);
    final rows = await q.order('name');
    return rows.map<Product>(Product.fromJson).toList();
  }

  /// Creates or updates an app and returns its id.
  Future<String> saveProduct(Map<String, dynamic> row, {String? id}) async {
    if (id == null) {
      final created = await sb.from('products').insert(row).select('id').single();
      return created['id'] as String;
    }
    await sb.from('products').update(row).eq('id', id);
    return id;
  }

  Future<void> deleteProduct(String id) => sb.from('products').delete().eq('id', id);

  Future<List<ProductScreenshot>> screenshots(String productId) async {
    final rows = await sb.from('product_screenshots').select().eq('product_id', productId).order('sort_order');
    return rows.map<ProductScreenshot>(ProductScreenshot.fromJson).toList();
  }

  Future<void> addScreenshots(String productId, List<ProductScreenshot> shots, {int startAt = 0}) async {
    if (shots.isEmpty) return;
    await sb.from('product_screenshots').insert([
      for (var i = 0; i < shots.length; i++)
        {'product_id': productId, 'title': shots[i].title, 'caption': shots[i].caption, 'image_url': shots[i].url, 'sort_order': startAt + i},
    ]);
  }

  Future<void> deleteScreenshots(List<String> ids) async {
    if (ids.isEmpty) return;
    await sb.from('product_screenshots').delete().inFilter('id', ids);
  }

  Future<List<ProductComment>> comments(String productId) async {
    final rows = await sb
        .from('product_comments')
        .select('*, profiles(full_name, job_title, avatar_url)')
        .eq('product_id', productId)
        .order('created_at', ascending: false);
    return rows.map<ProductComment>(ProductComment.fromJson).toList();
  }

  Future<void> postComment(String productId, String body, {UploadedFile? attachment}) => sb.from('product_comments').insert({
        'product_id': productId,
        'body': body,
        if (attachment != null) ...{
          'attachment_name': attachment.name,
          'attachment_url': attachment.url,
          'attachment_type': 'image',
        },
      });

  Future<void> deleteComment(String id) => sb.from('product_comments').delete().eq('id', id);

  /// Lets the user pick an image, uploads it to the catalog-media bucket under their own folder
  /// (the storage policy requires it) and returns its public URL. Null when the picker is cancelled.
  Future<UploadedFile?> pickAndUploadImage(String folder) async {
    final picked = await pickImages();
    return picked.isEmpty ? null : _upload(picked.first, folder);
  }

  /// Same as [pickAndUploadImage] for several images at once.
  Future<List<UploadedFile>> pickAndUploadImages(String folder) async {
    final picked = await pickImages(multiple: true);
    return [for (final p in picked) await _upload(p, folder)];
  }

  Future<UploadedFile> _upload(PickedImage image, String folder) async {
    final safe = image.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '${sb.auth.currentUser!.id}/$folder/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await sb.storage.from(_bucket).uploadBinary(path, image.bytes, fileOptions: FileOptions(contentType: image.mimeType.isEmpty ? 'image/png' : image.mimeType));
    return UploadedFile(name: image.name, url: sb.storage.from(_bucket).getPublicUrl(path));
  }
}

class UploadedFile {
  const UploadedFile({required this.name, required this.url});
  final String name, url;
}

/// Shopping cart. [CartState] mirrors the item count for the top-bar badge.
class CartRepository {
  Future<List<CartItem>> items() async {
    final rows = await sb.from('cart_items').select('id, quantity, products($_productSelect)').order('created_at');
    return rows.map<CartItem>(CartItem.fromJson).toList();
  }

  Future<void> add(String productId) async {
    final existing = await sb.from('cart_items').select('id, quantity').eq('product_id', productId).maybeSingle();
    if (existing == null) {
      await sb.from('cart_items').insert({'product_id': productId});
    } else {
      await sb.from('cart_items').update({'quantity': (existing['quantity'] as int) + 1}).eq('id', existing['id'] as String);
    }
    await CartState.instance.refresh();
  }

  Future<void> setQuantity(String itemId, int quantity) async {
    await sb.from('cart_items').update({'quantity': quantity}).eq('id', itemId);
    await CartState.instance.refresh();
  }

  Future<void> remove(String itemId) async {
    await sb.from('cart_items').delete().eq('id', itemId);
    await CartState.instance.refresh();
  }

  Future<void> clear() async {
    await sb.from('cart_items').delete().eq('user_id', sb.auth.currentUser!.id);
    await CartState.instance.refresh();
  }
}

/// Domains in the basket (one row per user + domain; adding again replaces the duration).
class DomainCartRepository {
  Future<List<DomainPrice>> prices() async {
    final rows = await sb.from('domain_tld_prices').select().order('tld').order('years');
    return rows.map<DomainPrice>(DomainPrice.fromJson).toList();
  }

  Future<List<DomainCartItem>> items() async {
    final rows = await sb.from('domain_cart_items').select().order('created_at');
    return rows.map<DomainCartItem>(DomainCartItem.fromJson).toList();
  }

  Future<void> add(String domain, DomainPrice p) async {
    await sb.from('domain_cart_items').upsert({'domain': domain, 'years': p.years, 'price': p.price, 'currency': p.currency}, onConflict: 'user_id,domain');
    await CartState.instance.refresh();
  }

  Future<void> remove(String id) async {
    await sb.from('domain_cart_items').delete().eq('id', id);
    await CartState.instance.refresh();
  }

  Future<void> clear() async {
    await sb.from('domain_cart_items').delete().eq('user_id', sb.auth.currentUser!.id);
    await CartState.instance.refresh();
  }

  /// Saves the basket as an order and returns the Stripe payment page to send the browser to.
  Future<String> startCheckout(String returnUrl) async {
    final res = await sb.functions.invoke('domain-checkout', body: {'returnUrl': returnUrl});
    final data = res.data as Map?;
    final url = data?['url'] as String?;
    if (url == null) throw '${data?['error'] ?? 'Could not start checkout'}';
    return url;
  }

  Future<List<DomainOrder>> orders() async {
    final rows = await sb.from('domain_orders').select('*, domain_order_items(domain, years, status, note)').order('created_at', ascending: false).limit(10);
    return rows.map<DomainOrder>(DomainOrder.fromJson).toList();
  }
}

class CartState extends ChangeNotifier {
  CartState._();
  static final instance = CartState._();

  int _count = 0;
  int get count => _count;

  Future<void> refresh() async {
    try {
      final rows = await sb.from('cart_items').select('quantity');
      final domains = await sb.from('domain_cart_items').select('id').catchError((_) => <Map<String, dynamic>>[]); // table not created yet
      _count = rows.fold<int>(0, (sum, r) => sum + (r['quantity'] as int)) + domains.length;
    } catch (_) {
      _count = 0; // the badge is cosmetic; never block the page on it
    }
    notifyListeners();
  }
}

final catalogRepo = CatalogRepository();
final cartRepo = CartRepository();
final domainCartRepo = DomainCartRepository();
