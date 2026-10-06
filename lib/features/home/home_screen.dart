import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Filter { all, gainCity, infrastructure }

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Product>> _products = catalogRepo.products();
  _Filter _filter = _Filter.all;

  static const _infra = {'Hosting', 'Domain Registrar', 'Cybersecurity', 'Microsoft CSP'};

  List<Product> _apply(List<Product> all) => switch (_filter) {
        _Filter.all => all,
        _Filter.gainCity => all.where((p) => p.publisher.contains('Gain City') || p.name.contains('Gain City')).toList(),
        _Filter.infrastructure => all.where((p) => _infra.contains(p.category)).toList(),
      };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _WelcomeBanner(),
            const SizedBox(height: 32),
            const _JumpBackIn(),
            const SizedBox(height: 32),
            FutureBuilder<List<Product>>(
              future: _products,
              builder: (context, snap) {
                final header = _softwareHeader(snap.data?.length ?? 0);
                if (snap.hasError) {
                  return Column(children: [header, ErrorRetry(error: snap.error!, onRetry: () => setState(() => _products = catalogRepo.products()))]);
                }
                if (!snap.hasData) {
                  return Column(children: [header, const Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator())]);
                }
                final items = _apply(snap.data!);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  header,
                  const SizedBox(height: 16),
                  if (items.isEmpty)
                    Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('No software in this category yet.', style: T.bodyMd.copyWith(color: C.secondary))))
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 320, mainAxisExtent: 384, crossAxisSpacing: 24, mainAxisSpacing: 24),
                      itemBuilder: (_, i) => _SoftwareCard(product: items[i]),
                    ),
                ]);
              },
            ),
            const SizedBox(height: 32),
            const _WhatsNew(),
          ]),
        ),
      ),
    );
  }

  Widget _softwareHeader(int total) {
    Widget tab(String label, _Filter f) {
      final on = _filter == f;
      return InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => setState(() => _filter = f),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: on ? C.surfaceLowest : Colors.transparent, borderRadius: BorderRadius.circular(4)),
          child: Text(label, style: T.labelSm.copyWith(color: on ? C.primary : C.secondary, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
        ),
      );
    }

    return Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, spacing: 16, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.verified_outlined, color: C.primary, size: 24),
          const SizedBox(width: 8),
          Text('Software Provided By Us', style: T.headlineMd),
        ]),
        Text('Our Portfolio & Thumbnails • Direct Procurement & Reseller Licenses', style: T.bodySm.copyWith(color: C.secondary)),
      ]),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: C.surfaceLow, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          tab('All${total > 0 ? ' ($total)' : ''}', _Filter.all),
          tab('Gain City Solutions', _Filter.gainCity),
          tab('Infrastructure', _Filter.infrastructure),
        ]),
      ),
    ]);
  }
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [C.primary, C.primaryContainer, Color(0xFF006398)]),
          boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 8)],
        ),
        child: LayoutBuilder(builder: (context, c) {
          final row = c.maxWidth >= 900;
          final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.verified, size: 14, color: C.tertiaryFixed),
                const SizedBox(width: 8),
                Text('ENTERPRISE TIER-1 PARTNER', style: T.labelSm.copyWith(color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 0.9)),
              ]),
            ),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: AppState.instance,
              builder: (_, _) => Text(
                'Hello, ${AppState.instance.firstName}! Welcome to your intelligent cloud & software procurement platform.',
                style: (row ? T.headlineXl : T.headlineLg).copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'BizNest Hub simplifies how your enterprise buys and manages software, domains, and cloud services — all in one powerful, global platform.',
              style: T.bodyMd.copyWith(color: C.primaryFixed, height: 1.6),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in const [
                (Icons.cloud_sync_outlined, 'Cloud-iQ to Procurement'),
                (Icons.tune, 'Management'),
                (Icons.query_stats, 'Insights'),
                (Icons.credit_card, 'Billing'),
                (Icons.admin_panel_settings_outlined, 'Administration'),
              ])
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(t.$1, size: 13, color: const Color(0xFF93CCFF)),
                    const SizedBox(width: 6),
                    Text(t.$2, style: T.labelSm.copyWith(color: Colors.white)),
                  ]),
                ),
            ]),
          ]);
          final buttons = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              onPressed: () => context.go(Routes.software),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: C.primary,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: Text('New Subscription', style: T.labelLg.copyWith(color: C.primary)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => context.go(Routes.section('insights')),
              style: FilledButton.styleFrom(
                backgroundColor: C.primaryFixed.withValues(alpha: 0.2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.auto_graph, size: 18),
              label: Text('View Cost Insights', style: T.labelLg.copyWith(color: Colors.white)),
            ),
          ]);
          return row
              ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: text), const SizedBox(width: 24), SizedBox(width: 220, child: buttons)])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [text, const SizedBox(height: 24), buttons]);
        }),
      ),
    );
  }
}

class _JumpBackIn extends StatelessWidget {
  const _JumpBackIn();

  static const _tiles = [
    (Icons.manage_accounts_outlined, C.primaryFixed, C.primary, 'Manage Microsoft Accounts', 'Sync tenants & admin roles', 'manage'),
    (Icons.shopping_cart_checkout, C.secondaryContainer, C.secondary, 'Order Microsoft CSP Products', 'NCE licenses & enterprise SKUs', 'microsoft-csp'),
    (Icons.apps, C.primaryFixed, C.primary, 'Software Catalog', 'Browse 80+ enterprise platforms', 'software'),
    (Icons.query_stats, C.tertiaryFixed, C.tertiary, 'Service Provider Reporting', 'SPLA & usage validation reports', 'insights'),
    (Icons.support_agent, C.secondaryContainer, C.secondary, 'Create Support Request', 'Priority SLA escalation channel', 'support'),
    (Icons.analytics_outlined, C.primaryFixed, C.primary, 'Microsoft CSP Billing Analytics', 'Seat consumption & cost drift', 'transactions'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.bolt, color: C.primary, size: 20),
        const SizedBox(width: 8),
        Text('Jump Back In', style: T.headlineSm),
        const Spacer(),
        Flexible(child: Text('Frequently accessed operations', overflow: TextOverflow.ellipsis, style: T.labelSm.copyWith(color: C.secondary))),
      ]),
      const SizedBox(height: 8),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _tiles.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 440, mainAxisExtent: 72, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemBuilder: (_, i) {
          final t = _tiles[i];
          return AppCard(
            padding: const EdgeInsets.all(16),
            onTap: () => context.go(t.$6 == 'software' ? Routes.software : Routes.section(t.$6)),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: t.$2, borderRadius: BorderRadius.circular(8)),
                child: Icon(t.$1, size: 20, color: t.$3),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.$4, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.headlineSm),
                  Text(t.$5, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bodySm.copyWith(color: C.secondary)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: C.secondary),
            ]),
          );
        },
      ),
    ]);
  }
}

/// Category → badge colour and icon, matching the tags on the design cards.
({Color color, IconData icon}) categoryStyle(String category) => switch (category) {
      'AI & LLM' => (color: C.primary, icon: Icons.psychology_outlined),
      'Automotive' => (color: C.secondary, icon: Icons.directions_car_outlined),
      'Field Services' => (color: C.tertiary, icon: Icons.handyman_outlined),
      'Hosting' => (color: C.primary, icon: Icons.dns_outlined),
      'Domain Registrar' => (color: C.secondary, icon: Icons.language),
      'Microsoft CSP' => (color: C.primary, icon: Icons.grid_view),
      'Cybersecurity' => (color: C.error, icon: Icons.shield_outlined),
      'ERP & Supply' => (color: C.tertiary, icon: Icons.warehouse_outlined),
      _ => (color: C.primary, icon: Icons.apps),
    };

class _SoftwareCard extends StatelessWidget {
  const _SoftwareCard({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final style = categoryStyle(product.category);
    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      onTap: () => context.go(Routes.product(product.id)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 144,
          child: Stack(fit: StackFit.expand, children: [
            NetImage(product.imageUrl),
            Positioned(
              top: 12,
              left: 12,
              child: Pill(product.category, icon: style.icon, bg: style.color, fg: Colors.white, style: T.labelSm.copyWith(fontWeight: FontWeight.w700)),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(4)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star, size: 12, color: C.amber),
                  const SizedBox(width: 4),
                  Text(product.rating.toStringAsFixed(1), style: T.labelSm),
                ]),
              ),
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.headlineSm)),
                const SizedBox(width: 8),
                const Icon(Icons.verified, size: 16, color: C.primary),
              ]),
              const SizedBox(height: 4),
              Text(product.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.bodySm.copyWith(color: C.onSurfaceVariant)),
              const Spacer(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Flexible(child: Text('Model: ${product.pricingModel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.labelSm.copyWith(color: C.secondary))),
                const SizedBox(width: 8),
                Text(product.priceLabel, style: T.labelSm.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),
              PrimaryButton(label: 'Explore & Procure', icon: Icons.arrow_forward, height: 36, onPressed: () => context.go(Routes.product(product.id))),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _WhatsNew extends StatelessWidget {
  const _WhatsNew();

  static const _items = [
    (Icons.upgrade, C.primaryFixed, C.primary, 'Auto-Seat Scaling for Microsoft 365 NCE', 'Today',
        'IT Admins can now schedule automated seat decrements during off-cycle contract renewals without risking compliance penalties.'),
    (Icons.sync_alt, C.tertiaryFixed, C.tertiary, 'Direct Domain DNSSEC Auto-Provisioning', 'May 24',
        'Every newly registered domain via the BizNest DNS Engine now automatically negotiates cryptographic DNSSEC key exchange with ICANN registrars.'),
    (Icons.receipt_long_outlined, C.secondaryContainer, C.secondary, 'Gain City Enterprise ERP Connector 3.1', 'May 19',
        'Instant sync with Singapore IRAS invoice exchange formats and live automated GST tax breakdown columns in transactions ledger.'),
  ];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.new_releases_outlined, color: C.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text("What's New in BizNest Hub", style: T.headlineSm)),
          Text('View Full Changelog', style: T.labelSm.copyWith(color: C.primary, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 16),
        for (final i in _items)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.surfaceLow, borderRadius: BorderRadius.circular(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(color: i.$2, shape: BoxShape.circle),
                child: Icon(i.$1, size: 16, color: i.$3),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(i.$4, overflow: TextOverflow.ellipsis, style: T.labelLg)),
                    Text(i.$5, style: T.labelSm.copyWith(color: C.secondary)),
                  ]),
                  const SizedBox(height: 2),
                  Text(i.$6, style: T.bodySm.copyWith(color: C.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}
