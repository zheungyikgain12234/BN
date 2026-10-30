
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/format.dart';
import '../core/image_picker.dart';
import 'models.dart';
import 'repository.dart';
import 'stackcp_sso.dart';

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
    final rows = await sb.from('domain_prices').select().order('tld');
    return rows.map<DomainPrice>(DomainPrice.fromJson).toList();
  }

  Future<List<DomainCartItem>> items() async {
    final rows = await sb.from('domain_cart_items').select().order('created_at');
    final items = rows.map<DomainCartItem>(DomainCartItem.fromJson).toList();
    // Show today's Master Data price, the same one domain-checkout charges (the saved price may be stale).
    final prices = await this.prices();
    return [
      for (final i in items)
        () {
          final tld = i.domain.toLowerCase().split('.').skip(1).join('.');
          final p = prices.where((x) => x.tld == tld).firstOrNull;
          return p == null ? i : DomainCartItem(id: i.id, domain: i.domain, years: i.years, price: p.total(i.years), currency: kCurrency);
        }(),
    ];
  }

  Future<void> add(String domain, DomainPrice p, int years) async {
    await sb.from('domain_cart_items').upsert({'domain': domain, 'years': years, 'price': p.total(years), 'currency': kCurrency}, onConflict: 'user_id,domain');
    await CartState.instance.refresh();
  }

  /// The domain extensions the 20i shop sells, with 20i's yearly cost, plus who was logged in (for the debug line).
  /// Read through the same panel login Add to Basket uses (stackcp-sso, as the signed-in user), because the public 20i API
  /// has no price list.
  Future<({String appUser, String panelUser, List<({String tld, double cost})> tlds})> panelDomains() async {
    final res = await sb.functions.invoke('stackcp-sso', body: {'catalogue': true});
    final data = res.data as Map?;
    if (data?['catalogueError'] != null) throw '${data!['catalogueError']}';
    if (data?['sso'] != true) throw '${data?['reason'] ?? 'Panel login failed'}';
    final c = (data!['catalogue'] as Map?) ?? const {};
    return (
      appUser: sb.auth.currentUser?.email ?? '?',
      panelUser: '${data['panelUser']}',
      tlds: [for (final d in (c['domains'] as List? ?? const [])) (tld: '${d['tld']}', cost: (d['cost'] as num).toDouble())],
    );
  }

  Future<List<({String tld, double cost})>> tldsFrom20i() async => (await panelDomains()).tlds;

  /// The panel-basket ids of the given cart rows (null = every row of this user). Best effort: a missing id is skipped.
  Future<List<String>> _panelIds({String? id}) async {
    final q = sb.from('domain_cart_items').select('panel_item_id');
    final rows = await (id == null ? q.eq('user_id', sb.auth.currentUser!.id) : q.eq('id', id));
    return [for (final r in rows) if (r['panel_item_id'] != null) '${r['panel_item_id']}'];
  }

  /// The cart row id of a domain already in the basket (null if it isn't there).
  Future<String?> idOf(String domain) async =>
      (await sb.from('domain_cart_items').select('id').eq('domain', domain).eq('user_id', sb.auth.currentUser!.id).maybeSingle())?['id'] as String?;

  /// Saves the 20i panel basket id of a domain that was just mirrored there.
  Future<void> setPanelId(String domain, String panelId) =>
      sb.from('domain_cart_items').update({'panel_item_id': panelId}).eq('domain', domain).eq('user_id', sb.auth.currentUser!.id);

  /// Removes from our basket and, so the two stay the same, from the 20i panel basket. Returns a warning if the panel part failed.
  Future<String?> remove(String id) async {
    final why = await removeFromPanelBasket(await _panelIds(id: id));
    await sb.from('domain_cart_items').delete().eq('id', id);
    await CartState.instance.refresh();
    return why;
  }

  Future<String?> clear() async {
    final why = await removeFromPanelBasket(await _panelIds());
    await sb.from('domain_cart_items').delete().eq('user_id', sb.auth.currentUser!.id);
    await CartState.instance.refresh();
    return why;
  }

  /// Saves the basket as an order and returns the Stripe payment page to send the browser to.
  Future<String> startCheckout(String returnUrl) async {
    final tenant = AppState.instance.tenant;
    if (tenant == null) throw 'Select a company first';
    final res = await sb.functions.invoke('domain-checkout', body: {'returnUrl': returnUrl, 'tenantId': tenant.id});
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

/// Hosting packages in the basket (one row per user + domain). Prices are re-read from Master Data, like domains.
class HostingCartRepository {
  /// Selling prices (20i cost + profit %), from the hosting_prices view.
  Future<List<HostingPrice>> prices() async {
    final rows = await sb.from('hosting_prices').select().order('plan_name').order('months');
    return rows.map<HostingPrice>(HostingPrice.fromJson).toList();
  }

  Future<List<HostingCartItem>> items() async {
    final rows = await sb.from('hosting_cart_items').select().order('created_at');
    final items = rows.map<HostingCartItem>(HostingCartItem.fromJson).toList();
    // Show today's Master Data price, the same one hosting-checkout charges (the saved price may be stale).
    final prices = await this.prices();
    return [
      for (final i in items)
        () {
          final p = prices.where((x) => x.packageTypeId == i.packageTypeId && x.months == i.months).firstOrNull;
          return p == null
              ? i
              : HostingCartItem(id: i.id, packageTypeId: i.packageTypeId, planName: p.planName, months: i.months, domain: i.domain, price: p.price, currency: p.currency);
        }(),
    ];
  }

  Future<void> add(String domain, HostingPrice p) async {
    await sb.from('hosting_cart_items').upsert({
      'domain': domain,
      'package_type_id': p.packageTypeId,
      'plan_name': p.planName,
      'months': p.months,
      'price': p.price,
      'currency': p.currency,
    }, onConflict: 'user_id,domain');
    await CartState.instance.refresh();
  }

  /// The panel-basket ids of the given cart rows (null = every row of this user). Best effort: a missing id is skipped.
  Future<List<String>> _panelIds({String? id}) async {
    final q = sb.from('hosting_cart_items').select('panel_item_id');
    final rows = await (id == null ? q.eq('user_id', sb.auth.currentUser!.id) : q.eq('id', id));
    return [for (final r in rows) if (r['panel_item_id'] != null) '${r['panel_item_id']}'];
  }

  /// The cart row id of a domain already in the basket (null if it isn't there).
  Future<String?> idOf(String domain) async =>
      (await sb.from('hosting_cart_items').select('id').eq('domain', domain).eq('user_id', sb.auth.currentUser!.id).maybeSingle())?['id'] as String?;

  /// Saves the 20i panel basket id of a package that was just mirrored there.
  Future<void> setPanelId(String domain, String panelId) =>
      sb.from('hosting_cart_items').update({'panel_item_id': panelId}).eq('domain', domain).eq('user_id', sb.auth.currentUser!.id);

  /// Removes from our basket and, so the two stay the same, from the 20i panel basket. Returns a warning if the panel part failed.
  Future<String?> remove(String id) async {
    final why = await removeFromPanelBasket(await _panelIds(id: id));
    await sb.from('hosting_cart_items').delete().eq('id', id);
    await CartState.instance.refresh();
    return why;
  }

  Future<String?> clear() async {
    final why = await removeFromPanelBasket(await _panelIds());
    await sb.from('hosting_cart_items').delete().eq('user_id', sb.auth.currentUser!.id);
    await CartState.instance.refresh();
    return why;
  }

  /// Saves the basket as an order and returns the Stripe payment page to send the browser to.
  Future<String> startCheckout(String returnUrl) async {
    final tenant = AppState.instance.tenant;
    if (tenant == null) throw 'Select a company first';
    final res = await sb.functions.invoke('hosting-checkout', body: {'returnUrl': returnUrl, 'tenantId': tenant.id});
    final data = res.data as Map?;
    final url = data?['url'] as String?;
    if (url == null) throw '${data?['error'] ?? 'Could not start checkout'}';
    return url;
  }

  Future<List<HostingOrder>> orders() async {
    final rows = await sb.from('hosting_orders').select('*, hosting_order_items(plan_name, domain, months, status, note)').order('created_at', ascending: false).limit(10);
    return rows.map<HostingOrder>(HostingOrder.fromJson).toList();
  }

  /// The panel shop's hosting packages with 20i's cost per period, read through the stackcp-sso login (for the Master Data picker).
  /// [typeId] is the part of the shop code after the colon (e.g. 307997-1-sin), the `type` 20i's addStackUserPackageAllowance takes.
  Future<List<({String code, String typeId, String label, int months, double price})>> panelHosting() async {
    final res = await sb.functions.invoke('stackcp-sso', body: {'catalogue': true});
    final data = res.data as Map?;
    if (data?['catalogueError'] != null) throw '${data!['catalogueError']}';
    if (data?['sso'] != true) throw '${data?['reason'] ?? 'Panel login failed'}';
    final c = (data!['catalogue'] as Map?) ?? const {};
    final list = [
      for (final p in (c['hostingPlans'] as List? ?? const []))
        (code: '${p['code']}', typeId: '${p['typeId']}', label: '${p['label']}', months: (p['months'] as num?)?.toInt() ?? 12, price: (p['price'] as num?)?.toDouble() ?? 0),
    ];
    if (list.isEmpty) throw 'No hosting packages (stack_user_package_allowance) were found in the 20i shop. Product kinds seen: ${((c['catalogueCodes'] as Map?) ?? const {}).keys.join(', ')}';
    return list;
  }

  /// Plans the reseller can sell, straight from 20i (for the Master Data picker).
  Future<List<({String id, String name})>> plansFrom20i() async {
    final res = await sb.functions.invoke('hosting-plans');
    final data = res.data as Map?;
    if (data?['error'] != null) throw '${data!['error']}';
    return [for (final p in (data?['plans'] as List? ?? const [])) (id: '${p['id']}', name: '${p['name']}')];
  }
}

/// Customer-facing names of the data centres, by 20i code (Master Data > VPS locations). Filled whenever the list is read.
final Map<String, String> vpsLocationNames = {};
String vpsLocationLabel(String code) => vpsLocationNames[code] ?? code;

/// VPS servers in the basket (one row per user + server name). Prices are re-read from Master Data, like hosting.
class VpsCartRepository {
  /// Selling prices (20i cost + profit %), from the vps_prices view.
  Future<List<VpsPrice>> prices() async {
    final rows = await sb.from('vps_prices').select().order('plan_name').order('months');
    return rows.map<VpsPrice>(VpsPrice.fromJson).toList();
  }

  /// The panel shop's VPS plans and operating systems, read through the stackcp-sso login (for the Master Data pickers).
  /// The plan price is the shop's own price: a hint only, the reseller price is set in Master Data.
  Future<({List<({String code, String label, int months, double price, int? cores, int? ramMb, int? diskGb})> plans, List<({String code, String label, bool paid})> os})> panelCatalogue() async {
    final res = await sb.functions.invoke('stackcp-sso', body: {'catalogue': true});
    final data = res.data as Map?;
    if (data?['catalogueError'] != null) throw '${data!['catalogueError']}';
    if (data?['sso'] != true) throw '${data?['reason'] ?? 'Panel login failed'}';
    final c = (data!['catalogue'] as Map?) ?? const {};
    return (
      plans: [
        for (final p in (c['vpsPlans'] as List? ?? const []))
          (
            code: '${p['code']}',
            label: '${p['label']}',
            months: (p['months'] as num?)?.toInt() ?? 1,
            price: (p['price'] as num?)?.toDouble() ?? 0,
            cores: (p['cores'] as num?)?.toInt(),
            ramMb: (p['ramMb'] as num?)?.toInt(),
            diskGb: (p['diskGb'] as num?)?.toInt(),
          ),
      ],
      os: [
        for (final o in (c['vpsOs'] as List? ?? const [])) (code: '${o['code']}', label: '${o['label']}', paid: o['paid'] == true),
      ],
    );
  }

  /// cPanel, backup and disk add-ons the reseller sells (Master Data > VPS add-on prices).
  Future<List<VpsAddonPrice>> addonPrices() async {
    final rows = await sb.from('vps_addons_priced').select().order('label').order('months');
    return rows.map<VpsAddonPrice>(VpsAddonPrice.fromJson).toList();
  }

  /// The panel shop's VPS add-ons (cPanel, backup, disks), for the Master Data picker. Price is a hint only.
  Future<List<({String spec, String label, int months, double price})>> panelAddons() async {
    final res = await sb.functions.invoke('stackcp-sso', body: {'catalogue': true});
    final data = res.data as Map?;
    if (data?['catalogueError'] != null) throw '${data!['catalogueError']}';
    if (data?['sso'] != true) throw '${data?['reason'] ?? 'Panel login failed'}';
    final c = (data!['catalogue'] as Map?) ?? const {};
    return [
      for (final p in (c['vpsAddons'] as List? ?? const []))
        (spec: '${p['spec']}', label: '${p['label']}', months: (p['months'] as num?)?.toInt() ?? 1, price: (p['price'] as num?)?.toDouble() ?? 0),
    ];
  }

  /// The data centres 20i's panel offers (read from its order page by stackcp-sso), for the Master Data picker.
  Future<List<({String code, String label})>> panelLocations() async {
    final res = await sb.functions.invoke('stackcp-sso', body: {'catalogue': true});
    final data = res.data as Map?;
    if (data?['catalogueError'] != null) throw '${data!['catalogueError']}';
    if (data?['sso'] != true) throw '${data?['reason'] ?? 'Panel login failed'}';
    final c = (data!['catalogue'] as Map?) ?? const {};
    return [for (final l in (c['vpsLocations'] as List? ?? const [])) (code: '${l['code']}', label: '${l['label']}')];
  }

  /// Data centres the reseller offers (Master Data > VPS locations).
  Future<List<({String code, String label})>> locations() async {
    final rows = await sb.from('vps_locations').select().order('label');
    final list = [for (final r in rows) (code: '${r['code']}', label: '${r['label']}')];
    vpsLocationNames
      ..clear()
      ..addEntries(list.map((l) => MapEntry(l.code, l.label)));
    return list;
  }

  Future<List<VpsOs>> osOptions() async {
    final rows = await sb.from('vps_os_options').select().order('label');
    return rows.map<VpsOs>(VpsOs.fromJson).toList();
  }

  Future<List<VpsCartItem>> items() async {
    final rows = await sb.from('vps_cart_items').select().order('created_at');
    final items = rows.map<VpsCartItem>(VpsCartItem.fromJson).toList();
    await locations().catchError((_) => <({String code, String label})>[]); // only for the names shown in the basket
    // Show today's Master Data price, the same one vps-checkout charges (the saved price may be stale).
    final prices = await this.prices();
    final addonPrices = await this.addonPrices().catchError((_) => <VpsAddonPrice>[]); // table not created yet
    return [
      for (final i in items)
        () {
          final p = prices.where((x) => x.vpsType == i.vpsType && x.months == i.months).firstOrNull;
          final addons = [
            for (final a in i.addonSpecs)
              () {
                final ap = addonPrices.where((x) => x.spec == a.spec && x.months == a.months).firstOrNull;
                return ap == null ? null : VpsAddonChoice(spec: ap.spec, label: ap.label, months: ap.months, price: ap.price);
              }(),
          ].whereType<VpsAddonChoice>().toList();
          return VpsCartItem(
            id: i.id, vpsType: i.vpsType, planName: p?.planName ?? i.planName, months: i.months, osLabel: i.osLabel, location: i.location,
            serverName: i.serverName, price: p?.price ?? i.price, currency: p?.currency ?? i.currency, addons: addons, addonSpecs: i.addonSpecs,
          );
        }(),
    ];
  }

  Future<void> add({required String serverName, required VpsPrice plan, required VpsOs os, required String location, List<VpsAddonPrice> addons = const []}) async {
    await sb.from('vps_cart_items').upsert({
      'server_name': serverName,
      'vps_type': plan.vpsType,
      'plan_name': plan.planName,
      'months': plan.months,
      'os_code': os.code,
      'os_label': os.label,
      'location': location,
      'addons': [for (final a in addons) {'spec': a.spec, 'months': a.months}],
      'price': plan.price,
      'currency': plan.currency,
    }, onConflict: 'user_id,server_name');
    await CartState.instance.refresh();
  }

  /// The panel-basket ids of the given cart rows (null = every row of this user). Best effort: a missing id is skipped.
  Future<List<String>> _panelIds({String? id}) async {
    final q = sb.from('vps_cart_items').select('panel_item_id');
    final rows = await (id == null ? q.eq('user_id', sb.auth.currentUser!.id) : q.eq('id', id));
    return [for (final r in rows) if (r['panel_item_id'] != null) '${r['panel_item_id']}'];
  }

  /// The cart row id of a server already in the basket (null if it isn't there).
  Future<String?> idOf(String serverName) async =>
      (await sb.from('vps_cart_items').select('id').eq('server_name', serverName).eq('user_id', sb.auth.currentUser!.id).maybeSingle())?['id'] as String?;

  /// Saves the 20i panel basket id of a server that was just mirrored there.
  Future<void> setPanelId(String serverName, String panelId) =>
      sb.from('vps_cart_items').update({'panel_item_id': panelId}).eq('server_name', serverName).eq('user_id', sb.auth.currentUser!.id);

  /// Removes from our basket and, so the two stay the same, from the 20i panel basket. Returns a warning if the panel part failed.
  Future<String?> remove(String id) async {
    final why = await removeFromPanelBasket(await _panelIds(id: id));
    await sb.from('vps_cart_items').delete().eq('id', id);
    await CartState.instance.refresh();
    return why;
  }

  Future<String?> clear() async {
    final why = await removeFromPanelBasket(await _panelIds());
    await sb.from('vps_cart_items').delete().eq('user_id', sb.auth.currentUser!.id);
    await CartState.instance.refresh();
    return why;
  }

  /// Saves the basket as an order and returns the Stripe payment page to send the browser to.
  Future<String> startCheckout(String returnUrl) async {
    final tenant = AppState.instance.tenant;
    if (tenant == null) throw 'Select a company first';
    final res = await sb.functions.invoke('vps-checkout', body: {'returnUrl': returnUrl, 'tenantId': tenant.id});
    final data = res.data as Map?;
    final url = data?['url'] as String?;
    if (url == null) throw '${data?['error'] ?? 'Could not start checkout'}';
    return url;
  }

  Future<List<VpsOrder>> orders() async {
    final rows = await sb.from('vps_orders').select('*, vps_order_items(plan_name, server_name, months, status, note)').order('created_at', ascending: false).limit(10);
    return rows.map<VpsOrder>(VpsOrder.fromJson).toList();
  }
}

/// SSL certificates in the basket (one row per user + hostname + certificate type). Prices are re-read from Master Data.
class SslCartRepository {
  /// Selling prices (20i cost + profit %), from the ssl_prices view.
  Future<List<SslPrice>> prices() async {
    final rows = await sb.from('ssl_prices').select().order('plan_name').order('months');
    return rows.map<SslPrice>(SslPrice.fromJson).toList();
  }

  /// The panel shop's SSL certificates (code = 20i class-code), read through the stackcp-sso login for the Master Data picker.
  /// The price is 20i's cost for the whole period; the selling price is that plus the profit % set in Master Data.
  Future<List<({String code, String label, int months, double price})>> panelCatalogue() async {
    final res = await sb.functions.invoke('stackcp-sso', body: {'catalogue': true});
    final data = res.data as Map?;
    if (data?['catalogueError'] != null) throw '${data!['catalogueError']}';
    if (data?['sso'] != true) throw '${data?['reason'] ?? 'Panel login failed'}';
    final c = (data!['catalogue'] as Map?) ?? const {};
    return [
      for (final p in (c['sslPlans'] as List? ?? const []))
        (code: '${p['code']}', label: '${p['label']}', months: (p['months'] as num?)?.toInt() ?? 12, price: (p['price'] as num?)?.toDouble() ?? 0),
    ];
  }

  Future<List<SslCartItem>> items() async {
    final rows = await sb.from('ssl_cart_items').select().order('created_at');
    final items = rows.map<SslCartItem>(SslCartItem.fromJson).toList();
    // Show today's Master Data price, the same one ssl-checkout charges (the saved price may be stale).
    final prices = await this.prices();
    return [
      for (final i in items)
        () {
          final p = prices.where((x) => x.classCode == i.classCode && x.months == i.months).firstOrNull;
          return p == null
              ? i
              : SslCartItem(id: i.id, classCode: i.classCode, planName: p.planName, months: i.months, hostname: i.hostname, price: p.price, currency: p.currency);
        }(),
    ];
  }

  /// [contact] is the certificate contact block (type, name, country, phone, address, city, state, zip...).
  Future<void> add({required String hostname, required SslPrice plan, required String verification, required Map<String, String> contact}) async {
    await sb.from('ssl_cart_items').upsert({
      'hostname': hostname,
      'class_code': plan.classCode,
      'plan_name': plan.planName,
      'months': plan.months,
      'verification': verification,
      'contact': contact,
      'price': plan.price,
      'currency': plan.currency,
    }, onConflict: 'user_id,hostname,class_code');
    await CartState.instance.refresh();
  }

  /// The panel-basket ids of the given cart rows (null = every row of this user). Best effort: a missing id is skipped.
  Future<List<String>> _panelIds({String? id}) async {
    final q = sb.from('ssl_cart_items').select('panel_item_id');
    final rows = await (id == null ? q.eq('user_id', sb.auth.currentUser!.id) : q.eq('id', id));
    return [for (final r in rows) if (r['panel_item_id'] != null) '${r['panel_item_id']}'];
  }

  /// The cart row id of a certificate already in the basket (null if it isn't there).
  Future<String?> idOf(String hostname, String classCode) async =>
      (await sb.from('ssl_cart_items').select('id').eq('hostname', hostname).eq('class_code', classCode).eq('user_id', sb.auth.currentUser!.id).maybeSingle())?['id'] as String?;

  /// Saves the 20i panel basket id of a certificate that was just mirrored there.
  Future<void> setPanelId(String hostname, String classCode, String panelId) =>
      sb.from('ssl_cart_items').update({'panel_item_id': panelId}).eq('hostname', hostname).eq('class_code', classCode).eq('user_id', sb.auth.currentUser!.id);

  /// Removes from our basket and, so the two stay the same, from the 20i panel basket. Returns a warning if the panel part failed.
  Future<String?> remove(String id) async {
    final why = await removeFromPanelBasket(await _panelIds(id: id));
    await sb.from('ssl_cart_items').delete().eq('id', id);
    await CartState.instance.refresh();
    return why;
  }

  Future<String?> clear() async {
    final why = await removeFromPanelBasket(await _panelIds());
    await sb.from('ssl_cart_items').delete().eq('user_id', sb.auth.currentUser!.id);
    await CartState.instance.refresh();
    return why;
  }

  /// Saves the basket as an order and returns the Stripe payment page to send the browser to.
  Future<String> startCheckout(String returnUrl) async {
    final tenant = AppState.instance.tenant;
    if (tenant == null) throw 'Select a company first';
    final res = await sb.functions.invoke('ssl-checkout', body: {'returnUrl': returnUrl, 'tenantId': tenant.id});
    final data = res.data as Map?;
    final url = data?['url'] as String?;
    if (url == null) throw '${data?['error'] ?? 'Could not start checkout'}';
    return url;
  }

  Future<List<SslOrder>> orders() async {
    final rows = await sb.from('ssl_orders').select('*, ssl_order_items(plan_name, hostname, months, status, note)').order('created_at', ascending: false).limit(10);
    return rows.map<SslOrder>(SslOrder.fromJson).toList();
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
      final hosting = await sb.from('hosting_cart_items').select('id').catchError((_) => <Map<String, dynamic>>[]); // table not created yet
      final vps = await sb.from('vps_cart_items').select('id').catchError((_) => <Map<String, dynamic>>[]); // table not created yet
      final ssl = await sb.from('ssl_cart_items').select('id').catchError((_) => <Map<String, dynamic>>[]); // table not created yet
      _count = rows.fold<int>(0, (sum, r) => sum + (r['quantity'] as int)) + domains.length + hosting.length + vps.length + ssl.length;
    } catch (_) {
      _count = 0; // the badge is cosmetic; never block the page on it
    }
    notifyListeners();
  }
}

final catalogRepo = CatalogRepository();
final cartRepo = CartRepository();
final domainCartRepo = DomainCartRepository();
final hostingCartRepo = HostingCartRepository();
final vpsCartRepo = VpsCartRepository();
final sslCartRepo = SslCartRepository();
