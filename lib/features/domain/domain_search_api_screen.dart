import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/format.dart';
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

  /// Selling prices per extension (SGD per year), from Master Data. Only these extensions are shown.
  Map<String, DomainPrice> _prices = const {};

  /// Years typed per domain (defaults to 1; null while the box is empty or invalid).
  final Map<String, int?> _years = {};
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
      final prices = {for (final p in await domainCartRepo.prices()) p.tld: p};
      final typed = term.toLowerCase().replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'^www\.'), '').split('/').first;
      final label = typed.split('.').first;
      if (!mounted) return;
      // Search the bare name so 20i checks every extension, not only the one that was typed.
      final res = await withLoader(context, () => sb.functions.invoke('domain-search', body: {'term': label, 'tlds': prices.keys.toList()}), message: 'Searching 20i...');
      final data = res.data as Map?;
      if (data?['error'] != null) throw Exception(data!['error']);
      // 20i can return just the extension (".uk"), so put the searched name in front.
      String full(Object? d) => '$d'.startsWith('.') ? '$label$d' : '$d';
      // Only extensions in Master Data are listed; taken names stay in the list, labelled.
      final list = [
        for (final r in (data?['results'] as List? ?? const []))
          if (prices.containsKey(DomainResult(full(r['domain']), false).tld))
          DomainResult(full(r['domain']), r['available'] == true),
      ]..sort((a, b) {
          int rank(DomainResult r) => r.domain == typed ? 0 : (r.available ? 1 : 2); // the exact name typed first, then free, then taken
          final c = rank(a).compareTo(rank(b));
          return c != 0 ? c : a.domain.compareTo(b.domain);
        });
      if (!mounted) return;
      setState(() {
        _prices = prices;
        _results = list;
        _years.clear();
        _searched = term;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addToBasket(DomainResult r, DomainPrice p, int years) async {
    try {
      // Adding again replaces the duration, so drop the old copy from the 20i panel basket first (no duplicates there).
      final result = await withLoader(context, () async {
        final old = await domainCartRepo.idOf(r.domain);
        if (old != null) await domainCartRepo.remove(old);
        await domainCartRepo.add(r.domain, p, years);
        // Mirror into the hosting panel's basket so the panel checkout sees it too.
        final res = await addDomainsToPanelBasket([(name: r.domain, years: years, tld: p.tld, currency: kCurrency, price: p.total(years))]);
        final panelId = res.ids[r.domain];
        if (panelId != null) await domainCartRepo.setPanelId(r.domain, panelId);
        return res;
      }, message: 'Adding to your basket...');
      if (!mounted) return;
      setState(() => _added.add(r.domain));
      if (result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to your basket, but not to the hosting panel basket: ${result.error}'), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Years box, price and Add to Basket for an available domain. Any number of years can be typed.
  List<Widget> _buy(DomainResult r) {
    final price = _prices[r.tld]!;
    final years = _years.containsKey(r.domain) ? _years[r.domain] : 1;
    final valid = years != null && years >= 1 && years <= maxDomainYears;
    final inBasket = _added.contains(r.domain);
    return [
      SizedBox(
        width: 96,
        child: TextFormField(
          key: ValueKey('years-${r.domain}'),
          initialValue: '${years ?? ''}',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: fieldDecoration(hint: 'Years').copyWith(suffixText: 'yr', errorText: valid ? null : '1-$maxDomainYears'),
          onChanged: (v) => setState(() {
            _years[r.domain] = int.tryParse(v);
            _added.remove(r.domain);
          }),
        ),
      ),
      const SizedBox(width: 12),
      SizedBox(width: 120, child: Text(valid ? money(price.total(years)) : '—', style: T.labelLg, textAlign: TextAlign.end)),
      const SizedBox(width: 12),
      inBasket
          ? OutlinedButton.icon(onPressed: () => context.go(Routes.cart), icon: const Icon(Icons.check, size: 16), label: const Text('In basket'))
          : PrimaryButton(label: 'Add to Basket', icon: Icons.add_shopping_cart, expand: false, onPressed: valid ? () => _addToBasket(r, price, years) : null),
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
        AppCard(child: Text('No results for "$_searched".', style: T.bodyMd)),
      for (final r in _results)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            child: Row(children: [
              Icon(r.available ? Icons.check_circle : Icons.cancel, color: r.available ? C.primary : C.outline, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.domain, style: T.headlineSm),
                  Text("${money(_prices[r.tld]!.pricePerYear)} per year", style: T.bodySm.copyWith(color: C.secondary)),
                ]),
              ),
              if (!r.available) const Pill('Already taken') else ..._buy(r),
            ]),
          ),
        ),
    ]);
  }
}
