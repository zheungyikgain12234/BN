import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:web/web.dart' as web;

import '../../app_router.dart';
import '../../core/sortable_table.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog_repository.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/reseller_repository.dart';
import '../software/software_widgets.dart';

/// The user's cart: sortable, with quantity, remove and clear.
class _SoftwareCart extends StatefulWidget {
  const _SoftwareCart();

  @override
  State<_SoftwareCart> createState() => _SoftwareCartState();
}

class _SoftwareCartState extends State<_SoftwareCart> {
  List<CartItem>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await cartRepo.items();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text('All items will be removed from your cart.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear', style: TextStyle(color: C.error))),
        ],
      ),
    );
    if (ok == true) _run(cartRepo.clear);
  }

  Future<void> _checkout(List<CartItem> items) async {
    final tenant = AppState.instance.tenant;
    if (tenant == null) {
      showError(context, 'Pick a company first (Switch company) to purchase licenses.');
      return;
    }
    final clients = await resellerRepo.clients().catchError((_) => <Client>[]);
    if (!mounted) return;
    final done = await showDialog<bool>(context: context, builder: (_) => _CheckoutDialog(tenantId: tenant.id, items: items, clients: clients));
    if (done != true || !mounted) return;
    await CartState.instance.refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order complete. Licenses added to Purchased licenses.')));
    context.go(Routes.licenses);
  }

  /// One total per currency, since apps can be priced in different currencies.
  Widget _totals(List<CartItem> items) {
    final byCurrency = <String, double>{};
    for (final i in items) {
      byCurrency.update(i.product.currency, (v) => v + i.subtotal, ifAbsent: () => i.subtotal);
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.surfaceLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.outlineVariant.withValues(alpha: 0.6))),
      child: Wrap(alignment: WrapAlignment.end, spacing: 24, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Total', style: T.labelMd.copyWith(color: C.secondary)),
        for (final e in byCurrency.entries) Text('${e.key.isEmpty ? '' : '${e.key} '}${e.value.toStringAsFixed(2)}', style: T.headlineSm.copyWith(color: C.primary)),
        FilledButton.icon(onPressed: () => _checkout(items), icon: const Icon(Icons.shopping_bag_outlined, size: 18), label: const Text('Checkout')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : _items == null
                  ? const Center(child: CircularProgressIndicator())
                  : SortableTable<CartItem>(
                      rows: _items!,
                      searchHint: 'Search cart',
                      emptyLabel: 'Your cart is empty.',
                      searchText: (i) => '${i.product.name} ${i.product.categoryName}',
                      toolbar: [
                        OutlinedButton.icon(onPressed: () => context.go(Routes.software), icon: const Icon(Icons.storefront_outlined, size: 18), label: const Text('Browse software')),
                        if (_items!.isNotEmpty)
                          TextButton.icon(onPressed: _clear, icon: const Icon(Icons.remove_shopping_cart_outlined, size: 18, color: C.error), label: const Text('Clear cart', style: TextStyle(color: C.error))),
                      ],
                      footer: _items!.isEmpty ? null : _totals(_items!),
                      columns: [
                        TableCol(
                          label: 'Software',
                          sortValue: (i) => i.product.name.toLowerCase(),
                          cell: (i) => Row(mainAxisSize: MainAxisSize.min, children: [
                            AppIconTile(product: i.product, size: 40),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Text(i.product.name, style: T.labelLg, overflow: TextOverflow.ellipsis),
                              ]),
                            ),
                          ]),
                        ),
                        TableCol(label: 'Category', sortValue: (i) => i.product.categoryName, cell: (i) => Text(i.product.categoryName.isEmpty ? '—' : i.product.categoryName)),
                        TableCol(
                          label: 'Price',
                          numeric: true,
                          sortValue: (i) => i.product.price ?? 0,
                          cell: (i) => Text(i.product.price == null ? '—' : '${i.product.priceLabel}${i.product.priceUnit.isEmpty ? '' : '\n${i.product.priceUnit}'}'),
                        ),
                        TableCol(
                          label: 'Qty',
                          numeric: true,
                          sortValue: (i) => i.quantity,
                          cell: (i) => Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: 'Decrease',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove_circle_outline, size: 20),
                              onPressed: i.quantity <= 1 ? null : () => _run(() => cartRepo.setQuantity(i.id, i.quantity - 1)),
                            ),
                            Text('${i.quantity}', style: T.labelLg),
                            IconButton(
                              tooltip: 'Increase',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add_circle_outline, size: 20),
                              onPressed: () => _run(() => cartRepo.setQuantity(i.id, i.quantity + 1)),
                            ),
                          ]),
                        ),
                        TableCol(
                          label: 'Subtotal',
                          numeric: true,
                          sortValue: (i) => i.subtotal,
                          cell: (i) => Text(i.product.price == null ? '—' : '${i.product.currency.isEmpty ? '' : '${i.product.currency} '}${i.subtotal.toStringAsFixed(2)}', style: T.labelLg),
                        ),
                      ],
                      actions: (i) => [
                        IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, size: 20, color: C.error), onPressed: () => _run(() => cartRepo.remove(i.id))),
                      ],
                    ),
        ),
      ]),
    );
  }
}

/// Domains added from Domain Search (API). Registration at checkout is not wired up yet.
class _DomainCart extends StatefulWidget {
  const _DomainCart();

  @override
  State<_DomainCart> createState() => _DomainCartState();
}

class _DomainCartState extends State<_DomainCart> {
  List<DomainCartItem>? _items;
  List<DomainOrder> _orders = const [];
  Object? _error;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await domainCartRepo.items();
      // Orders are secondary: if their table isn't created yet the basket must still work.
      final orders = await domainCartRepo.orders().catchError((_) => <DomainOrder>[]);
      if (mounted) setState(() { _items = items; _orders = orders; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Runs a basket change. Removing also removes the item from the 20i panel basket (slow), so it shows the spinner;
  /// the action returns a warning text when the panel part failed.
  Future<void> _run(Future<String?> Function() action) async {
    try {
      final warn = await withLoader(context, action, message: 'Updating your basket...');
      await _load();
      if (warn != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Removed here, but not from the 20i panel basket: $warn'), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Sends the browser to Stripe's payment page; Stripe returns here afterwards.
  Future<void> _checkout() async {
    setState(() => _paying = true);
    try {
      final url = await domainCartRepo.startCheckout('${Uri.base.origin}/#${Routes.cart}');
      web.window.location.href = url;
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    final byCurrency = <String, double>{};
    for (final i in items) {
      byCurrency.update(i.currency, (v) => v + i.price, ifAbsent: () => i.price);
    }
    return ListView(children: [
      Row(children: [
        OutlinedButton.icon(onPressed: () => context.go(Routes.domainSearch), icon: const Icon(Icons.travel_explore, size: 18), label: const Text('Search domains')),
        const SizedBox(width: 8),
        if (items.isNotEmpty)
          TextButton.icon(onPressed: () => _run(domainCartRepo.clear), icon: const Icon(Icons.remove_shopping_cart_outlined, size: 18, color: C.error), label: const Text('Clear', style: TextStyle(color: C.error))),
      ]),
      const SizedBox(height: 12),
      if (items.isEmpty) AppCard(child: Text('No domains in your basket.', style: T.bodyMd)),
      for (final i in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            child: Row(children: [
              const Icon(Icons.language, color: C.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(i.domain, style: T.headlineSm)),
              Text('${i.years} ${i.years == 1 ? 'year' : 'years'}', style: T.bodyMd),
              const SizedBox(width: 16),
              Text('${i.currency} ${i.price.toStringAsFixed(2)}', style: T.labelLg),
              IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, size: 18, color: C.error), onPressed: () => _run(() => domainCartRepo.remove(i.id))),
            ]),
          ),
        ),
      if (items.isNotEmpty)
        AppCard(
          child: Wrap(alignment: WrapAlignment.end, spacing: 24, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Total', style: T.labelMd.copyWith(color: C.secondary)),
            for (final e in byCurrency.entries) Text('${e.key} ${e.value.toStringAsFixed(2)}', style: T.headlineSm.copyWith(color: C.primary)),
            if (byCurrency.length > 1)
              Text('Your basket mixes currencies; remove some to check out.', style: T.bodySm.copyWith(color: C.error))
            else
              PrimaryButton(label: _paying ? 'Opening Stripe...' : 'Pay with Stripe (test)', icon: Icons.lock_outline, expand: false, onPressed: _paying ? null : _checkout),
          ]),
        ),
      if (_orders.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(children: [
          Text('Recent orders', style: T.headlineSm),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh, size: 18), onPressed: _load),
        ]),
        for (final o in _orders)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${o.currency} ${o.total.toStringAsFixed(2)} · ${o.status}', style: T.labelLg),
                for (final i in o.items) Text('${i.domain} · ${i.years} ${i.years == 1 ? 'year' : 'years'} · ${i.note ?? i.status}', style: T.bodySm),
              ]),
            ),
          ),
      ],
    ]);
  }
}

/// Hosting packages added from Hosting Packages; paid with Stripe like the domain basket.
class _HostingCart extends StatefulWidget {
  const _HostingCart();

  @override
  State<_HostingCart> createState() => _HostingCartState();
}

class _HostingCartState extends State<_HostingCart> {
  List<HostingCartItem>? _items;
  List<HostingOrder> _orders = const [];
  Object? _error;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await hostingCartRepo.items();
      // Orders are secondary: if their table isn't created yet the basket must still work.
      final orders = await hostingCartRepo.orders().catchError((_) => <HostingOrder>[]);
      if (mounted) setState(() { _items = items; _orders = orders; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Removing also removes the package from the 20i panel basket (slow), so it shows the spinner; the action returns a warning
  /// text when the panel part failed.
  Future<void> _run(Future<String?> Function() action) async {
    try {
      final warn = await withLoader(context, action, message: 'Updating your basket...');
      await _load();
      if (warn != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Removed here, but not from the 20i panel basket: $warn'), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Sends the browser to Stripe's payment page; Stripe returns here afterwards.
  Future<void> _checkout() async {
    setState(() => _paying = true);
    try {
      final url = await hostingCartRepo.startCheckout('${Uri.base.origin}/#${Routes.cart}');
      web.window.location.href = url;
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  String _months(int m) => '$m ${m == 1 ? 'month' : 'months'}';

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    final byCurrency = <String, double>{};
    for (final i in items) {
      byCurrency.update(i.currency, (v) => v + i.price, ifAbsent: () => i.price);
    }
    return ListView(children: [
      Row(children: [
        OutlinedButton.icon(onPressed: () => context.go(Routes.orderHosting), icon: const Icon(Icons.cloud_outlined, size: 18), label: const Text('Browse hosting plans')),
        const SizedBox(width: 8),
        if (items.isNotEmpty)
          TextButton.icon(onPressed: () => _run(hostingCartRepo.clear), icon: const Icon(Icons.remove_shopping_cart_outlined, size: 18, color: C.error), label: const Text('Clear', style: TextStyle(color: C.error))),
      ]),
      const SizedBox(height: 12),
      if (items.isEmpty) AppCard(child: Text('No hosting in your basket.', style: T.bodyMd)),
      for (final i in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            child: Row(children: [
              const Icon(Icons.cloud_outlined, color: C.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text('${i.planName} · ${i.domain}', style: T.headlineSm)),
              Text(_months(i.months), style: T.bodyMd),
              const SizedBox(width: 16),
              Text('${i.currency} ${i.price.toStringAsFixed(2)}', style: T.labelLg),
              IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, size: 18, color: C.error), onPressed: () => _run(() => hostingCartRepo.remove(i.id))),
            ]),
          ),
        ),
      if (items.isNotEmpty)
        AppCard(
          child: Wrap(alignment: WrapAlignment.end, spacing: 24, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Total', style: T.labelMd.copyWith(color: C.secondary)),
            for (final e in byCurrency.entries) Text('${e.key} ${e.value.toStringAsFixed(2)}', style: T.headlineSm.copyWith(color: C.primary)),
            if (byCurrency.length > 1)
              Text('Your basket mixes currencies; remove some to check out.', style: T.bodySm.copyWith(color: C.error))
            else
              PrimaryButton(label: _paying ? 'Opening Stripe...' : 'Pay with Stripe (test)', icon: Icons.lock_outline, expand: false, onPressed: _paying ? null : _checkout),
          ]),
        ),
      if (_orders.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(children: [
          Text('Recent orders', style: T.headlineSm),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh, size: 18), onPressed: _load),
        ]),
        for (final o in _orders)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${o.currency} ${o.total.toStringAsFixed(2)} · ${o.status}', style: T.labelLg),
                for (final i in o.items) Text('${i.planName} · ${i.domain} · ${_months(i.months)} · ${i.note ?? i.status}', style: T.bodySm),
              ]),
            ),
          ),
      ],
    ]);
  }
}

/// VPS servers added from the VPS page; paid with Stripe like the domain and hosting baskets.
class _VpsCart extends StatefulWidget {
  const _VpsCart();

  @override
  State<_VpsCart> createState() => _VpsCartState();
}

class _VpsCartState extends State<_VpsCart> {
  List<VpsCartItem>? _items;
  List<VpsOrder> _orders = const [];
  Object? _error;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await vpsCartRepo.items();
      // Orders are secondary: if their table isn't created yet the basket must still work.
      final orders = await vpsCartRepo.orders().catchError((_) => <VpsOrder>[]);
      if (mounted) setState(() { _items = items; _orders = orders; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Removing also removes the server from the 20i panel basket (slow), so it shows the spinner; the action returns a warning
  /// text when the panel part failed.
  Future<void> _run(Future<String?> Function() action) async {
    try {
      final warn = await withLoader(context, action, message: 'Updating your basket...');
      await _load();
      if (warn != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Removed here, but not from the 20i panel basket: $warn'), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Sends the browser to Stripe's payment page; Stripe returns here afterwards.
  Future<void> _checkout() async {
    setState(() => _paying = true);
    try {
      final url = await vpsCartRepo.startCheckout('${Uri.base.origin}/#${Routes.cart}');
      web.window.location.href = url;
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  String _months(int m) => '$m ${m == 1 ? 'month' : 'months'}';

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    final byCurrency = <String, double>{};
    for (final i in items) {
      byCurrency.update(i.currency, (v) => v + i.total, ifAbsent: () => i.total);
    }
    return ListView(children: [
      Row(children: [
        OutlinedButton.icon(onPressed: () => context.go(Routes.orderVps), icon: const Icon(Icons.dns_outlined, size: 18), label: const Text('Browse VPS plans')),
        const SizedBox(width: 8),
        if (items.isNotEmpty)
          TextButton.icon(onPressed: () => _run(vpsCartRepo.clear), icon: const Icon(Icons.remove_shopping_cart_outlined, size: 18, color: C.error), label: const Text('Clear', style: TextStyle(color: C.error))),
      ]),
      const SizedBox(height: 12),
      if (items.isEmpty) AppCard(child: Text('No VPS in your basket.', style: T.bodyMd)),
      for (final i in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            child: Row(children: [
              const Icon(Icons.dns_outlined, color: C.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i.planName} · ${i.serverName}', style: T.headlineSm),
                  Text('${i.osLabel} · ${vpsLocationLabel(i.location)}', style: T.bodySm.copyWith(color: C.secondary)),
                  for (final a in i.addons) Text('+ ${a.label} (${_months(a.months)}, ${i.currency} ${a.price.toStringAsFixed(2)})', style: T.bodySm.copyWith(color: C.secondary)),
                ]),
              ),
              Text(_months(i.months), style: T.bodyMd),
              const SizedBox(width: 16),
              Text('${i.currency} ${i.total.toStringAsFixed(2)}', style: T.labelLg),
              IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, size: 18, color: C.error), onPressed: () => _run(() => vpsCartRepo.remove(i.id))),
            ]),
          ),
        ),
      if (items.isNotEmpty)
        AppCard(
          child: Wrap(alignment: WrapAlignment.end, spacing: 24, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Total', style: T.labelMd.copyWith(color: C.secondary)),
            for (final e in byCurrency.entries) Text('${e.key} ${e.value.toStringAsFixed(2)}', style: T.headlineSm.copyWith(color: C.primary)),
            if (byCurrency.length > 1)
              Text('Your basket mixes currencies; remove some to check out.', style: T.bodySm.copyWith(color: C.error))
            else
              PrimaryButton(label: _paying ? 'Opening Stripe...' : 'Pay with Stripe (test)', icon: Icons.lock_outline, expand: false, onPressed: _paying ? null : _checkout),
          ]),
        ),
      if (_orders.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(children: [
          Text('Recent orders', style: T.headlineSm),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh, size: 18), onPressed: _load),
        ]),
        for (final o in _orders)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${o.currency} ${o.total.toStringAsFixed(2)} · ${o.status}', style: T.labelLg),
                for (final i in o.items) Text('${i.planName} · ${i.serverName} · ${_months(i.months)} · ${i.note ?? i.status}', style: T.bodySm),
              ]),
            ),
          ),
      ],
    ]);
  }
}

/// SSL certificates added from the SSL page; paid with Stripe like the domain and hosting baskets.
class _SslCart extends StatefulWidget {
  const _SslCart();

  @override
  State<_SslCart> createState() => _SslCartState();
}

class _SslCartState extends State<_SslCart> {
  List<SslCartItem>? _items;
  List<SslOrder> _orders = const [];
  Object? _error;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await sslCartRepo.items();
      // Orders are secondary: if their table isn't created yet the basket must still work.
      final orders = await sslCartRepo.orders().catchError((_) => <SslOrder>[]);
      if (mounted) setState(() { _items = items; _orders = orders; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Removing also removes the certificate from the 20i panel basket (slow), so it shows the spinner; the action returns a warning
  /// text when the panel part failed.
  Future<void> _run(Future<String?> Function() action) async {
    try {
      final warn = await withLoader(context, action, message: 'Updating your basket...');
      await _load();
      if (warn != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Removed here, but not from the 20i panel basket: $warn'), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Sends the browser to Stripe's payment page; Stripe returns here afterwards.
  Future<void> _checkout() async {
    setState(() => _paying = true);
    try {
      final url = await sslCartRepo.startCheckout('${Uri.base.origin}/#${Routes.cart}');
      web.window.location.href = url;
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  String _months(int m) => '$m ${m == 1 ? 'month' : 'months'}';

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    final byCurrency = <String, double>{};
    for (final i in items) {
      byCurrency.update(i.currency, (v) => v + i.price, ifAbsent: () => i.price);
    }
    return ListView(children: [
      Row(children: [
        OutlinedButton.icon(onPressed: () => context.go(Routes.orderSsl), icon: const Icon(Icons.lock_outline, size: 18), label: const Text('Browse SSL certificates')),
        const SizedBox(width: 8),
        if (items.isNotEmpty)
          TextButton.icon(onPressed: () => _run(sslCartRepo.clear), icon: const Icon(Icons.remove_shopping_cart_outlined, size: 18, color: C.error), label: const Text('Clear', style: TextStyle(color: C.error))),
      ]),
      const SizedBox(height: 12),
      if (items.isEmpty) AppCard(child: Text('No SSL certificates in your basket.', style: T.bodyMd)),
      for (final i in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            child: Row(children: [
              const Icon(Icons.lock_outline, color: C.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text('${i.planName} · ${i.hostname}', style: T.headlineSm)),
              Text(_months(i.months), style: T.bodyMd),
              const SizedBox(width: 16),
              Text('${i.currency} ${i.price.toStringAsFixed(2)}', style: T.labelLg),
              IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, size: 18, color: C.error), onPressed: () => _run(() => sslCartRepo.remove(i.id))),
            ]),
          ),
        ),
      if (items.isNotEmpty)
        AppCard(
          child: Wrap(alignment: WrapAlignment.end, spacing: 24, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Total', style: T.labelMd.copyWith(color: C.secondary)),
            for (final e in byCurrency.entries) Text('${e.key} ${e.value.toStringAsFixed(2)}', style: T.headlineSm.copyWith(color: C.primary)),
            if (byCurrency.length > 1)
              Text('Your basket mixes currencies; remove some to check out.', style: T.bodySm.copyWith(color: C.error))
            else
              PrimaryButton(label: _paying ? 'Opening Stripe...' : 'Pay with Stripe (test)', icon: Icons.lock_outline, expand: false, onPressed: _paying ? null : _checkout),
          ]),
        ),
      if (_orders.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(children: [
          Text('Recent orders', style: T.headlineSm),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh, size: 18), onPressed: _load),
        ]),
        for (final o in _orders)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${o.currency} ${o.total.toStringAsFixed(2)} · ${o.status}', style: T.labelLg),
                for (final i in o.items) Text('${i.planName} · ${i.hostname} · ${_months(i.months)} · ${i.note ?? i.status}', style: T.bodySm),
              ]),
            ),
          ),
      ],
    ]);
  }
}


/// Cart page: our software cart, plus the hosting panel's own basket (domains, VPS, hosting, SSL).
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('My cart', style: T.headlineLg),
          const SizedBox(height: 8),
          const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: 'Software'), Tab(text: 'Domains'), Tab(text: 'Hosting Packages'), Tab(text: 'VPS'), Tab(text: 'SSL')]),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(children: [
              const _SoftwareCart(),
              const _DomainCart(),
              const _HostingCart(),
              const _VpsCart(),
              const _SslCart(),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Checkout (no payment gateway yet): optionally assign each line to a client now at the reseller's own price,
/// or leave it for later on the Purchased licenses page.
class _CheckoutDialog extends StatefulWidget {
  const _CheckoutDialog({required this.tenantId, required this.items, required this.clients});
  final String tenantId;
  final List<CartItem> items;
  final List<Client> clients;

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  // one entry per license unit: a line with quantity 3 gets three independent rows
  late final List<(CartItem, int)> _units = [for (final i in widget.items) for (var n = 1; n <= i.quantity; n++) (i, n)];
  late final List<String?> _client = List.filled(_units.length, null);
  late final List<TextEditingController> _price = [for (final u in _units) TextEditingController(text: (u.$1.product.price ?? 0).toStringAsFixed(2))];
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _price) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _confirm() async {
    final lines = <CheckoutLine>[];
    for (var k = 0; k < _units.length; k++) {
      final client = _client[k];
      final price = double.tryParse(_price[k].text.trim());
      if (client != null && price == null) {
        showError(context, 'Enter a selling price for ${_units[k].$1.product.name} #${_units[k].$2}.');
        return;
      }
      lines.add(CheckoutLine(_units[k].$1.id, clientId: client, sellPrice: client == null ? null : price));
    }
    setState(() => _saving = true);
    try {
      await resellerRepo.checkout(widget.tenantId, lines);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Checkout'),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Each license is assigned separately. Pick a client and your selling price, or leave "Assign later" and do it from '
              'Purchased licenses. Anything above your cost is your profit.', style: T.bodySm.copyWith(color: C.secondary)),
          const SizedBox(height: 12),
          for (var k = 0; k < _units.length; k++) ...[
            Text(
              '${_units[k].$1.product.name}${_units[k].$1.quantity > 1 ? '  #${_units[k].$2} of ${_units[k].$1.quantity}' : ''}   (cost ${money(_units[k].$1.product.price ?? 0, _units[k].$1.product.currency)})',
              style: T.labelLg,
            ),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String?>(
                  initialValue: _client[k],
                  isExpanded: true,
                  decoration: fieldDecoration(),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Assign later')),
                    for (final c in widget.clients) DropdownMenuItem<String?>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _client[k] = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _price[k],
                  enabled: _client[k] != null,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: fieldDecoration(hint: 'Selling price'),
                ),
              ),
            ]),
            const SizedBox(height: 14),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _confirm, child: Text(_saving ? 'Placing order...' : 'Place order')),
      ],
    );
  }
}
