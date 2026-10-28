import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog_repository.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/stackcp_sso.dart';

class DomainResult {
  DomainResult(this.domain, this.available);
  final String domain;
  final bool available;

  /// Extension without the dot: "com", "co.uk".
  String get tld => domain.substring(domain.indexOf('.') + 1);
}

/// Domain search with a native UI; availability comes from the `domain-search` Edge Function (20i API).
class DomainSearchApiScreen extends StatefulWidget {
  const DomainSearchApiScreen({super.key});

  @override
  State<DomainSearchApiScreen> createState() => _DomainSearchApiScreenState();
}

class _DomainSearchApiScreenState extends State<DomainSearchApiScreen> {
  final _term = TextEditingController();
  bool _loading = false;
  String? _searched;
  List<DomainResult> _results = const [];

  /// Selling prices per extension, from Master Data. Only these extensions are offered.
  Map<String, List<DomainPrice>> _prices = const {};

  /// Duration chosen per domain (defaults to the shortest).
  final Map<String, DomainPrice> _picked = {};
  final Set<String> _added = {};

  @override
  void dispose() {
    _term.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final term = _term.text.trim();
    if (term.isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      final prices = <String, List<DomainPrice>>{};
      for (final p in await domainCartRepo.prices()) {
        prices.putIfAbsent(p.tld, () => []).add(p);
      }
      final res = await sb.functions.invoke('domain-search', body: {'term': term});
      final data = res.data as Map?;
      if (data?['error'] != null) throw Exception(data!['error']);
      // 20i can return just the extension (".uk"), so put the searched name in front.
      final label = term.toLowerCase().replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'^www\.'), '').split('/').first.split('.').first;
      String full(Object? d) => '$d'.startsWith('.') ? '$label$d' : '$d';
      final list = [
        for (final r in (data?['results'] as List? ?? const []))
          if (prices.containsKey(DomainResult(full(r['domain']), false).tld)) DomainResult(full(r['domain']), r['available'] == true),
      ]..sort((a, b) => a.available == b.available ? 0 : (a.available ? -1 : 1));
      if (!mounted) return;
      setState(() {
        _prices = prices;
        _results = list;
        _picked.clear();
        _searched = term;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addToBasket(DomainResult r, DomainPrice p) async {
    try {
      await domainCartRepo.add(r.domain, p);
      if (mounted) setState(() => _added.add(r.domain));
      // Mirror into the hosting panel's basket so the panel checkout sees it too.
      final why = await addDomainsToPanelBasket([(name: r.domain, years: p.years, tld: p.tld, currency: p.currency, price: p.price)]);
      if (why != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to your basket, but not to the hosting panel basket: $why'), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Duration picker, price and Add to Basket for an available domain.
  List<Widget> _buy(DomainResult r) {
    final options = _prices[r.tld]!;
    final picked = _picked[r.domain] ?? options.first;
    final inBasket = _added.contains(r.domain);
    return [
      SizedBox(
        width: 230,
        child: DropdownButtonFormField<DomainPrice>(
          initialValue: picked,
          isExpanded: true,
          decoration: fieldDecoration(),
          items: [for (final p in options) DropdownMenuItem(value: p, child: Text(p.label, overflow: TextOverflow.ellipsis))],
          onChanged: (p) => setState(() {
            _picked[r.domain] = p!;
            _added.remove(r.domain);
          }),
        ),
      ),
      const SizedBox(width: 12),
      inBasket
          ? OutlinedButton.icon(onPressed: () => context.go(Routes.cart), icon: const Icon(Icons.check, size: 16), label: const Text('In basket'))
          : PrimaryButton(label: 'Add to Basket', icon: Icons.add_shopping_cart, expand: false, onPressed: () => _addToBasket(r, picked)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Domain Search', style: T.headlineLg),
      const SizedBox(height: 4),
      Text('Find a domain name for your business.', style: T.bodyMd.copyWith(color: C.onSurfaceVariant)),
      const SizedBox(height: 16),
      AppCard(
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _term,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(hintText: 'Search a domain, e.g. mybusiness.com', prefixIcon: Icon(Icons.search)),
            ),
          ),
          const SizedBox(width: 12),
          PrimaryButton(label: 'Search', loading: _loading, expand: false, onPressed: _search),
        ]),
      ),
      const SizedBox(height: 16),
      if (_searched != null && _results.isEmpty && !_loading)
        AppCard(child: Text(_prices.isEmpty ? 'No domain prices set up yet. Add them in Master Data > Domain prices.' : 'No results for "$_searched".', style: T.bodyMd)),
      for (final r in _results)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            child: Row(children: [
              Icon(r.available ? Icons.check_circle : Icons.cancel, color: r.available ? C.primary : C.outline, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(r.domain, style: T.headlineSm)),
              if (r.available) ..._buy(r) else const Pill('Taken'),
            ]),
          ),
        ),
    ]);
  }
}
