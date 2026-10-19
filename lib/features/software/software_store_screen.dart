import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/icon_registry.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog_repository.dart';
import '../../data/models.dart';
import 'software_detail_dialog.dart';
import 'software_widgets.dart';

enum _Sort { name, priceLow, priceHigh, newest }

extension on _Sort {
  String get label => switch (this) {
        _Sort.name => 'Name (A–Z)',
        _Sort.priceLow => 'Price: low to high',
        _Sort.priceHigh => 'Price: high to low',
        _Sort.newest => 'Newest first',
      };
}

/// App-store style catalogue: search, category chips, sort and a grid of apps.
class SoftwareStoreScreen extends StatefulWidget {
  const SoftwareStoreScreen({super.key});

  @override
  State<SoftwareStoreScreen> createState() => _SoftwareStoreScreenState();
}

class _SoftwareStoreScreenState extends State<SoftwareStoreScreen> {
  final _search = TextEditingController();
  late Future<(List<Product>, List<SoftwareCategory>)> _data = _load();
  String? _categoryId; // null = all
  _Sort _sort = _Sort.name;

  Future<(List<Product>, List<SoftwareCategory>)> _load() async {
    final results = await Future.wait([catalogRepo.products(), catalogRepo.categories()]);
    return (results[0] as List<Product>, results[1] as List<SoftwareCategory>);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Product> _apply(List<Product> all) {
    final q = _search.text.trim().toLowerCase();
    final list = all.where((p) {
      if (_categoryId != null && p.categoryId != _categoryId) return false;
      if (q.isEmpty) return true;
      return '${p.name} ${p.description} ${p.categoryName} ${p.tags.join(' ')}'.toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case _Sort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _Sort.priceLow:
        list.sort((a, b) => (a.price ?? double.infinity).compareTo(b.price ?? double.infinity));
      case _Sort.priceHigh:
        list.sort((a, b) => (b.price ?? -1).compareTo(a.price ?? -1));
      case _Sort.newest:
        list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    }
    return list;
  }

  Future<void> _addToCart(Product p) async {
    try {
      await cartRepo.add(p.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('${p.name} added to cart'),
          action: SnackBarAction(label: 'View cart', onPressed: () => context.go(Routes.cart)),
        ));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<Product>, List<SoftwareCategory>)>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) return ErrorRetry(error: snap.error!, onRetry: () => setState(() => _data = _load()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (all, categories) = snap.data!;
        final items = _apply(all);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Software', style: T.headlineLg),
                const SizedBox(height: 4),
                Text('Apps from every company', style: T.bodyMd.copyWith(color: C.secondary)),
                const SizedBox(height: 16),
                _controls(),
                const SizedBox(height: 12),
                _chips(categories),
                const SizedBox(height: 16),
                Text('${items.length} app${items.length == 1 ? '' : 's'}', style: T.labelMd.copyWith(color: C.secondary)),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(48),
                    child: Center(child: Text(all.isEmpty ? 'No software has been added yet.' : 'No apps match your search.', style: T.bodyMd.copyWith(color: C.secondary))),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 340, mainAxisExtent: 236, crossAxisSpacing: 16, mainAxisSpacing: 16),
                    itemBuilder: (_, i) => _AppCard(product: items[i], onOpen: () => showSoftwareDetail(context, items[i]), onAdd: () => _addToCart(items[i])),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _controls() => Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 360,
          height: 44,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: fieldDecoration(hint: 'Search apps, categories, tags', prefix: Icons.search).copyWith(
              contentPadding: EdgeInsets.zero,
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close, size: 18), onPressed: () => setState(_search.clear)),
            ),
          ),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<_Sort>(
            value: _sort,
            borderRadius: BorderRadius.circular(8),
            items: [for (final s in _Sort.values) DropdownMenuItem(value: s, child: Text(s.label))],
            onChanged: (v) => setState(() => _sort = v ?? _sort),
          ),
        ),
      ]);

  Widget _chips(List<SoftwareCategory> categories) {
    Widget chip(String label, IconData icon, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            avatar: Icon(icon, size: 16, color: on ? Colors.white : C.secondary),
            label: Text(label),
            selected: on,
            showCheckmark: false,
            selectedColor: C.primary,
            backgroundColor: C.surfaceLowest,
            labelStyle: T.labelMd.copyWith(color: on ? Colors.white : C.onSurface),
            onSelected: (_) => onTap(),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('All', Icons.apps, _categoryId == null, () => setState(() => _categoryId = null)),
        for (final c in categories) chip(c.name, categoryIcon(c.icon), _categoryId == c.id, () => setState(() => _categoryId = c.id)),
      ]),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.product, required this.onOpen, required this.onAdd});
  final Product product;
  final VoidCallback onOpen, onAdd;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AppIconTile(product: p, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.headlineSm),
              if (p.tenantName.isNotEmpty) Text(p.tenantName, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.labelSm.copyWith(color: C.secondary)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        if (p.categoryName.isNotEmpty) Pill(p.categoryName, icon: categoryIcon(p.categoryIcon), bg: C.primaryFixed, fg: C.onPrimaryFixed, radius: 6),
        const SizedBox(height: 8),
        Expanded(child: Text(p.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: T.bodySm.copyWith(color: C.onSurfaceVariant, height: 1.4))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: p.price == null
                ? const SizedBox.shrink()
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.priceLabel, style: T.labelLg.copyWith(color: C.primary)),
                    if (p.priceUnit.isNotEmpty) Text(p.priceUnit, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.labelSm.copyWith(color: C.secondary)),
                  ]),
          ),
          FilledButton.icon(
            onPressed: onAdd,
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            icon: const Icon(Icons.add_shopping_cart, size: 16),
            label: const Text('Add'),
          ),
        ]),
      ]),
    );
  }
}
