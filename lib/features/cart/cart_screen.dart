import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/config.dart';
import '../../core/sortable_table.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog_repository.dart';
import '../../data/models.dart';
import '../domain/domain_search_screen.dart';
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

/// Cart page: our software cart, plus the hosting panel's own basket (domains, VPS, hosting, SSL).
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('My cart', style: T.headlineLg),
          const SizedBox(height: 8),
          const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: 'Software'), Tab(text: 'Hosting orders')]),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(children: [
              const _SoftwareCart(),
              PanelEmbedScreen(title: 'Hosting orders', url: '${Env.panelBase}/checkout', embedded: true),
            ]),
          ),
        ]),
      ),
    );
  }
}
