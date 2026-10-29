import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog_repository.dart';
import '../../data/models.dart';

/// Hosting Packages with a native UI. Only plans that have a price in Master Data > Hosting prices are offered;
/// the customer picks a billing period, types the domain the package is for, and adds it to the basket.
class HostingScreen extends StatefulWidget {
  const HostingScreen({super.key});

  @override
  State<HostingScreen> createState() => _HostingScreenState();
}

class _HostingScreenState extends State<HostingScreen> {
  Map<String, List<HostingPrice>>? _plans; // by 20i package type id
  Object? _error;
  final Map<String, HostingPrice> _picked = {};
  final Map<String, TextEditingController> _domain = {};
  final Set<String> _added = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _domain.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final plans = <String, List<HostingPrice>>{};
      for (final p in await hostingCartRepo.prices()) {
        plans.putIfAbsent(p.packageTypeId, () => []).add(p);
      }
      if (mounted) setState(() => _plans = plans);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// "https://www.Example.com/x" -> "example.com", or null when it isn't a plausible domain.
  String? _clean(String raw) {
    final d = raw.trim().toLowerCase().replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'^www\.'), '').split('/').first;
    return RegExp(r'^[a-z0-9][a-z0-9-]*(\.[a-z0-9-]+)+$').hasMatch(d) ? d : null;
  }

  Future<void> _add(String planId, HostingPrice p) async {
    final domain = _clean(_domain[planId]?.text ?? '');
    if (domain == null) {
      showError(context, 'Enter the domain this hosting is for, e.g. mybusiness.com');
      return;
    }
    try {
      await hostingCartRepo.add(domain, p);
      if (mounted) setState(() => _added.add(planId));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _plan(String planId, List<HostingPrice> options) {
    final picked = _picked[planId] ?? options.first;
    final controller = _domain.putIfAbsent(planId, TextEditingController.new);
    final inBasket = _added.contains(planId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 220,
            child: Row(children: [
              const Icon(Icons.cloud_outlined, color: C.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(options.first.planName, style: T.headlineSm)),
            ]),
          ),
          SizedBox(
            width: 250,
            child: DropdownButtonFormField<HostingPrice>(
              initialValue: picked,
              isExpanded: true,
              decoration: fieldDecoration(),
              items: [for (final p in options) DropdownMenuItem(value: p, child: Text(p.label, overflow: TextOverflow.ellipsis))],
              onChanged: (p) => setState(() {
                _picked[planId] = p!;
                _added.remove(planId);
              }),
            ),
          ),
          SizedBox(
            width: 250,
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'Domain, e.g. mybusiness.com'),
              onChanged: (_) => setState(() => _added.remove(planId)),
            ),
          ),
          inBasket
              ? OutlinedButton.icon(onPressed: () => context.go(Routes.cart), icon: const Icon(Icons.check, size: 16), label: const Text('In basket'))
              : PrimaryButton(label: 'Add to Basket', icon: Icons.add_shopping_cart, expand: false, onPressed: () => _add(planId, picked)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final plans = _plans;
    if (plans == null) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Hosting Packages', style: T.headlineLg),
      const SizedBox(height: 4),
      Text('Choose a hosting plan for your website.', style: T.bodyMd.copyWith(color: C.onSurfaceVariant)),
      const SizedBox(height: 16),
      if (plans.isEmpty) AppCard(child: Text('No hosting plans set up yet. Add them in Master Data > Hosting prices.', style: T.bodyMd)),
      for (final e in plans.entries) _plan(e.key, e.value),
    ]);
  }
}
