import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog_repository.dart';
import '../../data/models.dart';

/// VPS with a native UI. Only plans that have a price in Master Data > VPS prices are offered; the reseller picks a
/// billing period, an operating system and a location, names the server, and adds it to the basket.
/// Left out for now: cPanel, snapshot backup, extra disks and one-click apps.
class VpsScreen extends StatefulWidget {
  const VpsScreen({super.key});

  @override
  State<VpsScreen> createState() => _VpsScreenState();
}

class _VpsScreenState extends State<VpsScreen> {
  /// Locations the panel offers. The codes are the data-centre values from 20i's addVPS docs (London, Dallas).
  static const _locations = {'dc_location-lhr': 'UK', 'dc_location-dfw': 'USA'};

  Map<String, List<VpsPrice>>? _plans; // by 20i VPS type
  List<VpsOs> _os = const [];
  Object? _error;
  final Map<String, VpsPrice> _period = {};
  final Map<String, VpsOs> _picked = {};
  final Map<String, String> _location = {};
  final Map<String, TextEditingController> _name = {};
  final Set<String> _added = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _name.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final plans = <String, List<VpsPrice>>{};
      for (final p in await vpsCartRepo.prices()) {
        plans.putIfAbsent(p.vpsType, () => []).add(p);
      }
      final os = await vpsCartRepo.osOptions();
      if (mounted) setState(() { _plans = plans; _os = os; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// A server name is a short label: letters, numbers, dots and dashes.
  String? _clean(String raw) {
    final n = raw.trim();
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$').hasMatch(n) ? n : null;
  }

  Future<void> _add(String type, VpsPrice plan) async {
    final name = _clean(_name[type]?.text ?? '');
    final os = _picked[type] ?? (_os.isEmpty ? null : _os.first);
    if (name == null) {
      showError(context, 'Give the server a name, e.g. web-01 (letters, numbers, dots and dashes).');
      return;
    }
    if (os == null) {
      showError(context, 'No operating systems are set up yet. Add them in Master Data > VPS operating systems.');
      return;
    }
    try {
      await vpsCartRepo.add(serverName: name, plan: plan, os: os, location: _location[type] ?? _locations.keys.first);
      if (mounted) setState(() => _added.add(type));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _plan(String type, List<VpsPrice> options) {
    final period = _period[type] ?? options.first;
    final os = _picked[type] ?? (_os.isEmpty ? null : _os.first);
    final controller = _name.putIfAbsent(type, TextEditingController.new);
    final inBasket = _added.contains(type);
    void edited() => _added.remove(type);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 220,
            child: Row(children: [
              const Icon(Icons.dns_outlined, color: C.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(options.first.planName, style: T.headlineSm)),
            ]),
          ),
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<VpsPrice>(
              initialValue: period,
              isExpanded: true,
              decoration: fieldDecoration(),
              items: [for (final p in options) DropdownMenuItem(value: p, child: Text(p.label, overflow: TextOverflow.ellipsis))],
              onChanged: (p) => setState(() { _period[type] = p!; edited(); }),
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<VpsOs>(
              initialValue: os,
              isExpanded: true,
              hint: dropdownHint('Operating system'),
              decoration: fieldDecoration(),
              items: [for (final o in _os) DropdownMenuItem(value: o, child: Text(o.label, overflow: TextOverflow.ellipsis))],
              onChanged: (o) => setState(() { _picked[type] = o!; edited(); }),
            ),
          ),
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<String>(
              initialValue: _location[type] ?? _locations.keys.first,
              isExpanded: true,
              decoration: fieldDecoration(),
              items: [for (final e in _locations.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (l) => setState(() { _location[type] = l!; edited(); }),
            ),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'Server name, e.g. web-01'),
              onChanged: (_) => setState(edited),
            ),
          ),
          inBasket
              ? OutlinedButton.icon(onPressed: () => context.go(Routes.cart), icon: const Icon(Icons.check, size: 16), label: const Text('In basket'))
              : PrimaryButton(label: 'Add to Basket', icon: Icons.add_shopping_cart, expand: false, onPressed: () => _add(type, period)),
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
      Text('VPS', style: T.headlineLg),
      const SizedBox(height: 4),
      Text('Choose a virtual private server, its operating system and location.', style: T.bodyMd.copyWith(color: C.onSurfaceVariant)),
      const SizedBox(height: 16),
      if (plans.isEmpty) AppCard(child: Text('No VPS plans set up yet. Add them in Master Data > VPS prices.', style: T.bodyMd)),
      for (final e in plans.entries) _plan(e.key, e.value),
    ]);
  }
}
